import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../storage/download_index.dart';
import '../../data/models/song.dart';
import '../../data/repositories/song_repository.dart';

class AudioManager extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  final DownloadIndex downloadIndex;
  final SongRepository songRepository;

  Song? _currentSong;
  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isShuffling = false;
  LoopMode _loopMode = LoopMode.off;

  Song? get currentSong => _currentSong;
  List<Song> get queue => _queue;
  bool get isPlaying => player.playing;
  bool get isShuffling => _isShuffling;
  LoopMode get loopMode => _loopMode;
  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<PlayerState> get playerStateStream => player.playerStateStream;

  AudioManager({
    required this.downloadIndex,
    required this.songRepository,
  }) {
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
      notifyListeners();
    });
  }

  /// Hybrid Playback Resolver (§5)
  Future<AudioSource> resolveSource(Song song) async {
    // 1. Check local offline index first (zero network egress)
    final localPath = await downloadIndex.pathFor(song.id);
    if (localPath != null && await File(localPath).exists()) {
      return AudioSource.file(localPath);
    }

    // 2. Fetch short-lived stream URL from Cloudflare Worker / backend
    final streamUrl = await songRepository.getStreamUrl(song.id);
    return AudioSource.uri(Uri.parse(streamUrl));
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    if (contextQueue != null) {
      _queue = List.from(contextQueue);
      _currentIndex = _queue.indexWhere((s) => s.id == song.id);
    } else if (!_queue.any((s) => s.id == song.id)) {
      _queue = [song];
      _currentIndex = 0;
    } else {
      _currentIndex = _queue.indexWhere((s) => s.id == song.id);
    }

    _currentSong = song;
    notifyListeners();

    try {
      final source = await resolveSource(song);
      await player.setAudioSource(source);
      await player.play();
    } catch (e) {
      debugPrint('[AudioManager] Error loading audio: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_queue.isEmpty || _currentIndex < 0) return;
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await playSong(_queue[_currentIndex]);
    } else if (_loopMode == LoopMode.all) {
      _currentIndex = 0;
      await playSong(_queue[0]);
    }
  }

  Future<void> playPrevious() async {
    if (_queue.isEmpty || _currentIndex < 0) return;
    if (player.position.inSeconds > 3) {
      await player.seek(Duration.zero);
      return;
    }
    if (_currentIndex - 1 >= 0) {
      _currentIndex--;
      await playSong(_queue[_currentIndex]);
    }
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  void toggleShuffle() {
    _isShuffling = !_isShuffling;
    notifyListeners();
  }

  void toggleLoop() {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    player.setLoopMode(_loopMode);
    notifyListeners();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
