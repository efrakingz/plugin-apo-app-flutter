import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';

/// Connection management screen.
/// Shows auto-discovery status, allows manual IP entry,
/// and displays server device information.
class ConnectionScreen extends StatefulWidget {
  final AppState state;

  const ConnectionScreen({super.key, required this.state});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late TextEditingController _ipCtrl;
  late TextEditingController _portCtrl;

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: widget.state.hostIp);
    _portCtrl = TextEditingController(text: '${widget.state.port}');
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final ip = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9876;
    if (ip.isNotEmpty) {
      widget.state.connectTo(ip, port);
      HapticFeedback.mediumImpact();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final isLandscape = c.maxWidth > c.maxHeight;
      return isLandscape
          ? _LandscapeConnection(
              state: widget.state,
              ipCtrl: _ipCtrl,
              portCtrl: _portCtrl,
              onConnect: _connect,
            )
          : _PortraitConnection(
              state: widget.state,
              ipCtrl: _ipCtrl,
              portCtrl: _portCtrl,
              onConnect: _connect,
            );
    });
  }
}

// ── LANDSCAPE ───────────────────────────────────────────────────────────────

class _LandscapeConnection extends StatelessWidget {
  final AppState state;
  final TextEditingController ipCtrl;
  final TextEditingController portCtrl;
  final VoidCallback onConnect;

  const _LandscapeConnection({
    required this.state,
    required this.ipCtrl,
    required this.portCtrl,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(children: [
                  _StatusCard(state: state),
                  const SizedBox(height: 6),
                  Expanded(child: _DiscoveryLogCard(state: state)),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 290,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _ManualConnectCard(
                    state: state,
                    ipCtrl: ipCtrl,
                    portCtrl: portCtrl,
                    onConnect: onConnect,
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

// ── PORTRAIT ────────────────────────────────────────────────────────────────

class _PortraitConnection extends StatelessWidget {
  final AppState state;
  final TextEditingController ipCtrl;
  final TextEditingController portCtrl;
  final VoidCallback onConnect;

  const _PortraitConnection({
    required this.state,
    required this.ipCtrl,
    required this.portCtrl,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        _StatusCard(state: state),
        const SizedBox(height: 8),
        _ManualConnectCard(
          state: state,
          ipCtrl: ipCtrl,
          portCtrl: portCtrl,
          onConnect: onConnect,
        ),
        const SizedBox(height: 8),
        _DiscoveryLogCard(state: state),
      ]),
    );
  }
}

// ── STATUS CARD ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final AppState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final connected = state.isConnected;
    final color = connected ? AppTheme.green : AppTheme.magenta;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: connected
            ? [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 20)]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(
              connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'CONECTADO' : 'DESCONECTADO',
                  style: AppTheme.heading.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                if (connected) ...[
                  Text(
                    '${state.hostIp}:${state.port}',
                    style: AppTheme.mono.copyWith(
                        color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.deviceName,
                    style: AppTheme.labelSm.copyWith(
                        color: AppTheme.textPrimary),
                  ),
                ] else ...[
                  Text(
                    state.connectionLog,
                    style: AppTheme.mono.copyWith(fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
          if (connected)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _InfoBadge(label: '${state.fps} FPS', color: AppTheme.green),
                const SizedBox(height: 4),
                _InfoBadge(
                    label: 'Puerto ${state.port}',
                    color: AppTheme.textSecondary),
              ],
            ),
        ],
      ),
    );
  }
}

// ── MANUAL CONNECT ────────────────────────────────────────────────────────────

class _ManualConnectCard extends StatelessWidget {
  final AppState state;
  final TextEditingController ipCtrl;
  final TextEditingController portCtrl;
  final VoidCallback onConnect;

  const _ManualConnectCard({
    required this.state,
    required this.ipCtrl,
    required this.portCtrl,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: AppTheme.bgSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppTheme.cyan, width: 1.5),
      ),
      labelStyle: AppTheme.labelSm.copyWith(fontSize: 10),
      hintStyle: AppTheme.mono.copyWith(fontSize: 10),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: AppTheme.cardDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.settings_ethernet_rounded,
                  color: AppTheme.cyan, size: 15),
              const SizedBox(width: 6),
              Text('CONEXIÓN MANUAL', style: AppTheme.heading.copyWith(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 6,
                child: TextField(
                  controller: ipCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: AppTheme.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'IP PC',
                    hintText: '192.168.1.9',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: AppTheme.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Puerto',
                    hintText: '9876',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton(
              onPressed: onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                foregroundColor: AppTheme.bgDeep,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: AppTheme.labelSm.copyWith(
                    color: AppTheme.bgDeep, fontSize: 10, fontWeight: FontWeight.w700),
              ),
              child: const Text('CONECTAR AL PC'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Auto-detección activa vía UDP en puerto 9877.',
            style: AppTheme.labelSm.copyWith(
                fontSize: 8, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── DISCOVERY LOG ─────────────────────────────────────────────────────────────

class _DiscoveryLogCard extends StatelessWidget {
  final AppState state;
  const _DiscoveryLogCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecor(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded,
                  color: AppTheme.cyan, size: 14),
              const SizedBox(width: 6),
              Text('AUTO-DETECCIÓN', style: AppTheme.labelSm),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                _LogItem(
                  icon: Icons.broadcast_on_home_rounded,
                  label: 'Beacon UDP',
                  sub: 'Puerto 9877 — escuchando',
                  active: !state.isConnected,
                ),
                const SizedBox(height: 6),
                _LogItem(
                  icon: Icons.search_rounded,
                  label: 'Escaneo de red',
                  sub: 'Subredes comunes cada 2s',
                  active: !state.isConnected,
                ),
                const SizedBox(height: 6),
                _LogItem(
                  icon: Icons.history_rounded,
                  label: 'IP guardada',
                  sub: state.hostIp,
                  active: true,
                ),
                const SizedBox(height: 6),
                _LogItem(
                  icon: Icons.info_outline_rounded,
                  label: 'Estado',
                  sub: state.connectionLog,
                  active: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool active;

  const _LogItem({
    required this.icon,
    required this.label,
    required this.sub,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.cyan : AppTheme.textMuted;
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTheme.labelSm.copyWith(color: AppTheme.textPrimary, fontSize: 9)),
              Text(sub, style: AppTheme.mono.copyWith(fontSize: 8)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTheme.mono.copyWith(fontSize: 8, color: color),
      ),
    );
  }
}
