import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileService {
  static const _nameKey = 'display_name';
  static const _adminModeKey = 'admin_mode';

  Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  Future<void> saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<bool> isAdminMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_adminModeKey) ?? false;
  }

  Future<void> setAdminMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adminModeKey, value);
  }
}
