import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/invite.dart';
import '../../data/models/profile.dart';
import '../../data/models/song.dart';
import '../../shared/theme/app_theme.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _isLoading = true;
  List<Profile> _users = [];
  List<Invite> _invites = [];
  Map<String, dynamic> _stats = {};

  // Bulk select mode for Library Management
  bool _isBulkMode = false;
  final Set<String> _selectedSongIds = {};

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  Future<void> _fetchAdminData() async {
    setState(() => _isLoading = true);
    final apiClient = ref.read(apiClientProvider);

    try {
      final usersRes = await apiClient.dio.get('/admin/users');
      final invitesRes = await apiClient.dio.get('/admin/invites');
      final statsRes = await apiClient.dio.get('/admin/stats');

      final users = (usersRes.data['users'] as List? ?? []).map((u) => Profile.fromJson(u)).toList();
      final invites = (invitesRes.data['invites'] as List? ?? []).map((i) => Invite.fromJson(i)).toList();
      final stats = statsRes.data['stats'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _users = users;
          _invites = invites;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cycleRole(Profile profile) async {
    final myProfile = ref.read(currentProfileProvider);
    if (profile.id == myProfile?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Owner cannot demote self'), backgroundColor: AppColors.surfaceAlt),
      );
      return;
    }

    String nextRole = 'listener';
    if (profile.role == 'listener') {
      nextRole = 'contributor';
    } else if (profile.role == 'contributor') {
      nextRole = 'owner';
    } else {
      nextRole = 'listener';
    }

    final apiClient = ref.read(apiClientProvider);
    try {
      await apiClient.dio.patch('/admin/users/${profile.id}/role', data: {'role': nextRole});
      _fetchAdminData();
    } catch (e) {
      debugPrint('[Admin] Role change failed: $e');
    }
  }

  Future<void> _generateInvite() async {
    final apiClient = ref.read(apiClientProvider);
    try {
      final res = await apiClient.dio.post('/admin/invites');
      final invite = Invite.fromJson(res.data['invite']);

      if (!mounted) return;
      _fetchAdminData();

      // Show copyable bottom sheet
      showModalBottomSheet(
        context: context,
        builder: (_) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NEW INVITE CODE', style: TextStyle(color: AppColors.textSecondary, letterSpacing: 1.5, fontSize: 12)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Text(
                  invite.code,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invite.code));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite code copied to clipboard!'), backgroundColor: AppColors.surfaceAlt),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                ),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy Code'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Admin] Generate invite failed: $e');
    }
  }

  Future<void> _revokeInvite(String code) async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.dio.delete('/admin/invites/$code');
    _fetchAdminData();
  }

  Future<void> _bulkDeleteSongs() async {
    if (_selectedSongIds.isEmpty) return;
    final songRepo = ref.read(songRepositoryProvider);

    for (final id in _selectedSongIds) {
      await songRepo.deleteSong(id);
    }

    _selectedSongIds.clear();
    setState(() => _isBulkMode = false);
    ref.invalidate(songsProvider);
    _fetchAdminData();
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(songsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('ADMIN CONSOLE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _fetchAdminData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Usage Snapshot
                const Text(
                  'SYSTEM SNAPSHOT',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildSnapshotCard('SONGS', '${_stats["total_songs"] ?? 0}'),
                    const SizedBox(width: 8),
                    _buildSnapshotCard('STORAGE', '${((_stats["total_bytes"] ?? 0) / (1024 * 1024)).toStringAsFixed(1)} MB'),
                    const SizedBox(width: 8),
                    _buildSnapshotCard('USERS', '${_stats["total_users"] ?? 0}'),
                  ],
                ),

                const SizedBox(height: 28),

                // 2. Invite Management
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'INVITES',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_invites.length} pending',
                            style: const TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: _generateInvite,
                      icon: const Icon(Icons.add, size: 16, color: AppColors.accent),
                      label: const Text('Generate', style: TextStyle(color: AppColors.accent, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_invites.isEmpty)
                  const Text('No outstanding unused invites.', style: TextStyle(color: AppColors.textDisabled, fontSize: 12))
                else
                  ..._invites.map((inv) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.key, color: AppColors.textSecondary, size: 18),
                        title: Text(inv.code, style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.destructiveText),
                          onPressed: () => _revokeInvite(inv.code),
                        ),
                      )),

                const SizedBox(height: 28),

                // 3. User Management
                const Text(
                  'USER ROLES',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ..._users.map((u) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(u.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                              Text(u.id, style: const TextStyle(color: AppColors.textDisabled, fontSize: 11)),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _cycleRole(u),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Text(
                                '${u.role.toUpperCase()} ↻',
                                style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: 28),

                // 4. Library Bulk Management
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'LIBRARY MANAGEMENT',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isBulkMode = !_isBulkMode;
                          _selectedSongIds.clear();
                        });
                      },
                      child: Text(
                        _isBulkMode ? 'Done' : 'Bulk Select',
                        style: const TextStyle(color: AppColors.accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (_isBulkMode) ...[
                  Row(
                    children: [
                      Text(
                        '${_selectedSongIds.length} selected',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _selectedSongIds.isNotEmpty ? _bulkDeleteSongs : null,
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.destructiveText),
                        label: const Text('Delete Selected', style: TextStyle(color: AppColors.destructiveText, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
                songsAsync.when(
                  data: (songs) => Column(
                    children: songs.map((s) {
                      if (!_isBulkMode) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                          subtitle: Text(s.artist ?? 'Unknown', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.textDisabled, size: 18),
                            onPressed: () async {
                              final songRepo = ref.read(songRepositoryProvider);
                              await songRepo.deleteSong(s.id);
                              ref.invalidate(songsProvider);
                              _fetchAdminData();
                            },
                          ),
                        );
                      }

                      final isChecked = _selectedSongIds.contains(s.id);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isChecked,
                        activeColor: AppColors.accent,
                        checkColor: AppColors.bg,
                        title: Text(s.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                        subtitle: Text(s.artist ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedSongIds.add(s.id);
                            } else {
                              _selectedSongIds.remove(s.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 36),

                // 5. Danger Zone (§6)
                const Text(
                  'DANGER ZONE',
                  style: TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        onPressed: () {
                          // Text-only safety action
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.destructiveText,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('Reset All Unused Invites', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.destructiveText,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('Revoke All Contributor Roles', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSnapshotCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}
