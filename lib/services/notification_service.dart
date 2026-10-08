import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_config.dart';
import 'local_profile_service.dart';
import 'nas_api_client.dart';
import 'pdf_cache_service.dart';

/// Handles both foreground local notifications and FCM notifications.
///
/// Firestore/NAS listeners cover changes while the app is open. FCM handles
/// the killed/background case when the Firebase functions in /functions are
/// deployed.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _deviceIdKey = 'notification_device_id';
  static const _channelId = 'wordcalendar_updates';
  static const _channelName = 'TheWordCalendar 업데이트';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final LocalProfileService _profile = LocalProfileService();
  final NasApiClient _nas = NasApiClient.instance;
  final Random _random = Random.secure();

  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _qnaSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pdfSubscription;
  Timer? _nasTimer;
  bool _nasPolling = false;

  String? _deviceId;
  String? _fcmToken;
  String? _pdfVersion;
  final Map<String, bool> _qnaAnswers = <String, bool>{};
  bool _qnaLoaded = false;
  bool _initialized = false;
  bool _localReady = false;

  Future<void> initialize({required bool firebaseEnabled}) async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _ensureLocalNotifications();
    } catch (error, stackTrace) {
      debugPrint('Local notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (firebaseEnabled && Firebase.apps.isNotEmpty) {
      await _initializeFirebaseNotifications(
        watchFirestore: !BackendConfig.useNas,
      );
    }
    if (BackendConfig.useNas) {
      _startNasPolling();
    }
  }

  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    if (BackendConfig.useNas && Firebase.apps.isNotEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        _deviceId = uid;
        return uid;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId =
          '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff).toRadixString(16)}';
      await prefs.setString(_deviceIdKey, _deviceId!);
    }
    return _deviceId!;
  }

  Future<String?> getFcmToken() async {
    if (Firebase.apps.isEmpty) return null;
    try {
      _fcmToken ??= await FirebaseMessaging.instance.getToken();
      return _fcmToken;
    } catch (error) {
      debugPrint('FCM token was not available: $error');
      return null;
    }
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    if (!_localReady) {
      try {
        await _ensureLocalNotifications();
      } catch (error, stackTrace) {
        debugPrint(
            'Background local notification initialization failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    final data = message.data;
    final type = data['type']?.toString() ?? 'general';
    if (type == 'pdf_update') {
      await _invalidatePdfCache();
    }
    final title = message.notification?.title ?? data['title']?.toString();
    final body = message.notification?.body ?? data['body']?.toString();
    if (title == null || body == null || title.isEmpty || body.isEmpty) return;

    await _showIfEnabled(
      type: type,
      title: title,
      body: body,
      payload: data['questionId']?.toString(),
    );
  }

  Future<void> _initializeFirebaseNotifications({
    required bool watchFirestore,
  }) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (BackendConfig.useNas && FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      _messageSubscription = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(showRemoteMessage(message)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Foreground FCM listener failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
      _tokenSubscription = messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        unawaited(_saveToken(token));
      });

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (var attempt = 0; attempt < 10; attempt++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apnsToken == null || apnsToken.isEmpty) {
          throw StateError('APNs token is not available yet.');
        }
      }

      _fcmToken = await messaging.getToken();
      await _saveToken(_fcmToken);

      if (watchFirestore) _watchFirestoreChanges();
    } catch (error, stackTrace) {
      // Devices without Google Play services can still use the rest of the app.
      debugPrint('FCM initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _saveToken(String? token) async {
    if (token == null || token.isEmpty || Firebase.apps.isEmpty) return;

    try {
      final deviceId = await getDeviceId();
      await FirebaseFirestore.instance
          .collection('notification_tokens')
          .doc(_safeDocumentId(token))
          .set({
        'token': token,
        'deviceId': deviceId,
        'platform': defaultTargetPlatform.name,
        'backend': BackendConfig.useNas ? 'nas' : 'firebase',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // Notification registration must never prevent the app from opening.
      debugPrint('Notification token registration failed: $error');
    }
  }

  void _watchFirestoreChanges() {
    _qnaSubscription =
        FirebaseFirestore.instance.collection('qna').snapshots().listen(
      (snapshot) => unawaited(_handleQnaSnapshot(snapshot)),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('QnA notification listener failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    _pdfSubscription = FirebaseFirestore.instance
        .collection('pdf_documents')
        .doc('current')
        .snapshots()
        .listen(
      (snapshot) => unawaited(_handlePdfSnapshot(snapshot)),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('PDF notification listener failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
  }

  Future<void> _handleQnaSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final deviceId = await getDeviceId();
    final token = _fcmToken ?? await getFcmToken();

    if (!_qnaLoaded) {
      for (final doc in snapshot.docs) {
        _qnaAnswers[doc.id] = doc.data()['isAnswered'] == true;
      }
      _qnaLoaded = true;
      return;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final wasAnswered = _qnaAnswers[doc.id] ?? false;
      final isAnswered = data['isAnswered'] == true;
      _qnaAnswers[doc.id] = isAnswered;

      final belongsToThisDevice = data['authorDeviceId'] == deviceId ||
          (token != null && data['notificationToken'] == token);
      if (!wasAnswered && isAnswered && belongsToThisDevice) {
        await _showIfEnabled(
          type: 'qna_answer',
          title: 'Q&A 답변이 등록되었습니다',
          body: _shortText(
            data['answer']?.toString() ?? '질문에 대한 답변을 확인해 보세요.',
          ),
          payload: doc.id,
        );
      }
    }
  }

  Future<void> _handlePdfSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!snapshot.exists) return;
    final data = snapshot.data() ?? <String, dynamic>{};
    final version =
        '${data['updatedAt'] ?? ''}|${data['pdfUrl'] ?? ''}|${data['fileSize'] ?? ''}';
    if (_pdfVersion == null) {
      _pdfVersion = version;
      return;
    }
    if (_pdfVersion == version) return;
    _pdfVersion = version;

    await _invalidatePdfCache();

    await _showIfEnabled(
      type: 'pdf_update',
      title: 'PDF가 업데이트되었습니다',
      body: '새로운 말씀 PDF를 확인해 보세요.',
    );
  }

  void _startNasPolling() {
    unawaited(_pollNas());
    _nasTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_pollNas());
    });
  }

  Future<void> _pollNas() async {
    if (_nasPolling) return;
    _nasPolling = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final qnaData = await _nas.getJson('/api/qna');
      final rawItems = qnaData['items'];
      if (rawItems is List) {
        final snapshot = rawItems.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            );
        final deviceId = await getDeviceId();
        if (!_qnaLoaded) {
          for (final item in snapshot) {
            final id = item['id']?.toString();
            if (id != null) {
              _qnaAnswers[id] = prefs.getBool('nas_qna_answer_$id') ??
                  (item['isAnswered'] == true);
              await prefs.setBool('nas_qna_answer_$id', _qnaAnswers[id]!);
            }
          }
          _qnaLoaded = true;
        } else {
          for (final item in snapshot) {
            final id = item['id']?.toString();
            if (id == null) continue;
            final answered = item['isAnswered'] == true;
            final belongsToThisDevice = item['authorDeviceId'] == deviceId;
            if (!(_qnaAnswers[id] ?? false) &&
                answered &&
                belongsToThisDevice) {
              await _showIfEnabled(
                type: 'qna_answer',
                title: 'Q&A 답변이 등록되었습니다',
                body: _shortText(item['answer']?.toString() ?? '답변을 확인해 보세요.'),
                payload: id,
              );
            }
            _qnaAnswers[id] = answered;
            if (belongsToThisDevice) {
              await prefs.setBool('nas_qna_answer_$id', answered);
            }
          }
        }
      }

      final pdf = await _nas.getJson('/api/pdf/current/metadata');
      final version = '${pdf['updatedAt'] ?? ''}|${pdf['fileSize'] ?? ''}';
      final previousVersion = _pdfVersion ?? prefs.getString('nas_pdf_version');
      if (previousVersion == null) {
        // A cached PDF can belong to an earlier backend or may have been used
        // while the NAS was unavailable during the first app launch. Establish
        // the baseline silently, and invalidate only if this process has not
        // already downloaded the current NAS PDF.
        _pdfVersion = version;
        if (!PdfCacheService().hasLoadedNasPdfFromServer) {
          await _invalidatePdfCache();
        }
      } else if (previousVersion != version) {
        _pdfVersion = version;
        await _invalidatePdfCache();
        await _showIfEnabled(
          type: 'pdf_update',
          title: 'PDF가 업데이트되었습니다',
          body: '새로운 말씀 PDF를 확인해 보세요.',
        );
      }
      await prefs.setString('nas_pdf_version', version);
    } catch (error) {
      debugPrint('NAS notification polling failed: $error');
    } finally {
      _nasPolling = false;
    }
  }

  Future<void> _invalidatePdfCache() async {
    try {
      await PdfCacheService().invalidate();
    } catch (error, stackTrace) {
      debugPrint('PDF cache invalidation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _ensureLocalNotifications() async {
    final isPhone = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!isPhone) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'TheWordCalendar Q&A 및 PDF 업데이트 알림',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();
    await _local
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _localReady = true;
  }

  Future<void> _showIfEnabled({
    required String type,
    required String title,
    required String body,
    String? payload,
  }) async {
    final enabled = type == 'qna_answer'
        ? await _profile.isQnaNotificationsEnabled()
        : await _profile.isPdfNotificationsEnabled();
    if (!enabled || !_localReady) return;

    try {
      await _local.show(
        // NAS foreground polling and FCM can detect the same change at nearly
        // the same time. A stable ID makes the second delivery update the
        // first notification instead of duplicating it in the tray.
        id: (payload ?? type).hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'TheWordCalendar 업데이트 알림',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (error) {
      debugPrint('Local notification display failed: $error');
    }
  }

  String _shortText(String value) {
    final text = value.trim();
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}…';
  }

  String _safeDocumentId(String token) => token.replaceAll('/', '_');

  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _qnaSubscription?.cancel();
    await _pdfSubscription?.cancel();
    _nasTimer?.cancel();
  }
}
