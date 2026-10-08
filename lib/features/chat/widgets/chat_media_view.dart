import 'dart:convert';
import 'dart:io';

import 'package:hermes_ui/app/theme/typography_tokens.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/widgets/hermes_dialog.dart';
import '../../../app/widgets/hermes_page_route.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/cache/cache_providers.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/models/message_attachment.dart';
import '../../../core/platform/external_opener.dart';
import '../../../l10n/app_localizations.dart';
import '../../diagnostics/diagnostics_models.dart';
import '../../diagnostics/diagnostics_service.dart';
import '../../downloads/download_confirm_dialog.dart';
import '../../downloads/download_models.dart';
import '../../downloads/download_page.dart';
import '../../downloads/download_providers.dart';
import '../../downloads/download_save_service.dart';
import '../../settings/settings_providers.dart';
import '../../workspace_manager/file_preview_body.dart';
import 'chat_media_parser.dart';

export '../../downloads/download_confirm_dialog.dart';

/// 单个网络媒体 URL → 本地缓存文件。
///
/// 经 [MediaCacheService] 走 dio 下载（带 cookie/自定义头/autoReauth）落盘后
/// 返回 [File]，渲染改用 `Image.file`；同一 URL 并发只下载一次（service 内
/// per-URL Future 合并）。未命中下载失败（非 2xx）时进入 error，渲染占位。
final mediaFileProvider = FutureProvider.family<File, String>((ref, url) {
  return ref.watch(mediaCacheServiceProvider).get(url);
});

/// 用户显式点过「点击加载」的图片 URL 集合（**进程内**，不落盘）。
///
/// 关闭「自动加载图片」时，闸门放行态原先只存在 `_ChatInlineMediaWidgetState`
/// 的 `_forceLoaded` 里 —— 状态跟着 widget State 走，「返回」时瓦片卸载即丢，
/// 再点开同消息又退回「点击加载」占位，用户看到的就是**图片消失了**。
///
/// 提到 provider 后：State 丢了也不会忘；只记 URL、不写磁盘、重启即清，
/// 所以「默认不自动加载」的意图不变（同一张图不重复要用户点第二次）。
final userLoadedMediaUrlsProvider =
    NotifierProvider<UserLoadedMediaUrls, Set<String>>(UserLoadedMediaUrls.new);

class UserLoadedMediaUrls extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void markLoaded(String url) {
    if (url.isEmpty || state.contains(url)) return;
    state = {...state, url};
  }
}

/// 强制刷新 [url] 的本地媒体缓存，并让所有消费它的图片组件重新解码。
///
/// 刷新成功后 `mediaFileProvider(url)` 会拿到**新路径**的缓存文件
/// （[MediaCacheService.refresh] 换名落盘）⇒ 聊天内联缩略图与灯箱一起换新。
/// 反过来说：别试图改成「同名写回 + `imageCache.evict`」—— `FileImage` 的 key
/// 只认路径，同名写回时 widget 不会重新 resolve（详见 service 的 `refresh`）。
Future<File> refreshCachedMedia(
  WidgetRef ref,
  String url, {
  String? sessionId,
}) async {
  final file = await ref
      .read(mediaCacheServiceProvider)
      .refresh(url, sessionId: sessionId);
  ref.invalidate(mediaFileProvider(url));
  return file;
}

/// 聊天内联媒体渲染组件（支持图片、base64 Data URI、本地文件与服务器 /api/media 路由）。
class ChatInlineMediaWidget extends ConsumerStatefulWidget {
  const ChatInlineMediaWidget({
    super.key,
    required this.rawUri,
    this.title,
    this.alt,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
    this.maxWidth = 360,
    this.maxHeight = 320,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.fit = BoxFit.contain,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.onIntrinsicSize,
  });

  final String rawUri;
  final String? title;
  final String? alt;
  final String? baseUrl;
  final String? sessionId;

  /// 兼容保留：自定义头现由 dio（ApiClient）在下载时统一处理，不再用于
  /// 内联渲染；保留参数以免破坏调用方签名。
  final Map<String, String>? customHeaders;
  final double maxWidth;
  final double maxHeight;
  final BorderRadius borderRadius;

  /// 图片填充方式。宫格瓦片用 [BoxFit.cover]（裁切成方），单图预览保持 contain。
  final BoxFit fit;

  /// 组件自带的外边距（默认上下各 4）。宫格排布时传 [EdgeInsets.zero]，
  /// 间距统一交给宫格的 spacing / runSpacing。
  final EdgeInsetsGeometry padding;

  /// 可选：图片**固有尺寸**（解码后的像素宽×高）首次就绪时回调一次。
  ///
  /// justified 宫格靠它拿真实宽高比来分行（回调是异步的：图没解码完拿不到固有
  /// 尺寸）。默认 `null` ⇒ 不挂任何监听、不做额外 IO，行为与旧版逐字节一致。
  final ValueChanged<Size>? onIntrinsicSize;

  @override
  ConsumerState<ChatInlineMediaWidget> createState() =>
      _ChatInlineMediaWidgetState();
}

class _ChatInlineMediaWidgetState extends ConsumerState<ChatInlineMediaWidget> {
  bool _forceLoaded = false;

  /// 固有尺寸是否已回报（只回报一次；失败/换图可重试）。
  bool _reportedIntrinsic = false;
  ImageStream? _intrinsicStream;
  ImageStreamListener? _intrinsicListener;

