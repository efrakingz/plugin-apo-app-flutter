import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'theme/app_theme.dart';
import 'screens/eq_screen.dart';
import 'screens/connection_screen.dart';
import 'widgets/header_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force landscape orientation (studio console mode)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Immersive dark UI
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF05070F),
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(ApoRemoteApp());
}

class ApoRemoteApp extends StatelessWidget {
  // Single global AppState instance
  final AppState _state = AppState();

  ApoRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APO Remote Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: HomeShell(state: _state),
    );
  }
}

/// Root shell with navigation bar and screen switcher.
class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  int _tab = 0;
  late AnimationController _bgAnim;

  @override
  void initState() {
    super.initState();
    _bgAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgAnim.dispose();
    super.dispose();
  }

  static const _tabs = [
    (Icons.graphic_eq_rounded, Icons.graphic_eq_rounded, 'ECUALIZADOR'),
    (Icons.wifi_find_rounded, Icons.wifi_rounded, 'CONEXIÓN'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Stack(
        children: [
          // Animated ambient background
          AnimatedBuilder(
            animation: _bgAnim,
            builder: (context, _) {
              final t = _bgAnim.value;
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      -0.5 + t * 0.3,
                      -0.6 - t * 0.2,
                    ),
                    radius: 1.4 + t * 0.3,
                    colors: const [
                      Color(0x1400EEFF),
                      Color(0x05FF0090),
                      Color(0xFF05070F),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Status header
                HeaderBar(state: widget.state),

                // Screen content
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      EqScreen(state: widget.state),
                      ConnectionScreen(state: widget.state),
                    ],
                  ),
                ),

                // Navigation bar
                _NavBar(
                  selected: _tab,
                  tabs: _tabs,
                  onSelect: (i) => setState(() => _tab = i),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── NAVIGATION BAR ────────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  final int selected;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onSelect;

  const _NavBar({
    required this.selected,
    required this.tabs,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = selected == i;
          final (inactiveIcon, activeIcon, label) = tabs[i];

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(i);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.cyan.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isActive
                      ? Border.all(
                          color: AppTheme.cyan.withValues(alpha: 0.25),
                          width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        isActive ? activeIcon : inactiveIcon,
                        key: ValueKey(isActive),
                        size: 16,
                        color:
                            isActive ? AppTheme.cyan : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: AppTheme.labelSm.copyWith(
                        fontSize: 9,
                        color: isActive
                            ? AppTheme.cyan
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
