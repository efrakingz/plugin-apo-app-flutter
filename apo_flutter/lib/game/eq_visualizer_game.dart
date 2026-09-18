import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';
import '../../app_state.dart';
import '../../theme/app_theme.dart';

/// Flame game for the EQ visualizer background.
/// Renders: ambient particles + spectrum bars + EQ response curve.
/// The game instance is kept alive in a StatefulWidget to avoid re-creation.
class EqVisualizerGame extends FlameGame {
  final AppState state;

  EqVisualizerGame({required this.state});

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    await addAll([
      _AmbientParticlesComponent(),
      _SpectrumComponent(state: state),
      _EqCurveComponent(state: state),
    ]);
  }
}

// ── SPECTRUM BARS ────────────────────────────────────────────────────────────

class _SpectrumComponent extends Component
    with HasGameReference<EqVisualizerGame> {
  final AppState state;
  final _barPaint  = Paint()..style = PaintingStyle.fill;
  final _peakPaint = Paint()..style = PaintingStyle.fill;

  _SpectrumComponent({required this.state});

  @override
  void render(Canvas canvas) {
    final size = game.size;
    final n = state.spectrum.length;
    if (n == 0) return;

    final barW = size.x / n;
    // Spectrum inputs are 0..100 from Python.
    // Boost and apply power law so low-to-mid signals rise high into the canvas.
    final maxH = size.y * 0.85;

    for (int i = 0; i < n; i++) {
      final rawVal = state.spectrum[i].clamp(0, 100) / 100.0;
      final val = (math.pow(rawVal, 0.7) * 1.35).clamp(0.0, 1.0);
      final peakRaw = state.spectrumPeaks[i].clamp(0, 100) / 100.0;
      final peakVal = (math.pow(peakRaw, 0.7) * 1.35).clamp(0.0, 1.0);

      final barH = math.max(1.5, val * maxH);
      final peakH = peakVal * maxH;
      final x = i * barW;

      // Rich gradient from dark teal to electric cyan to magenta at top peaks
      _barPaint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppTheme.cyanDim.withValues(alpha: 0.15 + val * 0.25),
          AppTheme.cyan.withValues(alpha: 0.35 + val * 0.45),
          AppTheme.magenta.withValues(alpha: 0.45 + val * 0.50),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(x, size.y - barH, barW, barH));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 0.5, size.y - barH, math.max(1.0, barW - 1.5), barH),
          const Radius.circular(2.0),
        ),
        _barPaint,
      );

      if (peakH > 3) {
        canvas.drawRect(
          Rect.fromLTWH(x + 0.5, size.y - peakH - 1.5, math.max(1.0, barW - 1.5), 1.8),
          _peakPaint..color = AppTheme.cyanBright.withValues(alpha: 0.75),
        );
      }
    }
  }
}

// ── EQ CURVE ─────────────────────────────────────────────────────────────────

class _EqCurveComponent extends Component
    with HasGameReference<EqVisualizerGame> {
  final AppState state;

  _EqCurveComponent({required this.state});

  static const _fMin   = 20.0;
  static const _fMax   = 20000.0;
  static const _maxDb  = 15.0;

  double _fx(double freq, double width) {
    final t = (math.log(freq) - math.log(_fMin)) /
        (math.log(_fMax) - math.log(_fMin));
    return t * width;
  }

  double _gy(double gain, double height) =>
      height / 2.0 - (gain / _maxDb) * (height / 2.0 - 10);

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;

    final path = Path();
    if (state.bandMode == EqBandMode.bands6) {
      // High-resolution rendering of broad musical bus curves
      const numPts = 60;
      final p0Gain = state.calculateBusGainAt(_fMin);
      path.moveTo(0, _gy(p0Gain, h));
      for (int i = 1; i <= numPts; i++) {
        final t = i / numPts;
        final freq = math.exp(math.log(_fMin) + t * (math.log(_fMax) - math.log(_fMin)));
        final gain = state.calculateBusGainAt(freq);
        final x = t * w;
        final y = _gy(gain, h);
        path.lineTo(x, y);
      }
    } else {
      final sorted = List<EqBand>.from(state.eqBands)
        ..sort((a, b) => a.frequency.compareTo(b.frequency));

      final points = <Offset>[
        Offset(-w * 0.04, h / 2),
        ...sorted.map((b) => Offset(_fx(b.frequency, w), _gy(b.gain, h))),
        Offset(w * 1.04, h / 2),
      ];

      path.moveTo(points[0].dx, points[0].dy);
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[math.max(0, i - 1)];
        final p1 = points[i];
        final p2 = points[i + 1];
        final p3 = points[math.min(points.length - 1, i + 2)];
        path.cubicTo(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
          p2.dx, p2.dy,
        );
      }
    }

    // Fill below curve
    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fillPath, Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.cyan.withValues(alpha: 0.12),
          AppTheme.cyan.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // Glow
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
      ..shader = LinearGradient(
        colors: [AppTheme.magenta, AppTheme.cyan, AppTheme.green],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // Sharp line
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = LinearGradient(
        colors: [AppTheme.magenta, AppTheme.cyan, AppTheme.green],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // 0 dB line
    final cy = _gy(0, h);
    canvas.drawLine(Offset(0, cy), Offset(w, cy),
        Paint()..color = AppTheme.textMuted.withValues(alpha: 0.35)..strokeWidth = 0.5);

    // ±5, ±10 dB grid
    for (final db in [-10.0, -5.0, 5.0, 10.0]) {
      final y = _gy(db, h);
      canvas.drawLine(Offset(0, y), Offset(w, y),
          Paint()..color = AppTheme.border.withValues(alpha: 0.4)..strokeWidth = 0.5);
    }
  }
}

// ── AMBIENT PARTICLES ─────────────────────────────────────────────────────────

class _AmbientParticlesComponent extends Component
    with HasGameReference<EqVisualizerGame> {
  final _rng = math.Random();
  final _particles = <_Particle>[];
  static const _count = 24;

  @override
  Future<void> onLoad() async {
    for (int i = 0; i < _count; i++) {
      _particles.add(_Particle(rng: _rng));
    }
  }

  @override
  void update(double dt) {
    for (final p in _particles) {
      p.update(dt, game.size);
    }
  }

  @override
  void render(Canvas canvas) {
    for (final p in _particles) {
      p.render(canvas);
    }
  }
}

class _Particle {
  final math.Random rng;
  late double x, y, vx, vy, size, opacity, maxOpacity;
  late Color color;

  _Particle({required this.rng}) {
    _init(Vector2(800, 400));
  }

  void _init(Vector2 s) {
    x = rng.nextDouble() * s.x;
    y = s.y + rng.nextDouble() * 20;
    vx = (rng.nextDouble() - 0.5) * 10;
    vy = -(rng.nextDouble() * 14 + 4);
    size = rng.nextDouble() * 2 + 0.5;
    maxOpacity = rng.nextDouble() * 0.3 + 0.04;
    opacity = 0;
    color = rng.nextBool() ? AppTheme.cyan : AppTheme.magenta;
  }

  void update(double dt, Vector2 size) {
    x += vx * dt;
    y += vy * dt;
    opacity = (opacity + dt * 0.5).clamp(0.0, maxOpacity);
    if (y < -10 || x < -20 || x > size.x + 20) _init(size);
  }

  void render(Canvas canvas) {
    canvas.drawCircle(Offset(x, y), size,
        Paint()..color = color.withValues(alpha: opacity));
  }
}