  @override
  void didUpdateWidget(ChatInlineMediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawUri != widget.rawUri) {
      _detachIntrinsic();
      _reportedIntrinsic = false;
    }
  }

  @override
  void dispose() {
    _detachIntrinsic();
    super.dispose();
  }

  void _detachIntrinsic() {
    final stream = _intrinsicStream;
    final listener = _intrinsicListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _intrinsicStream = null;
    _intrinsicListener = null;
  }

  /// 解析同一个 [ImageProvider]（与 `Image` 内部同 key ⇒ 命中同一份
  /// ImageCache），拿到固有尺寸后回调一次。
  ///
  /// ⚠️ 命中缓存时监听器会**同步**回调 —— 直接在 build 期调父级 `setState` 会撞
  /// 「build 期间 markNeedsBuild」，故同步分支推到帧后；异步分支（真解码完成）
  /// 在 build 之外，直接回调。
  void _reportIntrinsicSize(ImageProvider<Object> provider) {
    final callback = widget.onIntrinsicSize;
    if (callback == null || _reportedIntrinsic) return;
    _reportedIntrinsic = true;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, synchronousCall) {
        _detachIntrinsic();
        if (!mounted) return;
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (synchronousCall) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) callback(size);
          });
        } else {
          callback(size);
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        _detachIntrinsic();
        // 允许后续重试（例如网络图下载完成后重建 provider）。
        _reportedIntrinsic = false;
      },
    );
    _intrinsicStream = stream;
    _intrinsicListener = listener;
    stream.addListener(listener);
  }

  /// 点「点击加载」：本地置位（当帧即解闸）+ 记进进程级 URL 集合
  /// （返回再点开同消息时 State 已重建，靠集合里的记录仍然放行 —— 否则
  /// 用户看到的就是「图片消失了」，见 [userLoadedMediaUrlsProvider]）。
  void _markForceLoaded(String resolvedUrl) {
    setState(() => _forceLoaded = true);
    ref.read(userLoadedMediaUrlsProvider.notifier).markLoaded(resolvedUrl);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resolvedUrl = ChatMediaResolver.resolveMediaUrl(
      widget.rawUri,
      baseUrl: widget.baseUrl,
      sessionId: widget.sessionId,
    );

    if (resolvedUrl.isEmpty) {
      return _ImageErrorPlaceholder(
        altText: widget.alt ?? widget.title,
        rawUri: widget.rawUri,
        maxWidth: widget.maxWidth,
      );
    }

    final isDataUri = resolvedUrl.startsWith('data:image/');
    final isNetworkUrl =
        resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://');

    final autoLoadImages = ref.watch(autoLoadImagesProvider);
    final remembered = ref
        .watch(userLoadedMediaUrlsProvider)
        .contains(resolvedUrl);
    final shouldGate =
        !autoLoadImages && !_forceLoaded && !remembered && isNetworkUrl;

    if (shouldGate) {
      final displayName = widget.alt ?? widget.title;
      return Padding(
        padding: widget.padding,
        child: Container(
          constraints: BoxConstraints(
            minWidth: 32,
            minHeight: 32,
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.card,
              dark: CupertinoColors.systemGrey5,
            ),
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.cardBorder,
                dark: CupertinoColors.systemGrey4,
              ),
              width: 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, box) {
              // 文件名单独限宽：`Flexible` 在 `MainAxisSize.min` 的 Row 里会被
              // 分配整段剩余空间 ⇒ Row 撑到整宽、图标贴左、按钮居中，看着依旧
              // 不齐。改成按内容收缩的 ConstrainedBox；上限再留 8px 对称余量
              // （20 图标 + 8 间距 + 8×2），保证**超长名时 Row 也不会顶到盒子
              // 左右边缘**，整组内容始终落在中间。
              final maxLabelWidth = (box.maxWidth - 44).clamp(24.0, 100000.0);
              return Column(
                // 居中：闸门占位多数时候落在一个**固定盒子**里（单图 200×150、
                // 宫格瓦片 96×96），盒子被撑满后 `start + min` 会把「图标 +
                // 文件名 + 点击加载按钮」这组内容顶到左上角（主人报告：「加载
                // 按钮和提醒不在 placeholder 的正中间」）。松约束（Markdown
                // 行内图自带尺寸那种）下 Column 仍是内容尺寸，居中等于无操作。
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.photo,
                        size: 20,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                      ),
                      if (displayName != null && displayName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxLabelWidth),
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: kFontLabel,
                              fontWeight: FontWeight.w500,
                              color: LightSurfaces.resolve(
                                context,
                                LightSurfaces.textSecondary,
                                dark: CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    key: const ValueKey('chat-inline-media-tap-to-load'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.userDetail,
                      dark: CupertinoTheme.of(context).primaryColor,
                    ),
                    borderRadius: BorderRadius.circular(5),
                    minimumSize: const Size(36, 26),
                    onPressed: () => _markForceLoaded(resolvedUrl),
                    // 96 瓦片里可用宽只有 72：中文「点击加载」四个字 + 左右
                    // padding 正好顶格，浮点误差就让它折成两行（渲染图里
                    // 「点击加/载」）。scaleDown 保证**永远单行**，必要时
                    // 轻微缩字；英文 "Tap to load" 同样受益。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l10n.chatAutoLoadTapToLoad,
                        style: const TextStyle(
                          fontSize: kFontButton,
                          color: CupertinoColors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    final placeholderSize = _calculatePlaceholderSize(
      maxWidth: widget.maxWidth,
      maxHeight: widget.maxHeight,
      url: resolvedUrl,
    );

    Widget imageWidget;
    Uint8List? memoryBytes;
    // 与 `Image` 内部同 key 的 provider：用于回报固有尺寸（justified 宫格排序用）。
    ImageProvider<Object>? intrinsicProvider;

    if (isDataUri) {
      try {
        final commaIdx = resolvedUrl.indexOf(',');
        if (commaIdx != -1) {
          final payload = resolvedUrl.substring(commaIdx + 1);
          memoryBytes = base64Decode(payload);
          intrinsicProvider = MemoryImage(memoryBytes);
          imageWidget = Image.memory(
            memoryBytes,
            fit: widget.fit,
            errorBuilder: (context, error, stackTrace) {
              DiagnosticsService.instance.log(
                level: DiagnosticsLogLevel.error,
                tag: 'chat_media',
                message: 'Data URI 图片解码失败',
                errorKind: error.toString(),
              );
              return _ImageErrorPlaceholder(
                altText: widget.alt ?? widget.title,
                rawUri: widget.rawUri,
                maxWidth: widget.maxWidth,
              );
            },
          );
        } else {
          imageWidget = _ImageErrorPlaceholder(
            altText: widget.alt ?? widget.title,
            rawUri: widget.rawUri,
            maxWidth: widget.maxWidth,
          );
        }
      } catch (error) {
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.error,
          tag: 'chat_media',
          message: 'Data URI 图片解析异常',
          errorKind: error.toString(),
        );
        imageWidget = _ImageErrorPlaceholder(
          altText: widget.alt ?? widget.title,
          rawUri: widget.rawUri,
          maxWidth: widget.maxWidth,
        );
      }
    } else if (isNetworkUrl) {
      final fileAsync = ref.watch(mediaFileProvider(resolvedUrl));
      final cachedFile = fileAsync.valueOrNull;
      if (cachedFile != null) intrinsicProvider = FileImage(cachedFile);
      imageWidget = fileAsync.when(
        data: (file) => Image.file(
          file,
          fit: widget.fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return _mediaFadeIn(child);
            }
            return _loadingBox(
              context,
              widget.borderRadius,
              width: placeholderSize.width,
              height: placeholderSize.height,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            DiagnosticsService.instance.log(
              level: DiagnosticsLogLevel.error,
              tag: 'chat_media',
              message: '图片解码失败: $resolvedUrl',
              errorKind: error.toString(),
            );
            return _ImageErrorPlaceholder(
              altText: widget.alt ?? widget.title,
              rawUri: widget.rawUri,
              resolvedUrl: resolvedUrl,
              sessionId: widget.sessionId,
              maxWidth: widget.maxWidth,
            );
          },
        ),
        loading: () => _loadingBox(
          context,
          widget.borderRadius,
          width: placeholderSize.width,
          height: placeholderSize.height,
        ),
        error: (error, stackTrace) {
          DiagnosticsService.instance.log(
            level: DiagnosticsLogLevel.error,
            tag: 'chat_media',
            message: '网络图片下载失败: $resolvedUrl',
            errorKind: error.toString(),
          );
          return _ImageErrorPlaceholder(
            altText: widget.alt ?? widget.title,
            rawUri: widget.rawUri,
            resolvedUrl: resolvedUrl,
            sessionId: widget.sessionId,
            maxWidth: widget.maxWidth,
          );
        },
      );
    } else if (!kIsWeb && File(resolvedUrl).existsSync()) {
      final localFile = File(resolvedUrl);
      intrinsicProvider = FileImage(localFile);
      imageWidget = Image.file(
        localFile,
        fit: widget.fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return _mediaFadeIn(child);
          }
          return _loadingBox(
            context,
            widget.borderRadius,
            width: placeholderSize.width,
            height: placeholderSize.height,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          DiagnosticsService.instance.log(
            level: DiagnosticsLogLevel.error,
            tag: 'chat_media',
            message: '本地图片加载失败: $resolvedUrl',
            errorKind: error.toString(),
          );
          return _ImageErrorPlaceholder(
            altText: widget.alt ?? widget.title,
            rawUri: widget.rawUri,
            resolvedUrl: resolvedUrl,
            sessionId: widget.sessionId,
            maxWidth: widget.maxWidth,
          );
        },
      );
    } else {
      imageWidget = _ImageErrorPlaceholder(
        altText: widget.alt ?? widget.title,
        rawUri: widget.rawUri,
        resolvedUrl: resolvedUrl,
        sessionId: widget.sessionId,
        maxWidth: widget.maxWidth,
      );
    }

    // 固有尺寸回报（justified 宫格重排用）；provider 为空或回调为空时是 no-op。
    if (intrinsicProvider != null) {
      _reportIntrinsicSize(intrinsicProvider);
    }

    return Padding(
      padding: widget.padding,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openImageLightbox(
          context,
          resolvedUrl: resolvedUrl,
          memoryBytes: memoryBytes,
          altText: widget.alt ?? widget.title,
        ),
        child: Container(
          constraints: BoxConstraints(
            minWidth: 32,
            minHeight: 32,
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
          ),
          decoration: BoxDecoration(borderRadius: widget.borderRadius),
          clipBehavior: Clip.antiAlias,
          child: imageWidget,
        ),
      ),
    );
  }

  void _openImageLightbox(
    BuildContext context, {
    required String resolvedUrl,
    Uint8List? memoryBytes,
    String? altText,
  }) {
    showAttachmentPreview(
      context,
      resolvedUrl: resolvedUrl,
      bytes: memoryBytes,
      name: altText,
      altText: altText,
      isImage: true,
      sessionId: widget.sessionId,
    );
  }
}

