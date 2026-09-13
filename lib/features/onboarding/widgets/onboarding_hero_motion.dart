import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../l10n/app_localizations.dart';

/// A quiet, staggered brand entrance followed by a twelve-second breath.
///
/// Only the wide brand pane mounts this widget. Reduced motion renders the
/// settled composition without creating animation controllers or tickers.
class OnboardingHeroMotion extends StatefulWidget {
  /// Creates the brand composition using the surrounding page's palette.
  const OnboardingHeroMotion({super.key, required this.isDark});

  /// Whether to draw the graphite rather than the paper-colored halo.
  final bool isDark;

  @override
  State<OnboardingHeroMotion> createState() => _OnboardingHeroMotionState();
}

class _OnboardingHeroMotionState extends State<OnboardingHeroMotion>
    with TickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 1200);
  // Six seconds in each direction: twelve seconds for a complete breath.
  static const _ambientDuration = Duration(seconds: 6);
  static const _settleCurve = Cubic(0.16, 1, 0.3, 1);
  static const _typeCurve = Cubic(0.22, 1, 0.36, 1);
  static const _revealCurve = Cubic(0.22, 0.68, 0.28, 1);

  AnimationController? _entranceController;
  AnimationController? _ambientController;
  bool? _disableAnimations;

  Animation<double> _haloOpacity = const AlwaysStoppedAnimation(1);
  Animation<double> _logoOpacity = const AlwaysStoppedAnimation(1);
  Animation<double> _logoScale = const AlwaysStoppedAnimation(1);
  Animation<Offset> _logoOffset = const AlwaysStoppedAnimation(Offset.zero);
  Animation<double> _titleProgress = const AlwaysStoppedAnimation(1);
  Animation<double> _sloganOpacity = const AlwaysStoppedAnimation(1);
  Animation<Offset> _sloganOffset = const AlwaysStoppedAnimation(Offset.zero);
  Animation<double> _breath = const AlwaysStoppedAnimation(0);
  Animation<double> _logoBreath = const AlwaysStoppedAnimation(1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) return;

    final alreadyPresented = _disableAnimations != null;
    _disableAnimations = disableAnimations;
    if (disableAnimations) {
      _disposeControllers();
      _haloOpacity = const AlwaysStoppedAnimation(1);
      _logoOpacity = const AlwaysStoppedAnimation(1);
      _logoScale = const AlwaysStoppedAnimation(1);
      _logoOffset = const AlwaysStoppedAnimation(Offset.zero);
      _titleProgress = const AlwaysStoppedAnimation(1);
      _sloganOpacity = const AlwaysStoppedAnimation(1);
      _sloganOffset = const AlwaysStoppedAnimation(Offset.zero);
      _breath = const AlwaysStoppedAnimation(0);
      _logoBreath = const AlwaysStoppedAnimation(1);
      return;
    }

    final entrance = _entranceController = AnimationController(
      vsync: this,
      duration: _entranceDuration,
      value: alreadyPresented ? 1 : 0,
    );
    final ambient = _ambientController = AnimationController(
      vsync: this,
      duration: _ambientDuration,
    );

    // 0–600 ms: light; 100–760 ms: icon; 280–960 ms: typography;
    // 620–1200 ms: slogan. The text is never driven by the ambient controller.
    _haloOpacity = entrance.drive(
      CurveTween(curve: const Interval(0, 0.5, curve: _revealCurve)),
    );
    _logoOpacity = entrance.drive(
      CurveTween(
        curve: const Interval(100 / 1200, 760 / 1200, curve: _settleCurve),
      ),
    );
    _logoScale = _logoOpacity.drive(Tween(begin: 0.94, end: 1.0));
    _logoOffset = _logoOpacity.drive(
      Tween(begin: const Offset(0, 0.08), end: Offset.zero),
    );
    _titleProgress = entrance.drive(
      CurveTween(
        curve: const Interval(280 / 1200, 960 / 1200, curve: _typeCurve),
      ),
    );
    _sloganOpacity = entrance.drive(
      CurveTween(curve: const Interval(620 / 1200, 1, curve: _revealCurve)),
    );
    _sloganOffset = _sloganOpacity.drive(
      Tween(begin: const Offset(0, 0.24), end: Offset.zero),
    );
    _breath = ambient.drive(CurveTween(curve: const _BreathCurve()));
    _logoBreath = _breath.drive(Tween(begin: 1.0, end: 1.01));
    entrance.addStatusListener(_onEntranceStatus);

    if (alreadyPresented) {
      // Turning Reduce Motion off resumes the atmosphere without hiding text.
      unawaited(ambient.repeat(reverse: true));
    } else {
      unawaited(entrance.forward());
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      unawaited(_ambientController!.repeat(reverse: true));
    }
  }

  void _disposeControllers() {
    _entranceController?.dispose();
    _ambientController?.dispose();
    _entranceController = null;
    _ambientController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titleColor = CupertinoColors.label.resolveFrom(context);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: SizedBox.square(
                        dimension: 232,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: FadeTransition(
                                opacity: _haloOpacity,
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    key: const ValueKey('onboarding-hero-halo'),
                                    painter: _HaloPainter(
                                      isDark: widget.isDark,
                                      breath: _breath,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            FadeTransition(
                              key: const ValueKey(
                                'onboarding-hero-logo-opacity',
                              ),
                              opacity: _logoOpacity,
                              child: SlideTransition(
                                position: _logoOffset,
                                child: ScaleTransition(
                                  scale: _logoScale,
                                  child: ScaleTransition(
                                    key: const ValueKey(
                                      'onboarding-hero-logo-breath',
                                    ),
                                    scale: _logoBreath,
                                    child: RepaintBoundary(
                                      child: ClipRRect(
                                        borderRadius: const BorderRadius.all(
                                          Radius.circular(20),
                                        ),
                                        child: Image.asset(
                                          'assets/branding/hermes-agent-icon-1024.png',
                                          width: 88,
                                          height: 88,
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => _buildFallbackLogo(context),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Semantics(
                  header: true,
                  child: FadeTransition(
                    key: const ValueKey('onboarding-hero-title-opacity'),
                    opacity: _titleProgress,
                    alwaysIncludeSemantics: true,
                    child: AnimatedBuilder(
                      animation: _titleProgress,
                      builder: (context, child) => Text(
                        'Hermes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.5 - 3 * _titleProgress.value,
                          color: titleColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FadeTransition(
                  key: const ValueKey('onboarding-hero-slogan-opacity'),
                  opacity: _sloganOpacity,
                  alwaysIncludeSemantics: true,
                  child: SlideTransition(
                    position: _sloganOffset,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        l10n.onboardingBrandSlogan,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: LightSurfaces.resolve(
                            context,
                            LightSurfaces.textSecondary,
                            dark: secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The logo tile is part of the decorative hero; its black/white H is legible.
  Widget _buildFallbackLogo(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF1C1C1E)
            : const Color(0xFFE5E5EA),
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Text(
          'H',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.bold,
            color: widget.isDark
                ? CupertinoColors.white
                : CupertinoColors.black,
          ),
        ),
      ),
    );
  }
}

/// A half-cosine inhale; reversing it gives a breath with no velocity seams.
class _BreathCurve extends Curve {
  const _BreathCurve();

  @override
  double transformInternal(double t) => (1 - math.cos(math.pi * t)) / 2;
}

// The halo, orbit and guide lines are non-interactive brand decoration.
// Keep their palette and motion independent of readable form surfaces.
class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.isDark, required this.breath})
    : super(repaint: breath) {
    // Cache all drawing resources here; paint only transforms existing geometry.
    // This is Flutter's built-in radial gradient, with no runtime shader asset.
    _glowPaint.shader = ui.Gradient.radial(
      Offset.zero,
      110,
      isDark
          ? const [Color(0x384F6076), Color(0x18546983), Color(0x00546983)]
          : const [Color(0xE6FFFFFF), Color(0x1895A4B9), Color(0x0095A4B9)],
      const [0, 0.55, 1],
    );
    _ringPaint.color = isDark
        ? const Color(0x26CCD4DF)
        : const Color(0x22596879);
    _arcPaint.color = isDark
        ? const Color(0x466F8299)
        : const Color(0x3864788E);
    _guidePaint.color = isDark
        ? const Color(0x405F6C7D)
        : const Color(0x305D626B);
    _accentPaint.color = isDark
        ? const Color(0x998CA4BC)
        : const Color(0x80778CA1);
  }

  final bool isDark;
  final Animation<double> breath;

  static const _orbit = Rect.fromLTRB(-96, -96, 96, 96);
  static const _accentPoint = Offset(66.88, -68.87);
  final _glowPaint = Paint();
  final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  final _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.65;
  final _guidePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.5;
  final _accentPaint = Paint();
  final _registrationMarks = Path()
    ..moveTo(-112, 0)
    ..lineTo(-104, 0)
    ..moveTo(104, 0)
    ..lineTo(112, 0)
    ..moveTo(0, -112)
    ..lineTo(0, -104)
    ..moveTo(0, 104)
    ..lineTo(0, 112);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = breath.value;
    final fit = math.min(size.width, size.height) / 232;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(fit);

    canvas.save();
    canvas.translate(-3 + 6 * phase, -2 * phase);
    canvas.scale(1 + 0.025 * phase);
    canvas.drawCircle(Offset.zero, 110, _glowPaint);
    canvas.restore();

    canvas.drawPath(_registrationMarks, _guidePaint);
    canvas.drawCircle(Offset.zero, 76, _ringPaint);
    canvas.save();
    // A four-degree drift, not a spinning progress indicator.
    canvas.rotate(-0.035 + 0.07 * phase);
    canvas.drawArc(_orbit, -2.6, 1.8, false, _arcPaint);
    canvas.drawArc(_orbit, 0.54, 1.8, false, _arcPaint);
    canvas.drawCircle(_accentPoint, 1.4, _accentPaint);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HaloPainter oldDelegate) =>
      isDark != oldDelegate.isDark || breath != oldDelegate.breath;
}
