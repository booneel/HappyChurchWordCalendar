import 'package:flutter/material.dart';

class AdminCodePage extends StatefulWidget {
  const AdminCodePage({super.key});

  @override
  State<AdminCodePage> createState() => _AdminCodePageState();
}

class _AdminCodePageState extends State<AdminCodePage> {
  final controller = TextEditingController();
  bool obscure = true;
  String? error;

  // PROTOTYPE ONLY.
  // Do NOT ship a real secret here. Replace this with server-side verification.
  static const demoCode = '123456';

  void submit() {
    if (controller.text.trim() == demoCode) {
      Navigator.pop(context, true);
      return;
    }

    setState(() => error = '승인코드가 올바르지 않습니다.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('관리자 모드')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 30),
          const Icon(Icons.lock_outline, size: 58),
          const SizedBox(height: 18),
          const Text(
            '관리자 인증',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '관리자 승인코드를 입력하면\nPDF 관리 기능을 사용할 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 30),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: TextInputType.number,
            maxLength: 6,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: '승인코드',
              hintText: '6자리 코드',
              errorText: error,
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: submit,
            child: const SizedBox(
              height: 48,
              child: Center(child: Text('확인')),
            ),
          ),
        ],
      ),
    );
  }
}