/// 聊天正文 markdown 链接点击统一处理（#57）。
///
/// `MEDIA:` 标记会被 [ChatMediaParser] 转成 `[📎 name](url)` 形式的链接，
/// 但 flutter_markdown 默认 `onTapLink` 是 no-op——本函数接到三处
/// MarkdownBody（用户气泡 / 助手气泡 / live 文本段）：
/// - 图片 → 直接开 Lightbox 大图预览；
/// - 其余（apk/文档/音视频/任意文件）→ 开附件预览页（内含 #53 下载确认框
///   与下载中心入队链路），点击即可下载；
/// - http/https 普通网页链接 → url_launcher 外部打开；失败给可见提示。
Future<void> onChatMarkdownLinkTap(
  BuildContext context, {
  required String? link,
  String? linkText,
  String? sessionId,
}) async {
  if (link == null || link.isEmpty || !context.mounted) return;
  final uri = Uri.tryParse(link);
  final isHttp = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  final kind = MessageAttachment.mediaKindForName(link);

  // 图片：Lightbox 预览（内部含下载按钮）。
  if (kind == MessageMediaKind.image) {
    showAttachmentPreview(
      context,
      resolvedUrl: link,
      name: linkText,
      altText: linkText,
      isImage: true,
      sessionId: sessionId,
    );
    return;
  }

  // 明确的媒体/文档类型（apk、zip、txt…）：附件预览页 → 确认框 → 下载中心。
  if (kind != MessageMediaKind.file) {
    showAttachmentPreview(
      context,
      resolvedUrl: link,
      name: linkText,
      altText: linkText,
      isImage: false,
      sessionId: sessionId,
    );
    return;
  }

  // 纯 file 类：无扩展名的普通网页链接 → url_launcher 外部打开；
  // 带文件扩展名的 http(s) 直链（如 https://host/app.apk）→ 应用内预览下载。
  if (isHttp) {
    final lastSegment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : '';
    final looksLikeFile = lastSegment.contains('.');
    if (!looksLikeFile) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && context.mounted) {
          _showLinkFallbackPreview(context, link, linkText, sessionId);
        }
      } catch (_) {
        if (context.mounted) {
          _showLinkFallbackPreview(context, link, linkText, sessionId);
        }
      }
      return;
    }
  }

  showAttachmentPreview(
    context,
    resolvedUrl: link,
    name: linkText,
    altText: linkText,
    isImage: false,
    sessionId: sessionId,
  );
}

