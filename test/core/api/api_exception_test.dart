import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';

void main() {
  group('ApiException 层次（api_spec.md §2.3）', () {
    test('sealed 基类 + 5 类 + kanban/上传子类', () {
      expect(const InvalidServerUrlException('x'), isA<ApiException>());
      expect(
        NetworkException(NetworkExceptionKind.timedOut),
        isA<ApiException>(),
      );
      expect(HttpException.fromBody(500, null), isA<ApiException>());
      expect(const DecodingException(), isA<ApiException>());
      expect(const UnauthorizedException(), isA<ApiException>());
      expect(const KanbanNonJsonContentTypeException(), isA<ApiException>());
      expect(const KanbanDispatchMissingResultException(), isA<ApiException>());
      expect(
        const KanbanRunningStatusRequiresDispatcherException(),
        isA<ApiException>(),
      );
      expect(const UploadFileTooLargeException(), isA<ApiException>());
      expect(
        const RequestRejectedException('已达上限 (max 200)'),
        isA<ApiException>(),
      );
    });

    test('switch 穷尽匹配（sealed 语义验证）', () {
      String describe(ApiException error) => switch (error) {
        InvalidServerUrlException() => 'url',
        NetworkException() => 'network',
        HttpException() => 'http',
        DecodingException() => 'decoding',
        UnauthorizedException() => 'unauthorized',
        KanbanNonJsonContentTypeException() => 'kanban-json',
        KanbanDispatchMissingResultException() => 'kanban-dispatch',
        KanbanRunningStatusRequiresDispatcherException() => 'kanban-running',
        UploadFileTooLargeException() => 'upload-too-large',
        RequestRejectedException() => 'request-rejected',
      };
      expect(describe(const UnauthorizedException()), 'unauthorized');
      expect(
        describe(const RequestRejectedException('已达上限 (max 200)')),
        'request-rejected',
      );
      expect(describe(HttpException.fromBody(404, null)), 'http');
    });
  });

  group('HttpException.fromBody 语义字段解析', () {
    test('error / message / detail 按优先级取首个非空', () {
      final error = HttpException.fromBody(
        400,
        '{"error":"出错了","message":"备选","detail":"详情","code":"bad_request"}',
      );
      expect(error.serverMessage, '出错了');
      expect(error.serverCode, 'bad_request');

      final message = HttpException.fromBody(400, '{"message":"只有 message"}');
      expect(message.serverMessage, '只有 message');

      final detail = HttpException.fromBody(400, '{"detail":"只有 detail"}');
      expect(detail.serverMessage, '只有 detail');

      final trimmed = HttpException.fromBody(400, '{"error":"  空串  "}');
      expect(trimmed.serverMessage, '空串');
    });

    test('畸形 body → 字段全部置空', () {
      final error = HttpException.fromBody(500, 'not-json{');
      expect(error.serverMessage, isNull);
      expect(error.serverCode, isNull);
      expect(error.stale, isFalse);
      expect(error.activeStreamId, isNull);
      expect(error.body, 'not-json{');
    });

    test('null body 不崩', () {
      final error = HttpException.fromBody(500, null);
      expect(error.serverMessage, isNull);
      expect(error.message, contains('500'));
    });

    test('409 stale → indicatesExpiredPendingPrompt；active_stream_id 解析', () {
      final stale = HttpException.fromBody(
        409,
        '{"stale":true,"active_stream_id":"  st-9  "}',
      );
      expect(stale.indicatesExpiredPendingPrompt, isTrue);
      expect(stale.indicatesActiveStream, isTrue);
      expect(stale.activeStreamId, 'st-9');

      final notStale = HttpException.fromBody(409, '{"stale":false}');
      expect(notStale.indicatesExpiredPendingPrompt, isFalse);

      final not409 = HttpException.fromBody(400, '{"stale":true}');
      expect(not409.indicatesExpiredPendingPrompt, isFalse);
    });

    test('404 stream-not-found → indicatesMissingStream（大小写不敏感）', () {
      expect(
        HttpException.fromBody(
          404,
          '{"error":"Stream Not Found"}',
        ).indicatesMissingStream,
        isTrue,
      );
      expect(
        HttpException.fromBody(
          404,
          '{"message":"stream not found"}',
        ).indicatesMissingStream,
        isTrue,
      );
      expect(
        HttpException.fromBody(
          404,
          '{"error":"nothing"}',
        ).indicatesMissingStream,
        isFalse,
      );
      expect(
        HttpException.fromBody(
          500,
          '{"error":"stream not found"}',
        ).indicatesMissingStream,
        isFalse,
      );
    });

    test('404 Session not found → isVanishedSession', () {
      expect(
        HttpException.fromBody(
          404,
          '{"error":"Session not found"}',
        ).isVanishedSession,
        isTrue,
      );
      expect(
        HttpException.fromBody(
          404,
          '{"error":"session NOT FOUND"}',
        ).isVanishedSession,
        isTrue,
      );
      expect(
        HttpException.fromBody(404, '{"error":"other"}').isVanishedSession,
        isFalse,
      );
    });
  });

  group('NetworkException 分类消息', () {
    test('每个 kind 都有中文提示', () {
      expect(
        NetworkException(NetworkExceptionKind.timedOut).message,
        contains('超时'),
      );
      expect(
        NetworkException(NetworkExceptionKind.cannotFindHost).message,
        contains('地址'),
      );
      expect(
        NetworkException(NetworkExceptionKind.offline).message,
        contains('离线'),
      );
      expect(
        NetworkException(NetworkExceptionKind.cancelled).message,
        contains('取消'),
      );
    });
  });

  group('shouldUseCache（CacheFallbackPolicy）', () {
    test('网络类错误（DNS/连不上/离线/超时）→ 可用缓存', () {
      for (final kind in [
        NetworkExceptionKind.cannotFindHost,
        NetworkExceptionKind.cannotConnect,
        NetworkExceptionKind.offline,
        NetworkExceptionKind.timedOut,
      ]) {
        expect(
          ApiException.shouldUseCache(NetworkException(kind)),
          isTrue,
          reason: '$kind',
        );
      }
      expect(
        ApiException.shouldUseCache(NetworkException(NetworkExceptionKind.tls)),
        isFalse,
      );
    });

    test('HTTP 408/502/503/504 → 可用缓存', () {
      for (final code in [408, 502, 503, 504]) {
        expect(
          ApiException.shouldUseCache(HttpException.fromBody(code, null)),
          isTrue,
          reason: '$code',
        );
      }
      expect(
        ApiException.shouldUseCache(HttpException.fromBody(500, null)),
        isFalse,
      );
      expect(
        ApiException.shouldUseCache(const UnauthorizedException()),
        isFalse,
      );
    });
  });
}
