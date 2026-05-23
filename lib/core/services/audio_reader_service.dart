import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'ad_service.dart';

// ─── State ────────────────────────────────────────────────────────────────────

enum AudioStatus { stopped, playing, paused }

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
  });

  bool get isPlaying  => status == AudioStatus.playing;
  bool get isPaused   => status == AudioStatus.paused;
  bool get isStopped  => status == AudioStatus.stopped;
  bool get hasContent => paragraphs.isNotEmpty;

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
    Object? sleepAfterMin = _sentinel,
    Object? sleepStartedAt = _sentinel,
  }) {
    return AudioReaderState(
      status:        status        ?? this.status,
      paragraphs:    paragraphs    ?? this.paragraphs,
      currentIdx:    currentIdx    ?? this.currentIdx,
      speed:         speed         ?? this.speed,
      novelTitle:    novelTitle    ?? this.novelTitle,
      chapterTitle:  chapterTitle  ?? this.chapterTitle,
      coverUrl:      coverUrl      ?? this.coverUrl,
      sleepAfterMin: identical(sleepAfterMin, _sentinel)
          ? this.sleepAfterMin
          : sleepAfterMin as int?,
      sleepStartedAt: identical(sleepStartedAt, _sentinel)
          ? this.sleepStartedAt
          : sleepStartedAt as DateTime?,
    );
  }
}

const _sentinel = Object();

// ─── Notifier ─────────────────────────────────────────────────────────────────

class AudioReaderNotifier extends StateNotifier<AudioReaderState> {
  AudioReaderNotifier() : super(const AudioReaderState()) {
    _init();
  }

  final FlutterTts _tts = FlutterTts();
  Timer? _sleepTimer;

  // ── TTS rate mapping ───────────────────────────────────────────────────────
  /// Chuyển speed người dùng (0.5x–2.0x) → TTS speech rate
  /// iOS: 0.5 = normal (AVSpeechUtteranceDefaultSpeechRate), 1.0 = max
  /// Android: 1.0 = normal nhưng thực tế cũng nhanh, dùng 0.5 cho nhất quán
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

    // Khi đọc xong 1 đoạn → tự động qua đoạn tiếp
    _tts.setCompletionHandler(_onParagraphComplete);
    _tts.setCancelHandler(_onTtsCancelled);
    _tts.setErrorHandler((_) => _onTtsCancelled());
  }

  // ── Load chapter content ───────────────────────────────────────────────────
  /// Gọi khi user mở audio player hoặc chuyển chương
  Future<void> loadChapter({
    required String content,
    required String novelTitle,
    required String chapterTitle,
    String? coverUrl,
    bool autoPlay = true,
  }) async {
    if (kIsWeb) return;
    await _tts.stop();
    _sleepTimer?.cancel();

    final paragraphs = _splitParagraphs(content);
    state = state.copyWith(
      status:       AudioStatus.stopped,
      paragraphs:   paragraphs,
      currentIdx:   0,
      novelTitle:   novelTitle,
      chapterTitle: chapterTitle,
      coverUrl:     coverUrl,
      sleepAfterMin:   null,
      sleepStartedAt:  null,
    );

    if (autoPlay && paragraphs.isNotEmpty) {
      await _playFrom(0);
    }
  }

  // ── Play / Pause / Stop ───────────────────────────────────────────────────
  Future<void> play() async {
    if (kIsWeb || state.paragraphs.isEmpty) return;
    if (state.isPaused) {
      // Cập nhật UI ngay lập tức trước khi đợi TTS
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
    // Cập nhật UI ngay lập tức (responsive), rồi await stop để TTS thực sự dừng
    state = state.copyWith(status: AudioStatus.paused);
    _syncAdFlag();
    await _tts.stop(); // await để đảm bảo audio dừng hẳn
    // _onTtsCancelled sẽ fire nhưng state đã là paused → không làm gì thêm
  }

  Future<void> stop() async {
    if (kIsWeb) return;
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

  // ── Seek ───────────────────────────────────────────────────────────────────
  Future<void> seekTo(int idx) async {
    if (kIsWeb || idx < 0 || idx >= state.paragraphs.length) return;
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
    final idx        = state.currentIdx; // lưu lại trước khi state thay đổi
    state = state.copyWith(speed: speed);
    if (wasPlaying) {
      // Set paused TRƯỚC khi stop() — giống pause() — để _onTtsCancelled không can thiệp
      state = state.copyWith(status: AudioStatus.paused);
      await _tts.stop();
      // Restart đúng đoạn hiện tại (không phải từ đầu chương)
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

  /// Số giây còn lại của sleep timer
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

  // ── Internal ───────────────────────────────────────────────────────────────
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

  void _onParagraphComplete() {
    if (!state.isPlaying) return;
    final next = state.currentIdx + 1;
    if (next < state.paragraphs.length) {
      _playFrom(next);
    } else {
      // Hết chương — hủy sleep timer, reset state
      _sleepTimer?.cancel();
      state = state.copyWith(
        status:        AudioStatus.stopped,
        currentIdx:    0,
        sleepAfterMin:  null,
        sleepStartedAt: null,
      );
      _syncAdFlag();
    }
  }

  void _onTtsCancelled() {
    // TTS bị cancel từ bên ngoài (không phải từ code của mình)
    if (state.isPlaying) {
      state = state.copyWith(status: AudioStatus.paused);
      _syncAdFlag();
    }
  }

  // ── Text splitting ─────────────────────────────────────────────────────────
  static List<String> _splitParagraphs(String content) {
    // Bước 1: Block elements → newline trước khi strip tag
    final text = content
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        // Strip tất cả tag còn lại
        .replaceAll(RegExp(r'<[^>]*>'), '')
        // Escaped quotes (WordPress addslashes)
        .replaceAll('\\"', '"')
        .replaceAll("\\'", "'")
        // HTML entities
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ');

    // Bước 2: Split theo newline
    final lines = text
        .split(RegExp(r'\n+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Bước 3: Gộp các dòng ngắn (<50 ký tự) để TTS đọc tự nhiên hơn
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
    if (!kIsWeb) _tts.stop();
    super.dispose();
  }
}

// ─── Provider (global — sống suốt vòng đời app) ──────────────────────────────

final audioReaderProvider =
    StateNotifierProvider<AudioReaderNotifier, AudioReaderState>(
  (ref) => AudioReaderNotifier(),
);
