import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../shared/models/novel_model.dart' show Novel, filterNovels;

// ─── Genre slug → ID map ──────────────────────────────────────────────────────

final _genreMapProvider = FutureProvider<Map<String, int>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final genres = await api.getGenres(perPage: 100);
  return {for (final g in genres) (g['slug'] as String): (g['id'] as num).toInt()};
});

// ─── Providers ────────────────────────────────────────────────────────────────

/// 20 truyện mới cập nhật nhất
final _latestProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getNovels(page: 1, perPage: 20, orderby: 'modified', order: 'desc');
  return filterNovels(data.map(Novel.fromJson).toList());
});

/// Truyện thể loại "Hay" dùng cho slider
final _hayNovelsProvider = FutureProvider<List<Novel>>((ref) async {
  final genreMap = await ref.watch(_genreMapProvider.future);
  final hayId = genreMap['hay'] ??
      genreMap['truyen-hay'] ??
      genreMap['de-xuat'] ??
      genreMap['recommended'];
  final api = NovelApi(ref.read(cachedDioProvider));
  if (hayId != null) {
    final data = await api.getNovels(page: 1, perPage: 6, genreId: hayId);
    final filtered = filterNovels(data.map(Novel.fromJson).toList());
    if (filtered.isNotEmpty) return filtered;
  }
  final data = await api.getNovels(page: 1, perPage: 6, orderby: 'modified', order: 'desc');
  return filterNovels(data.map(Novel.fromJson).toList());
});

/// Truyện nên đọc — trang 2, shuffle
final _randomNovelsProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getNovels(
    page: 2, perPage: 20, orderby: 'modified', order: 'desc');
  final novels = filterNovels(data.map(Novel.fromJson).toList())
    ..shuffle(Random());
  return novels.take(20).toList();
});

/// Truyện Full — manga_status=completed
final _fullNovelsProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getNovels(
    page: 1, perPage: 9, orderby: 'modified', order: 'desc',
    status: 'completed',
  );
  return filterNovels(data.map(Novel.fromJson).toList());
});

/// Đề cử — genre ID 639
const _kDeucuGenreId = 639;

final _nominatedProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getNovels(
    page: 1, perPage: 6, genreId: _kDeucuGenreId,
    orderby: 'modified', order: 'desc',
  );
  return filterNovels(data.map(Novel.fromJson).toList());
});

// ─── Constants ────────────────────────────────────────────────────────────────

const _teal     = Color(0xFF22D3EE);
const _tealEnd  = Color(0xFF2DD4BF);
const _textPrimary   = Color(0xFF1A1A1A);
const _textSecondary = Color(0xFF757575);

