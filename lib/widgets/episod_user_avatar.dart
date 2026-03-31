import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class EpisodUserAvatar extends StatelessWidget {
  final String username;
  final double radius;
  final double fontSize;

  const EpisodUserAvatar({
    super.key,
    required this.username,
    this.radius = 20,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = username.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : "?";

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfaceAlt,
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
