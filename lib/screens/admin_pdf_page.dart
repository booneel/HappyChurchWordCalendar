import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../services/pdf_cache_service.dart';
import '../services/date_page_mapper.dart';
import '../services/pdf_settings_service.dart';
import '../services/backend_config.dart';
import '../services/nas_api_client.dart';

// ignore_for_file: unnecessary_brace_in_string_interps

class AdminPdfPage extends StatefulWidget {
  const AdminPdfPage({super.key});

  @override
  State<AdminPdfPage> createState() => _AdminPdfPageState();
}

class _AdminPdfPageState extends State<AdminPdfPage> {
  FirebaseStorage get _storage => FirebaseStorage.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final PdfCacheService _cacheService = PdfCacheService();
  final PdfSettingsService _settingsService = PdfSettingsService();
  final NasApiClient _nas = NasApiClient.instance;

  bool _loading = true;
  bool _uploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';

  // Remote metadata
  String _currentOriginalName = '';
  int? _currentPdfPageCount;
  String _currentFileName = '365일 매일묵상말씀.pdf';
  int? _currentSizeBytes;
  DateTime? _currentUpdatedTime;

  // Selected local file to upload
  PlatformFile? _pickedFile;
  int? _pickedFileSize;
  int? _pickedPdfPageCount;
  bool _readingPdfPageCount = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPdfInfo();
  }

  Future<void> _loadCurrentPdfInfo() async {
    setState(() => _loading = true);

    try {
      final settings = await _settingsService.loadSettings(forceRefresh: true);
      _currentFileName = settings.pdfFileName;
      _currentOriginalName = settings.pdfFileName;
      _currentPdfPageCount = settings.pdfPageCount;

      if (BackendConfig.useNas) {
        final data = await _nas.getJson('/api/pdf/current/metadata');
        _currentFileName =
            (data['fileName'] as String?)?.trim() ?? _currentFileName;
        _currentOriginalName =
            (data['originalName'] as String?)?.trim() ?? _currentFileName;
        _currentSizeBytes = (data['fileSize'] as num?)?.toInt();
        _currentPdfPageCount =
            (data['pdfPageCount'] as num?)?.toInt() ?? _currentPdfPageCount;
        _currentUpdatedTime = DateTime.tryParse(
          data['updatedAt']?.toString() ?? '',
        );
        return;
      }

      // Firestore doc 정보 확인
      final doc = await _db.collection('pdf_documents').doc('current').get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        if (data['fileName'] != null) {
          _currentFileName = data['fileName'] as String;
        }
        if (data['originalName'] != null) {
          _currentOriginalName = data['originalName'] as String;
        }
        if (data['fileSize'] != null) {
          _currentSizeBytes = (data['fileSize'] as num).toInt();
        }
        if (data['pdfPageCount'] != null) {
          _currentPdfPageCount = (data['pdfPageCount'] as num).toInt();
        }
        if (data['updatedAt'] != null) {
          _currentUpdatedTime = (data['updatedAt'] as Timestamp).toDate();
        }
      }

      // Storage 실제 metadata
      final ref = _storage.ref(_currentFileName);
      final metadata = await ref.getMetadata();
      _currentSizeBytes ??= metadata.size;
      _currentUpdatedTime ??= metadata.updated;
    } catch (_) {
      // Storage metadata 읽기 실패 시 기본값 유지
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (picked != null) {
      if (picked.extension?.toLowerCase() != 'pdf') {
        _showSnackBar('PDF 파일만 선택할 수 있습니다.');
        return;
      }
      if (picked.path == null) {
        _showSnackBar('선택한 PDF 파일의 경로를 읽지 못했습니다.');
        return;
      }
      final length = picked.lengthSync() ?? await picked.length();
      setState(() {
        _pickedFile = picked;
        _pickedFileSize = length;
        _pickedPdfPageCount = null;
        _readingPdfPageCount = true;
      });

      try {
        final document = await pdfrx.PdfDocument.openFile(picked.path!);
        final pageCount = document.pages.length;
        await document.dispose();
        if (!mounted) return;
        setState(() {
          _pickedPdfPageCount = pageCount;
          _readingPdfPageCount = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _readingPdfPageCount = false);
        _showSnackBar('PDF 페이지 수를 읽지 못했습니다. 파일을 확인해 주세요.');
      }
    }
  }

  int _dailyCountForPdf({required int totalPages, required int startPage}) {
    final availablePages = totalPages - startPage + 1;
    if (availablePages < 1) return 0;
    return availablePages > 366 ? 366 : availablePages;
  }

  Future<void> _uploadAndReplacePdf() async {
    if (_pickedFile == null || _pickedFile?.path == null) {
      _showSnackBar('교체할 PDF 파일을 선택해 주세요.');
      return;
    }

    if (_readingPdfPageCount || _pickedPdfPageCount == null) {
      _showSnackBar('PDF 페이지 수를 확인하는 중입니다. 잠시 후 다시 시도해 주세요.');
      return;
    }

    final filePath = _pickedFile!.path!;
    final fileToUpload = File(filePath);
    if (!await fileToUpload.exists()) {
      _showSnackBar('선택한 파일이 기기에 존재하지 않습니다.');
      return;
    }

    final fileSize = _pickedFileSize ?? await _pickedFile!.length() ?? 0;
    final pickedPdfPageCount = _pickedPdfPageCount!;
    final settings = await _settingsService.loadSettings();
    final dailyPageCount = _dailyCountForPdf(
      totalPages: pickedPdfPageCount,
      startPage: settings.dailyStartPdfPage,
    );

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('PDF 교체 확인'),
        content: SingleChildScrollView(
          child: Text(
            '새로운 PDF로 교체하시겠습니까?\n\n'
            '파일명: ${_pickedFile!.name}\n'
            '크기: ${_formatBytes(fileSize)}\n\n'
            '업로드 완료 후 모든 사용자가 새 PDF를 다운로드하게 됩니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('업로드 및 교체'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _uploading = true;
      _uploadProgress = 0.0;
      _uploadStatus = '업로드 준비 중...';
    });

    try {
      if (BackendConfig.useNas) {
        final uploaded = await _nas.uploadPdf(
          fileToUpload,
          fileName: _pickedFile!.name,
        );
        _currentFileName =
            uploaded['fileName']?.toString() ?? _pickedFile!.name;
        await _cacheService.refresh();

        if (!mounted) return;
        setState(() {
          _pickedFile = null;
          _pickedFileSize = null;
          _pickedPdfPageCount = null;
          _uploading = false;
        });
        await _settingsService.saveSettings(
          dailyStartPdfPage: settings.dailyStartPdfPage,
          dailyPageCount: dailyPageCount,
          pdfPageCount: pickedPdfPageCount,
          pdfFileName: _currentFileName,
        );
        await _loadCurrentPdfInfo();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('PDF 교체 완료'),
            content: const Text('NAS PDF가 교체되고 앱 캐시가 갱신되었습니다.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }

      final storageRef = _storage.ref(_currentFileName);

      final metadata = SettableMetadata(
        contentType: 'application/pdf',
        customMetadata: {
          'uploadedBy': 'admin',
          'originalName': _pickedFile!.name,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      final uploadTask = storageRef.putFile(fileToUpload, metadata);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (snapshot.totalBytes > 0) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
              _uploadStatus =
                  '${(progress * 100).toStringAsFixed(1)}% 업로드 중 (${_formatBytes(snapshot.bytesTransferred)} / ${_formatBytes(snapshot.totalBytes)})';
            });
          }
        }
      });

      await uploadTask;

      if (mounted) {
        setState(() => _uploadStatus = 'Firestore 및 캐시 갱신 중...');
      }

      final downloadUrl = await storageRef.getDownloadURL();

      // Firestore pdf_documents/current 업데이트
      await _db.collection('pdf_documents').doc('current').set({
        'pdfUrl': downloadUrl,
        'fileName': _currentFileName,
        'fileSize': fileSize,
        'pdfPageCount': pickedPdfPageCount,
        'dailyPageCount': dailyPageCount,
        'originalName': _pickedFile!.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 로컬 PDF 캐시 강제 새로고침
      await _cacheService.refresh();

      if (!mounted) return;

      setState(() {
        _pickedFile = null;
        _pickedFileSize = null;
        _pickedPdfPageCount = null;
        _uploading = false;
      });

      await _settingsService.saveSettings(
        dailyStartPdfPage: settings.dailyStartPdfPage,
        dailyPageCount: dailyPageCount,
        pdfPageCount: pickedPdfPageCount,
        pdfFileName: _currentFileName,
      );

      await _loadCurrentPdfInfo();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('PDF 교체 완료'),
          content: const Text(
            '성공적으로 PDF 파일이 교체되었습니다.\n'
            '앱 내 PDF 캐시가 새로고침되었습니다.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showErrorDialog('PDF 업로드 중 오류가 발생했습니다: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy년 M월 d일 HH:mm', 'ko_KR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF 관리'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading || _uploading ? null : _loadCurrentPdfInfo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. 현재 적용된 PDF 카드
                Text(
                  '📄 현재 저장소 PDF 정보',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.picture_as_pdf,
                                color: Color(0xFF4F7CAC),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentOriginalName.isNotEmpty
                                        ? _currentOriginalName
                                        : _currentFileName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _currentSizeBytes != null
                                        ? _formatBytes(_currentSizeBytes!)
                                        : '용량 정보 확인 중...',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (_currentPdfPageCount != null)
                                    Text(
                                      'PDF 전체 ${_currentPdfPageCount}페이지 · 날짜 매핑 ${DatePageMapper.dailyPageCount}일',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '최종 업데이트',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                _currentUpdatedTime != null
                                    ? dateFormat.format(_currentUpdatedTime!)
                                    : '알 수 없음',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // 2. 새 PDF 선택 및 업로드
                Text(
                  '📤 새 PDF 파일 교체',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '새로운 말씀 PDF 파일(.pdf)을 선택하여 서버에 업로드합니다.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_pickedFile != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.file_present,
                                  color: Color(0xFF4F7CAC),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _pickedFile!.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (_pickedFileSize != null)
                                        Text(
                                          _formatBytes(_pickedFileSize!),
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      if (_readingPdfPageCount)
                                        Text(
                                          'PDF 페이지 수 확인 중...',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        )
                                      else if (_pickedPdfPageCount != null)
                                        Text(
                                          '전체 ${_pickedPdfPageCount}페이지 · 매핑 일수 ${_dailyCountForPdf(totalPages: _pickedPdfPageCount!, startPage: _settingsService.currentSettings.dailyStartPdfPage)}일',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '선택 취소',
                                  onPressed: _uploading
                                      ? null
                                      : () => setState(() {
                                            _pickedFile = null;
                                            _pickedFileSize = null;
                                            _pickedPdfPageCount = null;
                                            _readingPdfPageCount = false;
                                          }),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _uploading ? null : _pickFile,
                                icon: const Icon(Icons.folder_open),
                                label: Text(
                                  _pickedFile == null
                                      ? 'PDF 파일 선택'
                                      : '다른 파일 선택',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_pickedFile != null) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  _uploading ? null : _uploadAndReplacePdf,
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('서버로 업로드 및 교체'),
                            ),
                          ),
                        ],
                        if (_uploading) ...[
                          const SizedBox(height: 20),
                          LinearProgressIndicator(value: _uploadProgress),
                          const SizedBox(height: 8),
                          Text(
                            _uploadStatus,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 안내 상자
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            BackendConfig.useNas
                                ? 'PDF 교체 후 실행 중인 사용자 앱은 약 30초 간격으로 변경을 확인합니다. '
                                    '앱이 완전히 종료된 경우 즉시 푸시 알림은 지원하지 않습니다.'
                                : 'PDF를 교체하면 서버에 새 파일이 저장되고 사용자에게 업데이트 알림이 전송됩니다. '
                                    '사용자 앱은 알림을 받거나 다시 실행할 때 새 PDF를 확인하며, 인터넷이 없으면 저장된 PDF를 계속 보여줍니다.',
                            style: const TextStyle(fontSize: 13, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
