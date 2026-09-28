import 'song.dart';

class Playlist {
  final String id;
  final String name;
  final String? createdBy;
  final int createdAt;
  final int songCount;
  final int totalBytes;
  final List<Song> songs;

  Playlist({
    required this.id,
    required this.name,
    this.createdBy,
    required this.createdAt,
    this.songCount = 0,
    this.totalBytes = 0,
    this.songs = const [],
  });

  String get formattedTotalSize {
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    var rawSongs = json['songs'] as List? ?? [];
    List<Song> parsedSongs = rawSongs.map((s) => Song.fromJson(s)).toList();

    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      createdBy: json['created_by'],
      createdAt: json['created_at'] ?? 0,
      songCount: json['song_count'] ?? parsedSongs.length,
      totalBytes: json['total_bytes'] ?? 0,
      songs: parsedSongs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_by': createdBy,
    'created_at': createdAt,
    'song_count': songCount,
    'total_bytes': totalBytes,
  };
}
