import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio/audio_manager.dart';
import 'network/api_client.dart';
import 'storage/download_index.dart';
import 'storage/download_manager.dart';
import '../data/models/playlist.dart';
import '../data/models/profile.dart';
import '../data/models/song.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/playlist_repository.dart';
import '../data/repositories/song_repository.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final downloadIndexProvider = Provider<DownloadIndex>((ref) => DownloadIndex());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return AuthRepository(client);
});

final songRepositoryProvider = Provider<SongRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  final index = ref.watch(downloadIndexProvider);
  return SongRepository(client, index);
});

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return PlaylistRepository(client);
});

final audioManagerProvider = ChangeNotifierProvider<AudioManager>((ref) {
  final index = ref.watch(downloadIndexProvider);
  final songRepo = ref.watch(songRepositoryProvider);
  return AudioManager(downloadIndex: index, songRepository: songRepo);
});

final downloadManagerProvider = ChangeNotifierProvider<DownloadManager>((ref) {
  final index = ref.watch(downloadIndexProvider);
  final songRepo = ref.watch(songRepositoryProvider);
  return DownloadManager(downloadIndex: index, songRepository: songRepo);
});

// Profile & Role Providers
final currentProfileProvider = StateProvider<Profile?>((ref) => null);

final isOwnerProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile?.role == 'owner';
});

final isContributorOrAboveProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile?.role == 'owner' || profile?.role == 'contributor';
});

// Songs & Playlists Providers
final songsProvider = FutureProvider.autoDispose<List<Song>>((ref) async {
  final repo = ref.watch(songRepositoryProvider);
  return repo.getSongs();
});

final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) async {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.getPlaylists();
});
