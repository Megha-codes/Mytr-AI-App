import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
                      Text(
                        'Showing last synced data while offline',
                        style: AppTheme.labelSmall.copyWith(color: Colors.white, letterSpacing: 0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: child),
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
                if (user?.userType == UserType.fitness)
                  _NavItem(
                    icon: LucideIcons.zap,
                    label: 'Activity',
                    isSelected: location == '/activity',
                    onTap: () => context.go('/activity'),
                  )
                else
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
