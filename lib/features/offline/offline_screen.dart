import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/song.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/song_tile.dart';
import '../../shared/widgets/storage_bar.dart';

class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  int _selectedFilterIndex = 0; // 0: All, 1: Playlists, 2: Liked
  int _storageUsedBytes = 0;
  List<Song> _downloadedSongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOfflineData();
  }

  Future<void> _loadOfflineData() async {
    setState(() => _isLoading = true);
    final downloadIndex = ref.read(downloadIndexProvider);
    final songRepo = ref.read(songRepositoryProvider);

    final downloads = await downloadIndex.getAll();
    final used = await downloadIndex.getTotalStorageUsed();

    // Map downloaded items to songs
    final allSongs = await songRepo.getSongs();
    final downloaded = allSongs.where((s) => downloads.any((d) => d.songId == s.id)).toList();

    if (mounted) {
      setState(() {
        _storageUsedBytes = used;
        _downloadedSongs = downloaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDeleteSong(Song song) async {
    final downloadMgr = ref.read(downloadManagerProvider);
    final previousList = List<Song>.from(_downloadedSongs);

    // Optimistically remove
    setState(() {
      _downloadedSongs.removeWhere((s) => s.id == song.id);
    });

    await downloadMgr.removeDownloadedSong(song.id);
    _loadOfflineData();

    if (!mounted) return;

    // Spec §8.3: Undo snackbar over confirm dialog
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${song.title}" from offline storage'),
        backgroundColor: AppColors.surfaceAlt,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: AppColors.accent,
          onPressed: () async {
            // Restore download
            downloadMgr.downloadSong(song);
            setState(() {
              _downloadedSongs = previousList;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(audioManagerProvider);
    final songRepo = ref.watch(songRepositoryProvider);

    List<Song> displaySongs = _downloadedSongs;
    if (_selectedFilterIndex == 2) {
      // Liked only
      displaySongs = _downloadedSongs.where((s) => s.isFavorite).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('OFFLINE LIBRARY'),
      ),
      body: Column(
        children: [
          // Top Storage Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: StorageBar(usedBytes: _storageUsedBytes),
          ),

          // Segmented Filter Control: All / Playlists / Liked
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                _buildSegment(0, 'All'),
                _buildSegment(1, 'Playlists'),
                _buildSegment(2, 'Liked'),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.divider),

          // Downloaded Song List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                : displaySongs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textDisabled),
                            const SizedBox(height: 12),
                            Text(
                              _selectedFilterIndex == 2
                                  ? 'No liked offline songs'
                                  : 'No downloaded songs yet',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Tap the download icon on any track to save offline.',
                              style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: displaySongs.length,
                        itemBuilder: (context, index) {
                          final song = displaySongs[index];
                          final isPlaying = audio.currentSong?.id == song.id && audio.isPlaying;

                          return SongTile(
                            song: song,
                            isPlaying: isPlaying,
                            isDownloaded: true,
                            onTap: () {
                              audio.playSong(song, contextQueue: displaySongs);
                            },
                            onToggleFavorite: () async {
                              await songRepo.toggleFavorite(song.id);
                              _loadOfflineData();
                            },
                            onDownload: () {},
                            onDelete: () => _handleDeleteSong(song),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(int index, String label) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.bg : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
