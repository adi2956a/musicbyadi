import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/download_index.dart';
import '../models/song.dart';

class SongRepository {
  final ApiClient apiClient;
  final DownloadIndex downloadIndex;

  // In-memory stream URL cache to avoid re-fetching on seeker replay (§8.5)
  final Map<String, ({String url, DateTime expiresAt})> _streamUrlCache = {};

  SongRepository(this.apiClient, this.downloadIndex);

  Future<List<Song>> getSongs() async {
    try {
      final response = await apiClient.dio.get('/songs');
      final list = (response.data['songs'] as List? ?? []);
      List<Song> songs = list.map((s) => Song.fromJson(s)).toList();

      // Enrich with local download paths
      final enriched = <Song>[];
      for (final song in songs) {
        final localPath = await downloadIndex.pathFor(song.id);
        enriched.add(song.copyWith(localPath: localPath));
      }
      return enriched;
    } catch (e) {
      // Offline fallback: load from downloads
      final downloaded = await downloadIndex.getAll();
      return downloaded.map((d) {
        return Song(
          id: d.songId,
          title: 'Offline Track (${d.songId.substring(0, 6)})',
          artist: 'Saved Locally',
          r2Key: '',
          sizeBytes: d.sizeBytes,
          createdAt: d.downloadedAt,
          localPath: d.localPath,
        );
      }).toList();
    }
  }

  Future<String> getStreamUrl(String songId) async {
    // 1. Check cache first
    final cached = _streamUrlCache[songId];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      return cached.url;
    }

    // 2. Fetch from backend
    final response = await apiClient.dio.get('/songs/$songId/stream-url');
    final streamUrl = response.data['stream_url'] as String;
    final expiresIn = (response.data['expires_in'] as int?) ?? 600;

    // Resolve relative URL against API client baseUrl if needed
    final resolvedUrl = streamUrl.startsWith('http')
        ? streamUrl
        : '${apiClient.dio.options.baseUrl}$streamUrl';

    _streamUrlCache[songId] = (
      url: resolvedUrl,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 30)),
    );

    return resolvedUrl;
  }

  Future<bool> toggleFavorite(String songId) async {
    final response = await apiClient.dio.post('/favorites/$songId');
    return response.data['is_favorite'] == true;
  }

  Future<void> deleteSong(String songId) async {
    await apiClient.dio.delete('/songs/$songId');
    await downloadIndex.remove(songId);
  }

  Future<Song> uploadSong({
    required String title,
    String? artist,
    int? durationS,
    int? sizeBytes,
  }) async {
    final response = await apiClient.dio.post('/songs', data: {
      'title': title,
      'artist': artist,
      'duration_s': durationS,
      'size_bytes': sizeBytes,
    });
    return Song.fromJson(response.data['song']);
  }
}
