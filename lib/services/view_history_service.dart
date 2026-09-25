import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_config.dart';
import 'nas_api_client.dart';

class PageViewStat {
  final int page;
  final int views;

  const PageViewStat({
    required this.page,
    required this.views,
  });
}

class RecentDirectOpen {
  final int page;
  final DateTime date;
  final DateTime openedAt;

  const RecentDirectOpen({
    required this.page,
    required this.date,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
        'page': page,
        'date': date.toIso8601String(),
        'openedAt': openedAt.toIso8601String(),
      };

  static RecentDirectOpen? fromJson(
    Map<String, dynamic> json,
  ) {
    final page = (json['page'] as num?)?.toInt();
    final date = DateTime.tryParse(
      json['date']?.toString() ?? '',
    );
    final openedAt = DateTime.tryParse(
      json['openedAt']?.toString() ?? '',
    );

    if (page == null || date == null || openedAt == null) {
      return null;
    }

    return RecentDirectOpen(
      page: page,
      date: date,
      openedAt: openedAt,
    );
  }
}

class ViewHistoryService {
  ViewHistoryService._() {
    _init();
  }

  static final ViewHistoryService instance = ViewHistoryService._();

  factory ViewHistoryService() => instance;

  static const String _recentKey = 'recent_direct_devotional_opens_v1';
  static const String _pageViewsKey = 'local_page_view_counts_v1';
  static const String _pendingNasViewsKey = 'pending_nas_page_views_v1';

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final NasApiClient _nas = NasApiClient.instance;
  final StreamController<List<PageViewStat>> _topPagesController =
      StreamController<List<PageViewStat>>.broadcast();
  Future<void> _nasWriteQueue = Future<void>.value();
  final Random _random = Random();

  Map<int, int> _cachedLocalViews = {};
  final Map<int, int> _cachedRemoteViews = {};
  Future<void> _localWriteQueue = Future<void>.value();

  void _init() {
    _getLocalPageViews().then((_) => _emitTopPages());

    // Widget tests can mount DatePdfApp without running main(), so Firebase
    // may not have an app yet. In that case local history remains available
    // and the remote listener is attached after normal app initialization.
    if (BackendConfig.useNas) {
      unawaited(_flushPendingNasViews());
      return;
    }
    if (Firebase.apps.isEmpty) return;

    _db.collection('page_stats').snapshots().listen(
      (snapshot) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final pageNum =
              (data['page'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
          final views = (data['views'] as num?)?.toInt() ?? 0;

          if (pageNum > 0) {
            _cachedRemoteViews[pageNum] = views;
          }
        }
        _emitTopPages();
      },
      onError: (_) {
        _emitTopPages();
      },
    );
  }

  void _emitTopPages({int limit = 100}) {
    final statsMap = <int, int>{};

    for (final entry in _cachedLocalViews.entries) {
      statsMap[entry.key] = entry.value;
    }

    for (final entry in _cachedRemoteViews.entries) {
      final localViews = statsMap[entry.key] ?? 0;
      statsMap[entry.key] = max(localViews, entry.value);
    }

    final list = statsMap.entries
        .map((e) => PageViewStat(page: e.key, views: e.value))
        .where((e) => e.page > 0 && e.views > 0)
        .toList();

    list.sort((a, b) => b.views.compareTo(a.views));
    _topPagesController.add(list.take(limit).toList());
  }

  /// 실시간 많이 본 말씀 Top N 스트림
  Stream<List<PageViewStat>> streamTopPages({int limit = 3}) {
    Future.microtask(_emitTopPages);
    return _topPagesController.stream
        .map((items) => items.take(limit).toList());
  }

  /// 반드시 "사용자가 목록/카드/버튼을 직접 눌러 PDF에 진입할 때"만 호출합니다.
  Future<void> recordDirectOpen({
    required int page,
    required DateTime date,
  }) async {
    final localUpdate = _localWriteQueue.then((_) async {
      await _recordRecentLocally(page: page, date: date);
      await _incrementLocalPageView(page);
      _emitTopPages();
    });
    _localWriteQueue = localUpdate.catchError((_) {});
    await localUpdate;

    // NAS는 실패한 조회수를 로컬 대기열에 남겨 재전송합니다.
    // Firebase는 SDK의 오프라인 쓰기 큐를 사용합니다.
    if (BackendConfig.useNas) {
      unawaited(_queueNasView(page));
    } else {
      unawaited(_writeRemoteView(page));
    }
  }

