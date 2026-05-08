import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services/database_service.dart';
import 'screens/home_screen.dart';

import 'screens/sticky_board_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/lock_screen.dart'; 
import 'theme/tokens.dart';
import 'providers/sticky_notes_provider.dart';
import 'widgets/sticky_overlay_layer.dart';
import 'providers/app_launch_watcher.dart';

// ─── GLOBAL STREAM CACHES (Prevents "Bad State" Stream Errors) ─────────────
final Stream<dynamic> sharedOverlayStream = FlutterOverlayWindow.overlayListener.asBroadcastStream();

// ─── CUSTOM CLIPPERS & PAINTERS ─────────────────────────────────────────────
class FoldedCornerClipper extends CustomClipper<Path> {
  final double foldSize;
  FoldedCornerClipper({this.foldSize = 28.0});

  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(foldSize, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, foldSize);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ─── NATIVE OS OVERLAY ENTRY POINT ──────────────────────────────────────────
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent, 
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: const Scaffold(
        backgroundColor: Colors.transparent,
        body: OSFloatingCompanion(),
      ),
    ),
  );
}

class OSFloatingCompanion extends StatefulWidget {
  const OSFloatingCompanion({super.key});

  @override
  State<OSFloatingCompanion> createState() => _OSFloatingCompanionState();
}

class _OSFloatingCompanionState extends State<OSFloatingCompanion> {
  bool _isBubble = true;
  Color _bgColor = const Color(0xFFF5C842);
  String _title = "";
  String _content = "";
  String _id = "";
  
  double _overlayWidth = 300.0;
  double _overlayHeight = 300.0;

  StreamSubscription? _overlaySubscription;

  @override
  void initState() {
    super.initState();
    // Listen to the global shared stream
    _overlaySubscription = sharedOverlayStream.listen((event) {
      if (event.toString().startsWith("note:")) {
        try {
          final data = jsonDecode(event.toString().substring(5));
          setState(() {
            _id = data['id'];
            _title = data['title'];
            _content = data['content'];
            _bgColor = Color(data['color']);
            _isBubble = data['isBubble'];
            _overlayWidth = 300.0; 
            _overlayHeight = 300.0;
          });
          
          if (_isBubble) {
            FlutterOverlayWindow.resizeOverlay(100, 100, true);
          } else {
            FlutterOverlayWindow.resizeOverlay(_overlayWidth.toInt(), _overlayHeight.toInt(), true);
          }
        } catch (e) {
          debugPrint("Overlay Parse Error: $e");
        }
      }
    });
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.none,
        child: _isBubble ? _buildBubble() : _buildExpandedNote(),
      ),
    );
  }

  Widget _buildBubble() {
    return GestureDetector(
      onDoubleTap: () {
        HapticFeedback.mediumImpact(); 
        setState(() => _isBubble = false);
        FlutterOverlayWindow.resizeOverlay(_overlayWidth.toInt(), _overlayHeight.toInt(), true);
      },
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: _bgColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: _bgColor.withValues(alpha: 0.4), blurRadius: 15, spreadRadius: 2),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
        ),
        child: const Center(
          child: Icon(Icons.edit_note_rounded, color: Color(0xFF412402), size: 28),
        ),
      ),
    );
  }

  Widget _buildExpandedNote() {
    const double foldSize = 28.0;

    return Container(
      width: _overlayWidth,
      height: _overlayHeight,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15), 
            blurRadius: 32, 
            offset: const Offset(0, 12)
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipPath(
            clipper: FoldedCornerClipper(foldSize: foldSize),
            child: Container(
              width: _overlayWidth,
              height: _overlayHeight,
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 16.0),
                          child: Icon(Icons.drag_indicator, size: 20, color: Colors.black26),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() => _isBubble = true);
                                FlutterOverlayWindow.resizeOverlay(100, 100, true);
                              },
                              icon: const Icon(Icons.minimize, size: 24, color: Colors.black87),
                              tooltip: 'Minimize to Bubble',
                            ),
                            IconButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                FlutterOverlayWindow.shareData("restore:$_id");
                                FlutterOverlayWindow.closeOverlay();
                              },
                              icon: const Icon(Icons.close, size: 24, color: Colors.black87),
                              tooltip: 'Close & Restore',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_title.isNotEmpty)
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1C1C18),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _content.isNotEmpty ? _content : ' ',
                          style: GoogleFonts.caveat(
                            fontSize: 24, height: 1.2, color: const Color(0xCC1C1C18),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _overlayWidth = (_overlayWidth + details.delta.dx).clamp(250.0, 600.0);
                                _overlayHeight = (_overlayHeight + details.delta.dy).clamp(250.0, 800.0);
                              });
                              FlutterOverlayWindow.resizeOverlay(_overlayWidth.toInt(), _overlayHeight.toInt(), true);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Icon(Icons.drag_indicator_rounded, size: 20, color: Colors.black26),
                              ),
                            ),
                          )
                        ],
                      )
                    )
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: foldSize,
              height: foldSize,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(10), 
                  topLeft: Radius.circular(14),     
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(2, 2),
                  )
                ]
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Theme Mode Provider ──────────────────────────────────────────────────────
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode') ?? 'system';
    state = saved == 'dark'
        ? ThemeMode.dark
        : saved == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final str = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
            ? 'light'
            : 'system';
    await prefs.setString('theme_mode', str);
  }
}

