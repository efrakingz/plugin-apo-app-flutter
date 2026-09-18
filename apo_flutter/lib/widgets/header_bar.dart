import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';

/// Top status bar showing connection status, device name, FPS and bypass toggle.
class HeaderBar extends StatelessWidget {
  final AppState state;

  const HeaderBar({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final connected = state.isConnected;
        final dotColor = connected ? AppTheme.green : AppTheme.magenta;

        return Container(
          height: 38,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: connected ? AppTheme.borderGlow : AppTheme.magentaDim,
              width: 1,
            ),
          ),
          child: Row(
        children: [
          // Status dot
          _PulseDot(color: dotColor, active: state.isSearching && !connected),
          const SizedBox(width: 8),

          // Status text
          Text(
            connected ? 'EN LÍNEA' : 'BUSCANDO...',
            style: AppTheme.labelSm.copyWith(
              color: dotColor,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 10),

          // Device name
          Expanded(
            child: Text(
              connected ? state.deviceName : state.connectionLog,
              style: AppTheme.mono.copyWith(fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // FPS badge
          if (connected) ...[
            _Badge(
              label: '${state.fps} FPS',
              color: AppTheme.green,
            ),
            const SizedBox(width: 8),
          ],

          // BYPASS toggle
          GestureDetector(
            onTap: () => state.setBypass(!state.bypass),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: state.bypass
                    ? AppTheme.magentaDim
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: state.bypass ? AppTheme.magenta : AppTheme.border,
                ),
              ),
              child: Text(
                'BYPASS',
                style: AppTheme.labelSm.copyWith(
                  color: state.bypass ? AppTheme.magenta : AppTheme.textMuted,
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: AppTheme.mono.copyWith(
          fontSize: 8,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Animated pulsing dot (used for "searching" state).
class _PulseDot extends StatefulWidget {
  final Color color;
  final bool active;

  const _PulseDot({required this.color, required this.active});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final opacity = widget.active ? _anim.value : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: opacity),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: opacity * 0.6),
                blurRadius: 6,
              ),
            ],
          ),
        );
      },
    );
  }
}
