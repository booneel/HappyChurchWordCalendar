import 'package:flutter/material.dart';

import '../services/admin_service.dart';
import '../services/backend_config.dart';

class AdminCodePage extends StatefulWidget {
  const AdminCodePage({super.key});

  @override
  State<AdminCodePage> createState() => _AdminCodePageState();
}

class _AdminCodePageState extends State<AdminCodePage> {
  final AdminService _adminService = AdminService();
  final _codeController = TextEditingController();

  bool _obscure = true;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      setState(() => _errorMessage = '관리자 인증값을 입력해 주세요.');
      return;
    }

    bool verified;
    try {
      verified = await _adminService.verifyAdminCode(code);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'NAS 관리자 인증 서버에 연결할 수 없습니다.');
      return;
    }
    if (!mounted) return;
    if (verified) {
      await _adminService.signInAsAdmin();
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      setState(() => _errorMessage = '승인코드가 올바르지 않습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 인증'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 30),
          const Icon(
            Icons.lock_outline,
            size: 64,
            color: Color(0xFF4F7CAC),
          ),
          const SizedBox(height: 18),
          const Text(
            '관리자 인증',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            BackendConfig.useNas
                ? 'NAS에 설정한 관리자 토큰을 입력하세요. 앱을 종료하면 다시 입력해야 합니다.'
                : '6자리 관리자 승인코드를 입력하면\nPDF 및 앱 콘텐츠 관리 기능을 사용할 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 30),

          TextField(
            controller: _codeController,
            obscureText: _obscure,
            keyboardType: TextInputType.visiblePassword,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '승인코드',
              hintText: 'NAS: 관리자 토큰 / Firebase: 6자리 코드',
              errorText: _errorMessage,
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 16),

          FilledButton(
            onPressed: _submit,
            child: const SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  '확인',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
