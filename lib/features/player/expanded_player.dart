import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../shared/theme/app_theme.dart';

class ExpandedPlayer extends ConsumerWidget {
  const ExpandedPlayer({Key? key}) : super(key: key);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioManagerProvider);
    final song = audio.currentSong;
    final downloadMgr = ref.watch(downloadManagerProvider);
    final songRepo = ref.watch(songRepositoryProvider);

    if (song == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // Dismiss handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textPrimary, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                'NOW PLAYING',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 48), // Balancing spacer
            ],
          ),

          const Spacer(),

          // Monochrome Artwork Visualizer Box
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      audio.isPlaying ? Icons.graphic_eq : Icons.music_note,
                      size: 64,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      song.r2Key.contains('tracks/') ? 'LOSSLESS AUDIO' : 'DIRECT STREAM',
                      style: const TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),

          // Song Title & Artist
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist ?? 'Unknown Artist',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Scrubber Bar
          StreamBuilder<Duration>(
            stream: audio.positionStream,
            builder: (context, posSnap) {
              final position = posSnap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: audio.durationStream,
                builder: (context, durSnap) {
                  final duration = durSnap.data ?? Duration(seconds: song.durationS ?? 180);
                  final maxMs = duration.inMilliseconds.toDouble();
                  final currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: AppColors.accent,
                          inactiveTrackColor: AppColors.divider,
                          thumbColor: AppColors.accent,
                        ),
                        child: Slider(
                          value: currentMs,
                          min: 0.0,
                          max: maxMs > 0 ? maxMs : 1.0,
                          onChanged: (val) {
                            audio.seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),

          const SizedBox(height: 16),

          // Main Controls Row: Shuffle, Prev, Play/Pause, Next, Loop
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: audio.isShuffling ? AppColors.accent : AppColors.textSecondary,
                  size: 22,
                ),
                onPressed: () => audio.toggleShuffle(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, color: AppColors.textPrimary, size: 32),
                onPressed: () => audio.playPrevious(),
              ),
              GestureDetector(
                onTap: () => audio.togglePlayPause(),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    audio.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: AppColors.bg,
                    size: 32,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: AppColors.textPrimary, size: 32),
                onPressed: () => audio.playNext(),
              ),
              IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: audio.loopMode != LoopMode.off ? AppColors.accent : AppColors.textSecondary,
                  size: 22,
                ),
                onPressed: () => audio.toggleLoop(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Secondary Row: Favorite + Download (distinct from playback controls per §6)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () async {
                  await songRepo.toggleFavorite(song.id);
                  ref.invalidate(songsProvider);
                },
                icon: Icon(
                  song.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: song.isFavorite ? AppColors.accent : AppColors.textSecondary,
                  size: 20,
                ),
                label: Text(
                  song.isFavorite ? 'FAVORITED' : 'FAVORITE',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  downloadMgr.downloadSong(song);
                },
                icon: Icon(
                  song.isDownloaded ? Icons.check_circle_outline : Icons.download_outlined,
                  color: song.isDownloaded ? AppColors.accent : AppColors.textSecondary,
                  size: 20,
                ),
                label: Text(
                  song.isDownloaded ? 'DOWNLOADED' : 'DOWNLOAD',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
