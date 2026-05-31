import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../api/dio_client.dart';
import '../api/novel_api.dart';
import 'ad_service.dart';

// ─── State ────────────────────────────────────────────────────────────────────

enum AudioStatus { stopped, playing, paused, loadingNext }

class AudioReaderState {
  final AudioStatus status;
  final List<String> paragraphs;   // text chunks
  final int currentIdx;            // paragraph đang đọc
  final double speed;              // 0.5 / 1.0 / 1.5 / 2.0
  final String novelTitle;
  final String chapterTitle;
  final String? coverUrl;
  final int? sleepAfterMin;        // null = không hẹn giờ
  final DateTime? sleepStartedAt;  // khi nào bắt đầu đếm
  // Chapter navigation — cần để auto-advance
  final int? novelId;
  final int? chapterId;
  final int? chapterNumber;

  const AudioReaderState({
    this.status = AudioStatus.stopped,
    this.paragraphs = const [],
    this.currentIdx = 0,
    this.speed = 1.0,
    this.novelTitle = '',
    this.chapterTitle = '',
    this.coverUrl,
    this.sleepAfterMin,
    this.sleepStartedAt,
    this.novelId,
    this.chapterId,
    this.chapterNumber,
  });

  bool get isPlaying     => status == AudioStatus.playing;
  bool get isPaused      => status == AudioStatus.paused;
  bool get isStopped     => status == AudioStatus.stopped;
  bool get isLoadingNext => status == AudioStatus.loadingNext;
  bool get hasContent    => paragraphs.isNotEmpty;

  String get currentText =>
      (currentIdx < paragraphs.length) ? paragraphs[currentIdx] : '';

  double get progress => paragraphs.isEmpty
      ? 0
      : currentIdx / paragraphs.length;

  AudioReaderState copyWith({
    AudioStatus? status,
    List<String>? paragraphs,
    int? currentIdx,
    double? speed,
    String? novelTitle,
    String? chapterTitle,
    String? coverUrl,
    Object? sleepAfterMin  = _sentinel,
    Object? sleepStartedAt = _sentinel,
    Object? novelId        = _sentinel,
    Object? chapterId      = _sentinel,
    Object? chapterNumber  = _sentinel,
  }) {
    return AudioReaderState(
      status:        status        ?? this.status,
      paragraphs:    paragraphs    ?? this.paragraphs,
      currentIdx:    currentIdx    ?? this.currentIdx,
      speed:         speed         ?? this.speed,
      novelTitle:    novelTitle    ?? this.novelTitle,
      chapterTitle:  chapterTitle  ?? this.chapterTitle,
      coverUrl:      coverUrl      ?? this.coverUrl,
      sleepAfterMin:  identical(sleepAfterMin,  _sentinel) ? this.sleepAfterMin  : sleepAfterMin  as int?,
      sleepStartedAt: identical(sleepStartedAt, _sentinel) ? this.sleepStartedAt : sleepStartedAt as DateTime?,
      novelId:        identical(novelId,        _sentinel) ? this.novelId        : novelId        as int?,
      chapterId:      identical(chapterId,      _sentinel) ? this.chapterId      : chapterId      as int?,
      chapterNumber:  identical(chapterNumber,  _sentinel) ? this.chapterNumber  : chapterNumber  as int?,
    );
  }
}

const _sentinel = Object();

// ─── Notifier ─────────────────────────────────────────────────────────────────

class AudioReaderNotifier extends StateNotifier<AudioReaderState> {
  AudioReaderNotifier(this._ref) : super(const AudioReaderState()) {
    _init();
  }

  final Ref _ref;
  final FlutterTts _tts = FlutterTts();
  Timer? _sleepTimer;

  /// Flag: TTS đang đọc thông báo "Hết chương, chuyển sang chương mới"
  /// → completionHandler cần biết để gọi fetch thay vì advance paragraph.
  bool _isAnnouncingTransition = false;

  // ── TTS rate mapping ───────────────────────────────────────────────────────
  static double _toTtsRate(double speed) => (speed * 0.5).clamp(0.0, 1.0);

