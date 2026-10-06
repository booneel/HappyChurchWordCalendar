import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'view_history_service.dart';

class BookmarkItem {
  final int page;
  final DateTime date;
  final DateTime bookmarkedAt;

  const BookmarkItem({
    required this.page,
    required this.date,
    required this.bookmarkedAt,
  });

  Map<String, dynamic> toJson() => {
        'page': page,
        'date': date.toIso8601String(),
        'bookmarkedAt': bookmarkedAt.toIso8601String(),
      };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      page: (json['page'] as num?)?.toInt() ?? 0,
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      bookmarkedAt:
          DateTime.tryParse(json['bookmarkedAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}

class BookmarkService {
  BookmarkService._() {
    _init();
  }

  static final BookmarkService instance = BookmarkService._();
  factory BookmarkService() => instance;

  static const String _bookmarksKey = 'user_bookmarks_list_v1';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final StreamController<List<BookmarkItem>> _bookmarksController =
      StreamController<List<BookmarkItem>>.broadcast();
  final StreamController<List<PageViewStat>> _topBookmarksController =
      StreamController<List<PageViewStat>>.broadcast();

  List<BookmarkItem> _cachedBookmarks = [];
  final Map<int, int> _cachedRemoteBookmarks = {};

  void _init() {
    _loadLocalBookmarks().then((_) {
      _emitBookmarks();
      _emitTopBookmarks();
    });

    try {
      _db.collection('bookmark_stats').snapshots().listen(
        (snapshot) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final pageNum = (data['page'] as num?)?.toInt() ??
                int.tryParse(doc.id) ??
                0;
            final count = (data['count'] as num?)?.toInt() ?? 0;
            if (pageNum > 0) {
              _cachedRemoteBookmarks[pageNum] = count;
            }
          }
          _emitTopBookmarks();
        },
        onError: (_) {
          _emitTopBookmarks();
        },
      );
    } catch (_) {}
  }

  void _emitBookmarks() {
    _bookmarksController.add(List.unmodifiable(_cachedBookmarks));
  }

  void _emitTopBookmarks() {
    final statsMap = <int, int>{};

    // 1. Calculate local bookmark counts
    for (final item in _cachedBookmarks) {
      statsMap[item.page] = (statsMap[item.page] ?? 0) + 1;
    }

    // 2. Merge remote Firestore bookmark counts
    for (final entry in _cachedRemoteBookmarks.entries) {
      final local = statsMap[entry.key] ?? 0;
      statsMap[entry.key] = max(local, entry.value);
    }

    final list = statsMap.entries
        .map((e) => PageViewStat(page: e.key, views: e.value))
        .where((e) => e.page > 0 && e.views > 0)
        .toList();

    list.sort((a, b) => b.views.compareTo(a.views));
    _topBookmarksController.add(list.take(10).toList());
  }

  /// 특정 페이지가 즐겨찾기 되어있는지 확인
  bool isBookmarkedSync(int page) {
    return _cachedBookmarks.any((b) => b.page == page);
  }

  Future<bool> isBookmarked(int page) async {
    await _loadLocalBookmarks();
    return isBookmarkedSync(page);
  }

  /// 즐겨찾기 토글 (추가/해제)
  Future<bool> toggleBookmark({
    required int page,
    required DateTime date,
  }) async {
    await _loadLocalBookmarks();

    final existingIndex = _cachedBookmarks.indexWhere((b) => b.page == page);
    final isAdded = existingIndex == -1;

    if (isAdded) {
      _cachedBookmarks.insert(
        0,
        BookmarkItem(
          page: page,
          date: date,
          bookmarkedAt: DateTime.now(),
        ),
      );
    } else {
      _cachedBookmarks.removeAt(existingIndex);
    }

    await _saveLocalBookmarks();
    _emitBookmarks();
    _emitTopBookmarks();

    // Firestore Sync
    try {
      final docRef = _db.collection('bookmark_stats').doc(page.toString());
      await docRef.set(
        {
          'page': page,
          'count': FieldValue.increment(isAdded ? 1 : -1),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}

    return isAdded;
  }

  /// 사용자의 즐겨찾기 목록 스트림
  Stream<List<BookmarkItem>> streamBookmarks() {
    Future.microtask(() => _emitBookmarks());
    return _bookmarksController.stream;
  }

  /// 사용자의 즐겨찾기 목록 일회성 조회
  Future<List<BookmarkItem>> getBookmarks() async {
    await _loadLocalBookmarks();
    return List.unmodifiable(_cachedBookmarks);
  }

  /// 즐겨찾기 수가 높은 말씀 Top N 스트림
  Stream<List<PageViewStat>> streamTopBookmarkedPages({int limit = 3}) {
    Future.microtask(() => _emitTopBookmarks());
    return _topBookmarksController.stream.map((list) => list.take(limit).toList());
  }

  /// 즐겨찾기 수가 높은 말씀 Top N 조회
  Future<List<PageViewStat>> getTopBookmarkedPages({int limit = 10}) async {
    await _loadLocalBookmarks();

    final statsMap = <int, int>{};
    for (final item in _cachedBookmarks) {
      statsMap[item.page] = (statsMap[item.page] ?? 0) + 1;
    }

    try {
      final snapshot = await _db.collection('bookmark_stats').get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final pageNum = (data['page'] as num?)?.toInt() ??
            int.tryParse(doc.id) ??
            0;
        final count = (data['count'] as num?)?.toInt() ?? 0;
        if (pageNum > 0) {
          final local = statsMap[pageNum] ?? 0;
          statsMap[pageNum] = max(local, count);
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

  Future<void> _loadLocalBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_bookmarksKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      _cachedBookmarks = [];
      return;
    }

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        _cachedBookmarks = decoded
            .whereType<Map<String, dynamic>>()
            .map((item) => BookmarkItem.fromJson(item))
            .toList();
      }
    } catch (_) {
      _cachedBookmarks = [];
    }
  }

  Future<void> _saveLocalBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _bookmarksKey,
      jsonEncode(_cachedBookmarks.map((e) => e.toJson()).toList()),
    );
  }
}