void _showLinkFallbackPreview(
  BuildContext context,
  String link,
  String? linkText,
  String? sessionId,
) {
  // 外部浏览器启动失败：退到应用内预览页（可见，不静默吞点击）。
  showAttachmentPreview(
    context,
    resolvedUrl: link,
    name: linkText,
    altText: linkText,
    isImage: false,
    sessionId: sessionId,
  );
}

/// 打开附件预览全屏弹窗（图片走 Lightbox 大图，非图展示文档信息与下载操作）。
void showAttachmentPreview(
  BuildContext context, {
  Uint8List? bytes,
  String? resolvedUrl,
  String? name,
  bool? isImage,
  String? altText,
  String? sessionId,
  int? expectedBytes,
  String? mimeType,
  Future<void> Function(String path)? onOpenFile,
}) {
  final displayName = name ?? altText ?? '';
  final hasExplicitImage = isImage != null;
  final bool effectiveIsImage = hasExplicitImage
      ? isImage
      : ((bytes != null &&
                (displayName.isEmpty ||
                    MessageAttachment.isImageReference(displayName))) ||
            (resolvedUrl != null &&
                (resolvedUrl.startsWith('data:image/') ||
                    MessageAttachment.isImageReference(resolvedUrl) ||
                    (displayName.isNotEmpty &&
                        MessageAttachment.isImageReference(displayName)))));

  Navigator.of(context).push(
    HermesPageRoute<void>(
      fullscreenDialog: true,
      builder: (dialogContext) => AttachmentLightbox(
        bytes: bytes,
        resolvedUrl: resolvedUrl,
        name: displayName.isNotEmpty ? displayName : null,
        altText: altText,
        isImage: effectiveIsImage,
        sessionId: sessionId,
        expectedBytes: expectedBytes,
        mimeType: mimeType,
        onOpenFile: onOpenFile,
      ),
    ),
  );
}

/// 附件 Lightbox / 预览页面（图片缩放查看，非图文件详情与下载）。
class AttachmentLightbox extends StatelessWidget {
  const AttachmentLightbox({
    super.key,
    this.bytes,
    this.resolvedUrl,
    this.name,
    this.altText,
    this.isImage = true,
    this.sessionId,
    this.expectedBytes,
    this.mimeType,
    this.onOpenFile,
  });

