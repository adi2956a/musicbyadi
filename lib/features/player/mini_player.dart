import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../shared/theme/app_theme.dart';
import 'expanded_player.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioManagerProvider);
    final currentSong = audio.currentSong;

    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const ExpandedPlayer(),
        );
      },
      child: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: Column(
          children: [
            // Thin progress line
            StreamBuilder<Duration>(
              stream: audio.positionStream,
              builder: (context, posSnap) {
                return StreamBuilder<Duration?>(
                  stream: audio.durationStream,
                  builder: (context, durSnap) {
                    final pos = posSnap.data?.inMilliseconds ?? 0;
                    final dur = durSnap.data?.inMilliseconds ?? 1;
                    final double progress = (dur > 0 ? pos / dur : 0.0).clamp(0.0, 1.0);

                    return LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: AppColors.divider,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                    );
                  },
                );
              },
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Icon / Album art placeholder
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: const Icon(Icons.music_note, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 12),

                    // Title & Artist
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentSong.artist ?? 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Controls
                    IconButton(
                      icon: Icon(
                        audio.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: AppColors.textPrimary,
                        size: 26,
                      ),
                      splashRadius: 20,
                      onPressed: () => audio.togglePlayPause(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                      splashRadius: 20,
                      onPressed: () => audio.playNext(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
