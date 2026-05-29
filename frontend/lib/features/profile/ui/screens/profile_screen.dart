import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/dark_header.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../../core/widgets/state_feedback_widgets.dart';
import '../../providers/user_profile_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/achievements_provider.dart';
import '../../providers/report_provider.dart';
import '../../../home/providers/providers.dart';
import '../widgets/profile_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
// Removed redundant import

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final cgm = ref.watch(cgmProvider);
    final activity = ref.watch(activityProvider);
    final deviceState = ref.watch(deviceProvider);
    final achievementsAsync = ref.watch(achievementsProvider);
    final reportState = ref.watch(reportProvider);

    return userAsync.when(
      data: (user) {
        final isDiabetic = user.userType != UserType.fitness;
        return Scaffold(
          backgroundColor: AppTheme.backgroundCream,
          body: SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(context, ref, user, isDiabetic),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPadding),
                  child: Transform.translate(
                    offset: const Offset(0, -20),
                    child: Column(
                      children: [
                        _buildStatsRow(isDiabetic, activity, cgm, user),
                        const SizedBox(height: 16),
                        _buildHealthSection(context, isDiabetic, user, deviceState),
                        const SizedBox(height: 16),
                        if (isDiabetic) ...[
                          _buildReportsSection(context, ref, reportState),
                          const SizedBox(height: 16),
                        ],
                        achievementsAsync.when(
                          data: (achievements) => _buildAchievementsSection(context, ref, achievements),
                          loading: () => const CardShimmer(height: 180),
                          error: (e, _) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingsSection(context, ref),
                        const SizedBox(height: 40),
                        TextButton(
                          onPressed: () => _showSignOutSheet(context),
                          child: const Text(
                            'Sign out',
                            style: TextStyle(color: AppTheme.glucoseLow, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const _ProfileLoadingView(),
      error: (e, st) => Scaffold(
        body: Center(
          child: InlineErrorCard(
            message: 'Failed to load profile',
            onRetry: () => ref.refresh(userProfileProvider),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, UserProfile user, bool isDiabetic) {
    final themeColor = isDiabetic ? AppTheme.accentCyan : AppTheme.brandGreen;

    return DarkHeader(
      title: 'Profile',
      eyebrow: 'YOUR ACCOUNT',
      eyebrowColor: themeColor,
      bottomContent: Row(
        children: [
          GestureDetector(
            onTap: () => _handleAvatarTap(context, ref),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.brandGreen,
              backgroundImage: user.avatarImageUrl != null ? NetworkImage(user.avatarImageUrl!) : null,
              child: user.avatarImageUrl == null
                  ? Text(
                      user.displayName.isNotEmpty ? user.displayName.substring(0, 1) : 'U',
                      style: AppTheme.displayMedium.copyWith(color: Colors.white),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: AppTheme.displayMedium.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TagPill(
                      label: isDiabetic ? 'TYPE 1' : 'FITNESS',
                      backgroundColor: themeColor.withValues(alpha: 0.2),
                      textColor: themeColor,
                    ),
                    const SizedBox(width: 8),
                    TagPill(
                      label: 'LVL ${user.currentLevel}',
                      backgroundColor: themeColor.withValues(alpha: 0.2),
                      textColor: themeColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isDiabetic, AsyncValue<ActivityState> activityAsync, AsyncValue<CGMState> cgmAsync, UserProfile user) {
    return Row(
      children: [
        const Expanded(
          child: StatTile(
            label: 'Streak',
            value: '12',
            unit: '🔥',
            textColor: AppTheme.accentOrange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: cgmAsync.when(
            data: (cgm) => StatTile(
              label: isDiabetic ? 'Avg TIR' : 'Metabolism',
              value: isDiabetic ? '${cgm.timeInRange24h.toInt()}%' : 'Good',
              textColor: AppTheme.brandGreen,
            ),
            loading: () => const StatTileShimmer(),
            error: (e, s) => const StatTile(label: 'CGM', value: '--', textColor: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: activityAsync.when(
            data: (activity) => StatTile(
              label: isDiabetic ? 'Steps' : 'Daily Goal',
              value: '${activity.stepsToday}',
              textColor: AppTheme.accentCyan,
            ),
            loading: () => const StatTileShimmer(),
            error: (e, s) => const StatTile(label: 'Steps', value: '--', textColor: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthSection(BuildContext context, bool isDiabetic, UserProfile user, DeviceState deviceState) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfileSectionHeader(title: 'Health'),
          if (isDiabetic) ...[
            ProfileRow(
              title: 'Insulin Profile',
              trailing: Text('1:12 ICR', style: AppTheme.labelSmall),
              onTap: () => context.push('/profile/insulin'),
            ),
            const Divider(height: 1),
            ProfileRow(
              title: 'Target glucose range',
              trailing: Text('70–180 mg/dL', style: AppTheme.labelSmall),
              onTap: () => context.push('/profile/glucose-target'),
            ),
            const Divider(height: 1),
            ProfileRow(
              title: 'CGM Device',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(deviceState.connectedCGM?.name ?? 'Not connected', style: AppTheme.labelSmall),
                  if (deviceState.connectedCGM != null) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.circle, size: 8, color: AppTheme.brandGreen),
                  ],
                ],
              ),
              onTap: () => context.push('/profile/devices'),
            ),
          ] else ...[
            ProfileRow(
              title: 'Personal stats',
              trailing: Text('182cm, 78kg', style: AppTheme.labelSmall),
              onTap: () => context.push('/profile/stats-edit'),
            ),
            const Divider(height: 1),
            ProfileRow(
              title: 'Goals',
              trailing: Text(user.primaryGoal, style: AppTheme.labelSmall),
              onTap: () => context.push('/profile/goals'),
            ),
            const Divider(height: 1),
            ProfileRow(
              title: 'Connected devices',
              trailing: Text(
                deviceState.connectedWearables.isNotEmpty ? deviceState.connectedWearables.first.name : 'None connected',
                style: AppTheme.labelSmall,
              ),
              onTap: () => context.push('/profile/devices'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportsSection(BuildContext context, WidgetRef ref, ReportState reportState) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfileSectionHeader(title: 'Reports'),
          ProfileRow(
            title: 'Generate doctor report',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.accentCyanLight, borderRadius: BorderRadius.circular(8)),
              child: Text(reportState.isGenerating ? 'Generating...' : 'PDF →', style: AppTheme.labelSmall.copyWith(color: AppTheme.accentCyan)),
            ),
            onTap: () => ref.read(reportProvider.notifier).generate(),
          ),
          const Divider(height: 1),
          ProfileRow(
            title: 'Share with doctor',
            trailing: Text('Read-only link →', style: AppTheme.labelSmall),
            onTap: () async {
              final link = await ref.read(profileProvider.notifier).generateShareLink();
              debugPrint('Shared link: $link');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection(BuildContext context, WidgetRef ref, AchievementState achievements) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfileSectionHeader(title: 'Achievements'),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: 3, 
            itemBuilder: (context, index) {
              if (index >= achievements.unlockedAchievements.length) {
                final locked = achievements.allAchievements.where((Achievement a) => !a.isUnlocked).toList();
                if (locked.isEmpty) return const SizedBox.shrink();
                return AchievementBadge(achievement: locked[index - achievements.unlockedAchievements.length]);
              }
              return AchievementBadge(achievement: achievements.unlockedAchievements[index]);
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: () => context.push('/profile/achievements'),
              child: Text(
                'See all ${achievements.allAchievements.length} achievements',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.accentCyan, decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProfileSectionHeader(title: 'Settings'),
          ProfileRow(title: 'Notifications', onTap: () => context.push('/profile/notifications')),
          const Divider(height: 1),
          ProfileRow(title: 'Units', onTap: () => context.push('/profile/units')),
          const Divider(height: 1),
          ProfileRow(title: 'Export my data', onTap: () {}),
          const Divider(height: 1),
          ProfileRow(title: 'Privacy & data', onTap: () => context.push('/profile/privacy')),
          const Divider(height: 1),
          ProfileRow(title: 'Help & support', onTap: () {}),
        ],
      ),
    );
  }

  void _handleAvatarTap(BuildContext context, WidgetRef ref) {
    debugPrint('Upload avatar tapped');
  }

  void _showSignOutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to sign out?', style: AppTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.go('/onboarding/intro'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.glucoseLow, foregroundColor: Colors.white),
                child: const Text('Sign out'),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _ProfileLoadingView extends StatelessWidget {
  const _ProfileLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: SingleChildScrollView(
        child: Column(
          children: [
            CardShimmer(height: 250), // Header shimmer
            Padding(
              padding: EdgeInsets.all(AppTheme.screenPadding),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: StatTileShimmer()),
                      SizedBox(width: 12),
                      Expanded(child: StatTileShimmer()),
                      SizedBox(width: 12),
                      Expanded(child: StatTileShimmer()),
                    ],
                  ),
                  SizedBox(height: 24),
                  CardShimmer(height: 200),
                  SizedBox(height: 16),
                  CardShimmer(height: 150),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