  final Uint8List? bytes;
  final String? resolvedUrl;
  final String? name;
  final String? altText;
  final bool isImage;
  final String? sessionId;
  final int? expectedBytes;
  final String? mimeType;
  final Future<void> Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titleText = name ?? altText ?? '';

    final previewKind = workspaceFileKindOf(titleText);

    // 远端图片（http/https）才有「刷新」语义：内容可能在服务端被改写而 URL
    // 不变，本地缓存会一直挡着（key = sha256(URL)、TTL 30 天）。内存字节 /
    // data: URI / 本地文件都没有远端副本，不渲染刷新按钮。
    final bool refreshableImage =
        (isImage || previewKind == WorkspaceFileKind.image) &&
        resolvedUrl != null &&
        (resolvedUrl!.startsWith('http://') ||
            resolvedUrl!.startsWith('https://'));

    // 下载/状态按钮统一钉导航栏右上角（全分支唯一实例，单一状态显示）：
    // 失败/已下载等状态就地变化，不随兜底卡布局漂移，也不重复渲染。
    final navDownloadBtn = _AttachmentDownloadButton(
      resolvedUrl: resolvedUrl,
      bytes: bytes,
      filename: titleText.isNotEmpty ? titleText : 'image.png',
      sessionId: sessionId,
      expectedBytes: expectedBytes ?? bytes?.length,
      mimeType: mimeType ?? (isImage ? 'image/png' : null),
      onOpenFile: onOpenFile,
      compact: true,
    );

    Widget body;
    if (isImage || previewKind == WorkspaceFileKind.image) {
      Widget viewerContent;
      if (bytes != null) {
        viewerContent = Image.memory(bytes!, fit: BoxFit.contain);
      } else if (resolvedUrl != null &&
          (resolvedUrl!.startsWith('http://') ||
              resolvedUrl!.startsWith('https://'))) {
        viewerContent = _LightboxNetworkImage(mediaUrl: resolvedUrl!);
      } else if (resolvedUrl != null &&
          resolvedUrl!.startsWith('data:image/')) {
        Uint8List? decoded;
        try {
          final commaIdx = resolvedUrl!.indexOf(',');
          if (commaIdx != -1) {
            final payload = resolvedUrl!.substring(commaIdx + 1);
            decoded = base64Decode(payload);
          }
        } catch (_) {}
        viewerContent = decoded != null
            ? Image.memory(decoded, fit: BoxFit.contain)
            : const Icon(
                CupertinoIcons.photo,
                size: 64,
                color: CupertinoColors.white,
              );
      } else if (resolvedUrl != null &&
          !kIsWeb &&
          File(resolvedUrl!).existsSync()) {
        viewerContent = Image.file(File(resolvedUrl!), fit: BoxFit.contain);
      } else {
        viewerContent = const Icon(
          CupertinoIcons.photo,
          size: 64,
          color: CupertinoColors.white,
        );
      }

      body = Column(
        children: [
          // 注意：InteractiveViewer 的 ClipRect 采用自身盒子尺寸，而其盒子会收缩到
          // 子图自然尺寸（Center/松约束下 1x1 小图 = 视口缩没，放大内容被裁回小框，
          // 真机反馈 bug）。SizedBox.expand 把视口钉满全屏，子 Image 均为
          // BoxFit.contain，紧约束下初始即 contain 铺满视口。
          Expanded(
            child: SizedBox.expand(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: viewerContent,
              ),
            ),
          ),
        ],
      );
    } else if (previewKind == WorkspaceFileKind.pdf ||
        previewKind == WorkspaceFileKind.office ||
        previewKind == WorkspaceFileKind.video ||
        previewKind == WorkspaceFileKind.audio ||
        previewKind == WorkspaceFileKind.text) {
      // 下载/状态按钮已由导航栏右上角统一承担（唯一实例）；预览体不再挂
      // downloadButton/onDownload —— 失败兜底卡只剩单一「重试」，杜绝多处
      // 重复按钮与状态漂移。
      final previewBody = FilePreviewBody(
        source: FilePreviewSource.resolved(
          resolvedUrl,
          bytes: bytes,
          sessionId: sessionId,
        ),
        fileName: titleText,
        sizeBytes: expectedBytes ?? bytes?.length,
      );

      body = Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              child: previewKind == WorkspaceFileKind.pdf
                  ? SizedBox.expand(child: previewBody)
                  : SingleChildScrollView(child: previewBody),
            ),
          ),
        ],
      );
    } else {
      final kind = MessageAttachment.mediaKindForName(titleText);
      IconData iconData;
      switch (kind) {
        case MessageMediaKind.image:
          iconData = CupertinoIcons.photo;
        case MessageMediaKind.audio:
          iconData = CupertinoIcons.music_note;
        case MessageMediaKind.video:
          iconData = CupertinoIcons.film;
        case MessageMediaKind.document:
          iconData = CupertinoIcons.doc_text;
        case MessageMediaKind.file:
          iconData = CupertinoIcons.doc;
      }

      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData, size: 64, color: CupertinoColors.white),
              if (titleText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  titleText,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    // TODO(type): 未进梯子
                    fontSize: kFontItemTitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                l10n.previewUnsupported,
                style: const TextStyle(
                  // Inverse media preview on black: #8E8E93 is 6.440674:1; theme-independent.
                  color: CupertinoColors.systemGrey,
                  fontSize: kFontBody,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        // 全屏媒体查看器：栏体恒黑，结构线在其上只会变成一条亮线 ⇒ 刻意不给线，
        // 只显式关掉 SDK 那条黑 30%（避免线族里存留异色，口径见 nav_bar_hairline.dart）。
        border: null,
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.7),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.clear_thick,
            color: CupertinoColors.white,
            size: 20,
          ),
        ),
        middle: titleText.isNotEmpty
            ? Text(
                titleText,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: kFontBody,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refreshableImage)
              _MediaRefreshButton(mediaUrl: resolvedUrl!, sessionId: sessionId),
            navDownloadBtn,
          ],
        ),
      ),
      child: SafeArea(child: body),
    );
  }
}

