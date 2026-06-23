import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../icons/lucide_icons.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import '../theme/app_theme.dart';

class MainShellScreen extends StatelessWidget {
  const MainShellScreen({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: CurvedNavigationBar(
        index: currentIndex,
        height: 60.0,
        items: <Widget>[
          Icon(LucideIcons.home, size: 28, color: currentIndex == 0 ? AppTheme.brandPurple : Colors.white.withValues(alpha: 0.5)),
          Icon(LucideIcons.activity, size: 28, color: currentIndex == 1 ? AppTheme.brandPurple : Colors.white.withValues(alpha: 0.5)),
          Icon(LucideIcons.camera, size: 32, color: currentIndex == 2 ? AppTheme.brandPurple : Colors.white.withValues(alpha: 0.5)),
          Icon(LucideIcons.messageSquare, size: 28, color: currentIndex == 3 ? AppTheme.brandPurple : Colors.white.withValues(alpha: 0.5)),
          Icon(LucideIcons.user, size: 28, color: currentIndex == 4 ? AppTheme.brandPurple : Colors.white.withValues(alpha: 0.5)),
        ],
        color: AppTheme.backgroundDark,
        buttonBackgroundColor: AppTheme.backgroundDark2,
        backgroundColor: AppTheme.backgroundWhite,
        animationCurve: Curves.easeInOut,
        animationDuration: const Duration(milliseconds: 300),
        onTap: _goBranch,
        letIndexChange: (index) => true,
      ),
    );
  }
}
