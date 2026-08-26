import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DarkHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Color? eyebrowColor;
  final Widget? trailing;
  final Widget? bottomContent;

  const DarkHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.eyebrowColor,
    this.trailing,
    this.bottomContent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.backgroundDark,
      padding: EdgeInsets.fromLTRB(
        AppTheme.screenPadding,
        MediaQuery.of(context).padding.top + 20,
        AppTheme.screenPadding,
        30,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          eyebrow?.toUpperCase() ?? '',
                          style: AppTheme.labelSmall.copyWith(
                            color: eyebrowColor ?? AppTheme.textOnDarkMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // title is often user-generated (e.g. home_screen.dart
                    // passes the signed-in user's own display name) — capped
                    // to keep this header's height predictable regardless of
                    // trailing's own layout (a LevelBadge/icon row that
                    // doesn't grow with a wrapped multi-line title).
                    Text(
                      title,
                      style: AppTheme.titleMedium.copyWith(color: AppTheme.textOnDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle ?? '',
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textOnDarkMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          if (bottomContent != null) ...[
            const SizedBox(height: 24),
            bottomContent ?? const SizedBox.shrink(),
          ],
        ],
      ),
    );
  }
}

