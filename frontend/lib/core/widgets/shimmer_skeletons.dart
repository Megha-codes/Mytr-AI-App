import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

class CardShimmer extends StatelessWidget {
  final double height;
  final double width;
  const CardShimmer({super.key, this.height = 160, this.width = double.infinity});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.borderLight.withValues(alpha: 0.5),
      highlightColor: AppTheme.backgroundWhite,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
      ),
    );
  }
}

class StatTileShimmer extends StatelessWidget {
  const StatTileShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.borderLight.withValues(alpha: 0.5),
      highlightColor: AppTheme.backgroundWhite,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
      ),
    );
  }
}

class ListShimmer extends StatelessWidget {
  final int count;
  const ListShimmer({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CardShimmer(height: 60),
      )),
    );
  }
}
