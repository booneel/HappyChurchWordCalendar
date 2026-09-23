import 'package:flutter/material.dart';

import '../services/local_profile_service.dart';
import 'admin_code_page.dart';
import 'admin_page.dart';

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
  late bool adminMode;

  @override
  void initState() {
    super.initState();
    adminMode = widget.adminMode;
  }

  Future<void> _changeName() async {
    final controller = TextEditingController(text: widget.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '표시할 이름'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('저장')),
        ],
      ),
    );

    if (value != null && value.isNotEmpty) {
      await profile.saveName(value);
      widget.onChanged();
      if (mounted) setState(() {});
    }
  }

  Future<void> _adminEntry() async {
    if (adminMode) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminPage()),
      );
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
    }
  }

  Future<void> _exitAdmin() async {
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
              subtitle: Text(widget.displayName),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changeName,
            ),
          ),
          const SizedBox(height: 20),

          const SectionTitle('🔔 알림'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('PDF 업데이트 알림'),
                  value: true,
                  onChanged: (_) {},
                ),
                SwitchListTile(
                  title: const Text('QnA 답변 알림'),
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SectionTitle('🔐 관리자'),
          Card(
            child: ListTile(
              leading: Icon(adminMode ? Icons.admin_panel_settings : Icons.lock_outline),
              title: Text(adminMode ? '관리자 모드' : '관리자 모드'),
              subtitle: Text(adminMode ? '현재 활성화됨' : '승인코드로 관리자 기능 사용'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _adminEntry,
            ),
          ),
          if (adminMode) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('관리자 모드 종료'),
                onTap: _exitAdmin,
              ),
            ),
          ],

          const SizedBox(height: 20),
          const SectionTitle('ℹ️ 앱 정보'),
          Card(
            child: Column(
              children: const [
                ListTile(
                  title: Text('앱 버전'),
                  trailing: Text('1.0.0'),
                ),
                ListTile(
                  title: Text('현재 PDF'),
                  trailing: Text('v1'),
                ),
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
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    );
  }
}
