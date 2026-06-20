import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../icons/lucide_icons.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import '../app_colors.dart';

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
          Icon(LucideIcons.home, size: 28, color: currentIndex == 0 ? AppColors.limeAccent : Colors.white),
          Icon(LucideIcons.activity, size: 28, color: currentIndex == 1 ? AppColors.limeAccent : Colors.white),
          Icon(LucideIcons.camera, size: 32, color: currentIndex == 2 ? AppColors.limeAccent : Colors.white),
          Icon(LucideIcons.messageSquare, size: 28, color: currentIndex == 3 ? AppColors.limeAccent : Colors.white),
          Icon(LucideIcons.user, size: 28, color: currentIndex == 4 ? AppColors.limeAccent : Colors.white),
        ],
        color: AppColors.nearBlack, // The color of the bar itself
        buttonBackgroundColor: AppColors.nearBlack, // The color of the floating button
        backgroundColor: AppColors.sageGreen, // Reverting to the sage green background to match scaffold
        animationCurve: Curves.easeInOut,
        animationDuration: const Duration(milliseconds: 300),
        onTap: (index) {
          _goBranch(index);
        },
        letIndexChange: (index) => true,
      ),
    );
  }
}
