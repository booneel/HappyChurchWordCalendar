import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/backend_config.dart';
import '../services/local_profile_service.dart';
import '../services/nas_api_client.dart';
import '../services/pdf_cache_service.dart';
import '../services/pdf_catalog_service.dart';
import '../services/pdf_settings_service.dart';
import 'home_page.dart';
import 'schedule_page.dart';
import 'qna_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final profile = LocalProfileService();

  int index = 1;
  String displayName = '사용자';
  bool adminMode = false;

  @override
  void initState() {
    super.initState();

    _load();

    // 사용자 화면에서 기다리지 않도록
    // PDF와 제목 카탈로그를 미리 준비.
    unawaited(_preloadAssets());
  }

  Future<void> _preloadAssets() async {
    try {
      await PdfCacheService().preload();
    } catch (error, stackTrace) {
      debugPrint('PDF preload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      await PdfCatalogService().loadTitles();
    } catch (error, stackTrace) {
      debugPrint('PDF title preload failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _load() async {
    final name = await profile.getName();

    final admin = await profile.isAdminMode();

    await PdfSettingsService().loadSettings();

    if (!mounted) return;

    setState(() {
      displayName = name?.isNotEmpty == true ? name! : '사용자';

      adminMode = admin;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          displayName: displayName,
          adminMode: adminMode,
          onChanged: _load,
        ),
      ),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      SchedulePage(displayName: displayName),
      HomePage(
        displayName: displayName,
        adminMode: adminMode,
        onSettings: _openSettings,
      ),
      QnaPage(),
    ];

    return Scaffold(
      body: Column(
        children: [
          if (BackendConfig.useNas)
            ValueListenableBuilder<bool?>(
              valueListenable: NasApiClient.serverReachability,
              builder: (context, reachable, _) {
                if (reachable != false) return const SizedBox.shrink();
                return Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'NAS 오프라인: 저장된 PDF와 Q&A를 읽기 전용으로 표시합니다. 질문과 답변은 연결 후 이용할 수 있습니다.',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          Expanded(child: pages[index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() {
            index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '찾아보기',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'QnA',
          ),
        ],
      ),
    );
  }
}

class Header extends StatelessWidget {
  final String displayName;
  final VoidCallback onSettings;

  const Header({
    super.key,
    required this.displayName,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(DateTime.now());

    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.person_outline),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$displayName님',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(today, style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        IconButton(
          tooltip: '설정',
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}
