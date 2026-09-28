class Song {
  final String id;
  final String title;
  final String? artist;
  final String r2Key;
  final String? thumbKey;
  final int sizeBytes;
  final int? durationS;
  final String? uploadedBy;
  final int createdAt;
  final bool isFavorite;
  final String? localPath;
  final String? streamUrl;

  Song({
    required this.id,
    required this.title,
    this.artist,
    required this.r2Key,
    this.thumbKey,
    required this.sizeBytes,
    this.durationS,
    this.uploadedBy,
    required this.createdAt,
    this.isFavorite = false,
    this.localPath,
    this.streamUrl,
  });

  bool get isDownloaded => localPath != null;

  String get formattedDuration {
    if (durationS == null || durationS! <= 0) return '0:00';
    final minutes = durationS! ~/ 60;
    final seconds = durationS! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? r2Key,
    String? thumbKey,
    int? sizeBytes,
    int? durationS,
    String? uploadedBy,
    int? createdAt,
    bool? isFavorite,
    String? localPath,
    String? streamUrl,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      r2Key: r2Key ?? this.r2Key,
      thumbKey: thumbKey ?? this.thumbKey,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationS: durationS ?? this.durationS,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      localPath: localPath ?? this.localPath,
      streamUrl: streamUrl ?? this.streamUrl,
    );
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      artist: json['artist'],
      r2Key: json['r2_key'] ?? '',
      thumbKey: json['thumb_key'],
      sizeBytes: json['size_bytes'] ?? 0,
      durationS: json['duration_s'],
      uploadedBy: json['uploaded_by'],
      createdAt: json['created_at'] ?? 0,
      isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1,
      streamUrl: json['stream_url'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'r2_key': r2Key,
    'thumb_key': thumbKey,
    'size_bytes': sizeBytes,
    'duration_s': durationS,
    'uploaded_by': uploadedBy,
    'created_at': createdAt,
    'is_favorite': isFavorite,
  };
}
