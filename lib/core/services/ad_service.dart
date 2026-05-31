import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  // ── Ad Unit IDs ─────────────────────────────────────────────────────────────
  static String get _interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3816336764347521/9964163694';
    } else {
      return 'ca-app-pub-3816336764347521/7634725271';
    }
  }

  // ── State ────────────────────────────────────────────────────────────────────
  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;

  // Reader: mỗi 3 chương chuyển
  int _chapterReadCount = 0;
  static const int _chaptersPerAd = 3;

  /// Được set bởi AudioReaderNotifier — tránh show ad khi nghe liên tục
  bool isAudioPlaying = false;

  // ── Init ─────────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (kIsWeb) return;
    await MobileAds.instance.initialize();
    _loadInterstitialAd();
  }

  // ── Load ─────────────────────────────────────────────────────────────────────
  void _loadInterstitialAd() {
    if (kIsWeb) return;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdReady = true;
          _interstitialAd!.setImmersiveMode(true);
        },
        onAdFailedToLoad: (error) {
          _isAdReady = false;
          _interstitialAd = null;
          Future.delayed(const Duration(minutes: 1), _loadInterstitialAd);
        },
      ),
    );
  }

  // ── Reader: gọi khi user chuyển chương ──────────────────────────────────────
  /// Trả về true nếu đã hiển thị ad
  bool onChapterChanged() {
    if (kIsWeb) return false;
    _chapterReadCount++;
    if (_chapterReadCount >= _chaptersPerAd) {
      _chapterReadCount = 0;
      // Không interrupt khi đang nghe audio liên tục
      if (_isAdReady && _interstitialAd != null && !isAudioPlaying) {
        _showAd();
        return true;
      }
    }
    return false;
  }

  // ── Audio: gọi khi user mở audio player lần đầu ─────────────────────────────
  /// Luôn hiển thị ad ngay nếu có (không cần đếm)
  /// [onDismissed]: callback sau khi ad đóng — để play audio sau ad
  bool onAudioPlayerOpened({void Function()? onDismissed}) {
    if (kIsWeb) return false;
    if (_isAdReady && _interstitialAd != null) {
      _showAd(onDismissed: onDismissed);
      return true;
    }
    return false;
  }



  // ── Internal ─────────────────────────────────────────────────────────────────
  void _showAd({void Function()? onDismissed}) {
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isAdReady = false;
        _loadInterstitialAd();
        onDismissed?.call(); // Resume audio sau khi ad đóng
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _isAdReady = false;
        _loadInterstitialAd();
        onDismissed?.call(); // Không có ad → vẫn cần resume
      },
    );
    _interstitialAd!.show();
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
