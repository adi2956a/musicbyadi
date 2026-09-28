import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'features/offline/offline_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/player/mini_player.dart';
import 'features/playlists/playlists_screen.dart';
import 'features/stream/stream_screen.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MusicByAdiApp()));
}

class MusicByAdiApp extends ConsumerWidget {
  const MusicByAdiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Music by Adi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final authRepo = ref.read(authRepositoryProvider);
    final profile = await authRepo.getMe();
    if (profile != null) {
      ref.read(currentProfileProvider.notifier).state = profile;
    }
    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
      );
    }

    final profile = ref.watch(currentProfileProvider);
    if (profile == null) {
      return OnboardingScreen(
        onComplete: () {
          setState(() {});
        },
      );
    }

    return const MainShell();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({Key? key}) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              StreamScreen(
                onSelectPlaylist: (pl) {
                  setState(() => _currentIndex = 1);
                },
              ),
              const PlaylistsScreen(),
              const OfflineScreen(),
            ],
          ),
          // Shared MiniPlayer pinned directly above bottom navigation
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          backgroundColor: AppColors.bg,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.textDisabled,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.graphic_eq_outlined),
              activeIcon: Icon(Icons.graphic_eq),
              label: 'Stream',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.queue_music_outlined),
              activeIcon: Icon(Icons.queue_music),
              label: 'Playlists',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.offline_pin_outlined),
              activeIcon: Icon(Icons.offline_pin),
              label: 'Offline',
            ),
          ],
          onTap: (index) {
            setState(() => _currentIndex = index);
          },
        ),
      ),
    );
  }
}
