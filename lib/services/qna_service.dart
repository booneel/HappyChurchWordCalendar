import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_config.dart';
import 'nas_api_client.dart';
import 'notification_service.dart';

class QnaItem {
  final String id;
  final String title;
  final String content;
  final String authorName;
  final String? authorDeviceId;
  final String? notificationToken;
  final DateTime createdAt;
  final String? answer;
  final DateTime? answeredAt;
  final bool isAnswered;
  final bool isReadByAdmin;

  const QnaItem({
    required this.id,
    required this.title,
    required this.content,
    required this.authorName,
    this.authorDeviceId,
    this.notificationToken,
    required this.createdAt,
    this.answer,
    this.answeredAt,
    this.isAnswered = false,
    this.isReadByAdmin = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'authorName': authorName,
        'authorDeviceId': authorDeviceId,
        'notificationToken': notificationToken,
        'createdAt': createdAt.toIso8601String(),
        'answer': answer,
        'answeredAt': answeredAt?.toIso8601String(),
        'isAnswered': isAnswered,
        'isReadByAdmin': isReadByAdmin,
      };

  factory QnaItem.fromJson(Map<String, dynamic> json) {
    return QnaItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '익명',
      authorDeviceId: json['authorDeviceId'] as String?,
      notificationToken: json['notificationToken'] as String?,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      answer: json['answer'] as String?,
      answeredAt: DateTime.tryParse(json['answeredAt']?.toString() ?? ''),
      isAnswered: json['isAnswered'] as bool? ?? false,
      isReadByAdmin: json['isReadByAdmin'] as bool? ?? false,
    );
  }

  factory QnaItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return QnaItem(
      id: doc.id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '익명',
      authorDeviceId: data['authorDeviceId'] as String?,
      notificationToken: data['notificationToken'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answer: data['answer'] as String?,
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate(),
      isAnswered: data['isAnswered'] as bool? ?? false,
      isReadByAdmin: data['isReadByAdmin'] as bool? ?? false,
    );
  }
}

class QnaService {
  QnaService._();
  static final QnaService instance = QnaService._();
  factory QnaService() => instance;

  static const String _collection = 'qna';
  static const String _localKey = 'qna_items_local_v1';