class _AttachmentDownloadButton extends ConsumerWidget {
  const _AttachmentDownloadButton({
    this.resolvedUrl,
    this.bytes,
    this.filename,
    this.sessionId,
    this.expectedBytes,
    this.mimeType,
    this.onOpenFile,
    this.compact = false,
  });

  final String? resolvedUrl;
  final Uint8List? bytes;
  final String? filename;
  final String? sessionId;
  final int? expectedBytes;
  final String? mimeType;
  final Future<void> Function(String path)? onOpenFile;

  /// 紧凑图标模式（导航栏右上角）：图标 + 小号状态字，白字透明底；
  /// false 时为整块 filled 按钮（正文兜底区）。
  final bool compact;

  /// 统一按 compact 包装按钮外观，状态逻辑与文案零分叉。
  Widget _btn({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool activity = false,
    bool destructive = false,
  }) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (activity)
          const CupertinoActivityIndicator(
            color: CupertinoColors.white,
            radius: 6,
          )
        else
          Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: compact
              ? const TextStyle(
                  fontSize: kFontCaption,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                )
              : null,
        ),
      ],
    );
    if (compact) {
      return CupertinoButton(
        key: const ValueKey('attachment-download-button'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        onPressed: onPressed,
        child: Opacity(
          // 禁用态：不可点的占位（如无法解析来源）半透明弱化。
          opacity: destructive
              ? 0.35
              : onPressed == null
              ? 0.6
              : 1.0,
          child: row,
        ),
      );
    }
    return CupertinoButton.filled(
      key: const ValueKey('attachment-download-button'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      onPressed: onPressed,
      child: row,
    );
  }

  String? _effectiveUrl(WidgetRef ref) {
    var url = resolvedUrl;
    if (url != null && url.isNotEmpty) {
      if (!url.startsWith('http://') &&
          !url.startsWith('https://') &&
          !url.startsWith('data:')) {
        // 无激活连接（如测试环境/未引导）时容错：不抛，按原值返回。
        String baseUrl = '';
        try {
          baseUrl = ref.read(apiClientProvider).baseUrl;
        } catch (_) {
          baseUrl = '';
        }
        if (baseUrl.isNotEmpty) {
          url = ChatMediaResolver.resolveMediaUrl(
            url,
            baseUrl: baseUrl,
            sessionId: sessionId,
          );
        }
      }
    }
    return url;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final downloadState = ref.watch(downloadControllerProvider);
    final controller = ref.read(downloadControllerProvider.notifier);

    final url = _effectiveUrl(ref);
    final cleanName = DownloadSaveService.sanitizeFileName(
      filename?.isNotEmpty == true ? filename! : (url ?? 'download'),
      mimeType: mimeType,
    );

    final task = (url != null && url.isNotEmpty)
        ? downloadState.tasks.where((t) => t.sourceUrl == url).firstOrNull
        : downloadState.tasks
              .where(
                (t) =>
                    t.sourceType == DownloadSourceType.bytes &&
                    t.fileName == cleanName,
              )
              .firstOrNull;

    final bool isLocalAvailable =
        url != null && !kIsWeb && File(url).existsSync();

    // 不可解析来源（既无内存字节、URL 又非 http/data/本地文件）：禁用态 + 可见提示，
    // 不再静默禁用「点了没反应」（#53 A-2）。
    final bool hasResolvableUrl =
        url != null &&
        url.isNotEmpty &&
        (url.startsWith('http://') ||
            url.startsWith('https://') ||
            url.startsWith('data:') ||
            (!kIsWeb && File(url).existsSync()));
    if (bytes == null && !hasResolvableUrl) {
      return _btn(
        onPressed: null,
        icon: CupertinoIcons.cloud_download,
        label: l10n.dl53CannotDownload,
      );
    }

    if (isLocalAvailable) {
      return _btn(
        onPressed: () async {
          await openDownloadedFile(
            context,
            url,
            mimeType: mimeType,
            customOpener: onOpenFile,
            opener: ref.read(externalOpenerProvider),
          );
        },
        icon: CupertinoIcons.check_mark,
        label: l10n.downloaded,
      );
    }

    if (task != null) {
      if (task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.downloading) {
        return _btn(
          onPressed: null,
          icon: CupertinoIcons.cloud_download,
          label: l10n.downloading,
          activity: true,
        );
      }

      if (task.status == DownloadStatus.completed) {
        final fileExists =
            task.savedPath != null && File(task.savedPath!).existsSync();
        if (fileExists) {
          return _btn(
            onPressed: () async {
              await openDownloadedFile(
                context,
                task.savedPath!,
                mimeType: task.mimeType ?? mimeType,
                customOpener: onOpenFile,
                opener: ref.read(externalOpenerProvider),
              );
            },
            icon: CupertinoIcons.check_mark,
            label: l10n.downloaded,
          );
        } else {
          return _btn(
            onPressed: () => _triggerDownload(context, ref),
            icon: CupertinoIcons.arrow_clockwise,
            label: l10n.downloadRedownload,
          );
        }
      }

      if (task.status == DownloadStatus.failed ||
          task.status == DownloadStatus.cancelled) {
        return _btn(
          onPressed: () async {
            await controller.retry(task.id);
          },
          icon: CupertinoIcons.arrow_clockwise,
          label: l10n.downloadRetry,
        );
      }
    }

    final hasBytes = bytes != null;
    final canDownload =
        hasBytes ||
        (url != null &&
            (url.startsWith('http://') ||
                url.startsWith('https://') ||
                url.startsWith('data:')));

    if (!canDownload) {
      if (compact) {
        return _btn(
          onPressed: null,
          icon: CupertinoIcons.cloud_download,
          label: l10n.mediaDownload,
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(
            onPressed: null,
            icon: CupertinoIcons.cloud_download,
            label: l10n.mediaDownload,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.dl53CannotDownload,
            style: const TextStyle(
              fontSize: kFontCaption,
              // Inverse media preview on black: #8E8E93 is 6.440674:1; theme-independent.
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      );
    }

    return _btn(
      onPressed: () => _triggerDownload(context, ref),
      icon: CupertinoIcons.cloud_download,
      label: l10n.mediaDownload,
    );
  }

  Future<void> _triggerDownload(BuildContext context, WidgetRef ref) async {
    final url = _effectiveUrl(ref);
    final hasBytes = bytes != null;
    if (!hasBytes && (url == null || url.isEmpty)) return;

    final displayName = filename?.isNotEmpty == true
        ? filename!
        : (url?.split('/').last.split('?').first ?? 'download');
    final cleanName = DownloadSaveService.sanitizeFileName(
      displayName,
      mimeType: mimeType,
    );

    Uint8List? dataBytes = bytes;
    if (dataBytes == null && url != null && url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          dataBytes = base64Decode(url.substring(comma + 1));
        } catch (_) {}
      }
    }

    final confirmed = await showDownloadConfirmationDialog(
      context,
      fileName: cleanName,
      mimeType: mimeType,
      expectedBytes: expectedBytes ?? dataBytes?.length,
      sessionId: sessionId,
    );

    if (confirmed == true && context.mounted) {
      await ref
          .read(downloadControllerProvider.notifier)
          .enqueue(
            sourceUrl: url,
            bytes: dataBytes,
            fileName: cleanName,
            mimeType: mimeType,
            expectedBytes: expectedBytes ?? dataBytes?.length,
            sessionId: sessionId,
          );
    }
  }
}

/// 媒体预览的「刷新」按钮：强制绕过本地缓存重取同一 URL。
///
/// 只对 http(s) 远端媒体有意义，由调用方判定是否渲染（本组件不做隐式判断，
/// 保持单一职责便于测试）。刷新失败只提示、不破坏已有缓存（service 层保证）。
/// 刷新中换活动指示器：既给即时反馈，也顺带防连点。
class _MediaRefreshButton extends ConsumerStatefulWidget {
  const _MediaRefreshButton({required this.mediaUrl, this.sessionId});

  final String mediaUrl;
  final String? sessionId;

  @override
  ConsumerState<_MediaRefreshButton> createState() =>
      _MediaRefreshButtonState();
}

class _MediaRefreshButtonState extends ConsumerState<_MediaRefreshButton> {
  bool _refreshing = false;

  Future<void> _onPressed() async {
    if (_refreshing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _refreshing = true);
    try {
      await refreshCachedMedia(
        ref,
        widget.mediaUrl,
        sessionId: widget.sessionId,
      );
    } catch (error) {
      // 刷新失败保留旧图（service 先下载后落盘），这里只把原因说清楚。
      if (!mounted) return;
      // 批次 5 · C5：失败提示 → 380（宽屏居中卡片；窄屏系统弹窗不变）。
      await showHermesDialog<void>(
        context,
        kind: HermesDialogKind.confirm,
        title: (_) => Text(l10n.refreshFailed),
        content: (_) =>
            Text(error is ApiException ? error.message : error.toString()),
        actions: [
          HermesDialogAction(
            key: const ValueKey('media-refresh-error-ok'),
            builder: (_) => Text(l10n.ok),
            onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_refreshing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: CupertinoActivityIndicator(
          radius: 8,
          color: CupertinoColors.white,
        ),
      );
    }
    return Tooltip(
      message: AppLocalizations.of(context).refreshImage,
      child: CupertinoButton(
        key: const ValueKey('media-refresh-button'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        onPressed: _onPressed,
        child: const Icon(
          CupertinoIcons.arrow_clockwise,
          color: CupertinoColors.white,
          size: 20,
        ),
      ),
    );
  }
}

/// Lightbox 中的网络图片查看器：同样消费 `mediaFileProvider`（缓存命中即
/// Image.file，不二次网络请求；失败显示占位图标而非白屏）。
class _LightboxNetworkImage extends ConsumerWidget {
  const _LightboxNetworkImage({required this.mediaUrl});

  final String mediaUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileAsync = ref.watch(mediaFileProvider(mediaUrl));
    return fileAsync.when(
      data: (file) => Image.file(
        file,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return _mediaFadeIn(child);
          }
          return const Center(child: CupertinoActivityIndicator());
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          CupertinoIcons.photo,
          size: 64,
          color: CupertinoColors.white,
        ),
      ),
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (error, stackTrace) => const Icon(
        CupertinoIcons.photo,
        size: 64,
        color: CupertinoColors.white,
      ),
    );
  }
}

/// 从 URL 查询参数中解析宽高提示（如 `?w=400&h=300` 或 `?width=400&height=300`）。
(double, double)? _parseDimensionsFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final wStr = uri.queryParameters['w'] ?? uri.queryParameters['width'];
    final hStr = uri.queryParameters['h'] ?? uri.queryParameters['height'];
    if (wStr != null && hStr != null) {
      final w = double.tryParse(wStr);
      final h = double.tryParse(hStr);
      if (w != null && h != null && w > 0 && h > 0) {
        return (w, h);
      }
    }
  } catch (_) {
    // 忽略异常格式
  }
  return null;
}

