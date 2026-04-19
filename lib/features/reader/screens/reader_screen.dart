import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../shared/models/novel_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/library_service.dart';
import '../../novel/screens/novel_detail_screen.dart'
    show ReadingProgressService, chapterCountProvider,
         novelDetailInitialTabProvider, chapterPageProvider, ChapterPageState;

// ─── Providers ────────────────────────────────────────────────────────────────

final _chapterContentProvider =
    FutureProvider.family<Chapter, int>((ref, chapterId) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getChapterById(chapterId);
  return Chapter.fromJson(data);
});

/// Args cho _adjacentProvider — hỗ trợ pre-computed data để tránh API calls
typedef _AdjacentArgs = ({
  int novelId,
  int chapterNumber,
  // Pre-computed từ caller (chapter list / reader nav) — nếu có thì 0 API call
  int? prevId,
  String? prevTitle,
  int? prevNum,
  int? nextId,
  String? nextTitle,
  int? nextNum,
});

/// Tìm chương kề — thông minh:
/// • Cả 2 đã biết  → return ngay, 0 API calls
/// • 1 đã biết     → chỉ fetch 1 cái còn lại (1 call thay vì 2)
/// • Không biết gì → fetch cả 2 song song (fallback từ history/library)
final _adjacentProvider = FutureProvider.family<
    ({Chapter? prev, Chapter? next}), _AdjacentArgs>((ref, args) async {

  Chapter lite(int id, String? title, int? num) => Chapter(
        id: id, novelId: args.novelId,
        title: title ?? '', slug: '',
        chapterNumber: num ?? 0,
      );

  // ── Fast path: cả 2 đã biết → 0 API calls ────────────────────────────
  if (args.prevId != null && args.nextId != null) {
    return (
      prev: lite(args.prevId!, args.prevTitle, args.prevNum),
      next: lite(args.nextId!, args.nextTitle, args.nextNum),
    );
  }

  // ── Cần fetch ít nhất 1 chapter ───────────────────────────────────────
  if (args.chapterNumber <= 0) return (prev: null, next: null);

  final total = await ref.read(chapterCountProvider(args.novelId).future);
  if (total <= 0) return (prev: null, next: null);

  const perPage = 50;
  final totalPages = (total / perPage).ceil();
  final api = NovelApi(ref.read(cachedDioProvider));

  Future<Chapter?> findByNum(int num) async {
    if (num < 1 || num > total) return null;
    final posFromTop = total - num + 1;
    final calcPage = (posFromTop / perPage).ceil().clamp(1, totalPages);
    for (final pg in [calcPage, calcPage + 1, calcPage - 1]) {
      if (pg < 1 || pg > totalPages) continue;
      try {
        final res = await api.getChapters(
            novelId: args.novelId, page: pg, perPage: perPage);
        final items = res['items'] as List? ?? [];
        final chapters = items
            .map((j) => Chapter.fromJson(j as Map<String, dynamic>))
            .toList();
        return chapters.firstWhere((c) => c.chapterNumber == num);
      } catch (_) {}
    }
    return null;
  }

  // Dùng giá trị biết sẵn nếu có, chỉ fetch cái chưa biết
  final prevFuture = args.prevId != null
      ? Future.value(lite(args.prevId!, args.prevTitle, args.prevNum))
      : findByNum(args.chapterNumber - 1);

  final nextFuture = args.nextId != null
      ? Future.value(lite(args.nextId!, args.nextTitle, args.nextNum))
      : findByNum(args.chapterNumber + 1);

  final results = await Future.wait([prevFuture, nextFuture]);
  return (prev: results[0], next: results[1]);
});

// ─── Reader Settings ──────────────────────────────────────────────────────────

final _readerSettingsProvider =
    StateProvider<_ReaderSettings>((ref) => const _ReaderSettings());

// 0 = Mặc định, 1 = Inter, 2 = Noto Serif, 3 = Lora
const _kFontNames = ['Mặc định', 'Inter', 'Noto Serif', 'Lora'];

class _ReaderSettings {
  final double fontSize;
  final int themeIndex;
  final double lineHeight;
  final int fontIndex;

