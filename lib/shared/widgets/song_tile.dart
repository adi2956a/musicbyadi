import 'package:flutter/material.dart';
import '../../data/models/song.dart';
import '../theme/app_theme.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isDownloaded;
  final double? downloadProgress;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDownload;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onDelete;

  const SongTile({
    Key? key,
    required this.song,
    required this.isPlaying,
    required this.isDownloaded,
    this.downloadProgress,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onDownload,
    this.onAddToPlaylist,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Playing indicator or index
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isPlaying ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow_outlined,
                size: 18,
                color: isPlaying ? AppColors.bg : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),

            // Title & Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPlaying ? AppColors.textPrimary : AppColors.textPrimary,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• ${song.formattedSize}',
                        style: const TextStyle(
                          color: AppColors.textDisabled,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Actions: Heart + Download (or Delete)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    song.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: song.isFavorite ? AppColors.accent : AppColors.textSecondary,
                  ),
                  splashRadius: 18,
                  onPressed: onToggleFavorite,
                ),
                if (onAddToPlaylist != null)
                  IconButton(
                    icon: const Icon(Icons.playlist_add, size: 20, color: AppColors.textSecondary),
                    splashRadius: 18,
                    onPressed: onAddToPlaylist,
                  ),
                if (downloadProgress != null)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: downloadProgress! > 0 ? downloadProgress : null,
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                else if (isDownloaded)
                  onDelete != null
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textSecondary),
                          splashRadius: 18,
                          onPressed: onDelete,
                        )
                      : const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(Icons.check_circle_outline, size: 18, color: AppColors.accent),
                        )
                else
                  IconButton(
                    icon: const Icon(Icons.download_outlined, size: 18, color: AppColors.textSecondary),
                    splashRadius: 18,
                    onPressed: onDownload,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
