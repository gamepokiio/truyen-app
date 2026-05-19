import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../shared/models/novel_model.dart' show Novel, NovelTerm;

// ─── Helpers ──────────────────────────────────────────────────────────────────

int _parseId(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// Parse Novel trực tiếp từ ranking endpoint response.
/// Ranking API đã trả đủ: id, title, slug, cover, author, views, genres, chapters.
/// Không cần 2-step → nhanh hơn, view count chính xác.
Novel _novelFromRankItem(Map<String, dynamic> e) {
  final rawGenres = e['genres'];
  final genreNames = rawGenres is List
      ? rawGenres.map((g) => g.toString()).toList()
      : <String>[];
  return Novel(
    id: _parseId(e['id']),
    title: e['title'] as String? ?? '',
    slug: e['slug'] as String? ?? '',
    coverUrl: e['cover'] as String?,
    authorName: e['author'] as String?,
    genres: genreNames
        .map((name) => NovelTerm(id: 0, name: name))
        .toList(),
    viewCount: _parseId(e['views']),
    chapterCount: _parseId(e['chapters']),
    status: 'ongoing',
  );
}

/// Single-step fetch: gọi ranking API → parse trực tiếp → không filter genre
/// (ranking do web curate, đã loại nội dung không phù hợp)
Future<List<Novel>> _fetchRanking(NovelApi api, {required String? range}) async {
  final rankItems = await api.getRanking(tab: 'views', range: range, limit: 50);
  if (rankItems.isEmpty) return [];
  return rankItems.map(_novelFromRankItem).toList();
}

// ─── Providers ────────────────────────────────────────────────────────────────

/// Top tuần
final _rankWeekProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  return _fetchRanking(api, range: 'week');
});

/// Top tháng
final _rankMonthProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  return _fetchRanking(api, range: 'month');
});

/// Top tất cả
final _rankAllProvider = FutureProvider<List<Novel>>((ref) async {
  final api = NovelApi(ref.read(cachedDioProvider));
  return _fetchRanking(api, range: null);
});

const _accent = Color(0xFF1E3A8A);

// ─── Screen ───────────────────────────────────────────────────────────────────

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.leaderboard_rounded, color: _accent, size: 22),
            SizedBox(width: 8),
            Text('Xếp Hạng',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A))),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _accent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _accent,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: 'Tuần này'),
            Tab(text: 'Tháng này'),
            Tab(text: 'Tất cả'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _RankList(provider: _rankWeekProvider),
          _RankList(provider: _rankMonthProvider),
          _RankList(provider: _rankAllProvider),
        ],
      ),
    );
  }
}

// ─── Rank list — lazy: chỉ load khi tab được hiển thị lần đầu ───────────────

class _RankList extends ConsumerStatefulWidget {
  final ProviderBase<AsyncValue<List<Novel>>> provider;
  const _RankList({required this.provider});

  @override
  ConsumerState<_RankList> createState() => _RankListState();
}

class _RankListState extends ConsumerState<_RankList>
    with AutomaticKeepAliveClientMixin {
  // Giữ state khi chuyển tab (không rebuild lại từ đầu)
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final async = ref.watch(widget.provider);
    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
      error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(widget.provider)),
      data: (novels) {
        if (novels.isEmpty) {
          return const _EmptyView();
        }
        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => ref.invalidate(widget.provider),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: novels.length,
            itemBuilder: (_, i) => _RankTile(novel: novels[i], rank: i + 1),
          ),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.leaderboard_outlined, size: 56, color: Color(0xFFD1D5DB)),
          SizedBox(height: 12),
          Text('Chưa có dữ liệu xếp hạng',
              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}

// ─── Error state ──────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          const Text('Không tải được dữ liệu',
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18, color: _accent),
            label: const Text('Thử lại', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }
}

// ─── Rank tile ────────────────────────────────────────────────────────────────

class _RankTile extends StatelessWidget {
  final Novel novel;
  final int rank;
  const _RankTile({required this.novel, required this.rank});

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final rankColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : const Color(0xFF9CA3AF);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/novel/${novel.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
          children: [
            // Rank number
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: isTop3 ? 20 : 15,
                    fontWeight: FontWeight.bold,
                    color: rankColor),
              ),
            ),
            const SizedBox(width: 10),
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: novel.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: novel.coverUrl!,
                      width: 48, height: 64,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(width: 48, height: 64, color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) =>
                          Container(width: 48, height: 64, color: Colors.grey.shade200,
                              child: const Icon(Icons.menu_book, color: Colors.grey)),
                    )
                  : Container(width: 48, height: 64, color: Colors.grey.shade200),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(novel.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A))),
                  if (novel.authorName != null) ...[
                    const SizedBox(height: 3),
                    Text(novel.authorName!,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF757575))),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.visibility_outlined,
                          size: 12, color: _accent),
                      const SizedBox(width: 3),
                      Text('${_fmt(novel.viewCount)} lượt',
                          style: const TextStyle(
                              fontSize: 11, color: _accent,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),          // Row
          ),          // Padding
        ),          // InkWell
      ),            // Material
    );              // Container
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}
