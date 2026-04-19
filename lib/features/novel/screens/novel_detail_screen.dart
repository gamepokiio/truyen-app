import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truyen_app/core/api/dio_client.dart';
import 'package:truyen_app/core/api/mock_data.dart';
import 'package:truyen_app/core/api/novel_api.dart';
import 'package:truyen_app/core/services/library_service.dart';

import 'package:truyen_app/core/auth/auth_provider.dart';
import 'package:truyen_app/shared/models/novel_model.dart';

part 'novel_detail_screen.g.dart';

final novelDetailInitialTabProvider = StateProvider<int>((ref) => 0);

// ─── Reading Progress ─────────────────────────────────────────────────────────

class ReadingProgress {
  final int chapterId;
  final int chapterNumber;
  final String chapterTitle;
  const ReadingProgress({
    required this.chapterId,
    required this.chapterNumber,
    required this.chapterTitle,
  });
}

class ReadingProgressService {
  static String _key(int novelId, String field) => 'rp_${novelId}_$field';

  static Future<ReadingProgress?> get(int novelId) async {
    final prefs = await SharedPreferences.getInstance();
    final chapterId = prefs.getInt(_key(novelId, 'cid'));
    if (chapterId == null) return null;
    return ReadingProgress(
      chapterId: chapterId,
      chapterNumber: prefs.getInt(_key(novelId, 'cnum')) ?? 0,
      chapterTitle: prefs.getString(_key(novelId, 'ctitle')) ?? '',
    );
  }

  static Future<void> save(int novelId, int chapterId, int chapterNumber,
      String chapterTitle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(novelId, 'cid'), chapterId);
    await prefs.setInt(_key(novelId, 'cnum'), chapterNumber);
    await prefs.setString(_key(novelId, 'ctitle'), chapterTitle);
  }
}

final readingProgressProvider =
    FutureProvider.family<ReadingProgress?, int>(
        (ref, novelId) => ReadingProgressService.get(novelId));

/// Tìm chapter tiếp theo — 1 logic duy nhất cho mọi novel (1–3000 chương).
/// Tính toán trang chính xác bằng công thức: không cần cache, không cần load tất cả.
final nextChapterProvider =
    FutureProvider.family<Chapter?, int>((ref, novelId) async {
  final progress = await ref.watch(readingProgressProvider(novelId).future);
  if (progress == null || progress.chapterNumber <= 0) return null;

  final totalChapters = await ref.watch(chapterCountProvider(novelId).future);
  final nextNum = progress.chapterNumber + 1;
  if (nextNum > totalChapters) return null; // đang ở chương cuối

  // Chapters API: newest-first. Chapter số N nằm ở vị trí (total−N+1) từ đầu.
  const perPage = 50;
  final totalPages = (totalChapters / perPage).ceil();
  final posFromTop = totalChapters - nextNum + 1;
  final calcPage   = (posFromTop / perPage).ceil().clamp(1, totalPages);

  final api = NovelApi(ref.read(cachedDioProvider)); // cache hit nếu trang đã load
  // Kiểm tra calcPage ± 1 phòng edge-case (chương bị skip số)
  for (final page in [calcPage, calcPage + 1, calcPage - 1]) {
    if (page < 1 || page > totalPages) continue;
    final res = await api.getChapters(novelId: novelId, page: page, perPage: perPage);
    final items = res['items'] as List? ?? [];
    final chapters = items.map((j) => Chapter.fromJson(j as Map<String, dynamic>)).toList();
    try { return chapters.firstWhere((c) => c.chapterNumber == nextNum); }
    catch (_) {}
  }
  return null;
});

final firstChapterProvider =
    FutureProvider.family<Chapter?, int>((ref, novelId) async {
  final api = NovelApi(ref.read(cachedDioProvider)); // cached
  final count = await ref.watch(chapterCountProvider(novelId).future);
  final totalPages = (count / 50).ceil().clamp(1, 9999);
  final res =
      await api.getChapters(novelId: novelId, page: totalPages, perPage: 50);
  final items = res['items'] as List? ?? [];
  if (items.isEmpty) return null;
  final chapters =
      items.map((j) => Chapter.fromJson(j as Map<String, dynamic>)).toList();
  return chapters.last;
});

// ─── Providers ────────────────────────────────────────────────────────────────

@riverpod
Future<Novel> novelDetail(Ref ref, int id) async {
  if (kUseMock) {
    await Future.delayed(const Duration(milliseconds: 300));
    return kMockNovels.firstWhere((n) => n.id == id,
        orElse: () => kMockNovels.first);
  }
  final api = NovelApi(ref.read(cachedDioProvider)); // cached
  final data = await api.getNovelById(id);
  return Novel.fromJson(data);
}

@riverpod
Future<int> chapterCount(Ref ref, int novelId) async {
  final api = NovelApi(ref.read(cachedDioProvider)); // cached
  return api.getChapterCount(novelId);
}

@riverpod
Future<List<Novel>> novelsByAuthor(Ref ref, int authorTermId) async {
  final api = NovelApi(ref.read(cachedDioProvider)); // cached
  final data = await api.getNovelsByAuthorTax(authorTermId, perPage: 10);
  return filterNovels(data.map((j) => Novel.fromJson(j)).toList());
}

// ─── Chapter Pagination — fixed RAM, jump-to-chapter ─────────────────────────

class ChapterPageState {
  final List<Chapter> chapters;   // chỉ trang hiện tại (50 chương)
  final int  currentPage;
  final int  totalPages;
  final int  totalChapters;
  final bool isLoading;
  final int? highlightChapterNum; // chương cần highlight sau khi jump

  const ChapterPageState({
    this.chapters         = const [],
    this.currentPage      = 0,
    this.totalPages       = 1,
    this.totalChapters    = 0,
    this.isLoading        = false,
    this.highlightChapterNum,
  });

