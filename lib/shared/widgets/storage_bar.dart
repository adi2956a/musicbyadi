import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StorageBar extends StatelessWidget {
  final int usedBytes;
  final int totalQuotaBytes;

  const StorageBar({
    Key? key,
    required this.usedBytes,
    this.totalQuotaBytes = 5 * 1024 * 1024 * 1024, // 5 GB default cap for offline
  }) : super(key: key);

  String get _formattedUsed {
    final mb = usedBytes / (1024 * 1024);
    if (mb < 1000) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final double fraction = (usedBytes / totalQuotaBytes).clamp(0.01, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$_formattedUsed used',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text(
              'Offline Storage',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Container(
            height: 4,
            width: double.infinity,
            color: AppColors.divider,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}
