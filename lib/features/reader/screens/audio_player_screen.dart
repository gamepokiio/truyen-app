import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../core/services/audio_reader_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _bg      = Color(0xFF0F1923);
const _surface = Color(0xFF1A2535);
const _accent  = Color(0xFF5B8DEF);
const _textPri = Colors.white;

final _textSec = Colors.white.withValues(alpha: 0.6);

const _speeds       = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const _sleepOptions = [null, 15, 30, 60];

// ─── Screen ───────────────────────────────────────────────────────────────────

class AudioPlayerScreen extends ConsumerWidget {
  const AudioPlayerScreen({super.key});

  void _handlePlayPause(AudioReaderState s, AudioReaderNotifier ntf) {
    if (kIsWeb) { ntf.togglePlayPause(); return; }
    if (s.isPlaying) {
      ntf.pause();
    } else {
      ntf.play();
    }
  }

  void _showChapterList(BuildContext ctx, AudioReaderState s, AudioReaderNotifier ntf) {
    final novelId = s.novelId;
    if (novelId == null) return;
    showModalBottomSheet(
      context:           ctx,
      isScrollControlled: true,
      backgroundColor:   Colors.transparent,
      builder: (_) => _ChapterListSheet(
        novelId:              novelId,
        currentChapterId:     s.chapterId,
        currentChapterNumber: s.chapterNumber,
        notifier:             ntf,
      ),
    );
  }

  void _showSettings(BuildContext ctx) {
    showModalBottomSheet(
      context:            ctx,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => const _SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s   = ref.watch(audioReaderProvider);
    final ntf = ref.read(audioReaderProvider.notifier);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────
            _TopBar(
              novelTitle: s.novelTitle,
              hasChapterList: s.novelId != null,
              onClose: () async {
                await ntf.stop();
                if (context.mounted) Navigator.of(context).pop();
              },
              onChapterList: () => _showChapterList(context, s, ntf),
              onSettings:    () => _showSettings(context),
            ),
            const SizedBox(height: 12),

            // ── Cover ─────────────────────────────────────────────────
            _CoverWidget(coverUrl: s.coverUrl),
            const SizedBox(height: 16),

            // ── Chapter title ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                s.chapterTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textPri,
                    height: 1.35),
              ),
            ),
            const SizedBox(height: 12),

            // ── Loading next chapter indicator ────────────────────────
            if (s.isLoadingNext)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 13, height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _accent),
                    ),
                    const SizedBox(width: 8),
                    Text('Đang tải chương tiếp theo...',
                        style: TextStyle(fontSize: 12, color: _textSec)),
                  ],
                ),
              ),

            // ── Progress slider ───────────────────────────────────────
            _ProgressSlider(state: s, notifier: ntf),
            const SizedBox(height: 16),

            // ── Controls ──────────────────────────────────────────────
            _Controls(
              state:       s,
              notifier:    ntf,
              onPlayPause: () => _handlePlayPause(s, ntf),
            ),
            const SizedBox(height: 20),

            // ── Text preview (expanded — giờ to hơn vì không có speed/sleep) ──
            Expanded(child: _TextPreview(text: s.currentText)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String novelTitle;
  final bool hasChapterList;
  final VoidCallback onClose;
  final VoidCallback onChapterList;
  final VoidCallback onSettings;

  const _TopBar({
    required this.novelTitle,
    required this.hasChapterList,
    required this.onClose,
    required this.onChapterList,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // Nút đóng
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: _textPri, size: 28),
            onPressed: onClose,
          ),
          // Novel title
          Expanded(
            child: Text(
              novelTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: _textSec),
            ),
          ),
          // Danh sách chương
          IconButton(
            icon: Icon(Icons.list_rounded,
                color: hasChapterList ? _textPri : _textPri.withValues(alpha: 0.3),
                size: 24),
            tooltip: 'Danh sách chương',
            onPressed: hasChapterList ? onChapterList : null,
          ),
          // Cài đặt
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: _textPri, size: 22),
            tooltip: 'Cài đặt',
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

// ─── Cover ────────────────────────────────────────────────────────────────────

class _CoverWidget extends StatelessWidget {
  final String? coverUrl;
  const _CoverWidget({this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.48;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _accent.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: coverUrl != null
            ? CachedNetworkImage(
                imageUrl: coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: _surface),
                errorWidget: (_, __, ___) => _placeholder(size),
              )
            : _placeholder(size),
      ),
    );
  }

  Widget _placeholder(double size) => Container(
        color: _surface,
        child: Icon(Icons.menu_book_rounded,
            size: size * 0.35, color: _accent.withValues(alpha: 0.5)),
      );
}