// ─── Screen ───────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _heroPageCtrl       = PageController();
  final _latestScrollCtrl    = ScrollController();
  final _recommendScrollCtrl = ScrollController();
  final _fullScrollCtrl      = ScrollController();
  int _heroPage = 0;

  @override
  void dispose() {
    _heroPageCtrl.dispose();
    _latestScrollCtrl.dispose();
    _recommendScrollCtrl.dispose();
    _fullScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latestAsync    = ref.watch(_latestProvider);
    final hayAsync       = ref.watch(_hayNovelsProvider);
    final nominatedAsync = ref.watch(_nominatedProvider);
    final randomAsync    = ref.watch(_randomNovelsProvider);
    final fullAsync      = ref.watch(_fullNovelsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [

          // ── Sticky Header + Categories ──────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _HomeHeaderDelegate(
              statusBarHeight: MediaQuery.of(context).padding.top,
              genreMapAsync: ref.watch(_genreMapProvider),
              onSearch: () => context.push('/search'),
              onBrowse: () => context.push('/browse', extra: {'openFilter': true}),
            ),
          ),

          // ── Category shortcuts (KHÔNG sticky, nằm ngoài header) ────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _CategoryBtn(
                    icon: Icons.auto_stories_outlined,
                    label: 'Truyện Full',
                    onTap: () => context.push('/browse',
                        extra: const {'status': 'completed', 'label': 'Truyện Full'}),
                  ),
                  _CategoryBtn(
                    icon: Icons.auto_fix_high,
                    label: 'Tiên Hiệp',
                    onTap: () {
                      final map = ref.read(_genreMapProvider).valueOrNull;
                      final id  = map?['tien-hiep'];
                      context.push('/browse', extra: id != null
                          ? {'genreId': id, 'label': 'Tiên Hiệp'}
                          : {'genreSlug': 'tien-hiep', 'label': 'Tiên Hiệp'});
                    },
                  ),
                  _CategoryBtn(
                    icon: Icons.favorite_outline,
                    label: 'Ngôn Tình',
                    onTap: () {
                      final map = ref.read(_genreMapProvider).valueOrNull;
                      final id  = map?['ngon-tinh'];
                      context.push('/browse', extra: id != null
                          ? {'genreId': id, 'label': 'Ngôn Tình'}
                          : {'genreSlug': 'ngon-tinh', 'label': 'Ngôn Tình'});
                    },
                  ),
                  _CategoryBtn(
                    icon: Icons.psychology_outlined,
                    label: 'Hệ Thống',
                    onTap: () {
                      final map = ref.read(_genreMapProvider).valueOrNull;
                      final id  = map?['he-thong'];
                      context.push('/browse', extra: id != null
                          ? {'genreId': id, 'label': 'Hệ Thống'}
                          : {'genreSlug': 'he-thong', 'label': 'Hệ Thống'});
                    },
                  ),
                  _CategoryBtn(
                    icon: Icons.grid_view_rounded,
                    label: 'Thể Loại',
                    onTap: () => context.push('/genres'),
                  ),
                ],
              ),
            ),
          ),

          // ── Hero Carousel (thể loại Hay, 6 truyện) ─────────────────────
          SliverToBoxAdapter(
            child: hayAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: _teal)),
              ),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: PageView.builder(
                            controller: _heroPageCtrl,
                            itemCount: novels.length,
                            onPageChanged: (i) => setState(() => _heroPage = i),
                            itemBuilder: (_, i) {
                              final n = novels[i];
                              return GestureDetector(
                                onTap: () => context.push('/novel/${n.id}'),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    n.coverUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: n.coverUrl!,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) =>
                                                Container(color: Colors.grey.shade300),
                                            errorWidget: (_, __, ___) =>
                                                Container(color: Colors.grey.shade300),
                                          )
                                        : Container(color: Colors.grey.shade300),
                                    // Gradient overlay
                                    Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black54,
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Title overlay
                                    Positioned(
                                      bottom: 12, left: 12, right: 12,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(n.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15)),
                                          if (n.latestChapterTitle != null)
                                            Text(n.latestChapterTitle!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Pagination dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(novels.length, (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: _heroPage == i ? 16 : 6,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _heroPage == i ? _teal : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        )),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Mới nhất (3 hàng cố định, scroll ngang ~4 cột/view) ────────
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Mới nhất',
              icon: Icons.autorenew_rounded,   // vòng tròn mũi tên = cập nhật mới
              onMore: () => context.push('/browse'),
            ),
          ),
          SliverToBoxAdapter(
            child: latestAsync.when(
              loading: () => const SizedBox(
                  height: 240,
                  child: Center(
                      child: CircularProgressIndicator(color: _teal, strokeWidth: 2))),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                // list-style item: [50×68 cover | title + time]
                // mỗi "cột" ngang chứa 3 item xếp dọc
                const double itemH  = 82;  // 68 cover + padding trên dưới
                const double rowGap = 10;
                const double colW   = 162; // 50 cover + 8 gap + ~104 text
                const double colGap = 12;
                const double gridH  = 3 * itemH + 2 * rowGap; // 266

                final numCols = (novels.length / 3).ceil();

                return SizedBox(
                  height: gridH,
                  // Listener: bắt mouse wheel trên web → convert sang horizontal scroll
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          _latestScrollCtrl.hasClients) {
                        final offset = (_latestScrollCtrl.offset +
                                event.scrollDelta.dy)
                            .clamp(0.0,
                                _latestScrollCtrl.position.maxScrollExtent);
                        _latestScrollCtrl.jumpTo(offset);
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _latestScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(numCols, (col) {
                          return Padding(
                            padding: EdgeInsets.only(
                                right: col < numCols - 1 ? colGap : 0),
                            child: SizedBox(
                              width: colW,
                              child: Column(
                                children: List.generate(3, (row) {
                                  final idx = col * 3 + row;
                                  if (idx >= novels.length) {
                                    return SizedBox(
                                        height: itemH + (row < 2 ? rowGap : 0));
                                  }
                                  return Padding(
                                    padding: EdgeInsets.only(
                                        bottom: row < 2 ? rowGap : 0),
                                    child: SizedBox(
                                      height: itemH,
                                      child: _LatestCard(novel: novels[idx]),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Đề cử (3-col grid) ─────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  _SectionHeader(
                    title: 'Đề cử',
                    icon: Icons.local_fire_department_rounded,
                    onMore: () => context.push('/browse', extra: {
                      'genreId': _kDeucuGenreId,
                      'label': 'Đề cử',
                    }),
                  ),
                  nominatedAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: CircularProgressIndicator(color: _teal, strokeWidth: 2)),
                    ),
                    error: (_, __) => const _SectionError(),
                    data: (novels) {
                      if (novels.isEmpty) return const SizedBox.shrink();
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.58,
                        ),
                        itemCount: novels.length.clamp(0, 6),
                        itemBuilder: (_, i) => _GridNovelCard(novel: novels[i]),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Truyện hay nên đọc (random, cùng layout Mới nhất) ──────────
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Truyện nên đọc',
              icon: Icons.menu_book_rounded,   // sách mở = đọc sách
              onMore: () => context.push('/browse'),
            ),
          ),
          SliverToBoxAdapter(
            child: randomAsync.when(
              loading: () => const SizedBox(
                  height: 266,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: _teal, strokeWidth: 2))),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                const double itemH = 82;
                const double rowGap = 10;
                const double colW = 162;
                const double colGap = 12;
                const double gridH = 3 * itemH + 2 * rowGap;
                final numCols = (novels.length / 3).ceil();

                return SizedBox(
                  height: gridH,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          _recommendScrollCtrl.hasClients) {
                        final offset = (_recommendScrollCtrl.offset +
                                event.scrollDelta.dy)
                            .clamp(0.0,
                                _recommendScrollCtrl.position.maxScrollExtent);
                        _recommendScrollCtrl.jumpTo(offset);
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _recommendScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(numCols, (col) {
                          return Padding(
                            padding: EdgeInsets.only(
                                right: col < numCols - 1 ? colGap : 0),
                            child: SizedBox(
                              width: colW,
                              child: Column(
                                children: List.generate(3, (row) {
                                  final idx = col * 3 + row;
                                  if (idx >= novels.length) {
                                    return SizedBox(
                                        height:
                                            itemH + (row < 2 ? rowGap : 0));
                                  }
                                  return Padding(
                                    padding: EdgeInsets.only(
                                        bottom: row < 2 ? rowGap : 0),
                                    child: SizedBox(
                                      height: itemH,
                                      child: _LatestCard(novel: novels[idx]),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Truyện Full (manga_status=completed, server-side filter) ──────
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Truyện Full',
              icon: Icons.check_circle_rounded,  // check = hoàn thành
              onMore: () => context.push('/browse',
                  extra: const {'status': 'completed', 'label': 'Truyện Full'}),
            ),
          ),
          SliverToBoxAdapter(
            child: fullAsync.when(
              loading: () => const SizedBox(
                  height: 210,
                  child: Center(
                      child: CircularProgressIndicator(
                          color: _teal, strokeWidth: 2))),
              error: (err, __) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Lỗi: $err',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
              data: (novels) {
                if (novels.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Không có truyện full',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return SizedBox(
                  height: 210,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          _fullScrollCtrl.hasClients) {
                        final offset = (_fullScrollCtrl.offset +
                                event.scrollDelta.dy)
                            .clamp(
                                0.0, _fullScrollCtrl.position.maxScrollExtent);
                        _fullScrollCtrl.jumpTo(offset);
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _fullScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: novels
                            .map((n) => _FullNovelCard(novel: n))
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

// ─── _LatestCard — list-style: [📖 50×68] | title + time ─────────────────────

class _LatestCard extends StatelessWidget {
  final Novel novel;
  const _LatestCard({required this.novel});

  static String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60)  return 'khoảng ${diff.inMinutes} phút trước';
    if (diff.inHours   < 24)  return 'khoảng ${diff.inHours} tiếng trước';
    if (diff.inDays    < 30)  return '${diff.inDays} ngày trước';
    if (diff.inDays    < 365) return '${(diff.inDays / 30).floor()} tháng trước';
    return '${(diff.inDays / 365).floor()} năm trước';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/novel/${novel.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Cover 50 × 68 ───────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: novel.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: novel.coverUrl!,
                    width: 50, height: 68,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _placeholder(),
                    errorWidget:  (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 8),
          // ── Title + time ─────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  novel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                      height: 1.35),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 11, color: _textSecondary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        _timeAgo(novel.updatedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10, color: _textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _placeholder() => Container(
    width: 50, height: 68,
    decoration: BoxDecoration(
      color: Color(0xFFD0C4F7),
      borderRadius: BorderRadius.circular(7),
    ),
    child: const Icon(Icons.menu_book, color: Colors.white, size: 24),
  );
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _CategoryBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CategoryBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(icon, color: _teal, size: 26),
          ),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: _textPrimary)),
        ],
      ),
    );
  }
}

// ─── Sticky Header Delegate ───────────────────────────────────────────────────

class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double statusBarHeight;
  final AsyncValue<Map<String, int>> genreMapAsync;
  final VoidCallback onSearch;
  final VoidCallback onBrowse;

  static const double _toolbarH = 56;

  _HomeHeaderDelegate({
    required this.statusBarHeight,
    required this.genreMapAsync,
    required this.onSearch,
    required this.onBrowse,
  });

  @override double get minExtent => statusBarHeight + _toolbarH;
  @override double get maxExtent => statusBarHeight + _toolbarH;

  /// Dùng genre map để navigate, fallback về browse nếu chưa load
  void _goGenre(BuildContext context, String slug) {
    final map = genreMapAsync.valueOrNull;
    final id  = map?[slug];
    if (id != null) {
      context.push('/browse', extra: {'genreId': id, 'genreSlug': slug});
    } else {
      context.push('/browse', extra: {'genreSlug': slug});
    }
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Chỉ còn gradient header row, categories đã tách ra ngoài
    return Container(
          height: statusBarHeight + _toolbarH,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF22D3EE), Color(0xFF2DD4BF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: EdgeInsets.only(top: statusBarHeight, left: 14, right: 4),
          child: Row(
            children: [
              // App logo icon
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 8),
              const Text('TruyenCV',
                  style: TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontFamily: 'Orbitron',
                      fontWeight: FontWeight.bold, letterSpacing: 0.3)),
              const SizedBox(width: 10),
              // Search bar
              Expanded(
                child: GestureDetector(
                  onTap: onSearch,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: const Row(
                      children: [
                        Icon(Icons.search, color: Colors.white, size: 17),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text('Tìm kiếm truyện...',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Filter icon
              IconButton(
                icon: const Icon(Icons.tune, color: Colors.white, size: 22),
                onPressed: onBrowse,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ],
          ),
        );
  }

  @override
  bool shouldRebuild(_HomeHeaderDelegate old) =>
      old.statusBarHeight != statusBarHeight ||
      old.genreMapAsync != genreMapAsync;
}

// ─── Shared section header ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onMore;
  final IconData? icon;

  const _SectionHeader({
    required this.title,
    required this.onMore,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            // Icon nền teal + icon trắng — đồng bộ màu app
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF22D3EE), Color(0xFF2DD4BF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: onMore,
            child: const Icon(Icons.chevron_right, size: 22, color: _teal),
          ),
        ],
      ),
    );
  }
}

// ─── _FullNovelCard — cover lớn dọc + title, single-row scroll ───────────────

class _FullNovelCard extends StatelessWidget {
  final Novel novel;
  const _FullNovelCard({required this.novel});

  @override
  Widget build(BuildContext context) {
    const double cardW  = 120;
    const double coverH = 162;

    return GestureDetector(
      onTap: () => context.push('/novel/${novel.id}'),
      child: Container(
        width: cardW,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover ─────────────────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: novel.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: novel.coverUrl!,
                          width: cardW,
                          height: coverH,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(cardW, coverH),
                          errorWidget: (_, __, ___) =>
                              _placeholder(cardW, coverH),
                        )
                      : _placeholder(cardW, coverH),
                ),
                // Badge "Full"
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Full',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ── Title ─────────────────────────────────────────────
            Text(
              novel.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                  height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _placeholder(double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.menu_book, color: Colors.grey, size: 32),
  );
}

// ─── Grid card (Đề cử) ───────────────────────────────────────────────────────

class _GridNovelCard extends StatelessWidget {
  final Novel novel;
  const _GridNovelCard({required this.novel});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/novel/${novel.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: novel.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: novel.coverUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.grey.shade200,
                              child: const Icon(Icons.menu_book, color: Colors.grey)),
                    )
                  : Container(color: Colors.grey.shade200),
            ),
          ),
          const SizedBox(height: 6),
          Text(novel.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: _textPrimary)),
        ],
      ),
    );
  }
}

// ─── Section error widget ─────────────────────────────────────────────────────

class _SectionError extends StatelessWidget {
  const _SectionError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFD1D5DB)),
          SizedBox(width: 6),
          Text('Không tải được dữ liệu',
              style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB))),
        ],
      ),
    );
  }
}