  Future<bool> _writeRemoteView(
    int page, {
    int count = 1,
    String? eventId,
  }) async {
    try {
      if (BackendConfig.useNas) {
        await _nas.postJson('/api/stats/direct-open', {
          'page': page,
          'count': count,
          if (eventId != null) 'eventId': eventId,
          'openedAt': DateTime.now().toUtc().toIso8601String(),
        });
        return true;
      }
      await _db.collection('page_stats').doc(page.toString()).set(
        {
          'page': page,
          'views': FieldValue.increment(count),
          'lastDirectOpenedAt': FieldValue.serverTimestamp(),
          'countType': 'direct_open_only',
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _queueNasView(int page) {
    final operation = _nasWriteQueue.then((_) async {
      await _addPendingNasView(page);
      await _flushPendingNasViewsOnce();
    });
    _nasWriteQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _flushPendingNasViews() {
    final operation = _nasWriteQueue.then((_) => _flushPendingNasViewsOnce());
    _nasWriteQueue = operation.catchError((_) {});
    return operation;
  }

  Future<Map<String, List<String>>> _loadPendingNasViews() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingNasViewsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final result = <String, List<String>>{};
        for (final entry in decoded.entries) {
          if (int.tryParse(entry.key.toString()) == null) continue;
          if (entry.value is List) {
            final eventIds = entry.value
                .map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .toList();
            if (eventIds.isNotEmpty) {
              result[entry.key.toString()] = eventIds;
            }
            continue;
          }

          // 이전 버전의 숫자 대기열도 유실 없이 읽습니다.
          final count = (entry.value as num?)?.toInt();
          if (count != null && count > 0) {
            result[entry.key.toString()] = List.generate(
              count,
              (index) => 'legacy-${entry.key}-$index',
            );
          }
        }
        return result;
      }
    } catch (_) {}

    return {};
  }

  Future<void> _savePendingNasViews(
    Map<String, List<String>> pending,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingNasViewsKey, jsonEncode(pending));
  }

  Future<void> _addPendingNasView(int page) async {
    final pending = await _loadPendingNasViews();
    final key = page.toString();
    pending[key] = [
      ...?pending[key],
      _newNasEventId(),
    ];
    await _savePendingNasViews(pending);
  }

  String _newNasEventId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff).toRadixString(16)}';
  }

  Future<void> _flushPendingNasViewsOnce() async {
    if (!BackendConfig.useNas) return;

    final pending = await _loadPendingNasViews();
    for (final entry in pending.entries.toList()) {
      final success = await _writeRemoteView(
        int.parse(entry.key),
        count: entry.value.length,
        eventId: entry.value.first,
      );
      if (!success) return;

      pending.remove(entry.key);
      await _savePendingNasViews(pending);
    }
  }

  /// 많이 본 말씀 목록 일회성 조회
  Future<List<PageViewStat>> getTopPages({
    int limit = 3,
  }) async {
    final statsMap = <int, int>{};

    final localMap = await _getLocalPageViews();
    for (final entry in localMap.entries) {
      statsMap[entry.key] = entry.value;
    }

    try {
      if (BackendConfig.useNas) {
        final data = await _nas.getJson(
          '/api/stats/top',
          query: {'limit': '$limit'},
        );
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final raw in rawItems) {
            if (raw is! Map) continue;
            final page = (raw['page'] as num?)?.toInt() ?? 0;
            final views = (raw['views'] as num?)?.toInt() ?? 0;
            if (page > 0 && views > 0) {
              final currentLocal = statsMap[page] ?? 0;
              statsMap[page] = max(currentLocal, views);
              _cachedRemoteViews[page] = views;
            }
          }
        }
      } else {
        final snapshot = await _db
            .collection('page_stats')
            .get()
            .timeout(const Duration(seconds: 4));

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final pageNum =
              (data['page'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0;
          final views = (data['views'] as num?)?.toInt() ?? 0;

          if (pageNum > 0) {
            final currentLocal = statsMap[pageNum] ?? 0;
            statsMap[pageNum] = max(currentLocal, views);
            _cachedRemoteViews[pageNum] = views;
          }
        }
      }
    } catch (_) {}

    final list = statsMap.entries
        .map((e) => PageViewStat(page: e.key, views: e.value))
        .where((e) => e.page > 0 && e.views > 0)
        .toList();

    list.sort((a, b) => b.views.compareTo(a.views));

    return list.take(limit).toList();
  }

  Future<List<RecentDirectOpen>> getRecent({
    int limit = 100,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);

    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return const [];
      }

      final result = <RecentDirectOpen>[];

      for (final item in decoded) {
        if (item is Map) {
          final parsed = RecentDirectOpen.fromJson(
            Map<String, dynamic>.from(item),
          );

          if (parsed != null) {
            result.add(parsed);
          }
        }
      }

      return result.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _recordRecentLocally({
    required int page,
    required DateTime date,
  }) async {
    final current = await getRecent(limit: 100);

    final updated = current.where((item) => item.page != page).toList();

    updated.insert(
      0,
      RecentDirectOpen(
        page: page,
        date: DateTime(
          date.year,
          date.month,
          date.day,
        ),
        openedAt: DateTime.now(),
      ),
    );

    final trimmed = updated.take(100).toList();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _recentKey,
      jsonEncode(
        trimmed.map((e) => e.toJson()).toList(),
      ),
    );
  }

  Future<Map<int, int>> _getLocalPageViews() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_pageViewsKey);
    if (jsonStr == null || jsonStr.isEmpty) return {};

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        final result = <int, int>{};
        for (final entry in decoded.entries) {
          final page = int.tryParse(entry.key.toString());
          final views = (entry.value as num?)?.toInt();
          if (page != null && views != null) {
            result[page] = views;
          }
        }
        _cachedLocalViews = result;
        return result;
      }
    } catch (_) {}

    return {};
  }

  Future<void> _incrementLocalPageView(int page) async {
    final views = await _getLocalPageViews();
    views[page] = (views[page] ?? 0) + 1;
    _cachedLocalViews = views;

    final prefs = await SharedPreferences.getInstance();
    final strMap = <String, int>{};
    for (final entry in views.entries) {
      strMap[entry.key.toString()] = entry.value;
    }
    await prefs.setString(_pageViewsKey, jsonEncode(strMap));
  }
}
