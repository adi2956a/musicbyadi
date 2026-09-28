class Profile {
  final String id;
  final String name;
  final String role; // 'listener' | 'contributor' | 'owner'
  final int createdAt;

  Profile({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  bool get isOwner => role == 'owner';
  bool get isContributorOrAbove => role == 'owner' || role == 'contributor';

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'listener',
      createdAt: json['created_at'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'created_at': createdAt,
  };
}
