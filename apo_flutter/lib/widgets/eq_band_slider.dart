import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// A custom vertical slider for a single EQ band.
/// Supports -[maxDb] to +[maxDb] dB range with drag gesture.
class EqBandSlider extends StatefulWidget {
  final String frequency;
  final double gain;
  final double maxDb;
  final double sliderHeight;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;

  const EqBandSlider({
    super.key,
    required this.frequency,
    required this.gain,
    required this.onChanged,
    this.maxDb = 15.0,
    this.sliderHeight = 160.0,
    this.onChangeEnd,
  });

  @override
  State<EqBandSlider> createState() => _EqBandSliderState();
}

class _EqBandSliderState extends State<EqBandSlider>
    with SingleTickerProviderStateMixin {
  bool _dragging = false;
  late AnimationController _glowAnim;
  late Animation<double> _glowVal;

  @override
  void initState() {
    super.initState();
    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _glowVal = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _glowAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _glowAnim.dispose();
    super.dispose();
  }

  double _clampGain(double g) => g.clamp(-widget.maxDb, widget.maxDb);

  double _gainToFrac(double gain) =>
      0.5 - gain / (2 * widget.maxDb); // 0=top, 1=bottom

  double _fracToGain(double frac) =>
      _clampGain((0.5 - frac) * 2 * widget.maxDb);

  String _freqLabel(String f) {
    final hz = int.tryParse(f) ?? 0;
    if (hz >= 1000) return '${hz ~/ 1000}k';
    return f;
  }

  Color get _thumbColor {
    if (widget.gain > 0.5) {
      return Color.lerp(AppTheme.cyan, AppTheme.cyanBright,
          widget.gain / widget.maxDb)!;
    } else if (widget.gain < -0.5) {
      return Color.lerp(AppTheme.magenta, const Color(0xFFFF66AA),
          -widget.gain / widget.maxDb)!;
    }
    return AppTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final slotH = widget.sliderHeight;
    final thumbY = _gainToFrac(widget.gain) * slotH;
    final zeroY = slotH / 2;

    return GestureDetector(
      onVerticalDragStart: (_) {
        setState(() => _dragging = true);
        _glowAnim.forward();
        HapticFeedback.selectionClick();
      },
      onVerticalDragUpdate: (d) {
        final newGain = _fracToGain(
          _gainToFrac(widget.gain) + d.delta.dy / slotH,
        );
        // Snap to 0 dB near center
        final snapped = newGain.abs() < 0.4 ? 0.0 : newGain;
        widget.onChanged(double.parse(snapped.toStringAsFixed(1)));
      },
      onVerticalDragEnd: (_) {
        setState(() => _dragging = false);
        _glowAnim.reverse();
        widget.onChangeEnd?.call();
      },
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        widget.onChanged(0.0);
        widget.onChangeEnd?.call();
      },
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // dB value label
            SizedBox(
              height: 18,
              child: Text(
                widget.gain == 0
                    ? '0'
                    : '${widget.gain > 0 ? '+' : ''}${widget.gain.toStringAsFixed(1)}',
                style: AppTheme.mono.copyWith(
                  fontSize: 8,
                  color: _thumbColor,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            // Slider track area
            AnimatedBuilder(
              animation: _glowVal,
              builder: (context, child) {
                return SizedBox(
                  height: slotH,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Track line
                      Positioned(
                        left: 20,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: AppTheme.border,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      // Filled segment between 0dB and thumb
                      Positioned(
                        left: 19,
                        top: widget.gain >= 0 ? thumbY : zeroY,
                        height: (thumbY - zeroY).abs().clamp(0, slotH),
                        child: Container(
                          width: 4,
                          decoration: BoxDecoration(
                            color: _thumbColor.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 0 dB tick mark
                      Positioned(
                        top: zeroY - 1,
                        left: 14,
                        child: Container(
                          width: 14,
                          height: 1,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      // ±5 dB ticks
                      for (final db in [-10.0, -5.0, 5.0, 10.0])
                        Positioned(
                          top: _gainToFrac(db) * slotH - 0.5,
                          left: 16,
                          child: Container(
                            width: 8,
                            height: 0.5,
                            color: AppTheme.textMuted.withValues(alpha: 0.4),
                          ),
                        ),
                      // Thumb
                      Positioned(
                        top: thumbY - 8,
                        left: 20 - 8,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.bgCard,
                            border: Border.all(
                              color: _thumbColor,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _thumbColor.withValues(
                                    alpha: 0.3 + _glowVal.value * 0.5),
                                blurRadius: 8 + _glowVal.value * 12,
                                spreadRadius: _dragging ? 2 : 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // Frequency label
            const SizedBox(height: 4),
            Text(
              _freqLabel(widget.frequency),
              style: AppTheme.labelXs.copyWith(
                color: _dragging ? _thumbColor : AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
