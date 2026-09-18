import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Paints a real-time spectrum analyzer as a translucent background layer.
/// Draws 64 frequency bars with peak indicators.
class SpectrumPainter extends CustomPainter {
  final List<int> spectrum;
  final List<int> peaks;
  final bool mirror; // mirror symmetry for aesthetic

  const SpectrumPainter({
    required this.spectrum,
    required this.peaks,
    this.mirror = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = spectrum.length;
    if (n == 0) return;

    final barWidth = size.width / n;

    // Gradient shader for bars
    final barPaint = Paint()..style = PaintingStyle.fill;
    final peakPaint = Paint()
      ..color = AppTheme.cyan.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final val = (spectrum[i].clamp(0, 255)) / 255.0;
      final peakVal = (peaks[i].clamp(0, 255)) / 255.0;

      final x = i * barWidth;
      final barH = val * size.height;
      final peakH = peakVal * size.height;

      // Colour shifts from green (low amp) → cyan → magenta (high amp)
      final t = val;
      final barColor = Color.lerp(
        const Color(0xFF00FFB2),
        const Color(0xFF00EEFF),
        t,
      )!.withValues(alpha: 0.18 + t * 0.22);

      barPaint.color = barColor;

      // Bar rect
      canvas.drawRect(
        Rect.fromLTWH(x + 1, size.height - barH, barWidth - 2, barH),
        barPaint,
      );

      // Peak dot
      if (peakH > 4) {
        canvas.drawRect(
          Rect.fromLTWH(
              x + 1, size.height - peakH - 1, barWidth - 2, 1.5),
          peakPaint..color =
              AppTheme.cyan.withValues(alpha: 0.35),
        );
      }
    }
  }

  @override
  bool shouldRepaint(SpectrumPainter old) =>
      old.spectrum != spectrum || old.peaks != peaks;
}

/// Paints the EQ frequency response curve over the spectrum background.
/// Uses the 15 band gain values to draw a smooth Catmull-Rom spline.
class EqCurvePainter extends CustomPainter {
  final Map<String, double> bands;
  final List<String> frequencies;
  final double maxGainDb;

  const EqCurvePainter({
    required this.bands,
    required this.frequencies,
    this.maxGainDb = 15.0,
  });

  /// Maps a frequency (Hz) to a normalised X position using log10 scale.
  double _freqToX(double freq, double width) {
    const fMin = 20.0;
    const fMax = 20000.0;
    final t = (math.log(freq) - math.log(fMin)) /
        (math.log(fMax) - math.log(fMin));
    return t * width;
  }

  /// Maps a gain (dB) to a Y position.
  double _gainToY(double gain, double height) {
    // 0 dB = center line
    return height / 2.0 - (gain / maxGainDb) * (height / 2.0 - 6);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (frequencies.isEmpty) return;

    final points = <Offset>[];
    for (final freq in frequencies) {
      final f = double.tryParse(freq) ?? 0;
      final gain = bands[freq] ?? 0.0;
      points.add(Offset(
        _freqToX(f, size.width),
        _gainToY(gain, size.height),
      ));
    }

    // Extend with virtual start/end points
    final all = <Offset>[
      Offset(-size.width * 0.05, size.height / 2),
      ...points,
      Offset(size.width * 1.05, size.height / 2),
    ];

    // Build smooth Catmull-Rom path
    final path = Path();
    path.moveTo(all[0].dx, all[0].dy);

    for (int i = 0; i < all.length - 1; i++) {
      final p0 = all[math.max(0, i - 1)];
      final p1 = all[i];
      final p2 = all[i + 1];
      final p3 = all[math.min(all.length - 1, i + 2)];

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    // Fill path (gradient above/below center line)
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.cyan.withValues(alpha: 0.18),
          AppTheme.cyan.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Negative fill (below center)
    final negFillPath = Path();
    negFillPath.moveTo(0, size.height / 2);
    negFillPath.lineTo(size.width, size.height / 2);
    negFillPath.lineTo(size.width, size.height);
    negFillPath.lineTo(0, size.height);
    negFillPath.close();

    // Glow stroke
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..shader = LinearGradient(
        colors: [
          AppTheme.magenta.withValues(alpha: 0.5),
          AppTheme.cyan.withValues(alpha: 0.8),
          AppTheme.green.withValues(alpha: 0.5),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, glowPaint);

    // Sharp stroke
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = LinearGradient(
        colors: [AppTheme.magenta, AppTheme.cyan, AppTheme.green],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, linePaint);

    // Center 0 dB line
    final centerY = _gainToY(0, size.height);
    final gridPaint = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), gridPaint);

    // dB grid lines at ±5, ±10
    for (final db in [-10.0, -5.0, 5.0, 10.0]) {
      final y = _gainToY(db, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()
            ..color = AppTheme.border.withValues(alpha: 0.6)
            ..strokeWidth = 0.5);
    }
  }

  @override
  bool shouldRepaint(EqCurvePainter old) =>
      old.bands != bands || old.frequencies != frequencies;
}
