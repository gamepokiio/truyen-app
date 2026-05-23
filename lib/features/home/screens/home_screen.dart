import 'dart:async';
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

/// Ngôn Tình — genre ID 19
final _nuCuongProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getNovels(
    page: 1, perPage: 19, genreId: 19,
    orderby: 'modified', order: 'desc',
  );
  return filterNovels(data.map(Novel.fromJson).toList());
});

/// Đề Cử Convert — tag_ID 972
final _convertProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  final data = await api.getNovels(
    page: 1, perPage: 19, genreId: 972,
    orderby: 'modified', order: 'desc',
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

const _accent        = Color(0xFF1E3A8A); // navy chủ đạo
const _textPrimary   = Color(0xFF0F172A); // đen xanh đậm
const _textSecondary = Color(0xFF6B7280); // xám trung tính

// ─── Screen ───────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _heroPageCtrl        = PageController(viewportFraction: 0.93);
  final _nuCuongScrollCtrl   = ScrollController();
  final _convertScrollCtrl   = ScrollController();
  final _recommendScrollCtrl = ScrollController();
  final _fullScrollCtrl      = ScrollController();
  int _heroPage = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  /// Lên lịch slide tiếp theo sau 4 giây (single Timer, tự tái lịch).
  void _scheduleNext() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer(const Duration(seconds: 4), _autoAdvance);
  }

  void _autoAdvance() {
    if (!mounted || !_heroPageCtrl.hasClients) return;
    final novels = ref.read(_hayNovelsProvider).valueOrNull;
    if (novels == null || novels.isEmpty) { _scheduleNext(); return; }
    final next = (_heroPage + 1) % novels.length;
    _heroPageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _scheduleNext(); // lên lịch slide tiếp ngay sau khi trigger animation
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _heroPageCtrl.dispose();
    _nuCuongScrollCtrl.dispose();
    _convertScrollCtrl.dispose();
    _recommendScrollCtrl.dispose();
    _fullScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latestAsync    = ref.watch(_latestProvider);
    final hayAsync       = ref.watch(_hayNovelsProvider);
    final nuCuongAsync   = ref.watch(_nuCuongProvider);
    final convertAsync   = ref.watch(_convertProvider);
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

          // ── Hero Carousel (thể loại Hay, 6 truyện) ─────────────────────
          SliverToBoxAdapter(
            child: hayAsync.when(
              loading: () => const SizedBox(
                height: 246, // 220 card + 6 gap + 4×5 dots area
                child: Center(child: CircularProgressIndicator(color: _accent)),
              ),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: PageView.builder(
                        controller: _heroPageCtrl,
                        itemCount: novels.length,
                        onPageChanged: (i) {
                          setState(() => _heroPage = i);
                          _scheduleNext(); // reset đếm ngược sau mỗi lần đổi slide
                        },
                        itemBuilder: (_, i) {
                          final n = novels[i];
                          return AnimatedBuilder(
                            animation: _heroPageCtrl,
                            builder: (context, child) {
                              double scale = 0.96;
                              if (_heroPageCtrl.position.haveDimensions) {
                                final diff = (_heroPageCtrl.page! - i).abs();
                                scale = (1.0 - diff * 0.04).clamp(0.96, 1.0);
                              } else if (i == 0) {
                                scale = 1.0;
                              }
                              return Transform.scale(scale: scale, child: child);
                            },
                            child: GestureDetector(
                              onTap: () => context.push('/novel/${n.id}'),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
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
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Pagination dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(novels.length, (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: _heroPage == i ? 16 : 6,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _heroPage == i ? _accent : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Mới nhất (thumbnail strip + featured card) ─────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Mới nhất',
              icon: Icons.autorenew_rounded,
              onMore: () => context.push('/browse'),
            ),
          ),
          SliverToBoxAdapter(
            child: latestAsync.when(
              loading: () => const SizedBox(
                  height: 290,
                  child: Center(
                      child: CircularProgressIndicator(color: _accent, strokeWidth: 2))),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                return _NewestSection(novels: novels);
              },
            ),
          ),

          // ── Ngôn Tình ─────────────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Ngôn Tình',
              icon: Icons.female_rounded,
              onMore: () => context.push('/browse',
                  extra: const {'genreId': 19, 'label': 'Ngôn Tình'}),
            ),
          ),
          SliverToBoxAdapter(
            child: nuCuongAsync.when(
              loading: () => const SizedBox(
                  height: 195,
                  child: Center(
                      child: CircularProgressIndicator(color: _accent, strokeWidth: 2))),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 195,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent && _nuCuongScrollCtrl.hasClients) {
                        final offset = (_nuCuongScrollCtrl.offset + event.scrollDelta.dy)
                            .clamp(0.0, _nuCuongScrollCtrl.position.maxScrollExtent);
                        _nuCuongScrollCtrl.jumpTo(offset);
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _nuCuongScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Row(
                        children: novels.asMap().entries
                            .map((e) => _RankedNovelCard(novel: e.value, rank: e.key + 1))
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Đề Cử Convert ─────────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Đề Cử Convert',
              icon: Icons.translate_rounded,
              onMore: () => context.push('/browse',
                  extra: const {'genreId': 972, 'label': 'Đề Cử Convert'}),
            ),
          ),
          SliverToBoxAdapter(
            child: convertAsync.when(
              loading: () => const SizedBox(
                  height: 195,
                  child: Center(
                      child: CircularProgressIndicator(color: _accent, strokeWidth: 2))),
              error: (_, __) => const _SectionError(),
              data: (novels) {
                if (novels.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 195,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent && _convertScrollCtrl.hasClients) {
                        final offset = (_convertScrollCtrl.offset + event.scrollDelta.dy)
                            .clamp(0.0, _convertScrollCtrl.position.maxScrollExtent);
                        _convertScrollCtrl.jumpTo(offset);
                      }
                    },
                    child: SingleChildScrollView(
                      controller: _convertScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Row(
                        children: novels.asMap().entries
                            .map((e) => _RankedNovelCard(novel: e.value, rank: e.key + 1))
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Category shortcuts ─────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
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

          // ── Đề cử (3-col grid) ─────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
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
                          child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
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
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
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
                          color: _accent, strokeWidth: 2))),
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
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
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
                          color: _accent, strokeWidth: 2))),
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

// ─── _NewestSection — thumbnail strip + featured card ────────────────────────

class _NewestSection extends StatefulWidget {
  final List<Novel> novels;
  const _NewestSection({required this.novels});

  @override
  State<_NewestSection> createState() => _NewestSectionState();
}

class _NewestSectionState extends State<_NewestSection> {
  int _selectedIdx = 0;
  final _stripCtrl = ScrollController();

  @override
  void dispose() {
    _stripCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final novels  = widget.novels;
    final selected = novels[_selectedIdx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Thumbnail strip ──────────────────────────────────────────
        SizedBox(
          height: 84,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && _stripCtrl.hasClients) {
                final offset = (_stripCtrl.offset + event.scrollDelta.dy)
                    .clamp(0.0, _stripCtrl.position.maxScrollExtent);
                _stripCtrl.jumpTo(offset);
              }
            },
            child: ListView.builder(
              controller: _stripCtrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              itemCount: novels.length,
              itemBuilder: (_, i) => _ThumbItem(
                novel: novels[i],
                selected: i == _selectedIdx,
                onTap: () => setState(() => _selectedIdx = i),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // ── Featured detail card ─────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _FeaturedCard(
            key: ValueKey(selected.id),
            novel: selected,
            onRead: () => context.push('/novel/${selected.id}'),
            onAdd:  () => context.push('/novel/${selected.id}'),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── Thumbnail item ─────────────────────────────────────────────────────────────

class _ThumbItem extends StatelessWidget {
  final Novel novel;
  final bool selected;
  final VoidCallback onTap;
  const _ThumbItem({required this.novel, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 7, top: 3, bottom: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _accent : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _accent.withValues(alpha: 0.22), blurRadius: 5, offset: const Offset(0, 2))]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: novel.coverUrl != null
              ? CachedNetworkImage(
                  imageUrl: novel.coverUrl!,
                  width: 50, height: 70,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(width: 50, height: 70, color: Colors.grey.shade200),
                  errorWidget: (_, __, ___) =>
                      Container(width: 50, height: 70, color: Colors.grey.shade200,
                          child: const Icon(Icons.menu_book, color: Colors.grey, size: 18)),
                )
              : Container(width: 50, height: 70, color: Colors.grey.shade200),
        ),
      ),
    );
  }
}

// ── Featured card ──────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final Novel novel;
  final VoidCallback onRead;
  final VoidCallback onAdd;
  const _FeaturedCard({super.key, required this.novel, required this.onRead, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final genre = novel.genres.isNotEmpty ? novel.genres.first.name : null;
    // Ưu tiên excerpt → description → null
    final desc = (novel.excerpt?.isNotEmpty == true)
        ? novel.excerpt!
        : (novel.description?.isNotEmpty == true)
            ? novel.description!
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: info ───────────────────────────────────────────
          Expanded(
            child: SizedBox(
              height: 175,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                // Genre chip
                if (genre != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(genre,
                        style: const TextStyle(
                            fontSize: 10,
                            color: _accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                  ),
                const SizedBox(height: 7),
                // Title
                Text(novel.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                        height: 1.3)),
                const SizedBox(height: 6),
                // Mô tả (excerpt hoặc description)
                if (desc != null)
                  Text(desc,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                          height: 1.45)),
                const Spacer(),
                // Buttons
                Row(
                  children: [
                    GestureDetector(
                      onTap: onRead,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                        decoration: BoxDecoration(
                          color: _textPrimary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Đọc',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onAdd,
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade300, width: 1.5),
                        ),
                        child: const Icon(Icons.add_rounded, size: 18, color: _textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ), // SizedBox
          ), // Expanded
          const SizedBox(width: 12),
          // ── Right: cover ─────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: novel.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: novel.coverUrl!,
                    width: 112, height: 175,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(width: 112, height: 175, color: Colors.grey.shade200),
                    errorWidget: (_, __, ___) =>
                        Container(width: 112, height: 175, color: Colors.grey.shade200,
                            child: const Icon(Icons.menu_book, color: Colors.grey)),
                  )
                : Container(width: 112, height: 175, color: Colors.grey.shade200),
          ),
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
            child: Icon(icon, color: const Color(0xFF1E3A8A), size: 26),
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
    return Container(
      height: statusBarHeight + _toolbarH,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      padding: EdgeInsets.only(top: statusBarHeight, left: 14, right: 4),
      child: Row(
        children: [
          // App logo icon — navy
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A8A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          const Text('TruyenCV',
              style: TextStyle(
                  color: Color(0xFF0F172A), fontSize: 18,
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
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: Color(0xFF6B7280), size: 17),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text('Tìm kiếm truyện...',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Filter icon
          IconButton(
            icon: const Icon(Icons.tune, color: Color(0xFF0F172A), size: 22),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: onMore,
            child: const Icon(Icons.chevron_right, size: 22, color: _accent),
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

// ─── _RankedNovelCard — cover dọc + rank badge + title overlay ───────────────

class _RankedNovelCard extends StatelessWidget {
  final Novel novel;
  final int rank;
  const _RankedNovelCard({required this.novel, required this.rank});

  static Color _badgeColor(int rank) {
    if (rank == 1) return const Color(0xFFFFB800); // vàng
    if (rank == 2) return const Color(0xFF9E9E9E); // bạc
    if (rank == 3) return const Color(0xFFFF7043); // đồng
    return const Color(0xFF424242);                 // tối
  }

  @override
  Widget build(BuildContext context) {
    const double cardW = 128;
    const double cardH = 185;

    return GestureDetector(
      onTap: () => context.push('/novel/${novel.id}'),
      child: Container(
        width: cardW,
        margin: const EdgeInsets.only(right: 10),
        child: Stack(
          children: [
            // ── Cover ─────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: novel.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: novel.coverUrl!,
                      width: cardW, height: cardH,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(cardW, cardH),
                      errorWidget: (_, __, ___) => _placeholder(cardW, cardH),
                    )
                  : _placeholder(cardW, cardH),
            ),
            // ── Gradient overlay phía dưới ─────────────────────────────
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                      stops: [0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // ── Title ─────────────────────────────────────────────────
            Positioned(
              bottom: 8, left: 7, right: 7,
              child: Text(
                novel.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
            ),
            // ── Rank badge ────────────────────────────────────────────
            Positioned(
              top: 6, left: 6,
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: _badgeColor(rank),
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4, offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _placeholder(double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: Color(0xFFD0C4F7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.menu_book, color: Colors.white, size: 28),
  );
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
