import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../icons/lucide_icons.dart';
import '../../features/profile/providers/user_profile_provider.dart';
import '../../features/home/models/models.dart';
import '../theme/app_theme.dart';
import '../services/connectivity_service.dart';

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final user = userAsync.valueOrNull;
    final networkStatus = ref.watch(connectivityProvider);
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      body: Column(
        children: [
          if (networkStatus == NetworkStatus.offline)
            Material(
              color: AppTheme.glucoseLow,
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.wifiOff, color: Colors.white, size: 14),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Showing last synced data while offline',
                          style: AppTheme.labelSmall.copyWith(color: Colors.white, letterSpacing: 0),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                child,
                // Prominent chatbot entry point (POST /chat, chat_screen.dart)
                // — one shared FAB here (not per-screen) so it's guaranteed
                // identical position/style on every screen MainShell wraps
                // (home/glucose, activity, coach, profile), rather than each
                // screen having to remember to add its own.
                //
                // Bottom-right, above the bottom nav bar (this Stack is
                // `body`, which Scaffold already lays out above
                // bottomNavigationBar) — the conventional spot for a
                // persistent chat entry point. Deliberately NOT top-right:
                // that's where DarkHeader's own trailing row already puts a
                // per-screen chat icon on activity/glucose_screen.dart, and
                // stacking two chat affordances in the same corner would
                // look like a bug, not an upgrade. Clear of the
                // centerDocked camera FAB below (that one's horizontally
                // centered); HomeScreen's own debug-only FAB is moved to
                // startFloat (bottom-left) specifically to stay clear of
                // this one too.
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: _ChatFab(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.backgroundCream,
          border: Border(top: BorderSide(color: AppTheme.borderLight)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: LucideIcons.home,
                  label: 'Home',
                  isSelected: location == '/home',
                  onTap: () => context.go('/home'),
                ),
                // Always Glucose, regardless of user type — it used to swap
                // to Activity for fitness-type users, but Glucose (and its
                // "connect your CGM" empty state for anyone without one
                // connected yet) must always be reachable, per explicit
                // product direction. Activity stays reachable for everyone
                // via the "Health & Activity" link on /glucose instead of
                // needing its own nav slot too.
                _NavItem(
                  icon: LucideIcons.activity,
                  label: 'Glucose',
                  isSelected: location == '/glucose',
                  onTap: () => context.go('/glucose'),
                ),
                const SizedBox(width: 48), // Space for FAB
                _NavItem(
                  icon: LucideIcons.sparkles,
                  label: 'Coach',
                  isSelected: location == '/coach',
                  onTap: () => context.go('/coach'),
                ),
                _NavItem(
                  icon: LucideIcons.user,
                  label: 'Profile',
                  isSelected: location == '/profile',
                  onTap: () => context.go('/profile'),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FloatingActionButton(
          heroTag: 'main_camera_fab',
          elevation: 0,
          backgroundColor: user?.userType == UserType.fitness ? AppTheme.accentOrange : AppTheme.brandGreen,
          shape: const CircleBorder(),
          onPressed: () => context.push('/meals'),
          child: const Icon(LucideIcons.camera, color: Colors.white),
        ),
      ),
    );
  }
}

/// Shared floating entry point into the analytics chatbot (POST /chat,
/// chat_screen.dart) — see MainShell.build for why this lives here once
/// instead of on each screen individually.
class _ChatFab extends StatelessWidget {
  const _ChatFab();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'main_chat_fab',
      elevation: 2,
      backgroundColor: AppTheme.brandPurpleDeep,
      shape: const CircleBorder(),
      onPressed: () => context.push('/chat'),
      tooltip: 'Ask Mytr.AI',
      child: const Icon(LucideIcons.messageSquare, color: Colors.white),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.textPrimary : AppTheme.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(
              color: color,
              fontSize: 9,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
