import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileService {
  static const _nameKey = 'display_name';
  static const _adminModeKey = 'admin_mode';
  static const _pdfNotificationsKey = 'pdf_notifications_enabled';
  static const _qnaNotificationsKey = 'qna_notifications_enabled';

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

  Future<bool> isPdfNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pdfNotificationsKey) ?? true;
  }

  Future<void> setPdfNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pdfNotificationsKey, value);
  }

  Future<bool> isQnaNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_qnaNotificationsKey) ?? true;
  }

  Future<void> setQnaNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_qnaNotificationsKey, value);
  }
}
