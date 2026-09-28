import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/role_badge.dart';
import '../../shared/widgets/storage_bar.dart';
import '../admin/admin_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _wifiOnly = false;
  int _storageUsed = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final downloadIndex = ref.read(downloadIndexProvider);
    final used = await downloadIndex.getTotalStorageUsed();

    setState(() {
      _wifiOnly = prefs.getBool('musicbyadi_wifi_only') ?? false;
      _storageUsed = used;
    });
  }

  Future<void> _toggleWifiOnly(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('musicbyadi_wifi_only', val);
    setState(() => _wifiOnly = val);
  }

  Future<void> _handleClearAllDownloads() async {
    final downloadMgr = ref.read(downloadManagerProvider);
    await downloadMgr.clearAllDownloads();
    await _loadSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cleared all offline downloads'),
          backgroundColor: AppColors.surfaceAlt,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final isOwner = ref.watch(isOwnerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('SETTINGS'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Minimal Profile Block
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.name ?? 'Listener',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${profile?.id ?? "unknown"}',
                      style: const TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                RoleBadge(role: profile?.role ?? 'listener'),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Download Settings
          const Text(
            'DOWNLOADS & STORAGE',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          // Wi-Fi Only Toggle
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Download over Wi-Fi only', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            subtitle: const Text('Prevent using mobile cellular data', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            value: _wifiOnly,
            activeColor: AppColors.accent,
            onChanged: _toggleWifiOnly,
          ),

          const SizedBox(height: 16),

          // Storage Bar
          StorageBar(usedBytes: _storageUsed),
          const SizedBox(height: 12),

          // Plain text Clear All Downloads action
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _storageUsed > 0 ? _handleClearAllDownloads : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.destructiveText,
                disabledForegroundColor: AppColors.textDisabled,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Clear All Downloads', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),

          const SizedBox(height: 32),

          // Owner-Only Admin Panel Entry
          if (isOwner) ...[
            const Text(
              'ADMINISTRATION',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.textPrimary),
              title: const Text('Admin Console', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Manage users, invites & library', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, color: AppColors.textSecondary, size: 14),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // Logout Action
          const Divider(color: AppColors.divider),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sign Out', style: TextStyle(color: AppColors.destructiveText, fontSize: 14)),
            onTap: () async {
              final authRepo = ref.read(authRepositoryProvider);
              await authRepo.logout();
              ref.read(currentProfileProvider.notifier).state = null;
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
    );
  }
}
