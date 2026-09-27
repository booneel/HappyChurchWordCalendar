import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'screens/app_shell.dart';
import 'services/backend_config.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (error, stackTrace) {
    debugPrint('Firebase background initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  await NotificationService.instance.showRemoteMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting(
    'ko_KR',
    null,
  );

  var firebaseReady = false;
  if (!BackendConfig.useNas) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Firebase 설정/네트워크가 일시적으로 없어도 로컬 캐시 화면은
      // 실행할 수 있어야 합니다. 각 서비스는 Firebase 앱이 없을 때
      // 로컬 데이터로 동작하도록 방어되어 있습니다.
    }
  }

  if (firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );
  }

  await NotificationService.instance.initialize(firebaseEnabled: firebaseReady);

  runApp(
    const DatePdfApp(),
  );
}

class DatePdfApp extends StatelessWidget {
  const DatePdfApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      title: 'DatePDF',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [
        Locale('ko', 'KR'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(
            0xFF4F7CAC,
          ),
        ),
        scaffoldBackgroundColor: const Color(
          0xFFF7F9FC,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              14,
            ),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              20,
            ),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