/// 真图首次出帧的一次性淡入（替代 AnimatedSize 尺寸动画：淡入不改变布局，
/// extent 单次到位，配合列表 ScrollMetricsNotification 跟底一次补跳）。
/// const Tween 实例：仅首帧构建一次，后续帧同实例 →
/// TweenAnimationBuilder 不重启动画。
Widget _mediaFadeIn(Widget child) {
  return TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
    builder: (context, value, child) => Opacity(opacity: value, child: child),
    child: child,
  );
}

/// 计算占位容器尺寸：若 URL 携带尺寸提示则按 contain 计算，否则回退默认 160×120。
Size _calculatePlaceholderSize({
  required double maxWidth,
  required double maxHeight,
  String? url,
}) {
  if (url != null) {
    final dims = _parseDimensionsFromUrl(url);
    if (dims != null) {
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(dims.$1, dims.$2),
        Size(maxWidth, maxHeight),
      ).destination;
      return Size(
        fitted.width.clamp(32.0, maxWidth),
        fitted.height.clamp(32.0, maxHeight),
      );
    }
  }
  return Size(160.0.clamp(32.0, maxWidth), 120.0.clamp(32.0, maxHeight));
}

Widget _loadingBox(
  BuildContext context,
  BorderRadius borderRadius, {
  double width = 160,
  double height = 120,
}) {
  return Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.card,
        dark: CupertinoColors.systemGrey5,
      ),
      borderRadius: borderRadius,
    ),
    child: const CupertinoActivityIndicator(radius: 10),
  );
}