  ChapterPageState copyWith({
    List<Chapter>? chapters,
    int?  currentPage,
    int?  totalPages,
    int?  totalChapters,
    bool? isLoading,
    int?  highlightChapterNum,
    bool  clearHighlight = false,
  }) => ChapterPageState(
    chapters:          chapters       ?? this.chapters,
    currentPage:       currentPage    ?? this.currentPage,
    totalPages:        totalPages     ?? this.totalPages,
    totalChapters:     totalChapters  ?? this.totalChapters,
    isLoading:         isLoading      ?? this.isLoading,
    highlightChapterNum: clearHighlight ? null : (highlightChapterNum ?? this.highlightChapterNum),
  );
}

class ChapterPageNotifier extends StateNotifier<ChapterPageState> {
  final int novelId;
  final NovelApi _api;
  static const _perPage = 50;

  /// Cache các trang đã fetch: page → chapters
  /// RAM cố định: mỗi trang 50 chapters × ~200 bytes = ~10KB/trang
  final Map<int, List<Chapter>> _cache = {};

  ChapterPageNotifier(this.novelId, this._api, int totalChapters)
      : super(ChapterPageState(
          totalChapters: totalChapters,
          totalPages: (totalChapters / _perPage).ceil().clamp(1, 99999),
        )) {
    loadPage(1);
  }

  Future<void> loadPage(int page, {int? highlight}) async {
    if (state.isLoading) return;
    final p = page.clamp(1, state.totalPages);

    // ── Cache hit: hiển thị ngay, không cần API call ──────────────────
    if (_cache.containsKey(p)) {
      state = state.copyWith(
        chapters:           _cache[p]!,
        currentPage:        p,
        isLoading:          false,
        highlightChapterNum: highlight,
      );
      _prefetchAdjacent(p); // prefetch trang kế trong background
      return;
    }

    // ── Cache miss: fetch từ API ───────────────────────────────────────
    state = state.copyWith(isLoading: true, highlightChapterNum: highlight);
    try {
      final res = await _api.getChapters(
          novelId: novelId, page: p, perPage: _perPage);
      final items = res['items'] as List? ?? [];
      final apiTotal = (res['total_pages'] as num?)?.toInt() ?? state.totalPages;
      final chapters = items
          .map((j) => Chapter.fromJson(j as Map<String, dynamic>))
          .toList();
      _cache[p] = chapters; // lưu cache
      state = state.copyWith(
        chapters:           chapters,
        currentPage:        p,
        totalPages:         apiTotal,
        isLoading:          false,
        highlightChapterNum: highlight,
      );
      _prefetchAdjacent(p);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Prefetch trang kế/trước trong background — user không chờ
  void _prefetchAdjacent(int current) {
    for (final next in [current + 1, current - 1]) {
      if (next >= 1 && next <= state.totalPages && !_cache.containsKey(next)) {
        _api
            .getChapters(novelId: novelId, page: next, perPage: _perPage)
            .then((res) {
          final items = res['items'] as List? ?? [];
          _cache[next] = items
              .map((j) => Chapter.fromJson(j as Map<String, dynamic>))
              .toList();
        }).catchError((_) {});
      }
    }
  }

  /// Tính trang chứa chương số [num] → load (newest-first)
  Future<void> jumpToChapter(int num) async {
    final total = state.totalChapters;
    if (total <= 0 || num < 1) return;
    final posFromTop = (total - num + 1).clamp(1, total);
    final page = (posFromTop / _perPage).ceil().clamp(1, state.totalPages);
    await loadPage(page, highlight: num);
  }
}

final chapterPageProvider =
    StateNotifierProvider.family<ChapterPageNotifier, ChapterPageState,
        ({int novelId, int total})>(
  (ref, args) =>
      ChapterPageNotifier(args.novelId, NovelApi(ref.read(cachedDioProvider)), args.total),
);

bool _isFollowing(List<LibraryEntry> list, int novelId) =>
    list.any((e) => e.novelId == novelId);

// ─── Screen ───────────────────────────────────────────────────────────────────

class NovelDetailScreen extends ConsumerWidget {
  final int novelId;
  const NovelDetailScreen({super.key, required this.novelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novelAsync = ref.watch(novelDetailProvider(novelId));
    return novelAsync.when(
      loading: () => const Scaffold(
        backgroundColor: _heroBg,
        body: Center(child: CircularProgressIndicator(color: _tealStart)),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Lỗi: $e')),
      ),
      data: (novel) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(novelMetaCacheProvider.notifier).update((m) => {
                ...m,
                novel.id: LibraryEntry(
                  novelId: novel.id,
                  title: novel.title,
                  coverUrl: novel.coverUrl,
                  authorName: novel.authorName,
                ),
              });
        });
        return _NovelDetailContent(novel: novel);
      },
    );
  }
}

// ─── Constants ────────────────────────────────────────────────────────────────

const _heroBg = Color(0xFF0F1923);
const _tealStart = Color(0xFF22D3EE);
const _tealEnd = Color(0xFF2DD4BF);
const _bgContent = Color(0xFFF8F9FA);
const _textPrimary = Color(0xFF1A1A1A);
const Color _textSecondary = Color(0xFF757575);

// ─── Main Content ─────────────────────────────────────────────────────────────

class _NovelDetailContent extends ConsumerStatefulWidget {
  final Novel novel;
  const _NovelDetailContent({required this.novel});

  @override
  ConsumerState<_NovelDetailContent> createState() =>
      _NovelDetailContentState();
}

