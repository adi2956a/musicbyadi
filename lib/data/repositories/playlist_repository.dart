import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../models/playlist.dart';

class PlaylistRepository {
  final ApiClient apiClient;

  PlaylistRepository(this.apiClient);

  Future<List<Playlist>> getPlaylists() async {
    try {
      final response = await apiClient.dio.get('/playlists');
      final list = (response.data['playlists'] as List? ?? []);
      return list.map((p) => Playlist.fromJson(p)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Playlist> createPlaylist(String name) async {
    final response = await apiClient.dio.post('/playlists', data: {'name': name});
    return Playlist.fromJson(response.data['playlist']);
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    await apiClient.dio.post('/playlists/$playlistId/songs', data: {'song_id': songId});
  }

  Future<int> addMultipleSongsToPlaylist(String playlistId, List<String> songIds) async {
    final response = await apiClient.dio.post('/playlists/$playlistId/bulk-songs', data: {'song_ids': songIds});
    return (response.data['added_count'] as int?) ?? songIds.length;
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    await apiClient.dio.delete('/playlists/$playlistId/songs/$songId');
  }

  Future<void> deletePlaylist(String playlistId) async {
    await apiClient.dio.delete('/playlists/$playlistId');
  }
}