/// 图片加载失败占位符（灰色图标 + 提示文案 + 重新加载与下载原图操作）。
class _ImageErrorPlaceholder extends ConsumerWidget {
  const _ImageErrorPlaceholder({
    this.altText,
    this.rawUri,
    this.resolvedUrl,
    this.sessionId,
    this.maxWidth = 360,
  });

  final String? altText;
  final String? rawUri;
  final String? resolvedUrl;
  final String? sessionId;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final displayName =
        altText ?? rawUri?.split('/').last.split(r'\\').last ?? l10n.mediaImage;

    final hasValidUrl = resolvedUrl != null && resolvedUrl!.isNotEmpty;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.systemGrey5,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: CupertinoColors.systemGrey4,
          ),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.photo,
                size: 20,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: CupertinoColors.secondaryLabel,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.imageLoadFailed,
                      style: TextStyle(
                        fontSize: kFontLabel,
                        fontWeight: FontWeight.w500,
                        color: LightSurfaces.resolve(
                          context,
                          LightSurfaces.textSecondary,
                          dark: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                    if (displayName.isNotEmpty)
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kFontMicro,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: CupertinoColors.tertiaryLabel,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (hasValidUrl) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  key: const ValueKey('chat-media-reload-button'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.pressed,
                    dark: CupertinoColors.systemGrey4,
                  ),
                  borderRadius: BorderRadius.circular(5),
                  minimumSize: const Size(36, 26),
                  onPressed: () {
                    ref.invalidate(mediaFileProvider(resolvedUrl!));
                  },
                  child: Text(
                    l10n.imageReload,
                    style: TextStyle(
                      fontSize: kFontButton,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CupertinoButton(
                  key: const ValueKey('chat-media-download-original-button'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.userDetail,
                    dark: CupertinoTheme.of(context).primaryColor,
                  ),
                  borderRadius: BorderRadius.circular(5),
                  minimumSize: const Size(36, 26),
                  onPressed: () async {
                    final fileName = DownloadSaveService.sanitizeFileName(
                      displayName.isNotEmpty ? displayName : 'image.png',
                      mimeType: 'image/png',
                    );
                    final confirmed = await showDownloadConfirmationDialog(
                      context,
                      fileName: fileName,
                      mimeType: 'image/png',
                      sessionId: sessionId,
                    );
                    if (confirmed == true && context.mounted) {
                      await ref
                          .read(downloadControllerProvider.notifier)
                          .enqueue(
                            sourceUrl: resolvedUrl!,
                            fileName: fileName,
                            mimeType: 'image/png',
                            sessionId: sessionId,
                          );
                    }
                  },
                  child: Text(
                    l10n.imageDownloadOriginal,
                    style: const TextStyle(
                      fontSize: kFontMicro,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
