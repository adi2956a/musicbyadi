import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/playlist.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/search_bar_inline.dart';
import '../../shared/widgets/song_tile.dart';

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  String _searchQuery = '';

  void _showCreatePlaylistBottomSheet(BuildContext context) {
    final nameController = TextEditingController();
    bool isCreating = false;

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
                'NEW PLAYLIST',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Playlist Name',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isCreating
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) return;
                        setModalState(() => isCreating = true);

                        try {
                          final repo = ref.read(playlistRepositoryProvider);
                          await repo.createPlaylist(nameController.text.trim());
                          ref.invalidate(playlistsProvider);
                          if (mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setModalState(() => isCreating = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg),
                      )
                    : const Text('Create Playlist', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlaylistDetails(BuildContext context, Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlist: playlist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final isContributor = ref.watch(isContributorOrAboveProvider);
    final downloadMgr = ref.watch(downloadManagerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('PLAYLISTS'),
        actions: [
          SearchBarInline(
            hintText: 'Search playlists...',
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: isContributor
          ? FloatingActionButton(
              mini: true,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.bg,
              shape: const CircleBorder(),
              onPressed: () => _showCreatePlaylistBottomSheet(context),
              child: const Icon(Icons.add, size: 22),
            )
          : null,
      body: playlistsAsync.when(
        data: (playlists) {
          final filtered = playlists.where((p) {
            if (_searchQuery.isEmpty) return true;
            return p.name.toLowerCase().contains(_searchQuery);
          }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                _searchQuery.isEmpty ? 'No playlists created yet.' : 'No playlists matching "$_searchQuery"',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: () async {
              ref.invalidate(playlistsProvider);
            },
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (context, index) {
                final pl = filtered[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    pl.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    '${pl.songCount} tracks',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_for_offline_outlined, color: AppColors.textSecondary, size: 22),
                    tooltip: 'Download All',
                    splashRadius: 20,
                    onPressed: () {
                      for (final s in pl.songs) {
                        downloadMgr.downloadSong(s);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Downloading all ${pl.songs.length} tracks in "${pl.name}"'),
                          backgroundColor: AppColors.surfaceAlt,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  onTap: () => _openPlaylistDetails(context, pl),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
        ),
        error: (err, _) => Center(
          child: Text('Error loading playlists: $err', style: const TextStyle(color: AppColors.destructiveText)),
        ),
      ),
    );
  }
}

class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({Key? key, required this.playlist}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioManagerProvider);
    final downloadMgr = ref.watch(downloadManagerProvider);
    final songRepo = ref.watch(songRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(playlist.name),
      ),
      body: playlist.songs.isEmpty
          ? const Center(
              child: Text(
                'No tracks in this playlist yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView.builder(
              itemCount: playlist.songs.length,
              itemBuilder: (context, index) {
                final song = playlist.songs[index];
                final isPlaying = audio.currentSong?.id == song.id && audio.isPlaying;
                final progress = downloadMgr.downloadProgress[song.id];

                return SongTile(
                  song: song,
                  isPlaying: isPlaying,
                  isDownloaded: song.isDownloaded,
                  downloadProgress: progress,
                  onTap: () {
                    audio.playSong(song, contextQueue: playlist.songs);
                  },
                  onToggleFavorite: () async {
                    await songRepo.toggleFavorite(song.id);
                  },
                  onDownload: () {
                    downloadMgr.downloadSong(song);
                  },
                );
              },
            ),
    );
  }
}