class _NovelDetailContentState extends ConsumerState<_NovelDetailContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialTab = ref.read(novelDetailInitialTabProvider);
    _tabController =
        TabController(length: 4, vsync: this, initialIndex: initialTab);
    if (initialTab != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(novelDetailInitialTabProvider.notifier).state = 0;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final novel = widget.novel;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: _bgContent,
      body: Column(
        children: [
          _HeroSection(novel: novel),
          Material(
            color: Colors.white,
            elevation: 1,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _tealStart,
              indicatorWeight: 2,
              labelColor: _tealStart,
              unselectedLabelColor: _textSecondary,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: 'Giới thiệu'),
                Tab(text: 'Đánh giá'),
                Tab(text: 'Bình luận'),
                Tab(text: 'D.S Chương'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _IntroTab(novel: novel),
                _ReviewsTab(novelId: novel.id),
                _CommentsTab(novelId: novel.id),
                // Dùng novel.chapterCount thay vì gọi API riêng
                _ChaptersTab(novelId: novel.id, totalChapters: novel.chapterCount),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero Section ─────────────────────────────────────────────────────────────

class _HeroSection extends ConsumerWidget {
  final Novel novel;
  const _HeroSection({required this.novel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inBookshelf =
        ref.watch(followingProvider.select((list) => _isFollowing(list, novel.id)));
    final progressAsync = ref.watch(readingProgressProvider(novel.id));

    return SizedBox(
      height: 270,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (novel.coverUrl != null)
            CachedNetworkImage(imageUrl: novel.coverUrl!, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _heroBg.withValues(alpha: 0.6),
                    _heroBg,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _NavBtn(icon: Icons.arrow_back, onTap: () => context.pop()),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: novel.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: novel.coverUrl!,
                          width: 110,
                          height: 156,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 110,
                            height: 156,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 110,
                            height: 156,
                            color: Colors.white.withValues(alpha: 0.1),
                            child: const Icon(Icons.menu_book,
                                color: Colors.white54, size: 36),
                          ),
                        )
                      : Container(
                          width: 110,
                          height: 156,
                          color: Colors.white.withValues(alpha: 0.1),
                          child: const Icon(Icons.menu_book,
                              color: Colors.white54, size: 36),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        novel.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                          shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (novel.authorName != null) ...[
                        const SizedBox(height: 5),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13),
                            children: [
                              const TextSpan(
                                text: 'Tác giả: ',
                                style: TextStyle(color: Colors.white70),
                              ),
                              TextSpan(
                                text: novel.authorName!,
                                style: const TextStyle(
                                    color: _tealStart,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (novel.appRatingAvg > 0) ...[
                        const SizedBox(height: 6),
                        _AppRatingRow(
                            avg: novel.appRatingAvg,
                            count: novel.appReviewCount),
                      ] else if (novel.rating > 0) ...[
                        const SizedBox(height: 6),
                        _StarRow(rating: novel.rating),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ReadButton(
                              novel: novel,
                              progressAsync: progressAsync,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final entry = LibraryEntry(
                                novelId: novel.id,
                                title: novel.title,
                                coverUrl: novel.coverUrl,
                                authorName: novel.authorName,
                              );
                              ref
                                  .read(novelMetaCacheProvider.notifier)
                                  .update((m) => {...m, novel.id: entry});
                              ref.read(followingProvider.notifier).toggle(entry);
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: inBookshelf
                                    ? _tealStart.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: inBookshelf
                                      ? _tealStart
                                      : Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Icon(
                                inBookshelf
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                color: inBookshelf ? _tealStart : Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Intro Tab ────────────────────────────────────────────────────────────────

class _IntroTab extends ConsumerStatefulWidget {
  final Novel novel;
  const _IntroTab({required this.novel});

  @override
  ConsumerState<_IntroTab> createState() => _IntroTabState();
}

class _IntroTabState extends ConsumerState<_IntroTab>
    with AutomaticKeepAliveClientMixin {
  bool _expandDesc = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final novel = widget.novel;
    final chapterCountAsync = ref.watch(chapterCountProvider(novel.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        Row(
          children: [
            _StatBlock(label: 'Tình trạng', value: novel.statusLabel,
                valueColor: _statusColor(novel.status)),
            _divider(),
            _StatBlock(
              label: 'Số chương',
              value: chapterCountAsync.when(
                data: (c) => c.toString(),
                loading: () => '...',
                error: (_, __) => '?',
              ),
            ),
            _divider(),
            _StatBlock(label: 'Lượt đọc', value: _fmt(novel.viewCount)),
          ],
        ),
        const SizedBox(height: 20),
        if ((novel.description ?? novel.excerpt) != null &&
            (novel.description ?? novel.excerpt)!.isNotEmpty) ...[
          Text(
            (novel.description ?? novel.excerpt)!,
            maxLines: _expandDesc ? null : 4,
            overflow: _expandDesc ? null : TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14, color: _textPrimary, height: 1.6),
          ),
          TextButton(
            onPressed: () => setState(() => _expandDesc = !_expandDesc),
            child: Text(_expandDesc ? 'Thu gọn ▲' : 'Xem thêm ▼',
                style: const TextStyle(color: _tealStart, fontSize: 13)),
          ),
          const SizedBox(height: 12),
        ],
        // Genres
        if (novel.genres.isNotEmpty) ...[
          const Text('Thể loại',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: novel.genres.map((g) => GestureDetector(
              onTap: () => context.push('/browse',
                  extra: {'genreId': g.id, 'genreName': g.name}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _tealStart.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _tealStart.withValues(alpha: 0.3)),
                ),
                child: Text(g.name,
                    style: const TextStyle(color: _tealStart, fontSize: 12)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 20),
        ],
        // Groups (renamed: Nhóm dịch → Tag)
        if (novel.groups.isNotEmpty) ...[
          const Text('Tag',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: novel.groups.map((g) => Chip(
              label: Text(g.name, style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(color: Colors.grey.shade300),
              padding: EdgeInsets.zero,
            )).toList(),
          ),
          const SizedBox(height: 20),
        ],
        // Novels by same author
        if (novel.authorTermId != null) ...[
          const Text('Cùng tác giả',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _AuthorNovelsRow(authorTermId: novel.authorTermId!, currentId: novel.id),
        ],
        const SizedBox(height: 28),
        // Báo cáo truyện
        Center(
          child: TextButton.icon(
            onPressed: () => _reportNovel(context, novel.id, novel.title),
            icon: const Icon(Icons.flag_outlined, size: 15,
                color: Colors.grey),
            label: const Text('Báo cáo truyện',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ),
      ],
    );
  }

  void _reportNovel(BuildContext context, int novelId, String title) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ReportSheet(
        title: 'Báo cáo truyện',
        subject: 'Báo cáo truyện: $title (ID: $novelId)',
      ),
    );
  }
}

// ─── Chapters Tab — phân trang + jump-to-chapter ─────────────────────────────

class _ChaptersTab extends ConsumerStatefulWidget {
  final int novelId;
  final int totalChapters; // lấy từ novel.chapterCount — không cần API call thêm
  const _ChaptersTab({required this.novelId, required this.totalChapters});

  @override
  ConsumerState<_ChaptersTab> createState() => _ChaptersTabState();
}

class _ChaptersTabState extends ConsumerState<_ChaptersTab> {
  final _jumpCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _jumpFocus  = FocusNode();

  ({int novelId, int total}) get _args =>
      (novelId: widget.novelId, total: widget.totalChapters);

  @override
  void dispose() {
    _jumpCtrl.dispose();
    _scrollCtrl.dispose();
    _jumpFocus.dispose();
    super.dispose();
  }

  void _doJump() {
    final num = int.tryParse(_jumpCtrl.text.trim());
    if (num == null || num < 1) return;
    _jumpFocus.unfocus();
    ref.read(chapterPageProvider(_args).notifier).jumpToChapter(num);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state    = ref.watch(chapterPageProvider(_args));
    final notifier = ref.read(chapterPageProvider(_args).notifier);

    return Column(
      children: [
        // ── Jump-to-chapter ───────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jumpCtrl,
                  focusNode:  _jumpFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _doJump(),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Nhảy đến chương... (1–${widget.totalChapters})',
                    hintStyle: const TextStyle(
                        fontSize: 12, color: _textSecondary),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: _textSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: _tealStart)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _doJump,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _tealStart,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  elevation: 0,
                ),
                child: const Text('Đến', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Chapter list ──────────────────────────────────────────────────
        Expanded(
          child: state.isLoading && state.chapters.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: _tealStart))
              : state.chapters.isEmpty
                  ? const Center(
                      child: Text('Chưa có chương nào',
                          style: TextStyle(color: _textSecondary)))
                  : Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.only(bottom: 56),
                          itemCount: state.chapters.length,
                          itemBuilder: (ctx, i) {
                            final c = state.chapters[i];
                            final isHighlighted =
                                state.highlightChapterNum != null &&
                                c.chapterNumber == state.highlightChapterNum;
                            // Chapters là newest-first:
                            // [i-1] = chapter mới hơn (số cao hơn) = "next"
                            // [i+1] = chapter cũ hơn  (số thấp hơn) = "prev"
                            final nextCh = i > 0
                                ? state.chapters[i - 1] : null;
                            final prevCh = i < state.chapters.length - 1
                                ? state.chapters[i + 1] : null;
                            return _ChapterTile(
                              chapter: c,
                              isHighlighted: isHighlighted,
                              onTap: () {
                                ReadingProgressService.save(
                                    widget.novelId, c.id,
                                    c.chapterNumber, c.title);
                                context.push(
                                    '/reader/${widget.novelId}/${c.id}',
                                    extra: {
                                      'chapterTitle':   c.title,
                                      'chapterNumber':  c.chapterNumber,
                                      // Pre-computed adjacent — reader dùng ngay, 0 API calls
                                      'prevChapterId':    prevCh?.id,
                                      'prevChapterTitle': prevCh?.title,
                                      'prevChapterNum':   prevCh?.chapterNumber,
                                      'nextChapterId':    nextCh?.id,
                                      'nextChapterTitle': nextCh?.title,
                                      'nextChapterNum':   nextCh?.chapterNumber,
                                    });
                              },
                            );
                          },
                        ),
                        // Loading overlay khi chuyển trang
                        if (state.isLoading)
                          const Positioned.fill(
                            child: ColoredBox(
                              color: Color(0x55FFFFFF),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      color: _tealStart, strokeWidth: 2)),
                            ),
                          ),
                      ],
                    ),
        ),

        // ── Pagination bar ────────────────────────────────────────────────
        if (state.totalPages > 1)
          _PaginationBar(
            currentPage: state.currentPage,
            totalPages:  state.totalPages,
            isLoading:   state.isLoading,
            onPrev: state.currentPage > 1
                ? () {
                    notifier.loadPage(state.currentPage - 1);
                    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
                  }
                : null,
            onNext: state.currentPage < state.totalPages
                ? () {
                    notifier.loadPage(state.currentPage + 1);
                    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
                  }
                : null,
            onPageTap: (page) {
              notifier.loadPage(page);
              if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
            },
          ),
      ],
    );
  }
}

// ─── Chapter Tile ─────────────────────────────────────────────────────────────

class _ChapterTile extends StatelessWidget {
  final Chapter chapter;
  final bool isHighlighted;
  final VoidCallback onTap;
  const _ChapterTile({
    required this.chapter,
    required this.isHighlighted,
    required this.onTap,
  });

  /// Format: "Chương X: title" — tránh duplicate nếu title đã có "Chương"
  String get _displayTitle {
    final num = chapter.chapterNumber;
    final t   = chapter.title.trim();
    if (num <= 0) return t;
    final prefix = 'Chương $num';
    if (t.toLowerCase().startsWith('chương $num')) return t;
    return t.isEmpty ? prefix : '$prefix: $t';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: isHighlighted
          ? _tealStart.withValues(alpha: 0.10)
          : Colors.transparent,
      child: ListTile(
        dense: true,
        leading: isHighlighted
            ? const Icon(Icons.bookmark_rounded, size: 16, color: _tealStart)
            : null,
        title: Text(
          _displayTitle,
          style: TextStyle(
            fontSize: 13,
            color: _textPrimary,
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: chapter.publishedAt != null
            ? Text(_timeAgo(chapter.publishedAt),
                style: const TextStyle(fontSize: 11, color: _textSecondary))
            : null,
        onTap: onTap,
      ),
    );
  }
}

// ─── Pagination Bar ───────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(int page)? onPageTap;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.isLoading,
    required this.onPrev,
    required this.onNext,
    this.onPageTap,
  });

  /// Builds the list of page items to display.
  /// Returns `null` entries for ellipsis gaps.
  List<int?> _buildPageList() {
    final visible = <int>{};
    // Always show first 2 and last 2
    visible.addAll([1, 2].where((p) => p <= totalPages));
    visible.addAll([totalPages - 1, totalPages].where((p) => p >= 1));
    // Window around current page
    for (int delta = -2; delta <= 2; delta++) {
      final p = currentPage + delta;
      if (p >= 1 && p <= totalPages) visible.add(p);
    }
    final sorted = visible.toList()..sort();
    final result = <int?>[];
    int? prev;
    for (final p in sorted) {
      if (prev != null && p - prev > 1) result.add(null); // ellipsis
      result.add(p);
      prev = p;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPageList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // « về trang đầu
          _PagArrowBtn(
            label: '«',
            enabled: !isLoading && currentPage > 1,
            onTap: () => onPageTap?.call(1),
          ),
          const SizedBox(width: 4),
          // Danh sách số trang
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: pages.map((p) {
                  if (p == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('...',
                          style: TextStyle(
                              fontSize: 13, color: _textSecondary,
                              fontWeight: FontWeight.w500)),
                    );
                  }
                  final isCurrent = p == currentPage;
                  return GestureDetector(
                    onTap: (isLoading || isCurrent)
                        ? null
                        : () => onPageTap?.call(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 34,
                      height: 34,
                      decoration: isCurrent
                          ? BoxDecoration(
                              color: _tealStart,
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      alignment: Alignment.center,
                      child: Text(
                        '$p',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isCurrent
                              ? Colors.white
                              : _textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // » về trang cuối
          _PagArrowBtn(
            label: '»',
            enabled: !isLoading && currentPage < totalPages,
            onTap: () => onPageTap?.call(totalPages),
          ),
        ],
      ),
    );
  }
}

class _PagArrowBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _PagArrowBtn({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.grey.shade100
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? _textPrimary : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

// ─── Reviews Tab ─────────────────────────────────────────────────────────────

class _ReviewsTab extends StatelessWidget {
  final int novelId;
  const _ReviewsTab({required this.novelId});

  @override
  Widget build(BuildContext context) =>
      _CommentTab(novelId: novelId, isReview: true);
}

class _CommentsTab extends StatelessWidget {
  final int novelId;
  const _CommentsTab({required this.novelId});

  @override
  Widget build(BuildContext context) =>
      _CommentTab(novelId: novelId, isReview: false);
}

// ─── Comment/Review Tab ───────────────────────────────────────────────────────

class _CommentTab extends ConsumerStatefulWidget {
  final int novelId;
  final bool isReview;
  const _CommentTab({required this.novelId, required this.isReview});

  @override
  ConsumerState<_CommentTab> createState() => _CommentTabState();
}

class _CommentTabState extends ConsumerState<_CommentTab> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _userReviewed = false;
  int _selectedRating = 0;
  List<NovelComment> _items = [];
  int _page = 1;
  int _totalPages = 1;
  String? _error;
  String? _submitMsg;
  bool _submitOk = false;

  int? _replyToId;
  String? _replyToName;
  final Map<int, List<NovelComment>> _repliesMap = {};
  final Set<int> _loadingReplies = {};

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _items = [];
        _error = null;
        _loading = true;
        _repliesMap.clear();
        _replyToId = null;
        _replyToName = null;
      });
    }
    try {
      final api = NovelApi(ref.read(dioProvider));
      final res = widget.isReview
          ? await api.getReviews(widget.novelId, page: 1)
          : await api.getComments(widget.novelId, page: 1);
      final items = (res['items'] as List)
          .map((j) => NovelComment.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _totalPages = (res['total_pages'] as num?)?.toInt() ?? 1;
        _userReviewed = res['user_reviewed'] == true;
        _page = 1;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể tải dữ liệu';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    try {
      final api = NovelApi(ref.read(dioProvider));
      final next = _page + 1;
      final res = widget.isReview
          ? await api.getReviews(widget.novelId, page: next)
          : await api.getComments(widget.novelId, page: next);
      final items = (res['items'] as List)
          .map((j) => NovelComment.fromJson(j as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _page = next;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadReplies(int commentId) async {
    if (_loadingReplies.contains(commentId)) return;
    setState(() => _loadingReplies.add(commentId));
    try {
      final api = NovelApi(ref.read(dioProvider));
      final rawList =
          await api.getCommentReplies(widget.novelId, commentId);
      final replies =
          rawList.map((j) => NovelComment.fromJson(j)).toList();
      if (!mounted) return;
      setState(() {
        _repliesMap[commentId] = replies;
        _loadingReplies.remove(commentId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReplies.remove(commentId));
    }
  }

  void _setReplyTo(int? id, String? name) {
    setState(() {
      _replyToId = id;
      _replyToName = name;
    });
    if (id != null) _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (text.length < 3) {
      setState(() {
        _submitMsg = '⚠️ Nội dung quá ngắn (tối thiểu 3 ký tự)';
        _submitOk = false;
      });
      return;
    }
    if (widget.isReview && _selectedRating == 0) {
      setState(() {
        _submitMsg = '⚠️ Vui lòng chọn số sao đánh giá';
        _submitOk = false;
      });
      return;
    }
    setState(() {
      _sending = true;
      _submitMsg = null;
    });
    try {
      final api = NovelApi(ref.read(dioProvider));
      if (widget.isReview) {
        await api.submitReview(widget.novelId, text,
            rating: _selectedRating);
      } else {
        await api.submitComment(widget.novelId, text,
            parentId: _replyToId);
      }
      _ctrl.clear();
      final replyId = _replyToId;
      if (!mounted) return;
      setState(() {
        _sending = false;
        _submitOk = true;
        _replyToId = null;
        _replyToName = null;
        _submitMsg = widget.isReview
            ? '✅ Đánh giá đã được gửi!'
            : '✅ Bình luận đã được gửi!';
      });
      if (replyId != null) {
        _repliesMap.remove(replyId);
        _loadReplies(replyId);
      } else {
        _load(refresh: true);
      }
    } catch (e) {
      if (!mounted) return;
      final isDioError = e.toString().contains('409') ||
          e.toString().contains('already_reviewed');
      setState(() {
        _sending = false;
        _submitOk = false;
        _submitMsg = isDioError
            ? '⚠️ Bạn đã đánh giá truyện này rồi'
            : '❌ Gửi thất bại, vui lòng thử lại';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn =
        ref.watch(authProvider).valueOrNull?.user != null;
    final emptyText = widget.isReview
        ? 'Chưa có đánh giá nào\nHãy là người đầu tiên!'
        : 'Chưa có bình luận nào\nHãy là người đầu tiên!';

    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _tealStart))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style:
                                  const TextStyle(color: _textSecondary)),
                          const SizedBox(height: 8),
                          TextButton(
                              onPressed: _load,
                              child: const Text('Thử lại')),
                        ],
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Text(emptyText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: _textSecondary, height: 1.6)))
                      : RefreshIndicator(
                          onRefresh: () => _load(refresh: true),
                          color: _tealStart,
                          child: ListView.separated(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(
                                16, 12, 16, 16),
                            itemCount:
                                _items.length + (_loadingMore ? 1 : 0),
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: Color(0xFFEEEEEE)),
                            itemBuilder: (ctx, i) {
                              if (i >= _items.length) {
                                return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _tealStart)));
                              }
                              final c = _items[i];
                              return _CommentItem(
                                comment: c,
                                isReview: widget.isReview,
                                replies: _repliesMap[c.id],
                                isLoadingReplies:
                                    _loadingReplies.contains(c.id),
                                onReply: isLoggedIn && !widget.isReview
                                    ? () => _setReplyTo(
                                        c.id, c.authorName)
                                    : null,
                                onExpandReplies: c.replyCount > 0
                                    ? () => _loadReplies(c.id)
                                    : null,
                              );
                            },
                          ),
                        ),
        ),
        if (_submitMsg != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: _submitOk
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFFEBEE),
            child: Text(_submitMsg!,
                style: TextStyle(
                    fontSize: 13,
                    color: _submitOk
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828))),
          ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border:
                Border(top: BorderSide(color: Color(0xFFEEEEEE))),
          ),
          padding: EdgeInsets.fromLTRB(
              12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
          child: _buildInputBar(isLoggedIn, context),
        ),
      ],
    );
  }

  Widget _buildInputBar(bool isLoggedIn, BuildContext context) {
    if (widget.isReview && _userReviewed) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 16, color: _tealStart),
              SizedBox(width: 6),
              Text('Bạn đã đánh giá truyện này',
                  style:
                      TextStyle(color: _tealStart, fontSize: 13)),
            ]),
      );
    }

    if (!isLoggedIn) {
      return TextButton.icon(
        onPressed: () => context.push('/login'),
        icon: const Icon(Icons.login, size: 16),
        label: Text(widget.isReview
            ? 'Đăng nhập để đánh giá'
            : 'Đăng nhập để bình luận'),
        style: TextButton.styleFrom(foregroundColor: _tealStart),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isReview) ...[
          _StarPicker(
            selected: _selectedRating,
            onChanged: (v) => setState(() => _selectedRating = v),
          ),
          const SizedBox(height: 6),
        ],
        if (_replyToId != null)
          Row(children: [
            const Icon(Icons.reply, size: 14, color: _tealStart),
            const SizedBox(width: 4),
            Expanded(
                child: Text('Trả lời @$_replyToName',
                    style: const TextStyle(
                        fontSize: 12, color: _tealStart),
                    overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () => _setReplyTo(null, null),
              child: const Icon(Icons.close,
                  size: 14, color: _textSecondary),
            ),
          ]),
        if (_replyToId != null) const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: _replyToId != null
                    ? 'Viết trả lời...'
                    : widget.isReview
                        ? 'Viết đánh giá của bạn...'
                        : 'Viết bình luận...',
                hintStyle: const TextStyle(
                    color: _textSecondary, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _tealStart))
              : IconButton(
                  onPressed: _submit,
                  icon: const Icon(Icons.send_rounded),
                  color: _tealStart,
                  style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFE0F7FA)),
                ),
        ]),
      ],
    );
  }
}