  // ── Init TTS engine ────────────────────────────────────────────────────────
  Future<void> _init() async {
    if (kIsWeb) return;
    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(_toTtsRate(state.speed));
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // iOS: cho phép background audio
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
      IosTextToSpeechAudioMode.defaultMode,
    );

    _tts.setCompletionHandler(_onTtsCompleted);
    _tts.setCancelHandler(_onTtsCancelled);
    _tts.setErrorHandler((_) => _onTtsCancelled());
  }

  // ── Load chapter content ───────────────────────────────────────────────────
  Future<void> loadChapter({
    required String content,
    required String novelTitle,
    required String chapterTitle,
    String? coverUrl,
    int? novelId,
    int? chapterId,
    int? chapterNumber,
    bool autoPlay      = true,
    bool keepSleepTimer = false, // true khi auto-advance/user chọn chương — giữ nguyên timer
  }) async {
    if (kIsWeb) return;
    _isAnnouncingTransition = false;
    await _tts.stop();
    if (!keepSleepTimer) _sleepTimer?.cancel();

    final paragraphs = _splitParagraphs(content);
    state = state.copyWith(
      status:        AudioStatus.stopped,
      paragraphs:    paragraphs,
      currentIdx:    0,
      novelTitle:    novelTitle,
      chapterTitle:  chapterTitle,
      coverUrl:      coverUrl,
      novelId:       novelId,
      chapterId:     chapterId,
      chapterNumber: chapterNumber,
      sleepAfterMin:   keepSleepTimer ? state.sleepAfterMin  : null,
      sleepStartedAt:  keepSleepTimer ? state.sleepStartedAt : null,
    );

    if (autoPlay && paragraphs.isNotEmpty) {
      await _playFrom(0);
    }
  }

  // ── Play / Pause / Stop ───────────────────────────────────────────────────
  Future<void> play() async {
    if (kIsWeb || state.paragraphs.isEmpty) return;
    if (state.isPaused) {
      state = state.copyWith(status: AudioStatus.playing);
      _syncAdFlag();
      await _tts.setSpeechRate(_toTtsRate(state.speed));
      await _tts.speak(state.currentText);
    } else {
      await _playFrom(state.currentIdx);
    }
  }

  Future<void> pause() async {
    if (kIsWeb) return;
    _isAnnouncingTransition = false;
    state = state.copyWith(status: AudioStatus.paused);
    _syncAdFlag();
    await _tts.stop();
  }

  Future<void> stop() async {
    if (kIsWeb) return;
    _isAnnouncingTransition = false;
    await _tts.stop();
    _sleepTimer?.cancel();
    state = state.copyWith(
      status:        AudioStatus.stopped,
      currentIdx:    0,
      sleepAfterMin:   null,
      sleepStartedAt:  null,
    );
    _syncAdFlag();
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  // ── Load chapter by ID (user chọn từ danh sách chương) ───────────────────
  Future<void> loadChapterById({
    required int chapterId,
    required String chapterTitle,
    required int chapterNumber,
  }) async {
    if (kIsWeb) return;
    final novelId = state.novelId;
    if (novelId == null) return;

    _isAnnouncingTransition = false;
    await _tts.stop();
    _sleepTimer?.cancel();

    state = state.copyWith(
      status:        AudioStatus.loadingNext,
      paragraphs:    const [],
      currentIdx:    0,
      chapterTitle:  chapterTitle,
      chapterId:     chapterId,
      chapterNumber: chapterNumber,
      sleepAfterMin:  null,
      sleepStartedAt: null,
    );

    try {
      final api     = NovelApi(_ref.read(cachedDioProvider));
      final data    = await api.getChapterById(chapterId);
      final content = data['content'] as String? ?? '';

      if (content.isEmpty) { _stopAndReset(); return; }

      await loadChapter(
        content:        content,
        novelTitle:     state.novelTitle,
        chapterTitle:   chapterTitle,
        coverUrl:       state.coverUrl,
        novelId:        novelId,
        chapterId:      chapterId,
        chapterNumber:  chapterNumber,
        autoPlay:       true,
        keepSleepTimer: true, // giữ timer nếu user đang hẹn giờ
      );
    } catch (_) {
      _stopAndReset();
    }
  }

  // ── Seek ───────────────────────────────────────────────────────────────────
  Future<void> seekTo(int idx) async {
    if (kIsWeb || idx < 0 || idx >= state.paragraphs.length) return;
    _isAnnouncingTransition = false;
    await _tts.stop();
    await _playFrom(idx);
  }

  Future<void> previousParagraph() async {
    final next = (state.currentIdx - 1).clamp(0, state.paragraphs.length - 1);
    await seekTo(next);
  }

  Future<void> nextParagraph() async {
    final next = state.currentIdx + 1;
    if (next >= state.paragraphs.length) {
      await stop();
    } else {
      await seekTo(next);
    }
  }

  // ── Speed ──────────────────────────────────────────────────────────────────
  Future<void> setSpeed(double speed) async {
    if (kIsWeb) return;
    final wasPlaying = state.isPlaying;
    final idx        = state.currentIdx;
    state = state.copyWith(speed: speed);
    if (wasPlaying) {
      state = state.copyWith(status: AudioStatus.paused);
      await _tts.stop();
      await _tts.setSpeechRate(_toTtsRate(speed));
      await _playFrom(idx);
    } else {
      await _tts.setSpeechRate(_toTtsRate(speed));
    }
  }

  // ── Sleep timer ────────────────────────────────────────────────────────────
  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    if (minutes == null) {
      state = state.copyWith(sleepAfterMin: null, sleepStartedAt: null);
      return;
    }
    state = state.copyWith(
      sleepAfterMin:  minutes,
      sleepStartedAt: DateTime.now(),
    );
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await stop();
    });
  }

  int? get sleepRemainingSeconds {
    if (state.sleepAfterMin == null || state.sleepStartedAt == null) return null;
    final elapsed = DateTime.now().difference(state.sleepStartedAt!).inSeconds;
    final total   = state.sleepAfterMin! * 60;
    return (total - elapsed).clamp(0, total);
  }

  // ── Sync AdMob flag ────────────────────────────────────────────────────────
  void _syncAdFlag() {
    AdService.instance.isAudioPlaying = state.isPlaying;
  }

  // ── Internal playback ─────────────────────────────────────────────────────
  Future<void> _playFrom(int idx) async {
    if (kIsWeb || idx >= state.paragraphs.length) {
      state = state.copyWith(status: AudioStatus.stopped);
      _syncAdFlag();
      return;
    }
    state = state.copyWith(status: AudioStatus.playing, currentIdx: idx);
    _syncAdFlag();
    await _tts.setSpeechRate(_toTtsRate(state.speed));
    await _tts.speak(state.paragraphs[idx]);
  }

  // ── TTS completion handler ────────────────────────────────────────────────
  void _onTtsCompleted() {
    // Đang đọc thông báo chuyển chương → fetch chương tiếp
    if (_isAnnouncingTransition) {
      _isAnnouncingTransition = false;
      _fetchAndLoadNextChapter();
      return;
    }

    if (!state.isPlaying) return;

    final next = state.currentIdx + 1;
    if (next < state.paragraphs.length) {
      _playFrom(next);
    } else {
      _onChapterEnd();
    }
  }

  void _onTtsCancelled() {
    if (_isAnnouncingTransition) {
      _isAnnouncingTransition = false;
      return;
    }
    if (state.isPlaying) {
      state = state.copyWith(status: AudioStatus.paused);
      _syncAdFlag();
    }
  }

  // ── Chapter end logic ─────────────────────────────────────────────────────
  void _onChapterEnd() {
    // Không có thông tin novel → không thể auto-advance → dừng
    if (state.novelId == null || state.chapterNumber == null) {
      _sleepTimer?.cancel();
      state = state.copyWith(
        status:        AudioStatus.stopped,
        currentIdx:    0,
        sleepAfterMin:  null,
        sleepStartedAt: null,
      );
      _syncAdFlag();
      return;
    }

    // Có thông tin → thông báo TTS rồi chuyển chương
    _isAnnouncingTransition = true;
    // Đọc thông báo ở tốc độ bình thường (0.5) bất kể setting speed của user
    _tts.setSpeechRate(0.5).then((_) {
      _tts.speak('Hết chương, chuyển sang chương mới');
    });
  }

  // ── Fetch & load next chapter ──────────────────────────────────────────────
  Future<void> _fetchAndLoadNextChapter() async {
    final novelId     = state.novelId;
    final currentNum  = state.chapterNumber ?? 0;

    if (novelId == null || currentNum <= 0) {
      _stopAndReset();
      return;
    }

    // Hiện trạng loading — giữ thông tin truyện, clear paragraphs
    state = state.copyWith(
      status:      AudioStatus.loadingNext,
      paragraphs:  const [],
      currentIdx:  0,
      chapterTitle: 'Đang tải chương ${currentNum + 1}...',
    );

    try {
      final api       = NovelApi(_ref.read(cachedDioProvider));
      final targetNum = currentNum + 1;

      // Bước 1: Tìm chapter ID theo số chương
      // Chapters trả về theo thứ tự mới nhất trước (số lớn → đầu list)
      // Chapter #N nằm ở vị trí 0-based: (total - N), tính page tương ứng
      final total = await api.getChapterCount(novelId);
      if (total == 0 || targetNum > total) {
        // Hết truyện
        _stopAndReset();
        return;
      }

      const perPage  = 50;
      final zeroIdx  = total - targetNum;   // 0-based index từ đầu list
      final page     = (zeroIdx ~/ perPage) + 1;

      final chaptersResult = await api.getChapters(
        novelId: novelId, page: page, perPage: perPage,
      );
      final items = List<Map<String, dynamic>>.from(
        chaptersResult['items'] as List? ?? [],
      );

      Map<String, dynamic>? nextChap;
      for (final ch in items) {
        if (((ch['number'] as num?)?.round() ?? 0) == targetNum) {
          nextChap = ch;
          break;
        }
      }

      if (nextChap == null) {
        _stopAndReset();
        return;
      }

      final nextId    = nextChap['id'] as int;
      final nextTitle = nextChap['title'] as String? ?? 'Chương $targetNum';

      // Bước 2: Fetch nội dung chương tiếp
      final chapterData = await api.getChapterById(nextId);
      final content     = chapterData['content'] as String? ?? '';

      if (content.isEmpty) {
        _stopAndReset();
        return;
      }

      // Guard: sleep timer có thể đã fire trong lúc fetch → không phát nữa
      if (state.isStopped) return;

      // Bước 3: Load và phát — giữ sleep timer nếu user đã hẹn
      await loadChapter(
        content:        content,
        novelTitle:     state.novelTitle,
        chapterTitle:   nextTitle,
        coverUrl:       state.coverUrl,
        novelId:        novelId,
        chapterId:      nextId,
        chapterNumber:  targetNum,
        autoPlay:       true,
        keepSleepTimer: true,
      );
    } catch (_) {
      _stopAndReset();
    }
  }

  void _stopAndReset() {
    _sleepTimer?.cancel();
    state = state.copyWith(
      status:        AudioStatus.stopped,
      currentIdx:    0,
      sleepAfterMin:  null,
      sleepStartedAt: null,
    );
    _syncAdFlag();
  }

  // ── Text splitting ─────────────────────────────────────────────────────────
  static List<String> _splitParagraphs(String content) {
    final text = content
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('\\"', '"')
        .replaceAll("\\'", "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ');

    final lines = text
        .split(RegExp(r'\n+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final result = <String>[];
    String buffer = '';
    for (final line in lines) {
      if (buffer.isEmpty) {
        buffer = line;
      } else if (buffer.length < 50) {
        buffer = '$buffer $line';
      } else {
        result.add(buffer);
        buffer = line;
      }
    }
    if (buffer.isNotEmpty) result.add(buffer);
    return result;
  }

  // ── Dispose ────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _sleepTimer?.cancel();
    _isAnnouncingTransition = false;
    if (!kIsWeb) _tts.stop();
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final audioReaderProvider =
    StateNotifierProvider<AudioReaderNotifier, AudioReaderState>(
  (ref) => AudioReaderNotifier(ref),
);
