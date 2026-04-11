import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../shared/models/novel_model.dart';
import '../widgets/filter_bottom_sheet.dart';

class BrowseFilter {
  final int? genreId;              // single genre từ category shortcuts
  final List<int>? genreIds;       // multi-genre từ filter sheet
  final List<int>? teamIds;        // nhóm dịch từ filter sheet
  final String? genreName;
  final int? teamId;
  final String? status;
  final String? label;
  final String? search;
  final String orderby;
  final String? explicitOrderby;   // null = user chưa chọn sort
  final String order;

  const BrowseFilter({
    this.genreId,
    this.genreIds,
    this.teamIds,
    this.genreName,
    this.teamId,
    this.status,
    this.label,
    this.search,
    this.orderby = 'modified',
    this.explicitOrderby,
    this.order = 'desc',
  });

  String? get chipLabel => label ?? genreName;

  bool get hasActiveFilter =>
      genreId != null ||
      (genreIds?.isNotEmpty ?? false) ||
      (teamIds?.isNotEmpty ?? false) ||
      status != null ||
      explicitOrderby != null;

  BrowseFilter copyWith({
    int? genreId,
    List<int>? genreIds,
    List<int>? teamIds,
    String? genreName,
    int? teamId,
    String? status,
    String? label,
    String? search,
    String? orderby,
    String? explicitOrderby,
    String? order,
    bool clearGenre = false,
    bool clearStatus = false,
    bool clearSearch = false,
  }) {
    return BrowseFilter(
      genreId:        clearGenre ? null : (genreId  ?? this.genreId),
      genreIds:       clearGenre ? null : (genreIds ?? this.genreIds),
      teamIds:        teamIds ?? this.teamIds,
      genreName:      clearGenre ? null : (genreName ?? this.genreName),
      teamId:         teamId   ?? this.teamId,
      status:         clearStatus ? null : (status  ?? this.status),
      label:          clearStatus || clearGenre ? null : (label ?? this.label),
      search:         clearSearch ? null : (search  ?? this.search),
      orderby:        orderby ?? this.orderby,
      explicitOrderby: explicitOrderby ?? this.explicitOrderby,
      order:          order   ?? this.order,
    );
  }
}

class BrowseScreen extends ConsumerStatefulWidget {
  final BrowseFilter? initialFilter;
  final bool openFilter; // true → tự mở filter sheet ngay khi màn hình load
  const BrowseScreen({super.key, this.initialFilter, this.openFilter = false});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  BrowseFilter _filter = const BrowseFilter();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<Novel> _novels = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      _filter = widget.initialFilter!;
    }
    _fetchMore();
    // Tự mở filter sheet sau frame đầu tiên (khi gọi từ home tune icon)
    if (widget.openFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showFilterSheet());
    }
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
        _fetchMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final api = NovelApi(ref.read(dioProvider));
      final data = await api.getNovels(
        page: _page,
        perPage: 20,
        orderby: _filter.orderby,
        order: _filter.order,
        genreId: _filter.genreId,
        genreIds: _filter.genreIds,
        teamIds: _filter.teamIds,
        search: _filter.search,
        teamId: _filter.teamId,
        status: _filter.status,
      );
      final novels = filterNovels(data.map(Novel.fromJson).toList());
      setState(() {
        _novels.addAll(novels);
        _page++;
        _hasMore = data.length == 20;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _resetAndFetch() {
    setState(() {
      _novels.clear();
      _page = 1;
      _hasMore = true;
    });
    _fetchMore();
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,   // phủ toàn màn hình, ẩn bottom nav
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, __) => ProviderScope(
          parent: ProviderScope.containerOf(context),
          child: FilterBottomSheet(
            currentFilter: _filter,
            onApply: (newFilter) {
              _filter = newFilter;
              _resetAndFetch();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_filter.chipLabel != null ? _filter.chipLabel! : 'Danh Sách Truyện'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.tune_rounded,
                    color: Color(0xFF374151)),
                onPressed: _showFilterSheet,
              ),
              if (_filter.hasActiveFilter)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22D3EE),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm truyện...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filter = _filter.copyWith(clearSearch: true);
                          _resetAndFetch();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (val) {
                _filter = _filter.copyWith(search: val.trim());
                _resetAndFetch();
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _novels.isEmpty && _loading
                ? const Center(child: CircularProgressIndicator())
                : _novels.isEmpty
                    ? const Center(child: Text('Không tìm thấy truyện'))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        itemCount: _novels.length + (_hasMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _novels.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _BrowseTile(novel: _novels[i]);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _BrowseTile extends StatelessWidget {
  final Novel novel;
  const _BrowseTile({required this.novel});

  static const _orange = Color(0xFFEC5B13);

  String _formatViews(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M views';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k views';
    return '$v views';
  }

  @override
  Widget build(BuildContext context) {
    final visibleGenres = novel.genres
        .where((g) => !kExcludedGenreIds.contains(g.id))
        .take(2)
        .toList();

    return InkWell(
      onTap: () => context.push('/novel/${novel.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover — 72×96 (3:4 ratio)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: novel.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: novel.coverUrl!,
                      width: 72,
                      height: 96,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          width: 72, height: 96,
                          color: const Color(0xFFF1F5F9)),
                      errorWidget: (_, __, ___) => Container(
                          width: 72, height: 96,
                          color: const Color(0xFFE2E8F0),
                          child: const Icon(Icons.book_outlined,
                              color: Color(0xFF94A3B8))),
                    )
                  : Container(
                      width: 72, height: 96,
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(Icons.book_outlined,
                          color: Color(0xFF94A3B8))),
            ),
            const SizedBox(width: 12),
            // Text content — fixed height to match cover
            Expanded(
              child: SizedBox(
                height: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Genre hashtags
                    if (visibleGenres.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: visibleGenres.asMap().entries.map((e) => Text(
                          '#${e.value.name.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: e.key == 0
                                ? _orange
                                : const Color(0xFF94A3B8),
                          ),
                        )).toList(),
                      ),
                    const SizedBox(height: 3),
                    // Title
                    Text(
                      novel.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Author
                    if (novel.authorName != null)
                      Text(
                        novel.authorName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    const Spacer(),
                    // Bottom: star rating + views
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          novel.rating > 0
                              ? novel.rating.toStringAsFixed(1)
                              : '—',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569)),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.visibility_outlined,
                            size: 13, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 3),
                        Text(
                          _formatViews(novel.viewCount),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