// ─── Comment Item ─────────────────────────────────────────────────────────────

class _CommentItem extends StatelessWidget {
  final NovelComment comment;
  final bool isReview;
  final List<NovelComment>? replies;
  final bool isLoadingReplies;
  final VoidCallback? onReply;
  final VoidCallback? onExpandReplies;

  const _CommentItem({
    required this.comment,
    required this.isReview,
    this.replies,
    this.isLoadingReplies = false,
    this.onReply,
    this.onExpandReplies,
  });

  @override
  Widget build(BuildContext context) {
    final repliesLoaded = replies != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(
                  avatarUrl: comment.authorAvatarUrl,
                  name: comment.authorName,
                  size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  comment.authorName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (comment.authorLevel >= 10) ...[
                                const SizedBox(width: 5),
                                _RankBadgeInline(
                                  rankName: comment.rankName,
                                  level: comment.authorLevel,
                                  color: Color(comment.rankColor!),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _timeAgo(comment.date),
                          style: const TextStyle(
                              fontSize: 11, color: _textSecondary),
                        ),
                        GestureDetector(
                          onTap: () => showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16)),
                            ),
                            builder: (_) => _CommentReportSheet(
                              authorName: comment.authorName,
                              commentId: comment.id,
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.flag_outlined,
                                size: 15, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    if (isReview) ...[
                      const SizedBox(height: 4),
                      _ReviewStarRow(rating: comment.rating),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      comment.content,
                      style: const TextStyle(
                          fontSize: 14,
                          color: _textPrimary,
                          height: 1.45),
                    ),
                    if (onReply != null || comment.replyCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (onReply != null)
                            GestureDetector(
                              onTap: onReply,
                              child: const Row(children: [
                                Icon(Icons.reply,
                                    size: 14, color: _textSecondary),
                                SizedBox(width: 3),
                                Text('Trả lời',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _textSecondary)),
                              ]),
                            ),
                          if (onReply != null && comment.replyCount > 0)
                            const SizedBox(width: 16),
                          if (comment.replyCount > 0 && !repliesLoaded)
                            GestureDetector(
                              onTap: isLoadingReplies
                                  ? null
                                  : onExpandReplies,
                              child: isLoadingReplies
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: _tealStart))
                                  : Text(
                                      'Xem ${comment.replyCount} trả lời',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: _tealStart,
                                          fontWeight: FontWeight.w500)),
                            ),
                          if (repliesLoaded && replies!.isNotEmpty)
                            Text('${replies!.length} trả lời',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _textSecondary)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (repliesLoaded && replies!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 8),
              child: Column(
                children: replies!.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Avatar(
                          avatarUrl: r.authorAvatarUrl,
                          name: r.authorName,
                          size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(r.authorName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: _textPrimary),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (r.authorLevel >= 10) ...[
                                const SizedBox(width: 4),
                                _RankBadgeInline(
                                  rankName: r.rankName,
                                  level: r.authorLevel,
                                  color: Color(r.rankColor!),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Text(_timeAgo(r.date),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: _textSecondary)),
                            ]),
                            const SizedBox(height: 2),
                            Text(r.content,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: _textPrimary,
                                    height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final double size;
  const _Avatar({this.avatarUrl, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _tealStart.withValues(alpha: 0.2),
      backgroundImage:
          avatarUrl != null ? NetworkImage(avatarUrl!) : null,
      child: avatarUrl == null
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: _tealStart,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.bold))
          : null,
    );
  }
}

