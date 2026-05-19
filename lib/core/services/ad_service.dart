import 'dart:io';
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
  int _chapterReadCount = 0;
  static const int _chaptersPerAd = 3;

  // ── Init ─────────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitialAd();
  }

  // ── Load ─────────────────────────────────────────────────────────────────────
  void _loadInterstitialAd() {
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
          // Thử load lại sau 1 phút nếu thất bại
          Future.delayed(const Duration(minutes: 1), _loadInterstitialAd);
        },
      ),
    );
  }

  // ── Show logic: gọi mỗi khi user chuyển chương ───────────────────────────────
  /// Trả về true nếu đã hiển thị ads
  bool onChapterChanged() {
    _chapterReadCount++;
    if (_chapterReadCount >= _chaptersPerAd) {
      _chapterReadCount = 0; // Reset đếm
      if (_isAdReady && _interstitialAd != null) {
        _showAd();
        return true;
      }
    }
    return false;
  }

  void _showAd() {
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _isAdReady = false;
        _loadInterstitialAd(); // Load ad tiếp theo
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _isAdReady = false;
        _loadInterstitialAd();
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
