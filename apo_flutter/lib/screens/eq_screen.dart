import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../game/eq_visualizer_game.dart';
import '../theme/app_theme.dart';

// ── Log-scale helpers (shared by screen + painter) ───────────────────────────
const _fMin  = 20.0;
const _fMax  = 20000.0;
const _maxDb = 15.0;

double freqToX(double freq, double width) {
  final t = (math.log(freq.clamp(_fMin, _fMax)) - math.log(_fMin)) /
      (math.log(_fMax) - math.log(_fMin));
  return t * width;
}

double gainToY(double gain, double height) =>
    height / 2.0 - (gain.clamp(-_maxDb, _maxDb) / _maxDb) * (height / 2.0 - 8);

double xToFreq(double x, double width) {
  final t = (x / width).clamp(0.0, 1.0);
  return math.exp(math.log(_fMin) + t * (math.log(_fMax) - math.log(_fMin)));
}

double yToGain(double y, double height) {
  final gain = (height / 2.0 - y) / (height / 2.0 - 8) * _maxDb;
  return gain.clamp(-_maxDb, _maxDb);
}

// ── Main EQ Screen ───────────────────────────────────────────────────────────

/// Parametric EQ screen.
/// Background: Flame game (spectrum + curve + particles).
/// Overlay: Draggable node widgets.
class EqScreen extends StatefulWidget {
  final AppState state;
  const EqScreen({super.key, required this.state});

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen> {
  // Keep game alive across rebuilds
  late final EqVisualizerGame _game;

  @override
  void initState() {
    super.initState();
    _game = EqVisualizerGame(state: widget.state);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final isLandscape = c.maxWidth > c.maxHeight;
      return isLandscape
          ? _LandscapeEq(state: widget.state, game: _game,
              width: c.maxWidth, height: c.maxHeight)
          : _PortraitEq(state: widget.state, game: _game,
              width: c.maxWidth, height: c.maxHeight);
    });
  }
}

// ── LANDSCAPE ───────────────────────────────────────────────────────────────

class _LandscapeEq extends StatelessWidget {
  final AppState state;
  final EqVisualizerGame game;
  final double width, height;

  const _LandscapeEq({required this.state, required this.game,
      required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    // Leave room for top mode selector (26px) + freq axis (14px)
    final canvasH = (height - 52).clamp(140.0, 260.0);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // dB scale
              _DbScale(height: canvasH),

              // Main parametric EQ column (Mode selector + Canvas + Freq Axis)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Mode selector bar (6 Bands Bus, 10 Bands, 15 Bands)
                    _ModeSelector(state: state),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: canvasH,
                      child: _EqCanvas(state: state, game: game),
                    ),
                    const SizedBox(height: 2),
                    _FreqAxis(state: state, height: 13),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Professional Studio Console Fader (Larger, Skeuomorphic)
              StudioFader(state: state, height: canvasH + 42),
            ],
          ),
        );
      },
    );
  }
}