  final NasApiClient _nas = NasApiClient.instance;
  final Random _random = Random();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 새 질문 등록 (제목, 내용)
  Future<void> createQuestion({
    required String title,
    required String content,
    required String authorName,
  }) async {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff).toRadixString(16)}';
    final now = DateTime.now();
    final authorDeviceId = await NotificationService.instance.getDeviceId();
    final notificationToken = await NotificationService.instance.getFcmToken();

    final newItem = QnaItem(
      id: id,
      title: title.trim(),
      content: content.trim(),
      authorName: authorName.trim().isEmpty ? '사용자' : authorName.trim(),
      authorDeviceId: authorDeviceId,
      notificationToken: notificationToken,
      createdAt: now,
      isAnswered: false,
      isReadByAdmin: false,
    );

    // 1. 로컬 SharedPreferences에 먼저 저장
    await _saveLocalItem(newItem);

    // 2. NAS는 먼저 대기열에 기록해 앱이 종료되어도 재전송할 수 있게 합니다.
    if (BackendConfig.useNas) {
      await _nas.postJson('/api/qna', newItem.toJson());
      await _saveLocalItem(newItem);
      return;
    }

    await _saveLocalItem(newItem);

    // 3. Firestore 서버 저장
    try {
      await _db.collection(_collection).doc(id).set({
        'title': title.trim(),
        'content': content.trim(),
        'authorName': authorName.trim().isEmpty ? '사용자' : authorName.trim(),
        'authorDeviceId': authorDeviceId,
        'notificationToken': notificationToken,
        'createdAt': FieldValue.serverTimestamp(),
        'isAnswered': false,
        'isReadByAdmin': false,
      });
    } catch (_) {
      // 오프라인 상태에서도 로컬 데이터 유지
    }
  }

  /// QnA 전체 목록 가져오기
  Future<List<QnaItem>> getQuestions() async {
    try {
      if (BackendConfig.useNas) {
        final data = await _nas.getJson('/api/qna');
        final rawItems = data['items'];
        final items = rawItems is List
            ? rawItems
                .whereType<Map>()
                .map(
                    (item) => QnaItem.fromJson(Map<String, dynamic>.from(item)))
                .toList()
            : <QnaItem>[];
        await _saveLocalList(items);
        return items;
      }
      final snapshot = await _db
          .collection(_collection)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final remoteList =
          snapshot.docs.map((doc) => QnaItem.fromFirestore(doc)).toList();

      if (remoteList.isNotEmpty) {
        await _saveLocalList(remoteList);
        return remoteList;
      }
    } catch (_) {}

    return await _loadLocalList();
  }

  /// QnA 전체 목록 Realtime Stream
  Stream<List<QnaItem>> streamQuestions() {
    if (BackendConfig.useNas) return _nasQuestionStream();
    return _db
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => QnaItem.fromFirestore(doc)).toList());
  }

  Future<List<QnaItem>> getAdminQuestions() async {
    if (BackendConfig.useNas && !_nas.hasAdminToken) return [];
    try {
      if (BackendConfig.useNas) {
        final data = await _nas.getJson('/api/admin/qna', admin: true);
        final rawItems = data['items'];
        final items = rawItems is List
            ? rawItems
                .whereType<Map>()
                .map(
                    (item) => QnaItem.fromJson(Map<String, dynamic>.from(item)))
                .toList()
            : <QnaItem>[];
        await _saveLocalList(items);
        return items;
      }

      final snapshot = await _db
          .collection(_collection)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      final items =
          snapshot.docs.map((doc) => QnaItem.fromFirestore(doc)).toList();
      if (items.isNotEmpty) await _saveLocalList(items);
      return items;
    } catch (error) {
      if (error is HttpException &&
          (error.message.contains('401') || error.message.contains('403'))) {
        return [];
      }
      return _loadLocalList();
    }
  }

  Stream<List<QnaItem>> streamAdminQuestions() {
    if (BackendConfig.useNas) return _nasAdminQuestionStream();
    return _db
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => QnaItem.fromFirestore(doc)).toList());
  }

  /// 관리자: 질문에 답변 등록/수정
  Future<void> answerQuestion({
    required String questionId,
    required String answer,
  }) async {
    final now = DateTime.now();
    final updates = {
      'answer': answer.trim(),
      'answeredAt': now.toUtc().toIso8601String(),
      'isAnswered': true,
      'isReadByAdmin': true,
    };

    if (BackendConfig.useNas) {
      await _nas.putJson('/api/qna/$questionId', updates);
    } else {
      await _db.collection(_collection).doc(questionId).set(
        {
          'answer': answer.trim(),
          'answeredAt': FieldValue.serverTimestamp(),
          'isAnswered': true,
          'isReadByAdmin': true,
        },
        SetOptions(merge: true),
      );
    }

    // 로컬 갱신
    final local = await _loadLocalList();
    final updated = local.map((q) {
      if (q.id == questionId) {
        return QnaItem(
          id: q.id,
          title: q.title,
          content: q.content,
          authorName: q.authorName,
          authorDeviceId: q.authorDeviceId,
          notificationToken: q.notificationToken,
          createdAt: q.createdAt,
          answer: answer.trim(),
          answeredAt: now,
          isAnswered: true,
          isReadByAdmin: true,
        );
      }
      return q;
    }).toList();
    await _saveLocalList(updated);
  }

  Future<void> deleteQuestion(String questionId) async {
    if (BackendConfig.useNas) {
      await _nas.delete('/api/qna/$questionId');
    } else {
      await _db.collection(_collection).doc(questionId).delete();
    }

    final remaining = (await _loadLocalList())
        .where((item) => item.id != questionId)
        .toList();
    await _saveLocalList(remaining);
  }

  /// 관리자: 질문 읽음 처리
  Future<void> markAsReadByAdmin(String questionId) async {
    if (BackendConfig.useNas && !_nas.isServerReachable) return;
    try {
      if (BackendConfig.useNas) {
        await _nas.putJson('/api/qna/$questionId', {'isReadByAdmin': true});
      } else {
        await _db.collection(_collection).doc(questionId).set(
          {'isReadByAdmin': true},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  /// 관리자용 읽지 않은 질문 수 조회
  Future<int> getUnreadQuestionCount() async {
    try {
      if (BackendConfig.useNas) {
        final items = await getAdminQuestions();
        return items.where((item) => !item.isReadByAdmin).length;
      }
      final snapshot = await _db
          .collection(_collection)
          .where('isReadByAdmin', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// 관리자용 읽지 않은 질문 수 Stream
  Stream<int> streamUnreadCount() {
    if (BackendConfig.useNas) {
      return _nasAdminQuestionStream().map(
        (items) => items.where((item) => !item.isReadByAdmin).length,
      );
    }
    return _db
        .collection(_collection)
        .where('isReadByAdmin', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<List<QnaItem>> _nasQuestionStream() async* {
    yield await _loadLocalList();
    while (true) {
      yield await getQuestions();
      await Future<void>.delayed(const Duration(seconds: 30));
    }
  }

  Stream<List<QnaItem>> _nasAdminQuestionStream() async* {
    yield _nas.hasAdminToken ? await _loadLocalList() : <QnaItem>[];
    while (true) {
      yield await getAdminQuestions();
      await Future<void>.delayed(const Duration(seconds: 30));
    }
  }

  Future<List<QnaItem>> _loadLocalList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((item) => QnaItem.fromJson(item))
            .toList();
      }
    } catch (_) {}

    return [];
  }

  Future<void> _saveLocalList(List<QnaItem> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _localKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveLocalItem(QnaItem item) async {
    final list = await _loadLocalList();
    final updated = [item, ...list.where((e) => e.id != item.id)];
    await _saveLocalList(updated);
  }
}
