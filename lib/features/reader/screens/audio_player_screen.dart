import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/audio_reader_service.dart';
import '../../../core/services/ad_service.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _bg      = Color(0xFF0F1923);
const _surface = Color(0xFF1A2535);
const _accent  = Color(0xFF5B8DEF);
const _textPri = Colors.white;
final  _textSec = Colors.white.withValues(alpha: 0.6);

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const _sleepOptions = [null, 15, 30, 60]; // null = tắt

// ─── Screen ───────────────────────────────────────────────────────────────────

class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  Timer? _uiTimer; // refresh UI mỗi giây để cập nhật sleep countdown

  @override
  void initState() {
    super.initState();
    // Refresh UI mỗi giây (sleep timer countdown)
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Play/Pause với ad logic:
  /// - Nếu đang play → pause trước → show ad → sau ad dismiss mới play lại
  /// - Nếu đang pause/stop → show ad → sau ad dismiss mới play
  void _handlePlayPause(AudioReaderState s, AudioReaderNotifier ntf) {
    if (kIsWeb) { ntf.togglePlayPause(); return; }

    if (s.isPlaying) {
      // Đang play → pause ngay, rồi show ad, rồi resume sau ad
      ntf.pause();
      final adShown = AdService.instance.onAudioInteraction(
        onDismissed: () => ntf.play(),
      );
      if (!adShown) ntf.play(); // Không có ad → resume ngay
    } else {
      // Đang pause/stop → show ad trước, sau đó play
      final adShown = AdService.instance.onAudioInteraction(
        onDismissed: () => ntf.play(),
      );
      if (!adShown) ntf.play();
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
    // KHÔNG stop TTS ở đây — background playback
  }

  @override
  Widget build(BuildContext context) {
    final s   = ref.watch(audioReaderProvider);
    final ntf = ref.read(audioReaderProvider.notifier);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────
            _TopBar(novelTitle: s.novelTitle),
            const SizedBox(height: 12),

            // ── Cover ─────────────────────────────────────────────────
            _CoverWidget(coverUrl: s.coverUrl),
            const SizedBox(height: 20),

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
            const SizedBox(height: 20),

            // ── Progress slider ───────────────────────────────────────
            _ProgressSlider(state: s, notifier: ntf),
            const SizedBox(height: 16),

            // ── Controls ──────────────────────────────────────────────
            _Controls(
              state: s,
              notifier: ntf,
              onPlayPause: () => _handlePlayPause(s, ntf),
            ),
            const SizedBox(height: 20),

            // ── Speed selector ────────────────────────────────────────
            _SpeedSelector(current: s.speed, onSelect: ntf.setSpeed),
            const SizedBox(height: 16),

            // ── Text preview ──────────────────────────────────────────
            Expanded(
              child: _TextPreview(text: s.currentText),
            ),

            // ── Sleep timer ───────────────────────────────────────────
            _SleepTimerRow(
              state:    s,
              notifier: ntf,
              remaining: ntf.sleepRemainingSeconds,
            ),
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
  const _TopBar({required this.novelTitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: _textPri, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              novelTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: _textSec),
            ),
          ),
          const SizedBox(width: 48), // balance
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
    final size = MediaQuery.of(context).size.width * 0.52;
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
        // Prev paragraph
        _CtrlBtn(
          icon: Icons.skip_previous_rounded,
          size: 36,
          onTap: notifier.previousParagraph,
        ),
        const SizedBox(width: 28),

        // Play / Pause (big)
        GestureDetector(
          onTap: onPlayPause,
          child: Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _accent.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(
              state.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
        const SizedBox(width: 28),

        // Next paragraph
        _CtrlBtn(
          icon: Icons.skip_next_rounded,
          size: 36,
          onTap: notifier.nextParagraph,
        ),
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, size: size, color: _textPri),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _speeds.map((s) {
          final selected = (current - s).abs() < 0.01;
          return GestureDetector(
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13,
              color: _textSec,
              height: 1.6,
              fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}

// ─── Sleep Timer Row ──────────────────────────────────────────────────────────

class _SleepTimerRow extends StatelessWidget {
  final AudioReaderState state;
  final AudioReaderNotifier notifier;
  final int? remaining; // seconds

  const _SleepTimerRow({
    required this.state,
    required this.notifier,
    this.remaining,
  });

  String _label(int? min) {
    if (min == null) return 'Tắt';
    return '$min phút';
  }

  String _remainingText() {
    if (remaining == null) return '';
    final m = remaining! ~/ 60;
    final s = remaining! % 60;
    return ' (${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')})';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + countdown
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 15, color: _textSec),
              const SizedBox(width: 5),
              Text(
                'Hẹn giờ tắt${_remainingText()}',
                style: TextStyle(fontSize: 12, color: _textSec),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Options — scrollable để không bị tràn
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sleepOptions.map((opt) {
                final selected = state.sleepAfterMin == opt;
                return GestureDetector(
                  onTap: () => notifier.setSleepTimer(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color:        selected ? _accent : _surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _label(opt),
                      style: TextStyle(
                        fontSize: 13,
                        color: selected ? Colors.white : _textSec,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
