import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/playlist.dart';
import '../../data/models/song.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/search_bar_inline.dart';
import '../../shared/widgets/song_tile.dart';
import '../settings/settings_screen.dart';

class StreamScreen extends ConsumerStatefulWidget {
  final Function(Playlist playlist)? onSelectPlaylist;

  const StreamScreen({Key? key, this.onSelectPlaylist}) : super(key: key);

  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  String _searchQuery = '';

  void _showUploadBottomSheet(BuildContext context) {
    final titleController = TextEditingController();
    final artistController = TextEditingController();
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'UPLOAD AUDIO TRACK',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Track Title',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: artistController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Artist / Producer',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isUploading
                    ? null
                    : () async {
                        if (titleController.text.trim().isEmpty) return;
                        setModalState(() => isUploading = true);

                        try {
                          final songRepo = ref.read(songRepositoryProvider);
                          await songRepo.uploadSong(
                            title: titleController.text.trim(),
                            artist: artistController.text.trim(),
                            durationS: 180,
                            sizeBytes: 4200000,
                          );
                          ref.invalidate(songsProvider);
                          if (mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setModalState(() => isUploading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg),
                      )
                    : const Text('Add to Library', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  void _showAddToPlaylistBottomSheet(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final playlistsAsync = ref.watch(playlistsProvider);
        final playlistRepo = ref.read(playlistRepositoryProvider);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ADD TO PLAYLIST',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Track: ${song.title}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              playlistsAsync.when(
                data: (playlists) {
                  if (playlists.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No playlists created yet.', style: TextStyle(color: AppColors.textDisabled, fontSize: 13)),
                    );
                  }
                  return Column(
                    children: playlists.map((pl) {
                      final alreadyIn = pl.songs.any((s) => s.id == song.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(pl.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text('${pl.songCount} tracks', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        trailing: alreadyIn
                            ? const Text('✓ Added', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600))
                            : const Icon(Icons.add, color: AppColors.accent, size: 20),
                        onTap: () async {
                          await playlistRepo.addSongToPlaylist(pl.id, song.id);
                          ref.invalidate(playlistsProvider);
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Added "${song.title}" to "${pl.name}"'),
                                backgroundColor: AppColors.surfaceAlt,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
                error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppColors.destructiveText, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final audio = ref.watch(audioManagerProvider);
    final downloadMgr = ref.watch(downloadManagerProvider);
    final songRepo = ref.watch(songRepositoryProvider);
    final isContributor = ref.watch(isContributorOrAboveProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('STREAM'),
        actions: [
          SearchBarInline(
            hintText: 'Search tracks...',
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary, size: 22),
            splashRadius: 20,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: isContributor
          ? FloatingActionButton(
              mini: true,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bg,
              shape: const CircleBorder(),
              onPressed: () => _showUploadBottomSheet(context),
              child: const Icon(Icons.add, size: 22),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playlist Rail (§6: Cover-less, monochrome, name + track count, capped at ~8-10 visible)
          playlistsAsync.when(
            data: (playlists) {
              if (playlists.isEmpty) return const SizedBox.shrink();
              final visiblePlaylists = playlists.take(10).toList();

              return Container(
                height: 52,
                margin: const EdgeInsets.only(top: 4, bottom: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: visiblePlaylists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final pl = visiblePlaylists[index];
                    return ActionChip(
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.divider, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pl.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${pl.songCount}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      onPressed: () {
                        widget.onSelectPlaylist?.call(pl);
                      },
                    );
                  },
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const Divider(height: 1, color: AppColors.divider),

          // Main Song List
          Expanded(
            child: songsAsync.when(
              data: (songs) {
                final filtered = songs.where((s) {
                  if (_searchQuery.isEmpty) return true;
                  final matchTitle = s.title.toLowerCase().contains(_searchQuery);
                  final matchArtist = (s.artist ?? '').toLowerCase().contains(_searchQuery);
                  return matchTitle || matchArtist;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No songs in stream yet.' : 'No tracks matching "$_searchQuery"',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  onRefresh: () async {
                    ref.invalidate(songsProvider);
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final song = filtered[index];
                      final isPlaying = audio.currentSong?.id == song.id && audio.isPlaying;
                      final progress = downloadMgr.downloadProgress[song.id];

                      return SongTile(
                        song: song,
                        isPlaying: isPlaying,
                        isDownloaded: song.isDownloaded,
                        downloadProgress: progress,
                        onTap: () {
                          audio.playSong(song, contextQueue: filtered);
                        },
                        onToggleFavorite: () async {
                          await songRepo.toggleFavorite(song.id);
                          ref.invalidate(songsProvider);
                        },
                        onDownload: () {
                          downloadMgr.downloadSong(song);
                        },
                        onAddToPlaylist: () => _showAddToPlaylistBottomSheet(context, song),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Error loading songs: $err',
                  style: const TextStyle(color: AppColors.destructiveText, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