// ── MODE SELECTOR BAR ────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final AppState state;
  const _ModeSelector({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF090E1B),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF1B283E)),
      ),
      child: Row(
        children: [
          ...EqBandMode.values.map((m) {
            final active = state.bandMode == m;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                state.setBandMode(m);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? AppTheme.cyan.withValues(alpha: 0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: active
                      ? Border.all(color: AppTheme.cyan.withValues(alpha: 0.65), width: 1)
                      : null,
                ),
                child: Text(
                  m.label,
                  style: AppTheme.labelSm.copyWith(
                    fontSize: 8.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? AppTheme.cyan : AppTheme.textMuted,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1829),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF1E2D4A)),
            ),
            child: Text(
              state.bandMode == EqBandMode.bands6
                  ? 'BUSES MUSICALES AMPLIOS'
                  : state.bandMode == EqBandMode.bands10
                      ? '10 BANDAS ISO'
                      : '15 BANDAS ESTUDIO',
              style: AppTheme.monoSm.copyWith(fontSize: 7.5, color: AppTheme.cyanDim),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PORTRAIT ────────────────────────────────────────────────────────────────

class _PortraitEq extends StatelessWidget {
  final AppState state;
  final EqVisualizerGame game;
  final double width, height;

  const _PortraitEq({required this.state, required this.game,
      required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final canvasH = (height * 0.60).clamp(150.0, 300.0);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Column(
          children: [
            _MasterStripHorizontal(state: state),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _ModeSelector(state: state),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  _DbScale(height: canvasH),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(height: canvasH,
                            child: _EqCanvas(state: state, game: game)),
                        _FreqAxis(state: state, height: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── EQ CANVAS (Flame game + draggable nodes) ─────────────────────────────────

class _EqCanvas extends StatefulWidget {
  final AppState state;
  final EqVisualizerGame game;

  const _EqCanvas({required this.state, required this.game});

  @override
  State<_EqCanvas> createState() => _EqCanvasState();
}

class _EqCanvasState extends State<_EqCanvas> {
  int? _draggingIndex;
  Offset? _tooltip;
  double _tooltipFreq = 0;
  double _tooltipGain = 0;

  int? _findNode(Offset pos, Size size) {
    // Generous 46px hit radius for easy finger grabbing on Samsung S23
    const hitRadius = 46.0;
    int? best;
    double bestDist = hitRadius;
    for (int i = 0; i < widget.state.eqBands.length; i++) {
      final band = widget.state.eqBands[i];
      final nx = freqToX(band.frequency, size.width);
      final ny = gainToY(band.gain, size.height);
      final dist = (pos - Offset(nx, ny)).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final maxLeft = math.max(6.0, size.width - 90).toDouble();
          final maxTop = math.max(6.0, size.height - 48).toDouble();
          final tooltipLeft = _tooltip != null ? (_tooltip!.dx - 45).clamp(6.0, maxLeft) : 0.0;
          final tooltipTop = _tooltip != null ? (_tooltip!.dy - 56).clamp(6.0, maxTop) : 0.0;

          return Stack(
            children: [
              // 1. Flame background (IgnorePointer ensures 100% of gestures reach our detector)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: GameWidget(
                    game: widget.game,
                    backgroundBuilder: (_) =>
                        const ColoredBox(color: Color(0xFF080E1A)),
                  ),
                ),
              ),

              // 2. Draggable nodes overlay
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    final idx = _findNode(d.localPosition, size);
                    if (idx != null) {
                      HapticFeedback.selectionClick();
                      widget.state.startInteraction();
                      setState(() {
                        _draggingIndex = idx;
                        _tooltip = d.localPosition;
                        _tooltipFreq = widget.state.eqBands[idx].frequency;
                        _tooltipGain = widget.state.eqBands[idx].gain;
                      });
                    }
                  },
                  onPanUpdate: (d) {
                    if (_draggingIndex == null) return;
                    final x = d.localPosition.dx.clamp(0.0, size.width);
                    final y = d.localPosition.dy.clamp(0.0, size.height);
                    final freq = xToFreq(x, size.width);
                    final gain = yToGain(y, size.height);
                    widget.state.moveBand(_draggingIndex!, freq, gain);
                    setState(() {
                      _tooltip = d.localPosition;
                      _tooltipFreq = freq;
                      _tooltipGain = gain;
                    });
                  },
                  onPanEnd: (_) {
                    widget.state.endInteraction();
                    setState(() {
                      _draggingIndex = null;
                      _tooltip = null;
                    });
                  },
                  onPanCancel: () {
                    widget.state.endInteraction();
                    setState(() {
                      _draggingIndex = null;
                      _tooltip = null;
                    });
                  },
                  onDoubleTapDown: (d) {
                    final idx = _findNode(d.localPosition, size);
                    if (idx != null) {
                      HapticFeedback.mediumImpact();
                      widget.state.moveBand(
                          idx, widget.state.eqBands[idx].frequency, 0.0);
                    }
                  },
                  child: CustomPaint(
                    painter: _NodesPainter(
                      bands: widget.state.eqBands,
                      draggingIndex: _draggingIndex,
                    ),
                  ),
                ),
              ),

              // 3. Tooltip bubble while dragging (clamped within view)
              if (_tooltip != null && _draggingIndex != null)
                Positioned(
                  left: tooltipLeft,
                  top: tooltipTop,
                  child: IgnorePointer(
                    child: _Tooltip(
                      freq: _tooltipFreq,
                      gain: _tooltipGain,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── NODES PAINTER ─────────────────────────────────────────────────────────────

class _NodesPainter extends CustomPainter {
  final List<EqBand> bands;
  final int? draggingIndex;

  const _NodesPainter({required this.bands, this.draggingIndex});

  Color _nodeColor(double gain) {
    if (gain > 0.3) return Color.lerp(AppTheme.cyan, AppTheme.cyanBright, (gain / _maxDb).clamp(0.0, 1.0))!;
    if (gain < -0.3) return Color.lerp(AppTheme.magenta, const Color(0xFFFF66AA), (-gain / _maxDb).clamp(0.0, 1.0))!;
    return AppTheme.textSecondary;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sorted = List<EqBand>.from(bands)
      ..sort((a, b) => a.frequency.compareTo(b.frequency));

    final indexMap = {for (int i = 0; i < bands.length; i++) bands[i]: i};
    final isBusMode = bands.length == 6;

    // First draw guidelines if a node is being dragged
    if (draggingIndex != null && draggingIndex! < bands.length) {
      final activeBand = bands[draggingIndex!];
      final ax = freqToX(activeBand.frequency, size.width);
      final ay = gainToY(activeBand.gain, size.height);
      final guidePaint = Paint()
        ..color = AppTheme.cyan.withValues(alpha: 0.30)
        ..strokeWidth = 1.0;

      // Vertical guideline to frequency axis
      canvas.drawLine(Offset(ax, 0), Offset(ax, size.height), guidePaint);
      // Horizontal guideline to dB scale
      canvas.drawLine(Offset(0, ay), Offset(size.width, ay), guidePaint);
    }

    for (final band in sorted) {
      final origIdx = indexMap[band]!;
      final x = freqToX(band.frequency, size.width);
      final y = gainToY(band.gain, size.height);
      final color = _nodeColor(band.gain);
      final isDragging = draggingIndex == origIdx;
      final radius = isBusMode ? (isDragging ? 13.0 : 9.5) : (isDragging ? 11.0 : 7.5);

      // In 6-Band mode, draw wide translucent bell influence showing that this node affects a wide bus
      if (isBusMode) {
        final busW = isDragging ? 110.0 : 76.0;
        final busH = isDragging ? 46.0 : 30.0;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: busW, height: busH),
          Paint()
            ..color = color.withValues(alpha: isDragging ? 0.35 : 0.12)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDragging ? 12 : 8),
        );

        // Draw pronounced bandwidth bell arch when dragging or gain is significant
        if (isDragging || band.gain.abs() > 0.5) {
          final bellPath = Path();
          final leftX = (x - busW * 0.55).clamp(0.0, size.width);
          final rightX = (x + busW * 0.55).clamp(0.0, size.width);
          final zeroY = gainToY(0, size.height);
          bellPath.moveTo(leftX, zeroY);
          bellPath.quadraticBezierTo(x, y, rightX, zeroY);
          canvas.drawPath(
            bellPath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isDragging ? 2.0 : 1.2
              ..color = color.withValues(alpha: isDragging ? 0.65 : 0.28),
          );
        }
      }

      // Outer glow
      canvas.drawCircle(
        Offset(x, y),
        radius + (isDragging ? 9.0 : 4.0),
        Paint()
          ..color = color.withValues(alpha: isDragging ? 0.45 : 0.15)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDragging ? 8.0 : 4.0),
      );

      // Node background
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = isDragging ? color.withValues(alpha: 0.9) : AppTheme.bgCard,
      );

      // Node border
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isDragging ? 2.8 : 2.0
          ..color = color,
      );

      // Center core point
      canvas.drawCircle(
        Offset(x, y),
        isDragging ? 3.5 : 2.0,
        Paint()..color = isDragging ? Colors.white : color,
      );

      // Vertical line from 0 dB baseline to node
      final zeroY = gainToY(0, size.height);
      if ((y - zeroY).abs() > 3.0) {
        canvas.drawLine(
          Offset(x, math.min(y, zeroY) + (y < zeroY ? radius : -radius)),
          Offset(x, zeroY),
          Paint()
            ..color = color.withValues(alpha: isDragging ? 0.45 : 0.25)
            ..strokeWidth = isDragging ? 1.5 : 1.0,
        );
      }

      // Bus label text (SUB, GRAVES, etc.) for 6-band mode
      if (isBusMode && band.busLabel != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: band.busLabel,
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w800,
              color: isDragging ? Colors.white : color.withValues(alpha: 0.9),
              fontFamily: 'SpaceMono',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final textY = y > size.height / 2 ? y - radius - 11 : y + radius + 3;
        tp.paint(canvas, Offset(x - tp.width / 2, textY));
      }
    }
  }

  @override
  bool shouldRepaint(_NodesPainter old) =>
      old.bands != bands || old.draggingIndex != draggingIndex;
}

// ── TOOLTIP ───────────────────────────────────────────────────────────────────

class _Tooltip extends StatelessWidget {
  final double freq;
  final double gain;

  const _Tooltip({required this.freq, required this.gain});

  String _freqLabel(double f) {
    if (f >= 1000) return '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)} kHz';
    return '${f.round()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    final gainStr = gain == 0
        ? '0.0 dB'
        : '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB';
    final color = gain > 0.3
        ? AppTheme.cyan
        : gain < -0.3
            ? AppTheme.magenta
            : AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_freqLabel(freq),
              style: AppTheme.mono.copyWith(fontSize: 9, color: AppTheme.textPrimary)),
          Text(gainStr,
              style: AppTheme.mono.copyWith(
                  fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── FREQUENCY AXIS ────────────────────────────────────────────────────────────

class _FreqAxis extends StatelessWidget {
  final AppState state;
  final double height;

  const _FreqAxis({required this.state, required this.height});

  @override
  Widget build(BuildContext context) {
    const markers = <double>[20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];

    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        return Stack(
          children: markers.map((f) {
            final x = freqToX(f, c.maxWidth);
            final label = f >= 1000 ? '${(f / 1000).round()}k' : '${f.round()}';
            return Positioned(
              left: x - 12,
              top: 0,
              child: SizedBox(
                width: 24,
                child: Text(label,
                    style: AppTheme.monoSm.copyWith(fontSize: 7),
                    textAlign: TextAlign.center),
              ),
            );
          }).toList(),
        );
      }),
    );
  }
}

// ── dB SCALE ──────────────────────────────────────────────────────────────────

class _DbScale extends StatelessWidget {
  final double height;

  const _DbScale({required this.height});

  @override
  Widget build(BuildContext context) {
    const labels = ['+15', '+10', '+5', '0', '-5', '-10', '-15'];
    return SizedBox(
      width: 24,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels
            .map((l) => Text(l,
                style: AppTheme.monoSm.copyWith(fontSize: 7),
                textAlign: TextAlign.right))
            .toList(),
      ),
    );
  }
}

// ── PROFESSIONAL STUDIO CONSOLE FADER ────────────────────────────────────────

class StudioFader extends StatefulWidget {
  final AppState state;
  final double height;

  const StudioFader({super.key, required this.state, required this.height});

  @override
  State<StudioFader> createState() => _StudioFaderState();
}

class _StudioFaderState extends State<StudioFader> {
  bool _isDragging = false;

  void _updateFromDy(double localY, double usableTravel) {
    if (usableTravel <= 0) return;
    // 0.0 at top (+15 dB), 1.0 at bottom (-15 dB)
    final t = (localY / usableTravel).clamp(0.0, 1.0);
    double gain = 15.0 - t * 30.0;
    // Tactile magnetic snap at 0 dB
    if (gain.abs() < 0.4) {
      gain = 0.0;
    }
    final rounded = double.parse(gain.toStringAsFixed(1));
    if (rounded != widget.state.preamp) {
      widget.state.setPreamp(rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final preamp = widget.state.preamp;
        final preStr = '${preamp >= 0 ? '+' : ''}${preamp.toStringAsFixed(1)} dB';

        return Container(
          width: 68,
          height: widget.height,
          decoration: BoxDecoration(
            color: const Color(0xFF0C1322),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E2D4A), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(2, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          child: Column(
            children: [
              // Header title
              Text(
                'PREAMP',
                style: AppTheme.labelXs.copyWith(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 3),

              // Digital Value Badge
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.state.setPreamp(0.0);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: AppTheme.amber.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    preStr,
                    style: AppTheme.mono.copyWith(
                      fontSize: 8.5,
                      color: AppTheme.amber,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Step +0.5 dB
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.state.setPreamp((preamp + 0.5).clamp(-15.0, 15.0));
                },
                child: Container(
                  width: 32,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF131E33),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF223455)),
                  ),
                  child: const Icon(Icons.add_rounded, size: 14, color: AppTheme.amber),
                ),
              ),

              const SizedBox(height: 4),

              // Fader Track Slot + 3D Knob
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final trackH = c.maxHeight;
                    const knobH = 26.0;
                    const knobW = 54.0;
                    final usableTravel = math.max(1.0, trackH - knobH);
                    final t = ((15.0 - preamp) / 30.0).clamp(0.0, 1.0);
                    final knobTop = t * usableTravel;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (d) {
                        setState(() => _isDragging = true);
                        HapticFeedback.selectionClick();
                        _updateFromDy(d.localPosition.dy - knobH / 2, usableTravel);
                      },
                      onVerticalDragUpdate: (d) {
                        _updateFromDy(d.localPosition.dy - knobH / 2, usableTravel);
                      },
                      onVerticalDragEnd: (_) {
                        setState(() => _isDragging = false);
                      },
                      onVerticalDragCancel: () {
                        setState(() => _isDragging = false);
                      },
                      onTapDown: (d) {
                        HapticFeedback.selectionClick();
                        _updateFromDy(d.localPosition.dy - knobH / 2, usableTravel);
                      },
                      onDoubleTap: () {
                        HapticFeedback.mediumImpact();
                        widget.state.setPreamp(0.0);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Scale Tick Marks (+15, +10, +5, 0 dB, -5, -10, -15)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FaderScalePainter(
                                usableTravel: usableTravel,
                                knobH: knobH,
                              ),
                            ),
                          ),

                          // Central recessed metallic slot
                          Center(
                            child: Container(
                              width: 8,
                              height: trackH,
                              decoration: BoxDecoration(
                                color: const Color(0xFF050811),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF19253B),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 2,
                                  height: math.max(0.0, trackH - 10),
                                  color: const Color(0xFF0F1829),
                                ),
                              ),
                            ),
                          ),

                          // 3D Skeuomorphic Console Knob Cap
                          Positioned(
                            top: knobTop,
                            left: (c.maxWidth - knobW) / 2,
                            child: _FaderKnob(
                              width: knobW,
                              height: knobH,
                              isDragging: _isDragging,
                              isZero: preamp.abs() < 0.25,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 4),

              // Step -0.5 dB
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.state.setPreamp((preamp - 0.5).clamp(-15.0, 15.0));
                },
                child: Container(
                  width: 32,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF131E33),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF223455)),
                  ),
                  child: const Icon(Icons.remove_rounded, size: 14, color: AppTheme.amber),
                ),
              ),

              const SizedBox(height: 4),

              // Global Reset button
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.state.resetEq();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restart_alt_rounded, size: 13, color: AppTheme.textSecondary),
                    const SizedBox(width: 2),
                    Text(
                      'RST',
                      style: AppTheme.labelXs.copyWith(fontSize: 7.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 3D FADER KNOB ────────────────────────────────────────────────────────────

class _FaderKnob extends StatelessWidget {
  final double width;
  final double height;
  final bool isDragging;
  final bool isZero;

  const _FaderKnob({
    required this.width,
    required this.height,
    required this.isDragging,
    required this.isZero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF3B4A62),
            Color(0xFF222D3E),
            Color(0xFF141C2B),
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        border: Border.all(
          color: isDragging
              ? AppTheme.amber
              : isZero
                  ? const Color(0xFF536787)
                  : const Color(0xFF33435C),
          width: isDragging ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          if (isDragging)
            BoxShadow(
              color: AppTheme.amber.withValues(alpha: 0.35),
              blurRadius: 8,
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Horizontal finger grip ridges
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: width * 0.65, height: 1.2, color: const Color(0xFF0D1420)),
              const SizedBox(height: 3),
              Container(width: width * 0.65, height: 1.2, color: const Color(0xFF0D1420)),
              const SizedBox(height: 3),
              Container(width: width * 0.65, height: 1.2, color: const Color(0xFF0D1420)),
            ],
          ),

          // Center indicator stripe
          Container(
            width: width * 0.82,
            height: 2.2,
            decoration: BoxDecoration(
              color: isDragging || isZero ? AppTheme.amber : Colors.white,
              borderRadius: BorderRadius.circular(1),
              boxShadow: [
                BoxShadow(
                  color: (isDragging || isZero ? AppTheme.amber : Colors.white)
                      .withValues(alpha: 0.75),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── FADER SCALE PAINTER ──────────────────────────────────────────────────────

class _FaderScalePainter extends CustomPainter {
  final double usableTravel;
  final double knobH;

  const _FaderScalePainter({required this.usableTravel, required this.knobH});

  @override
  void paint(Canvas canvas, Size size) {
    final topY = knobH / 2;
    final marks = [
      (15.0, '+15', false),
      (10.0, '10', false),
      (5.0, '5', false),
      (0.0, '0', true),
      (-5.0, '-5', false),
      (-10.0, '-10', false),
      (-15.0, '-15', false),
    ];

    final tickPaint = Paint()
      ..color = const Color(0xFF263650)
      ..strokeWidth = 1.0;
    final zeroPaint = Paint()
      ..color = AppTheme.amber.withValues(alpha: 0.85)
      ..strokeWidth = 1.8;

    for (final m in marks) {
      final t = (15.0 - m.$1) / 30.0;
      final y = topY + t * usableTravel;
      final isZero = m.$3;

      // Left tick
      canvas.drawLine(
        Offset(2, y),
        Offset(isZero ? 13 : 8, y),
        isZero ? zeroPaint : tickPaint,
      );

      // Right tick
      canvas.drawLine(
        Offset(size.width - (isZero ? 13 : 8), y),
        Offset(size.width - 2, y),
        isZero ? zeroPaint : tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_FaderScalePainter old) =>
      old.usableTravel != usableTravel || old.knobH != knobH;
}

// ── MASTER STRIP HORIZONTAL (portrait) ───────────────────────────────────────

class _MasterStripHorizontal extends StatelessWidget {
  final AppState state;

  const _MasterStripHorizontal({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final preStr = '${state.preamp >= 0 ? '+' : ''}${state.preamp.toStringAsFixed(1)} dB';

        return Container(
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: AppTheme.cardDecor(),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text('PREAMP', style: AppTheme.labelSm),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => state.setPreamp((state.preamp - 0.5).clamp(-15.0, 15.0)),
                child: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.amber),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: AppTheme.amber,
                    inactiveTrackColor: AppTheme.border,
                    thumbColor: AppTheme.amber,
                    overlayColor: AppTheme.amberDim,
                  ),
                  child: Slider(
                    value: state.preamp.clamp(-15.0, 15.0),
                    min: -15,
                    max: 15,
                    onChanged: state.setPreamp,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => state.setPreamp((state.preamp + 0.5).clamp(-15.0, 15.0)),
                child: const Icon(Icons.add_circle_outline_rounded, size: 18, color: AppTheme.amber),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => state.setPreamp(0.0),
                child: Text(
                  preStr,
                  style: AppTheme.mono.copyWith(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: state.resetEq,
                child: Icon(Icons.restart_alt_rounded,
                    size: 18, color: AppTheme.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}
