import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/library_service.dart';
import '../../../core/theme/app_theme.dart';

const _teal = Color(0xFF22D3EE);

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgContent,
      appBar: AppBar(
        title: const Text(
          'Tủ truyện',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _teal,
          indicatorWeight: 2.5,
          labelColor: _teal,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: 'Lịch sử'),
            Tab(text: 'Theo dõi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _HistoryTab(),
          _FollowingTab(),
        ],
      ),
    );
  }
}

// ─── Tab Lịch sử ──────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)   return 'Vừa xong';
    if (diff.inMinutes < 60)  return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24)    return '${diff.inHours} giờ trước';
    if (diff.inDays < 30)     return '${diff.inDays} ngày trước';
    if (diff.inDays < 365)    return '${(diff.inDays / 30).floor()} tháng trước';
    return '${(diff.inDays / 365).floor()} năm trước';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    if (history.isEmpty) {
      return _EmptyState(
        icon: Icons.history_rounded,
        message: 'Chưa có lịch sử đọc',
        sub: 'Mở một truyện và bắt đầu đọc để lưu lịch sử',
        actionLabel: 'Khám phá truyện',
        onAction: () => context.push('/browse'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: history.length,
      itemBuilder: (context, i) {
        final entry = history[i];
        return _HistoryTile(
          entry: entry,
          timeAgo: _timeAgo(entry.readAt),
          onTap: () => context.push(
            '/reader/${entry.novelId}/${entry.chapterId}',
            extra: {
              'chapterTitle': entry.chapterTitle,
              'chapterNumber': entry.chapterNumber,
            },
          ),
          onNovelTap: () => context.push('/novel/${entry.novelId}'),
          onRemove: () => ref.read(historyProvider.notifier).removeHistory(entry.novelId),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final String timeAgo;
  final VoidCallback onTap;
  final VoidCallback onNovelTap;
  final VoidCallback onRemove;

  const _HistoryTile({
    required this.entry,
    required this.timeAgo,
    required this.onTap,
    required this.onNovelTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(entry.novelId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
      ),
      onDismissed: (_) => onRemove(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: Row(
            children: [
              // Cover
              GestureDetector(
                onTap: onNovelTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: entry.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: entry.coverUrl!,
                          width: 56, height: 76,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _coverPlaceholder(),
                          errorWidget: (_, __, ___) => _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Chapter đang đọc
                    Row(
                      children: [
                        const Icon(Icons.bookmark_rounded, size: 13, color: _teal),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.chapterTitle.isNotEmpty
                                ? entry.chapterTitle
                                : 'Chương ${entry.chapterId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: _teal,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Thời gian
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text(
                          timeAgo,
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Trailing: play + 3-dot menu
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ⋮ Menu
                  SizedBox(
                    width: 28, height: 28,
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert_rounded,
                          size: 18, color: AppColors.textSecondary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      onSelected: (val) {
                        if (val == 'remove') onRemove();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'remove',
                          child: Row(children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Xóa khỏi lịch sử',
                                style: TextStyle(fontSize: 13)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  // ▶ Đọc tiếp
                  const Icon(Icons.play_circle_outline_rounded,
                      color: _teal, size: 26),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _coverPlaceholder() => Container(
    width: 56, height: 76,
    decoration: BoxDecoration(
      color: const Color(0xFFD0C4F7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.menu_book, color: Colors.white, size: 22),
  );
}

// ─── Tab Theo dõi ─────────────────────────────────────────────────────────────

class _FollowingTab extends ConsumerWidget {
  const _FollowingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followingProvider);

    if (following.isEmpty) {
      return _EmptyState(
        icon: Icons.bookmarks_outlined,
        message: 'Chưa theo dõi truyện nào',
        sub: 'Nhấn nút bookmark trên trang truyện để theo dõi',
        actionLabel: 'Khám phá truyện',
        onAction: () => context.push('/browse'),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.58,
      ),
      itemCount: following.length,
      itemBuilder: (ctx, i) {
        final entry = following[i];
        return GestureDetector(
          onTap: () => context.push('/novel/${entry.novelId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: entry.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: entry.coverUrl!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: Colors.grey[200]),
                              errorWidget: (_, __, ___) =>
                                  Container(color: Colors.grey[300],
                                      child: const Icon(Icons.book)),
                            )
                          : Container(color: Colors.grey[300],
                              child: const Icon(Icons.book)),
                    ),
                    // 3-dot menu góc trên phải
                    Positioned(
                      top: 2, right: 2,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.50),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.more_vert_rounded,
                              color: Colors.white, size: 14),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        onSelected: (val) {
                          if (val == 'remove') {
                            ref.read(followingProvider.notifier).toggle(entry);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(children: [
                              Icon(Icons.bookmark_remove_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Bỏ theo dõi',
                                  style: TextStyle(fontSize: 13)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary),
              ),
              if (entry.authorName != null)
                Text(
                  entry.authorName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.grey[350]),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
              child: Text(actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
