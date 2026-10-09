import 'package:flutter/material.dart';

import '../services/admin_service.dart';
import '../services/local_profile_service.dart';
import '../services/notification_service.dart';
import 'admin_code_page.dart';
import 'admin_page.dart';
import 'recent_history_page.dart';

class SettingsPage extends StatefulWidget {
  final String displayName;
  final bool adminMode;
  final VoidCallback onChanged;

  const SettingsPage({
    super.key,
    required this.displayName,
    required this.adminMode,
    required this.onChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final profile = LocalProfileService();
  final adminService = AdminService.instance;
  late bool adminMode;
  late String currentDisplayName;
  bool pdfNotificationsEnabled = true;
  bool qnaNotificationsEnabled = true;

  bool dailyAlarmEnabled = false;
  TimeOfDay dailyAlarmTime = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();
    adminMode = widget.adminMode;
    currentDisplayName = widget.displayName;
    _loadNotificationPreferences();
    _checkAdminState();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayName != widget.displayName) {
      currentDisplayName = widget.displayName;
    }
  }

  Future<void> _loadNotificationPreferences() async {
    final pdfEnabled = await profile.isPdfNotificationsEnabled();
    final qnaEnabled = await profile.isQnaNotificationsEnabled();
    final alarmEnabled = await profile.isDailyAlarmEnabled();
    final hour = await profile.getDailyAlarmHour();
    final minute = await profile.getDailyAlarmMinute();

    if (!mounted) return;
    setState(() {
      pdfNotificationsEnabled = pdfEnabled;
      qnaNotificationsEnabled = qnaEnabled;
      dailyAlarmEnabled = alarmEnabled;
      dailyAlarmTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _checkAdminState() async {
    final signedIn = await adminService.isSignedInAsAdmin;
    if (mounted && signedIn != adminMode) {
      setState(() => adminMode = signedIn);
    }
  }

  Future<void> _changeName() async {
    final controller = TextEditingController(text: currentDisplayName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '표시할 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (value != null && value.isNotEmpty) {
      await profile.saveName(value);
      if (mounted) {
        setState(() => currentDisplayName = value);
      }
      widget.onChanged();
    }
  }

  Future<void> _setPdfNotifications(bool value) async {
    setState(() => pdfNotificationsEnabled = value);
    await profile.setPdfNotificationsEnabled(value);
  }

  Future<void> _setQnaNotifications(bool value) async {
    setState(() => qnaNotificationsEnabled = value);
    await profile.setQnaNotificationsEnabled(value);
  }

  Future<void> _setDailyAlarmEnabled(bool value) async {
    setState(() => dailyAlarmEnabled = value);
    await profile.setDailyAlarmEnabled(value);
    await NotificationService.instance.updateDailyAlarmSchedule(
      enabled: value,
      hour: dailyAlarmTime.hour,
      minute: dailyAlarmTime.minute,
      requestExactAlarmPermission: value,
    );
  }

  Future<void> _pickDailyAlarmTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: dailyAlarmTime,
    );

    if (picked != null) {
      setState(() {
        dailyAlarmTime = picked;
        dailyAlarmEnabled = true;
      });
      await profile.setDailyAlarmEnabled(true);
      await profile.setDailyAlarmTime(picked.hour, picked.minute);
      await NotificationService.instance.updateDailyAlarmSchedule(
        enabled: true,
        hour: picked.hour,
        minute: picked.minute,
        requestExactAlarmPermission: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⏰ 매일 ${picked.format(context)}에 말씀 알림이 설정되었습니다.',
          ),
        ),
      );
    }
  }

  Future<void> _adminEntry() async {
    final signedIn = await adminService.isSignedInAsAdmin;
    if (!mounted) return;

    if (signedIn || adminMode) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminPage()),
      );
      _syncAdminState();
      return;
    }

    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AdminCodePage()),
    );

    if (success == true) {
      await profile.setAdminMode(true);
      if (!mounted) return;
      setState(() => adminMode = true);
      widget.onChanged();
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminPage()),
      );
      _syncAdminState();
    }
  }

  Future<void> _syncAdminState() async {
    final signedIn = await adminService.isSignedInAsAdmin;
    if (mounted && adminMode != signedIn) {
      setState(() => adminMode = signedIn);
      widget.onChanged();
    }
  }

  Future<void> _exitAdmin() async {
    await adminService.signOut();
    await profile.setAdminMode(false);
    if (!mounted) return;
    setState(() => adminMode = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const SectionTitle('👤 사용자'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('이름'),
              subtitle: Text(
                currentDisplayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changeName,
            ),
          ),
          const SizedBox(height: 20),

          const SectionTitle('📖 나의 이용 기록'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history, color: Color(0xFF4F7CAC)),
              title: const Text('최근 본 말씀 기록'),
              subtitle: const Text('내가 직접 열어본 말씀 이력 확인'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecentHistoryPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          const SectionTitle('🔔 알림 설정'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('매일 말씀 지정 시간 알림'),
                  subtitle: Text(
                    dailyAlarmEnabled
                        ? '설정 시간: ${dailyAlarmTime.format(context)}'
                        : '설정한 시간에 매일 말씀을 알려드립니다.',
                  ),
                  value: dailyAlarmEnabled,
                  onChanged: _setDailyAlarmEnabled,
                ),
                if (dailyAlarmEnabled)
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: const Text('알림 시간 변경'),
                    trailing: Text(
                      dailyAlarmTime.format(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F7CAC),
                      ),
                    ),
                    onTap: _pickDailyAlarmTime,
                  ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('PDF 업데이트 알림'),
                  value: pdfNotificationsEnabled,
                  onChanged: _setPdfNotifications,
                ),
                SwitchListTile(
                  title: const Text('QnA 답변 알림'),
                  value: qnaNotificationsEnabled,
                  onChanged: _setQnaNotifications,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SectionTitle('🔐 관리자'),
          Card(
            child: ListTile(
              leading: Icon(
                adminMode ? Icons.admin_panel_settings : Icons.lock_outline,
              ),
              title: const Text('관리자 모드'),
              subtitle: Text(
                adminMode ? '현재 활성화됨 (관리자 전용 기능)' : '승인코드로 관리자 기능 사용',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _adminEntry,
            ),
          ),
          if (adminMode) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  '관리자 모드 종료',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _exitAdmin,
              ),
            ),
          ],
          const SizedBox(height: 20),

          const SectionTitle('ℹ️ 앱 정보'),
          Card(
            child: Column(
              children: const [
                ListTile(title: Text('앱 버전'), trailing: Text('1.0.0')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}
