import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─── LibraryEntry (Theo dõi / Bookmark) ───────────────────────────────────────

class LibraryEntry {
  final int novelId;
  final String title;
  final String? coverUrl;
  final String? authorName;

  const LibraryEntry({
    required this.novelId,
    required this.title,
    this.coverUrl,
    this.authorName,
  });

  Map<String, dynamic> toJson() => {
    'novelId': novelId,
    'title': title,
    'coverUrl': coverUrl,
    'authorName': authorName,
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
    novelId: json['novelId'] as int,
    title: json['title'] as String,
    coverUrl: json['coverUrl'] as String?,
    authorName: json['authorName'] as String?,
  );
}

class LibraryNotifier extends StateNotifier<List<LibraryEntry>> {
  LibraryNotifier() : super([]) {
    _load();
  }

  static const _key = 'library_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((j) => LibraryEntry.fromJson(j as Map<String, dynamic>))
        .toList();
    state = list;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  Future<void> toggle(LibraryEntry entry) async {
    final exists = state.any((e) => e.novelId == entry.novelId);
    if (exists) {
      state = state.where((e) => e.novelId != entry.novelId).toList();
    } else {
      state = [entry, ...state]; // thêm vào đầu danh sách
    }
    await _save();
  }

  bool isFollowing(int novelId) => state.any((e) => e.novelId == novelId);
}

final followingProvider = StateNotifierProvider<LibraryNotifier, List<LibraryEntry>>(
  (ref) => LibraryNotifier(),
);

// ─── HistoryEntry (Lịch sử đọc) ──────────────────────────────────────────────

class HistoryEntry {
  final int novelId;
  final String title;
  final String? coverUrl;
  final String? authorName;
  final int chapterId;
  final String chapterTitle;
  final int chapterNumber;
  final DateTime readAt;

  const HistoryEntry({
    required this.novelId,
    required this.title,
    this.coverUrl,
    this.authorName,
    required this.chapterId,
    required this.chapterTitle,
    this.chapterNumber = 0,
    required this.readAt,
  });

  Map<String, dynamic> toJson() => {
    'novelId': novelId,
    'title': title,
    'coverUrl': coverUrl,
    'authorName': authorName,
    'chapterId': chapterId,
    'chapterTitle': chapterTitle,
    'chapterNumber': chapterNumber,
    'readAt': readAt.toIso8601String(),
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    novelId: json['novelId'] as int,
    title: json['title'] as String,
    coverUrl: json['coverUrl'] as String?,
    authorName: json['authorName'] as String?,
    chapterId: json['chapterId'] as int,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    chapterNumber: json['chapterNumber'] as int? ?? 0,
    readAt: DateTime.tryParse(json['readAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class HistoryNotifier extends StateNotifier<List<HistoryEntry>> {
  HistoryNotifier() : super([]) {
    _load();
  }

  static const _key = 'history_v1';
  static const _maxItems = 100; // giữ tối đa 100 mục lịch sử

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((j) => HistoryEntry.fromJson(j as Map<String, dynamic>))
        .toList();
    state = list;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  /// Thêm/cập nhật lịch sử — cùng novel → update chapter + readAt, đưa lên đầu
  Future<void> addHistory(HistoryEntry entry) async {
    final updated = state.where((e) => e.novelId != entry.novelId).toList();
    updated.insert(0, entry); // mới nhất ở đầu
    state = updated.take(_maxItems).toList();
    await _save();
  }

  Future<void> removeHistory(int novelId) async {
    state = state.where((e) => e.novelId != novelId).toList();
    await _save();
  }

  Future<void> clearAll() async {
    state = [];
    await _save();
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, List<HistoryEntry>>(
  (ref) => HistoryNotifier(),
);

// ─── Novel Metadata Cache (dùng bởi ReaderScreen để lấy title/cover) ─────────

/// Cache novel metadata được populate khi mở NovelDetailScreen
final novelMetaCacheProvider = StateProvider<Map<int, LibraryEntry>>((ref) => {});
