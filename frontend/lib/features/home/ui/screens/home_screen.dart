import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/progress_widgets.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/api/ws_debug.dart';
import '../../../profile/providers/user_profile_provider.dart';
import '../../providers/providers.dart';
import '../widgets/header_contents.dart';
import '../widgets/body_contents.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundWhite,
      floatingActionButton: kDebugMode 
        ? FloatingActionButton.small(
            heroTag: 'home_debug_fab',
            onPressed: () => _showDebugConsole(context),
            backgroundColor: AppTheme.backgroundDark,
            child: const Icon(Icons.bug_report, color: Colors.white, size: 16),
          )
        : null,
      body: profileAsync.when(
        data: (profile) {
          final isDiabetic = profile.userType == UserType.type1 || profile.userType == UserType.type2;
          return RefreshIndicator(
            color: AppTheme.brandGreen,
            onRefresh: () async {
              ref.invalidate(dashboardProvider);
              ref.invalidate(userProfileProvider);
              // Wait for both to complete so the indicator dismisses cleanly
              await Future.wait([
                ref.read(dashboardProvider.future),
                ref.read(userProfileProvider.future),
              ]).catchError((_) => <Object>[]);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  DarkHeader(
                    eyebrow: _getGreeting(),
                    title: profile.displayName,
                    trailing: LevelBadge(
                      level: profile.currentLevel,
                      title: profile.levelTitle,
                      accentColor: isDiabetic ? AppTheme.brandGreen : AppTheme.accentOrange,
                    ),
                    bottomContent: Column(
                      children: [
                        XPProgressBar(
                          currentXP: profile.currentXP,
                          targetXP: profile.xpToNextLevel,
                        ),
                        const SizedBox(height: 24),
                        if (isDiabetic)
                          const DiabeticHeaderContent()
                        else
                          const FitnessHeaderContent(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.screenPadding),
                    child: isDiabetic
                      ? const DiabeticBodyContent()
                      : const FitnessBodyContent(),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
        loading: () => const _HomeLoadingView(),
        error: (e, st) => Center(
          child: InlineErrorCard(
            message: 'Failed to load dashboard',
            onRetry: () => ref.refresh(userProfileProvider),
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _showDebugConsole(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const WsDebugOverlay(),
    );
  }
}

class _HomeLoadingView extends StatelessWidget {
  const _HomeLoadingView();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        children: [
          CardShimmer(height: 280), // Header shimmer
          Padding(
            padding: EdgeInsets.all(AppTheme.screenPadding),
            child: Column(
              children: [
                CardShimmer(height: 200),
                SizedBox(height: 16),
                CardShimmer(height: 200),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
