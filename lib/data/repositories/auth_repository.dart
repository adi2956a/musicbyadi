import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';
import '../models/profile.dart';

class AuthRepository {
  final ApiClient apiClient;

  AuthRepository(this.apiClient);

  Future<Profile> redeemInvite(String name, String code) async {
    try {
      final response = await apiClient.dio.post('/auth/redeem', data: {
        'name': name.trim(),
        'code': code.trim().toUpperCase(),
      });

      final data = response.data;
      final token = data['token'] as String;
      final profile = Profile.fromJson(data['profile']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ApiClient.tokenKey, token);
      await prefs.setString('musicbyadi_profile_id', profile.id);
      await prefs.setString('musicbyadi_profile_name', profile.name);
      await prefs.setString('musicbyadi_profile_role', profile.role);

      return profile;
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['error'] ?? 'Failed to redeem invite code';
      throw Exception(errorMsg);
    }
  }

  Future<Profile?> getMe() async {
    try {
      final response = await apiClient.dio.get('/me');
      final profile = Profile.fromJson(response.data['profile']);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('musicbyadi_profile_id', profile.id);
      await prefs.setString('musicbyadi_profile_name', profile.name);
      await prefs.setString('musicbyadi_profile_role', profile.role);

      return profile;
    } catch (_) {
      // Offline fallback: load cached profile from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('musicbyadi_profile_id');
      final name = prefs.getString('musicbyadi_profile_name');
      final role = prefs.getString('musicbyadi_profile_role');

      if (id != null && name != null) {
        return Profile(id: id, name: name, role: role ?? 'listener', createdAt: 0);
      }
      return null;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ApiClient.tokenKey);
    await prefs.remove('musicbyadi_profile_id');
    await prefs.remove('musicbyadi_profile_name');
    await prefs.remove('musicbyadi_profile_role');
  }

  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(ApiClient.tokenKey);
    return token != null && token.isNotEmpty;
  }
}