  const _ReaderSettings({
    this.fontSize = 17,
    this.themeIndex = 0,
    this.lineHeight = 1.8,
    this.fontIndex = 0,
  });

  _ReaderSettings copyWith({
    double? fontSize,
    int? themeIndex,
    double? lineHeight,
    int? fontIndex,
  }) =>
      _ReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        themeIndex: themeIndex ?? this.themeIndex,
        lineHeight: lineHeight ?? this.lineHeight,
        fontIndex: fontIndex ?? this.fontIndex,
      );

  /// Tạo TextStyle đọc truyện theo font đã chọn
  TextStyle buildTextStyle({
    required Color color,
    double extraSize = 0,
    double? customHeight,
    FontWeight? fontWeight,
  }) {
    final sz = fontSize + extraSize;
    final h  = customHeight ?? lineHeight;
    switch (fontIndex) {
      case 1: return TextStyle(
          fontFamily: 'Inter',
          fontSize: sz, color: color, height: h, fontWeight: fontWeight);
      case 2: return GoogleFonts.notoSerif(
          fontSize: sz, color: color, height: h, fontWeight: fontWeight);
      case 3: return GoogleFonts.lora(
          fontSize: sz, color: color, height: h, fontWeight: fontWeight);
      default: return TextStyle(
          fontSize: sz, color: color, height: h, fontWeight: fontWeight);
    }
  }
}

// ─── ReaderScreen ─────────────────────────────────────────────────────────────

