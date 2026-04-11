import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/api/novel_api.dart';
import '../../../shared/models/novel_model.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final _searchProvider =
    FutureProvider.family<List<Novel>, String>((ref, query) async {
  if (query.length < 2) return [];
  final api = NovelApi(ref.read(dioProvider));
  final data = await api.getNovels(search: query, perPage: 20);
  return filterNovels(data.map(Novel.fromJson).toList());
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  Timer?  _debounce;
  String  _query = '';

  static const _teal = Color(0xFF22D3EE);

  @override
  void initState() {
    super.initState();
    // Auto-focus sau frame đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = val.trim());
    });
    setState(() {}); // cập nhật X button ngay lập tức
  }

  void _clear() {
    _ctrl.clear();
    _debounce?.cancel();
    setState(() => _query = '');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(_searchProvider(_query));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A1A)),
          onPressed: () => context.pop(),
        ),
        title: TextField(
          controller: _ctrl,
          focusNode:  _focus,
          onChanged:  _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            setState(() => _query = v.trim());
          },
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            hintText: 'Tìm kiếm truyện...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 20, color: Color(0xFF9CA3AF)),
              onPressed: _clear,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: _buildBody(resultsAsync),
    );
  }

  Widget _buildBody(AsyncValue<List<Novel>> resultsAsync) {
    // Chưa gõ gì
    if (_query.isEmpty) {
      return _EmptyHint(
        icon: Icons.search_rounded,
        message: 'Nhập tên truyện để tìm kiếm',
        sub: 'Ví dụ: Thiên Hạ, Đế Bá, Linh Kiếm...',
      );
    }

    return resultsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
      ),
      error: (e, _) => _EmptyHint(
        icon: Icons.wifi_off_rounded,
        message: 'Lỗi tìm kiếm',
        sub: e.toString(),
      ),
      data: (novels) {
        if (novels.isEmpty) {
          return _EmptyHint(
            icon: Icons.search_off_rounded,
            message: 'Không tìm thấy kết quả',
            sub: 'Thử từ khóa khác hoặc kiểm tra chính tả',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Tìm thấy ${novels.length} truyện',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: novels.length,
                itemBuilder: (_, i) => _SearchTile(novel: novels[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Search tile ──────────────────────────────────────────────────────────────

class _SearchTile extends StatelessWidget {
  final Novel novel;
  const _SearchTile({required this.novel});

  static const _teal = Color(0xFF22D3EE);

  @override
  Widget build(BuildContext context) {
    final isFull = novel.status == 'completed';

    return GestureDetector(
      onTap: () => context.push('/novel/${novel.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: novel.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: novel.coverUrl!,
                      width: 50, height: 68,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
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
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                          height: 1.3)),
                  if (novel.authorName != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(novel.authorName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF9CA3AF))),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isFull
                          ? const Color(0xFF22D3EE).withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isFull ? 'Full' : 'Đang Ra',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isFull ? _teal : Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 50, height: 68,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.menu_book, color: Colors.grey, size: 22),
      );
}

// ─── Empty hint ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  const _EmptyHint(
      {required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280))),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}