class _RankBadgeInline extends StatelessWidget {
  final String rankName;
  final int level;
  final Color color;
  const _RankBadgeInline(
      {required this.rankName, required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('★ $rankName · Lv.$level',
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _AppRatingRow extends StatelessWidget {
  final double avg;
  final int count;
  const _AppRatingRow({required this.avg, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(avg.toStringAsFixed(1),
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(width: 4),
        ...List.generate(5, (i) {
          if (i < avg.floor()) {
            return const Icon(Icons.star, color: Colors.amber, size: 14);
          } else if (i < avg.ceil() && avg % 1 >= 0.4) {
            return const Icon(Icons.star_half,
                color: Colors.amber, size: 14);
          } else {
            return const Icon(Icons.star_border,
                color: Colors.amber, size: 14);
          }
        }),
        const SizedBox(width: 6),
        Text('($count đánh giá)',
            style:
                const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    final stars = rating / 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(stars.toStringAsFixed(1),
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(width: 4),
        ...List.generate(5, (i) {
          if (i < stars.floor()) {
            return const Icon(Icons.star, color: Colors.amber, size: 14);
          } else if (i < stars.ceil() && stars % 1 >= 0.4) {
            return const Icon(Icons.star_half,
                color: Colors.amber, size: 14);
          } else {
            return const Icon(Icons.star_border,
                color: Colors.amber, size: 14);
          }
        }),
      ],
    );
  }
}

class _StarPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _StarPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Chọn sao: ',
            style: TextStyle(fontSize: 13, color: _textSecondary)),
        ...List.generate(5, (i) {
          final star = i + 1;
          return GestureDetector(
            onTap: () => onChanged(star),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                star <= selected
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: star <= selected
                    ? Colors.amber
                    : const Color(0xFFBDBDBD),
                size: 28,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ReviewStarRow extends StatelessWidget {
  final int rating;
  const _ReviewStarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          5,
          (i) => Icon(
                i < rating
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: i < rating
                    ? Colors.amber
                    : const Color(0xFFDDDDDD),
                size: 14,
              )),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ReadButton extends ConsumerWidget {
  final Novel novel;
  final AsyncValue<ReadingProgress?> progressAsync;
  const _ReadButton({required this.novel, required this.progressAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = progressAsync.valueOrNull;
    final firstChapterAsync  = ref.watch(firstChapterProvider(novel.id));
    final nextChapterAsync   = ref.watch(nextChapterProvider(novel.id));

    // Trạng thái đang tìm chapter tiếp theo
    final isSearchingNext = progress != null && nextChapterAsync.isLoading;

    return GestureDetector(
      onTap: isSearchingNext ? null : () {
        if (progress != null) {
          final next = nextChapterAsync.valueOrNull;
          // Dùng next chapter nếu tìm thấy, fallback về chapter đang đọc
          final target = next;
          if (target != null) {
            ReadingProgressService.save(
                novel.id, target.id, target.chapterNumber, target.title);
            context.push('/reader/${novel.id}/${target.id}', extra: {
              'chapterTitle': target.title,
              'chapterNumber': target.chapterNumber,
            });
          } else {
            // next == null: đang ở chương cuối → đọc lại chương đó
            context.push('/reader/${novel.id}/${progress.chapterId}', extra: {
              'chapterTitle': progress.chapterTitle,
              'chapterNumber': progress.chapterNumber,
            });
          }
        } else {
          firstChapterAsync.whenData((chapter) {
            if (chapter != null && context.mounted) {
              ReadingProgressService.save(
                  novel.id, chapter.id, chapter.chapterNumber, chapter.title);
              context.push('/reader/${novel.id}/${chapter.id}', extra: {
                'chapterTitle': chapter.title,
                'chapterNumber': chapter.chapterNumber,
              });
            }
          });
        }
      },
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSearchingNext
                ? [Colors.grey.shade400, Colors.grey.shade400]
                : [_tealStart, _tealEnd],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: isSearchingNext
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(
                  _buttonLabel(progress, nextChapterAsync.valueOrNull),
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
        ),
      ),
    );
  }

  static String _buttonLabel(ReadingProgress? progress, Chapter? next) {
    if (progress == null) return 'Đọc ngay';
    if (next != null) return 'Đọc tiếp';
    // next == null: đang ở chương cuối cùng
    return 'Đọc lại';
  }
}

class _AuthorNovelsRow extends ConsumerWidget {
  final int authorTermId;
  final int currentId;
  const _AuthorNovelsRow(
      {required this.authorTermId, required this.currentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novelsAsync = ref.watch(novelsByAuthorProvider(authorTermId));
    return novelsAsync.when(
      loading: () =>
          const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _tealStart))),
      error: (_, __) => const SizedBox.shrink(),
      data: (novels) {
        final filtered =
            novels.where((n) => n.id != currentId).toList();
        if (filtered.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final n = filtered[i];
              return GestureDetector(
                onTap: () => context.push('/novel/${n.id}'),
                child: SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: n.coverUrl != null
                            ? CachedNetworkImage(
                                imageUrl: n.coverUrl!,
                                width: 90,
                                height: 110,
                                fit: BoxFit.cover)
                            : Container(
                                width: 90,
                                height: 110,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.menu_book,
                                    color: Colors.grey)),
                      ),
                      const SizedBox(height: 4),
                      Text(n.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: _textPrimary)),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatBlock({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: valueColor ?? _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

Widget _divider() => Container(
      width: 1,
      height: 32,
      color: const Color(0xFFE0E0E0),
    );

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'completed': return Colors.green;
    case 'dropped': return Colors.red;
    default: return Colors.orange;
  }
}

String _timeAgo(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} năm trước';
  if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} tháng trước';
  if (diff.inDays > 0) return '${diff.inDays} ngày trước';
  if (diff.inHours > 0) return '${diff.inHours} giờ trước';
  if (diff.inMinutes > 0) return '${diff.inMinutes} phút trước';
  return 'Vừa xong';
}

// ignore: unused_element
String _timeAgoFromDate(DateTime? date) => _timeAgo(date);

// ─── Report Sheet ─────────────────────────────────────────────────────────────

class _ReportSheet extends StatefulWidget {
  final String title;
  final String subject;
  const _ReportSheet({required this.title, required this.subject});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  int? _selected;

  static const _reasons = [
    'Nội dung 18+, không phù hợp',
    'Vi phạm bản quyền',
    'Nội dung sai sự thật / spam',
    'Lỗi chương / nội dung bị thiếu',
    'Lý do khác',
  ];

  Future<void> _send() async {
    final reason = _selected != null ? _reasons[_selected!] : 'Không rõ';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@truyencv.io',
      queryParameters: {
        'subject': widget.subject,
        'body': 'Lý do báo cáo: $reason\n\n(Mô tả thêm nếu có)',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      if (mounted) Navigator.of(context).pop();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Không tìm thấy app email. Liên hệ: support@truyencv.io')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.flag_outlined, size: 18, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 4),
            const Text('Chọn lý do báo cáo:',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            ..._reasons.asMap().entries.map((e) => RadioListTile<int>(
                  value: e.key,
                  groupValue: _selected,
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  onChanged: (v) => setState(() => _selected = v),
                  activeColor: const Color(0xFF22D3EE),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected != null ? _send : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Gửi báo cáo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Comment Report Sheet ─────────────────────────────────────────────────────

class _CommentReportSheet extends StatefulWidget {
  final String authorName;
  final int commentId;
  const _CommentReportSheet({
    required this.authorName,
    required this.commentId,
  });

  @override
  State<_CommentReportSheet> createState() => _CommentReportSheetState();
}

class _CommentReportSheetState extends State<_CommentReportSheet> {
  int? _selected;

  static const _reasons = [
    'Spam / quảng cáo',
    'Ngôn từ thô tục / xúc phạm',
    'Nội dung không phù hợp',
    'Thông tin sai lệch / spoiler quá mức',
    'Lý do khác',
  ];

  Future<void> _send() async {
    final reason = _selected != null ? _reasons[_selected!] : 'Không rõ';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@truyencv.io',
      queryParameters: {
        'subject': 'Báo cáo bình luận #${widget.commentId}',
        'body':
            'Người dùng: ${widget.authorName}\n'
            'Lý do: $reason\n\n'
            '(Mô tả thêm nếu có)',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      if (mounted) Navigator.of(context).pop();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Không tìm thấy app email. Liên hệ: support@truyencv.io')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.flag_outlined,
                  size: 18, color: Colors.redAccent),
              const SizedBox(width: 8),
              const Text('Báo cáo bình luận',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 4),
            const Text('Chọn lý do báo cáo:',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            ..._reasons.asMap().entries.map((e) => RadioListTile<int>(
                  value: e.key,
                  groupValue: _selected,
                  title:
                      Text(e.value, style: const TextStyle(fontSize: 14)),
                  onChanged: (v) => setState(() => _selected = v),
                  activeColor: const Color(0xFF22D3EE),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected != null ? _send : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Gửi báo cáo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
