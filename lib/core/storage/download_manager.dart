import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/invite.dart';
import '../../data/models/song.dart';
import '../../data/repositories/song_repository.dart';
import 'download_index.dart';

class DownloadManager extends ChangeNotifier {
  final DownloadIndex downloadIndex;
  final SongRepository songRepository;
  final Dio dio = Dio();

  // In-flight download progress: songId -> progress (0.0 to 1.0)
  final Map<String, double> _downloadProgress = {};

  DownloadManager({
    required this.downloadIndex,
    required this.songRepository,
  });

  Map<String, double> get downloadProgress => _downloadProgress;

  bool isDownloading(String songId) => _downloadProgress.containsKey(songId);

  Future<String> _getStorageDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final musicDir = Directory(p.join(docs.path, 'tracks'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
      // Section 10: Create .nomedia so media scanners ignore offline music files
      final noMedia = File(p.join(musicDir.path, '.nomedia'));
      if (!await noMedia.exists()) {
        await noMedia.create();
      }
    }
    return musicDir.path;
  }

  Future<void> downloadSong(Song song) async {
    if (isDownloading(song.id)) return;

    // Check Wi-Fi only setting
    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool('musicbyadi_wifi_only') ?? false;
    // (In production, check connectivity state before proceeding if wifiOnly is true)

    _downloadProgress[song.id] = 0.01;
    notifyListeners();

    try {
      final streamUrl = await songRepository.getStreamUrl(song.id);
      final dir = await _getStorageDirectory();
      final extension = p.extension(song.r2Key).isNotEmpty ? p.extension(song.r2Key) : '.mp3';
      final savePath = p.join(dir, '${song.id}$extension');

      await dio.download(
        streamUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress[song.id] = received / total;
            notifyListeners();
          }
        },
      );

      final file = File(savePath);
      final size = await file.length();

      await downloadIndex.recordDownload(DownloadedTrack(
        songId: song.id,
        localPath: savePath,
        sizeBytes: size,
        downloadedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));
    } catch (e) {
      debugPrint('[DownloadManager] Download failed for ${song.title}: $e');
    } finally {
      _downloadProgress.remove(song.id);
      notifyListeners();
    }
  }

  Future<void> removeDownloadedSong(String songId) async {
    await downloadIndex.remove(songId);
    notifyListeners();
  }

  Future<void> clearAllDownloads() async {
    await downloadIndex.clearAll();
    notifyListeners();
  }
}
