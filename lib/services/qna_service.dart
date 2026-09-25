import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_config.dart';
import 'nas_api_client.dart';

class QnaItem {
  final String id;
  final String title;
  final String content;
  final String authorName;
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      answer: data['answer'] as String?,
      answeredAt: (data['answeredAt'] as Timestamp?)?.toDate(),
      isAnswered: data['isAnswered'] as bool? ?? false,
      isReadByAdmin: data['isReadByAdmin'] as bool? ?? false,
    );
  }
}

class QnaService {
  QnaService._() {
    if (BackendConfig.useNas) {
      unawaited(_flushPendingQuestions());
      unawaited(_flushPendingUpdates());
    }
  }
  static final QnaService instance = QnaService._();
  factory QnaService() => instance;

  static const String _collection = 'qna';
  static const String _localKey = 'qna_items_local_v1';
  static const String _pendingKey = 'qna_pending_uploads_v1';
  static const String _pendingUpdatesKey = 'qna_pending_updates_v1';

  final NasApiClient _nas = NasApiClient.instance;
  final Random _random = Random();
  Future<void> _pendingFlushQueue = Future<void>.value();

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

    final newItem = QnaItem(
      id: id,
      title: title.trim(),
      content: content.trim(),
      authorName: authorName.trim().isEmpty ? '사용자' : authorName.trim(),
      createdAt: now,
      isAnswered: false,
      isReadByAdmin: false,
    );

    // 1. 로컬 SharedPreferences에 먼저 저장
    await _saveLocalItem(newItem);

    // 2. NAS는 먼저 대기열에 기록해 앱이 종료되어도 재전송할 수 있게 합니다.
    if (BackendConfig.useNas) {
      await _enqueuePendingQuestion(newItem);
      await _flushPendingQuestions();
      return;
    }

    // 3. Firestore 서버 저장
    try {
      await _db.collection(_collection).doc(id).set({
        'title': title.trim(),
        'content': content.trim(),
        'authorName': authorName.trim().isEmpty ? '사용자' : authorName.trim(),
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
        if (items.isNotEmpty) await _saveLocalList(items);
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
      await _enqueuePendingUpdate(questionId, updates);
      await _flushPendingUpdates();
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

  /// 관리자: 질문 읽음 처리
  Future<void> markAsReadByAdmin(String questionId) async {
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
        final items = await getQuestions();
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
      return _nasQuestionStream().map(
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
    while (true) {
      yield await getQuestions();
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

  Future<List<QnaItem>> _loadPendingQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => QnaItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}

    return [];
  }

  Future<void> _savePendingQuestions(List<QnaItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _addPendingQuestion(QnaItem item) async {
    final pending = await _loadPendingQuestions();
    final updated = [item, ...pending.where((old) => old.id != item.id)];
    await _savePendingQuestions(updated);
  }

  Future<void> _enqueuePendingQuestion(QnaItem item) {
    final operation = _pendingFlushQueue.then((_) {
      return _addPendingQuestion(item);
    });
    _pendingFlushQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _flushPendingQuestions() {
    final operation =
        _pendingFlushQueue.then((_) => _flushPendingQuestionsOnce());
    _pendingFlushQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _flushPendingQuestionsOnce() async {
    if (!BackendConfig.useNas) return;

    final pending = await _loadPendingQuestions();
    if (pending.isEmpty) return;

    var firstUnsent = pending.length;
    for (var index = 0; index < pending.length; index++) {
      try {
        await _nas.postJson('/api/qna', pending[index].toJson());
      } catch (_) {
        firstUnsent = index;
        break;
      }
    }

    await _savePendingQuestions(pending.skip(firstUnsent).toList());
  }

  Future<List<Map<String, dynamic>>> _loadPendingUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingUpdatesKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where(
              (item) => item['questionId'] is String && item['updates'] is Map,
            )
            .toList();
      }
    } catch (_) {}

    return [];
  }

  Future<void> _savePendingUpdates(
    List<Map<String, dynamic>> updates,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingUpdatesKey, jsonEncode(updates));
  }

  Future<void> _enqueuePendingUpdate(
    String questionId,
    Map<String, dynamic> updates,
  ) {
    final operation = _pendingFlushQueue.then((_) async {
      final pending = await _loadPendingUpdates();
      final withoutSameQuestion = pending.where(
        (item) => item['questionId'] != questionId,
      );
      await _savePendingUpdates([
        ...withoutSameQuestion,
        {
          'questionId': questionId,
          'updates': updates,
        },
      ]);
    });
    _pendingFlushQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _flushPendingUpdates() {
    final operation =
        _pendingFlushQueue.then((_) => _flushPendingUpdatesOnce());
    _pendingFlushQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _flushPendingUpdatesOnce() async {
    if (!BackendConfig.useNas) return;

    final pending = await _loadPendingUpdates();
    var firstUnsent = pending.length;
    for (var index = 0; index < pending.length; index++) {
      final item = pending[index];
      try {
        await _nas.putJson(
          '/api/qna/${item['questionId']}',
          Map<String, dynamic>.from(item['updates'] as Map),
        );
      } catch (_) {
        firstUnsent = index;
        break;
      }
    }

    await _savePendingUpdates(pending.skip(firstUnsent).toList());
  }
}
