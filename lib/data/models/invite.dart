class Invite {
  final String code;
  final bool isUsed;
  final String? usedBy;
  final String? createdBy;
  final int createdAt;

  Invite({
    required this.code,
    required this.isUsed,
    this.usedBy,
    this.createdBy,
    required this.createdAt,
  });

  factory Invite.fromJson(Map<String, dynamic> json) {
    return Invite(
      code: json['code'] ?? '',
      isUsed: json['is_used'] == 1 || json['is_used'] == true,
      usedBy: json['used_by'],
      createdBy: json['created_by'],
      createdAt: json['created_at'] ?? 0,
    );
  }
}

class DownloadedTrack {
  final String songId;
  final String localPath;
  final int sizeBytes;
  final int downloadedAt;

  DownloadedTrack({
    required this.songId,
    required this.localPath,
    required this.sizeBytes,
    required this.downloadedAt,
  });

  factory DownloadedTrack.fromMap(Map<String, dynamic> map) {
    return DownloadedTrack(
      songId: map['song_id'] as String,
      localPath: map['local_path'] as String,
      sizeBytes: map['size_bytes'] as int,
      downloadedAt: map['downloaded_at'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
    'song_id': songId,
    'local_path': localPath,
    'size_bytes': sizeBytes,
    'downloaded_at': downloadedAt,
  };
}