// ─── Entry Point ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications & timezone
  tz.initializeTimeZones();
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await DatabaseService.init();
  runApp(const ProviderScope(child: NoveApp()));
}

class NoveApp extends ConsumerWidget {
  const NoveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'NOVE',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const _AppEntry(),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: NoveColors.cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NoveColors.terracotta,
        brightness: Brightness.light,
        surface: NoveColors.warmWhite,
      ),
      textTheme: GoogleFonts.dmSansTextTheme().copyWith(
        displayLarge: GoogleFonts.lora(),
        displayMedium: GoogleFonts.lora(),
        displaySmall: GoogleFonts.lora(),
        headlineLarge: GoogleFonts.lora(),
        headlineMedium: GoogleFonts.lora(),
        headlineSmall: GoogleFonts.lora(),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NoveColors.cream,
        elevation: 0,
        centerTitle: false,
        foregroundColor: NoveColors.warmGray900,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: NoveColors.terracotta,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NoveColors.warmWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoveRadii.lg),
          borderSide: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NoveColors.warmWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NoveColors.warmGray900,
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NoveColors.deepDark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NoveColors.terracottaLight,
        brightness: Brightness.dark,
        surface: NoveColors.cardDark,
      ),
      textTheme: GoogleFonts.dmSansTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.lora(),
        displayMedium: GoogleFonts.lora(),
        displaySmall: GoogleFonts.lora(),
        headlineLarge: GoogleFonts.lora(),
        headlineMedium: GoogleFonts.lora(),
        headlineSmall: GoogleFonts.lora(),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NoveColors.deepDark,
        elevation: 0,
        centerTitle: false,
        foregroundColor: NoveColors.cream,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: NoveColors.terracottaLight,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NoveColors.cardDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NoveRadii.lg),
          borderSide: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NoveColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NoveColors.warmGray200,
        contentTextStyle: GoogleFonts.dmSans(color: NoveColors.warmGray900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─── App Entry — checks onboarding & wraps in biometric lock ────────────────
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    setState(() => _showOnboarding = !done);
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_showOnboarding == true) {
      return OnboardingScreen(
        onDone: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('onboarding_done', true);
          if (!context.mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LockScreen(child: NoveShell())),
          );
        },
      );
    }
    return const LockScreen(child: NoveShell());
  }
}

// ─── Main Shell ───────────────────────────────────────────────────────────────
class NoveShell extends ConsumerStatefulWidget {
  const NoveShell({super.key});

  @override
  ConsumerState<NoveShell> createState() => _NoveShellState();
}

class _NoveShellState extends ConsumerState<NoveShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const _screens = [
    HomeScreen(),
    StickyBoardScreen(),
    SettingsScreen(),
  ];

  StreamSubscription? _overlaySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Listen to the global shared stream
    _overlaySubscription = sharedOverlayStream.listen((event) {
      if (event.toString().startsWith("restore:")) {
        if (mounted) {
          setState(() => _currentIndex = 1); 
        }
        ref.read(poppedOutNoteProvider.notifier).state = null; 
      }
    });
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel(); 
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      try {
        bool isActive = await FlutterOverlayWindow.isActive();
        if (!isActive) {
          ref.read(poppedOutNoteProvider.notifier).state = null;
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLaunchWatcherProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StickyOverlayLayer( 
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _NoveTabBar(
                currentIndex: _currentIndex,
                onTap: (i) => setState(() => _currentIndex = i),
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Custom Tab Bar ───────────────────────────────────────────────────────────
class _NoveTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  const _NoveTabBar({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _TabItem(icon: Icons.description_outlined, activeIcon: Icons.description, label: 'Notes'),
      _TabItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Board'),
      _TabItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
    ];

    final bgColor = isDark 
        ? NoveColors.cardDark.withValues(alpha: 0.7) 
        : const Color(0xFFFCF9F3).withValues(alpha: 0.85);
    final borderColor = isDark 
        ? NoveColors.warmGray800.withValues(alpha: 0.5) 
        : NoveColors.warmGray200.withValues(alpha: 0.5);
    final inactiveColor = isDark ? NoveColors.warmGray500 : NoveColors.warmGray500;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    final isActive = currentIndex == i;
                    
                    return Expanded(
                      child: Semantics(
                        label: '${item.label} Tab',
                        selected: isActive,
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact(); 
                            onTap(i);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                            duration: NoveAnimation.fast,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            decoration: BoxDecoration(
                              color: isActive ? NoveColors.terracotta : Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isActive ? item.activeIcon : item.icon,
                                  color: isActive ? Colors.white : inactiveColor,
                                  size: 20,
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    item.label,
                                    style: GoogleFonts.dmSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabItem({required this.icon, required this.activeIcon, required this.label});
}