// ─── Progress Slider ──────────────────────────────────────────────────────────

class _ProgressSlider extends StatelessWidget {
  final AudioReaderState state;
  final AudioReaderNotifier notifier;
  const _ProgressSlider({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final total   = state.paragraphs.length;
    final current = state.currentIdx;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor:   _accent,
              inactiveTrackColor: _surface,
              thumbColor:         _accent,
              overlayColor:       _accent.withValues(alpha: 0.15),
              trackHeight:        3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              min:   0,
              max:   total > 0 ? (total - 1).toDouble() : 1,
              value: current.toDouble().clamp(0, total > 0 ? total - 1.0 : 1),
              onChanged: (v) => notifier.seekTo(v.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(state.progress * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: _textSec)),
                Text('$current / $total đoạn',
                    style: TextStyle(fontSize: 11, color: _textSec)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Controls ─────────────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final AudioReaderState state;
  final AudioReaderNotifier notifier;
  final VoidCallback onPlayPause;
  const _Controls({required this.state, required this.notifier, required this.onPlayPause});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CtrlBtn(icon: Icons.skip_previous_rounded, size: 36,
            onTap: notifier.previousParagraph),
        const SizedBox(width: 28),
        GestureDetector(
          onTap: onPlayPause,
          child: Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _accent.withValues(alpha: 0.4),
                    blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(
              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white, size: 38,
            ),
          ),
        ),
        const SizedBox(width: 28),
        _CtrlBtn(icon: Icons.skip_next_rounded, size: 36,
            onTap: notifier.nextParagraph),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap,
          child: Icon(icon, size: size, color: _textPri));
}

// ─── Text Preview ─────────────────────────────────────────────────────────────

class _TextPreview extends StatelessWidget {
  final String text;
  const _TextPreview({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text.isEmpty ? 'Chưa có nội dung' : '"$text"',
          textAlign: TextAlign.center,
          overflow: TextOverflow.fade,
          style: TextStyle(
              fontSize: 13, color: _textSec,
              height: 1.6, fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}

// ─── Settings Sheet ───────────────────────────────────────────────────────────

class _SettingsSheet extends ConsumerStatefulWidget {
  const _SettingsSheet();

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh mỗi giây để countdown sleep timer cập nhật
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider trực tiếp → chip selection cập nhật realtime khi user thay đổi
    final s   = ref.watch(audioReaderProvider);
    final ntf = ref.read(audioReaderProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: _textPri.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),

          // ── Tốc độ đọc ───────────────────────────────────────────
          Text('Tốc độ đọc',
              style: TextStyle(fontSize: 13, color: _textSec,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _SpeedSelector(current: s.speed, onSelect: ntf.setSpeed),
          const SizedBox(height: 24),

          // Divider
          Divider(color: _textPri.withValues(alpha: 0.08), height: 1),
          const SizedBox(height: 24),

          // ── Hẹn giờ tắt ──────────────────────────────────────────
          _SleepTimerSection(
            state:     s,
            notifier:  ntf,
            remaining: ntf.sleepRemainingSeconds,
          ),
        ],
      ),
    );
  }
}

// ─── Speed Selector ───────────────────────────────────────────────────────────

class _SpeedSelector extends StatelessWidget {
  final double current;
  final void Function(double) onSelect;
  const _SpeedSelector({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _speeds.map((s) {
          final selected = (current - s).abs() < 0.01;
          return GestureDetector(
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color:        selected ? _accent : _surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${s}x',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : _textSec),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Sleep Timer Section ──────────────────────────────────────────────────────

class _SleepTimerSection extends StatelessWidget {
  final AudioReaderState state;
  final AudioReaderNotifier notifier;
  final int? remaining;

  const _SleepTimerSection({
    required this.state,
    required this.notifier,
    this.remaining,
  });

  String _remainingText() {
    if (remaining == null) return '';
    final m = remaining! ~/ 60;
    final s = remaining! % 60;
    return ' (${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')})';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 15, color: _textSec),
            const SizedBox(width: 5),
            Text(
              'Hẹn giờ tắt${_remainingText()}',
              style: TextStyle(fontSize: 13, color: _textSec,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _sleepOptions.map((opt) {
              final selected = state.sleepAfterMin == opt;
              final label    = opt == null ? 'Tắt' : '$opt phút';
              return GestureDetector(
                onTap: () => notifier.setSleepTimer(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color:        selected ? _accent : _surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? Colors.white : _textSec,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Chapter List Sheet ───────────────────────────────────────────────────────

class _ChapterListSheet extends ConsumerStatefulWidget {
  final int novelId;
  final int? currentChapterId;
  final int? currentChapterNumber;
  final AudioReaderNotifier notifier;

  const _ChapterListSheet({
    required this.novelId,
    required this.currentChapterId,
    required this.currentChapterNumber,
    required this.notifier,
  });

  @override
  ConsumerState<_ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends ConsumerState<_ChapterListSheet> {
  final _scrollCtrl = ScrollController();
  final _chapters   = <Map<String, dynamic>>[];
  int  _loadedPage  = 0;
  int  _totalPages  = 1;
  bool _isLoading   = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadInitialPage();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  // Tải trang chứa chương đang nghe, sau đó auto-scroll đến nó
  Future<void> _loadInitialPage() async {
    setState(() => _isLoading = true);
    try {
      final api   = NovelApi(ref.read(cachedDioProvider));
      final total = await api.getChapterCount(widget.novelId);
      if (total == 0) { setState(() => _isLoading = false); return; }

      const perPage   = 50;
      final currentNum = widget.currentChapterNumber ?? 1;

      // Chapters newest-first: chapter #N ở vị trí 0-based = (total - N)
      final zeroIdx  = (total - currentNum).clamp(0, total - 1);
      final initPage = (zeroIdx ~/ perPage) + 1;

      _totalPages = (total / perPage).ceil();

      final result = await api.getChapters(
          novelId: widget.novelId, page: initPage, perPage: perPage);
      final items  = List<Map<String, dynamic>>.from(
          result['items'] as List? ?? []);

      setState(() {
        _chapters.addAll(items);
        _loadedPage = initPage;
        _isLoading  = false;
      });

      // Auto-scroll đến chương đang nghe
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentChapter();
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _scrollToCurrentChapter() {
    final currentNum = widget.currentChapterNumber;
    if (currentNum == null || !_scrollCtrl.hasClients) return;
    final idx = _chapters.indexWhere(
        (ch) => ((ch['number'] as num?)?.round() ?? 0) == currentNum);
    if (idx >= 0) {
      final offset = (idx * 64.0).clamp(
          0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl.animateTo(offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
    }
  }

  // Load thêm trang khi scroll đến cuối
  void _onScroll() {
    if (_isLoading) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    final nextPage = _loadedPage + 1;
    if (nextPage > _totalPages || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      final api    = NovelApi(ref.read(cachedDioProvider));
      final result = await api.getChapters(
          novelId: widget.novelId, page: nextPage, perPage: 50);
      final items  = List<Map<String, dynamic>>.from(
          result['items'] as List? ?? []);
      setState(() {
        _chapters.addAll(items);
        _loadedPage = nextPage;
        _isLoading  = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle + Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: _textPri.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.list_rounded,
                          color: _textPri, size: 20),
                      const SizedBox(width: 8),
                      const Text('Danh sách chương',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textPri)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: _textPri, size: 22),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: _textPri.withValues(alpha: 0.08), height: 1),

            // Chapter list
            Expanded(
              child: _chapters.isEmpty && _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      itemCount: _chapters.length + (_isLoading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _chapters.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: _accent, strokeWidth: 2)),
                          );
                        }
                        final ch        = _chapters[i];
                        final chNum     = ((ch['number'] as num?)?.round() ?? 0);
                        final chId      = ch['id'] as int? ?? 0;
                        final chTitle   = ch['title'] as String? ?? '';
                        final isCurrent = chId == widget.currentChapterId;

                        return _ChapterListItem(
                          chapterNumber: chNum,
                          chapterTitle:  chTitle,
                          isCurrent:     isCurrent,
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.notifier.loadChapterById(
                              chapterId:     chId,
                              chapterTitle:  chTitle,
                              chapterNumber: chNum,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterListItem extends StatelessWidget {
  final int chapterNumber;
  final String chapterTitle;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ChapterListItem({
    required this.chapterNumber,
    required this.chapterTitle,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isCurrent ? _accent.withValues(alpha: 0.12) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Playing indicator
            SizedBox(
              width: 24,
              child: isCurrent
                  ? const Icon(Icons.volume_up_rounded,
                        color: _accent, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
            // Chapter info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chương $chapterNumber',
                    style: TextStyle(
                        fontSize: 12,
                        color: isCurrent ? _accent : _textSec),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chapterTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isCurrent ? _accent : _textPri),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
