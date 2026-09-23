import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class PdfRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> getPdfDownloadUrl() async {
    final ref = _storage.ref('365일 매일묵상말씀.pdf');
    return ref.getDownloadURL();
  }

  Future<String?> getCurrentPdfUrl() async {
    final doc = await _db.collection('pdf_documents').doc('current').get();
    return doc.data()?['pdfUrl'] as String?;
  }

  Future<int?> getPageForDate(DateTime date) async {
    final doc = await _db.collection('pdf_pages').doc(_dateKey(date)).get();
    return (doc.data()?['page'] as num?)?.toInt();
  }

  Future<String?> getTitleForDate(DateTime date) async {
    final doc = await _db.collection('pdf_pages').doc(_dateKey(date)).get();
    final value = doc.data()?['title'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Future<String?> getTitleForPage(int page) async {
    final snapshot = await _db
        .collection('pdf_pages')
        .where('page', isEqualTo: page)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final value = snapshot.docs.first.data()['title'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getTopPages() async {
    final snapshot = await _db
        .collection('page_stats')
        .orderBy('views', descending: true)
        .limit(3)
        .get();

    return snapshot.docs
        .map(
          (d) => {
            'page': d.data()['page'] ?? 0,
            'views': d.data()['views'] ?? 0,
          },
        )
        .toList();
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
