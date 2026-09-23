import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ViewHistoryService._();

  static final ViewHistoryService instance =
      ViewHistoryService._();

  factory ViewHistoryService() => instance;

  static const String _recentKey =
      'recent_direct_devotional_opens_v1';

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  /// 반드시 "사용자가 목록/카드/버튼을 직접 눌러 PDF에 진입할 때"만 호출합니다.
  ///
  /// PdfViewer의 onPageChanged / 스크롤 / 손가락으로 페이지 이동에서는
  /// 절대 호출하지 않습니다.
  Future<void> recordDirectOpen({
    required int page,
    required DateTime date,
  }) async {
    await _recordRecentLocally(
      page: page,
      date: date,
    );

    try {
      await _db
          .collection('page_stats')
          .doc(page.toString())
          .set(
        {
          'page': page,
          'views': FieldValue.increment(1),
          'lastDirectOpenedAt':
              FieldValue.serverTimestamp(),
          'countType': 'direct_open_only',
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 통계 쓰기 실패가 PDF 열기를 막으면 안 됩니다.
    }
  }

  Future<List<PageViewStat>> getTopPages({
    int limit = 3,
  }) async {
    try {
      final snapshot = await _db
          .collection('page_stats')
          .orderBy('views', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map(
            (doc) => PageViewStat(
              page:
                  (doc.data()['page'] as num?)?.toInt() ??
                      int.tryParse(doc.id) ??
                      0,
              views:
                  (doc.data()['views'] as num?)?.toInt() ??
                      0,
            ),
          )
          .where((item) => item.page > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<RecentDirectOpen>> getRecent({
    int limit = 6,
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
    final current = await getRecent(limit: 30);

    final updated = current
        .where((item) => item.page != page)
        .toList();

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

    final trimmed = updated.take(20).toList();

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _recentKey,
      jsonEncode(
        trimmed.map((e) => e.toJson()).toList(),
      ),
    );
  }
}