class ReaderScreen extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterId;
  final String chapterTitle;
  final int chapterNumber;
  // Pre-computed adjacent info — nếu có thì _adjacentProvider skip API calls
  final int? prevChapterId;
  final String? prevChapterTitle;
  final int? prevChapterNum;
  final int? nextChapterId;
  final String? nextChapterTitle;
  final int? nextChapterNum;

  const ReaderScreen({
    super.key,
    required this.novelId,
    required this.chapterId,
    required this.chapterTitle,
    this.chapterNumber = 0,
    this.prevChapterId,
    this.prevChapterTitle,
    this.prevChapterNum,
    this.nextChapterId,
    this.nextChapterTitle,
    this.nextChapterNum,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showBottomBar = false; // bottom bar ẩn mặc định
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _trackReading();
    // Immersive ngay từ đầu để tối đa diện tích đọc
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    // Restore system UI khi thoát reader
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Track reading progress + history ──────────────────────────────────────

  Future<void> _trackReading() async {
    try {
      final api = UserApi(ref.read(dioProvider));
      await api.trackReading(widget.novelId, widget.chapterId);
    } catch (_) {}

    await ReadingProgressService.save(
      widget.novelId,
      widget.chapterId,
      widget.chapterNumber,
      widget.chapterTitle,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_chapter_${widget.novelId}', widget.chapterId);

    final meta = ref.read(novelMetaCacheProvider)[widget.novelId];
    if (meta != null) {
      await ref.read(historyProvider.notifier).addHistory(HistoryEntry(
            novelId: widget.novelId,
            title: meta.title,
            coverUrl: meta.coverUrl,
            authorName: meta.authorName,
            chapterId: widget.chapterId,
            chapterTitle: widget.chapterTitle,
            chapterNumber: widget.chapterNumber,
            readAt: DateTime.now(),
          ));
    }
  }

  // ── Chapter title helpers ─────────────────────────────────────────────────

  /// Format "Chương X: title" — tránh duplicate nếu title đã có prefix
  String get _formattedTitle {
    final num = widget.chapterNumber;
    final t = widget.chapterTitle.trim();
    if (num <= 0) return t;
    final prefix = 'Chương $num';
    if (t.toLowerCase().startsWith('chương $num')) return t;
    return t.isEmpty ? prefix : '$prefix: $t';
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _navigateTo(Chapter chapter) {
    // Khi navigate tới chapter mới, current chapter là adjacent đã biết:
    // • Đi tới "next" (số cao hơn) → current = prev của chapter mới
    // • Đi tới "prev" (số thấp hơn) → current = next của chapter mới
    final goingNext = chapter.chapterNumber > widget.chapterNumber;
    context.pushReplacement(
      '/reader/${widget.novelId}/${chapter.id}',
      extra: {
        'chapterTitle':  chapter.title,
        'chapterNumber': chapter.chapterNumber,
        if (goingNext) ...{
          'prevChapterId':    widget.chapterId,
          'prevChapterTitle': widget.chapterTitle,
          'prevChapterNum':   widget.chapterNumber,
        } else ...{
          'nextChapterId':    widget.chapterId,
          'nextChapterTitle': widget.chapterTitle,
          'nextChapterNum':   widget.chapterNumber,
        },
      },
    );
  }

  void _toggleBottomBar() {
    setState(() => _showBottomBar = !_showBottomBar);
  }

  void _showChapterList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChapterListSheet(
        novelId: widget.novelId,
        currentChapterId: widget.chapterId,
        onChapterTap: (chapter) {
          Navigator.of(context).pop(); // đóng sheet
          _navigateTo(chapter);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chapterAsync =
        ref.watch(_chapterContentProvider(widget.chapterId));
    final settings = ref.watch(_readerSettingsProvider);
    final theme = ReaderTheme.all[settings.themeIndex];

    final adjacentAsync = ref.watch(_adjacentProvider((
      novelId:      widget.novelId,
      chapterNumber: widget.chapterNumber,
      prevId:    widget.prevChapterId,
      prevTitle: widget.prevChapterTitle,
      prevNum:   widget.prevChapterNum,
      nextId:    widget.nextChapterId,
      nextTitle: widget.nextChapterTitle,
      nextNum:   widget.nextChapterNum,
    )));
    final prev = adjacentAsync.valueOrNull?.prev;
    final next = adjacentAsync.valueOrNull?.next;
    final adjacentLoading = adjacentAsync.isLoading;

    return Scaffold(
      backgroundColor: theme.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleBottomBar, // chỉ toggle bottom bar
        child: Stack(
          children: [
            // ── Nội dung chương ──────────────────────────────────────────
            chapterAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Lỗi tải chương: $e')),
              data: (chapter) {
                final paragraphs =
                    _splitParagraphs(chapter.content ?? '');
                // +1 header + +1 footer
                return ListView.builder(
                  controller: _scrollCtrl,
                  // top=100 luôn vì top bar luôn hiển thị
                  padding: const EdgeInsets.fromLTRB(20, 100, 20, 80),
                  itemCount: paragraphs.length + 2,
                  itemBuilder: (ctx, i) {
                    // index 0 = chapter title header
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _formattedTitle,
                          style: settings.buildTextStyle(
                            color: theme.text,
                            extraSize: 3,
                            customHeight: 1.4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    // index cuối = footer
                    if (i == paragraphs.length + 1) {
                      return _ChapterFooter(
                        theme: theme,
                        prev: prev,
                        next: next,
                        isLoading: adjacentLoading,
                        onPrev: prev != null
                            ? () => _navigateTo(prev)
                            : null,
                        onNext: next != null
                            ? () => _navigateTo(next)
                            : null,
                      );
                    }
                    // paragraphs[i-1] (vì i=0 là header)
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        paragraphs[i - 1],
                        style: settings.buildTextStyle(color: theme.text),
                      ),
                    );
                  },
                );
              },
            ),

            // ── Top bar — LUÔN HIỂN THỊ ──────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                theme: theme,
                title: _formattedTitle,
                onBack: () => context.pop(),
                onSettings: () =>
                    _showSettingsSheet(context, ref, settings),
              ),
            ),

            // ── Bottom bar — ẩn mặc định, tap để hiện ────────────────────
            if (_showBottomBar)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _BottomBar(
                  theme: theme,
                  prev: prev,
                  next: next,
                  isLoading: adjacentLoading,
                  onPrev: prev != null ? () => _navigateTo(prev) : null,
                  onNext: next != null ? () => _navigateTo(next) : null,
                  onToc: _showChapterList,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Tách đoạn văn — xử lý đúng HTML (br, p, div) trước khi strip tag
  List<String> _splitParagraphs(String content) {
    return content
        // Block elements → newline TRƯỚC khi strip
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        // Strip tất cả tag còn lại
        .replaceAll(RegExp(r'<[^>]*>'), '')
        // Escaped quotes từ WordPress (theme dùng addslashes)
        .replaceAll('\\"', '"')
        .replaceAll("\\'", "'")
        // HTML entities
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        // Split trên bất kỳ newline nào (1 hoặc nhiều)
        .split(RegExp(r'\n+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  void _showSettingsSheet(
      BuildContext context, WidgetRef ref, _ReaderSettings settings) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _ReaderSettingsSheet(
        chapterId: widget.chapterId,
        chapterTitle: widget.chapterTitle,
        chapterNumber: widget.chapterNumber,
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final ReaderTheme theme;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  const _TopBar({
    required this.theme,
    required this.title,
    required this.onBack,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.bg.withValues(alpha: 0.96),
        border: Border(
            bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: theme.text, size: 20),
                onPressed: onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, color: theme.text, size: 20),
                onPressed: onSettings,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bottom Bar ───────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final ReaderTheme theme;
  final Chapter? prev;
  final Chapter? next;
  final bool isLoading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onToc;

  const _BottomBar({
    required this.theme,
    required this.prev,
    required this.next,
    required this.isLoading,
    required this.onPrev,
    required this.onNext,
    required this.onToc,
  });

  @override
  Widget build(BuildContext context) {
    final dimColor = theme.text.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: theme.bg.withValues(alpha: 0.96),
        border: Border(
            top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // ← Trước
              Expanded(
                child: TextButton.icon(
                  onPressed: isLoading ? null : onPrev,
                  icon: Icon(Icons.chevron_left_rounded, size: 20,
                      color: onPrev != null ? theme.text : dimColor),
                  label: Text('Trước',
                      style: TextStyle(
                          fontSize: 13,
                          color: onPrev != null ? theme.text : dimColor)),
                  style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft),
                ),
              ),

              // Mục lục
              GestureDetector(
                onTap: onToc,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 22, color: theme.text),
                    const SizedBox(height: 2),
                    Text('Mục lục',
                        style: TextStyle(
                            fontSize: 10, color: theme.text)),
                  ],
                ),
              ),

              // Sau →
              Expanded(
                child: TextButton.icon(
                  onPressed: isLoading ? null : onNext,
                  icon: Text('Sau',
                      style: TextStyle(
                          fontSize: 13,
                          color: onNext != null ? theme.text : dimColor)),
                  label: Icon(Icons.chevron_right_rounded, size: 20,
                      color: onNext != null ? theme.text : dimColor),
                  style: TextButton.styleFrom(
                      alignment: Alignment.centerRight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Chapter Footer ───────────────────────────────────────────────────────────

class _ChapterFooter extends StatelessWidget {
  final ReaderTheme theme;
  final Chapter? prev;
  final Chapter? next;
  final bool isLoading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _ChapterFooter({
    required this.theme,
    required this.prev,
    required this.next,
    required this.isLoading,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = !isLoading && next == null;
    final dividerColor = theme.text.withValues(alpha: 0.2);
    final labelColor = theme.text.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Hết chương / Hết truyện ──
          Row(
            children: [
              Expanded(child: Divider(color: dividerColor, thickness: 0.8)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  isLast ? '— Hết truyện —' : '— Hết chương —',
                  style: TextStyle(fontSize: 12, color: labelColor),
                ),
              ),
              Expanded(child: Divider(color: dividerColor, thickness: 0.8)),
            ],
          ),

          const SizedBox(height: 20),

          // ── Nút điều hướng ──
          if (isLoading)
            SizedBox(
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.text.withValues(alpha: 0.4)),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Chương trước (outlined)
                if (prev != null)
                  OutlinedButton.icon(
                    onPressed: onPrev,
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: Text('Ch.${prev!.chapterNumber}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.text,
                      side: BorderSide(
                          color: theme.text.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),

                if (prev != null && next != null)
                  const SizedBox(width: 12),

                // Chương tiếp (filled teal)
                if (next != null)
                  ElevatedButton.icon(
                    onPressed: onNext,
                    icon: Text('Ch.${next!.chapterNumber}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    label: const Icon(Icons.chevron_right_rounded,
                        size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22D3EE),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
              ],
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Settings Sheet ───────────────────────────────────────────────────────────

// ─── Chapter List Sheet (Mục lục) ────────────────────────────────────────────

class _ChapterListSheet extends ConsumerStatefulWidget {
  final int novelId;
  final int currentChapterId;
  final void Function(Chapter) onChapterTap;

  const _ChapterListSheet({
    required this.novelId,
    required this.currentChapterId,
    required this.onChapterTap,
  });

  @override
  ConsumerState<_ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends ConsumerState<_ChapterListSheet> {
  static const _teal = Color(0xFF22D3EE);

  @override
  Widget build(BuildContext context) {
    final totalAsync = ref.watch(chapterCountProvider(widget.novelId));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('Danh sách chương',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (totalAsync.hasValue)
                    Text('${totalAsync.value} chương',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: totalAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: _teal, strokeWidth: 2)),
                error: (_, __) => const Center(
                    child: Text('Không tải được danh sách chương')),
                data: (total) => _ChapterListContent(
                  novelId: widget.novelId,
                  total: total,
                  currentChapterId: widget.currentChapterId,
                  scrollCtrl: scrollCtrl,
                  onChapterTap: widget.onChapterTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterListContent extends ConsumerStatefulWidget {
  final int novelId;
  final int total;
  final int currentChapterId;
  final ScrollController scrollCtrl;
  final void Function(Chapter) onChapterTap;

  const _ChapterListContent({
    required this.novelId,
    required this.total,
    required this.currentChapterId,
    required this.scrollCtrl,
    required this.onChapterTap,
  });

  @override
  ConsumerState<_ChapterListContent> createState() =>
      _ChapterListContentState();
}

class _ChapterListContentState extends ConsumerState<_ChapterListContent> {
  static const _teal = Color(0xFF22D3EE);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(chapterPageProvider(
                  (novelId: widget.novelId, total: widget.total))
              .notifier)
          .loadPage(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final args = (novelId: widget.novelId, total: widget.total);
    final state = ref.watch(chapterPageProvider(args));
    final notifier = ref.read(chapterPageProvider(args).notifier);

    if (state.isLoading && state.chapters.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: _teal, strokeWidth: 2));
    }

    return Column(
      children: [
        // Chapter list
        Expanded(
          child: ListView.builder(
            controller: widget.scrollCtrl,
            itemCount: state.chapters.length,
            itemBuilder: (ctx, i) {
              final ch = state.chapters[i];
              final isCurrent = ch.id == widget.currentChapterId;
              return ListTile(
                dense: true,
                selected: isCurrent,
                selectedTileColor: _teal.withValues(alpha: 0.08),
                leading: isCurrent
                    ? const Icon(Icons.play_arrow_rounded,
                        size: 18, color: _teal)
                    : null,
                title: Text(
                  _chapterTitle(ch),
                  style: TextStyle(
                    fontSize: 13,
                    color: isCurrent ? _teal : const Color(0xFF1E293B),
                    fontWeight: isCurrent
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onChapterTap(ch),
              );
            },
          ),
        ),

        // Pagination bar
        if (state.totalPages > 1)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // «
                _SheetPagBtn(
                  label: '«',
                  enabled: state.currentPage > 1 && !state.isLoading,
                  onTap: () => notifier.loadPage(1),
                ),
                // ←
                _SheetPagBtn(
                  label: '‹',
                  enabled: state.currentPage > 1 && !state.isLoading,
                  onTap: () => notifier.loadPage(state.currentPage - 1),
                ),
                const SizedBox(width: 8),
                Text(
                  '${state.currentPage} / ${state.totalPages}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                // →
                _SheetPagBtn(
                  label: '›',
                  enabled: state.currentPage < state.totalPages &&
                      !state.isLoading,
                  onTap: () => notifier.loadPage(state.currentPage + 1),
                ),
                // »
                _SheetPagBtn(
                  label: '»',
                  enabled: state.currentPage < state.totalPages &&
                      !state.isLoading,
                  onTap: () => notifier.loadPage(state.totalPages),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _chapterTitle(Chapter ch) {
    final num = ch.chapterNumber;
    final t = ch.title.trim();
    if (num <= 0) return t;
    final prefix = 'Chương $num';
    if (t.toLowerCase().startsWith('chương $num')) return t;
    return t.isEmpty ? prefix : '$prefix: $t';
  }
}

class _SheetPagBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _SheetPagBtn(
      {required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: enabled ? Colors.grey.shade100 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: enabled
                ? const Color(0xFF1E293B)
                : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

// ─── Settings Sheet ───────────────────────────────────────────────────────────

class _ReaderSettingsSheet extends ConsumerWidget {
  final int chapterId;
  final String chapterTitle;
  final int chapterNumber;

  const _ReaderSettingsSheet({
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterNumber,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(_readerSettingsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cài đặt đọc',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Cỡ chữ
            Row(
              children: [
                const Text('Cỡ chữ'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: s.fontSize > 12
                      ? () => ref
                          .read(_readerSettingsProvider.notifier)
                          .update(
                              (st) => st.copyWith(fontSize: st.fontSize - 1))
                      : null,
                ),
                Text('${s.fontSize.toInt()}'),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: s.fontSize < 28
                      ? () => ref
                          .read(_readerSettingsProvider.notifier)
                          .update(
                              (st) => st.copyWith(fontSize: st.fontSize + 1))
                      : null,
                ),
              ],
            ),
            // Giao diện
            const Text('Giao diện'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: List.generate(ReaderTheme.all.length, (i) {
                final t = ReaderTheme.all[i];
                return GestureDetector(
                  onTap: () => ref
                      .read(_readerSettingsProvider.notifier)
                      .update((st) => st.copyWith(themeIndex: i)),
                  child: Container(
                    width: 72,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: s.themeIndex == i
                            ? const Color(0xFF22D3EE)
                            : Colors.grey[300]!,
                        width: s.themeIndex == i ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(t.name,
                        style: TextStyle(color: t.text, fontSize: 12)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            // Font chữ
            const Text('Font chữ'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: List.generate(_kFontNames.length, (i) {
                final selected = s.fontIndex == i;
                return GestureDetector(
                  onTap: () => ref
                      .read(_readerSettingsProvider.notifier)
                      .update((st) => st.copyWith(fontIndex: i)),
                  child: Container(
                    width: 88,
                    height: 40,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF22D3EE).withValues(alpha: 0.12)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF22D3EE)
                            : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _kFontNames[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: selected
                            ? const Color(0xFF0891B2)
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const Divider(height: 28),
            // Báo cáo chương
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                Future.microtask(() {
                  if (context.mounted) {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16))),
                      builder: (_) => _ChapterReportSheet(
                        chapterNumber: chapterNumber,
                        chapterTitle: chapterTitle,
                      ),
                    );
                  }
                });
              },
              child: const Row(
                children: [
                  Icon(Icons.flag_outlined, size: 16, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Báo cáo lỗi chương',
                      style: TextStyle(fontSize: 14, color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chapter Report Sheet ─────────────────────────────────────────────────────

class _ChapterReportSheet extends StatefulWidget {
  final int chapterNumber;
  final String chapterTitle;
  const _ChapterReportSheet(
      {required this.chapterNumber, required this.chapterTitle});

  @override
  State<_ChapterReportSheet> createState() => _ChapterReportSheetState();
}

class _ChapterReportSheetState extends State<_ChapterReportSheet> {
  int? _selected;

  static const _reasons = [
    'Nội dung bị lỗi / hiển thị sai',
    'Thiếu đoạn văn / bị cắt',
    'Sai chương / nhảy chương',
    'Nội dung 18+, không phù hợp',
    'Lý do khác',
  ];

  Future<void> _send() async {
    final reason = _selected != null ? _reasons[_selected!] : 'Không rõ';
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@truyencv.io',
      queryParameters: {
        'subject':
            'Báo cáo lỗi chương ${widget.chapterNumber}: ${widget.chapterTitle}',
        'body': 'Lý do: $reason\n\n(Mô tả thêm nếu có)',
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
              const Text('Báo cáo lỗi chương',
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
