import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/dio_client.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _accent       = Color(0xFF1E3A8A);
const _textPrimary  = Color(0xFF1A1A1A);
const _textSub      = Color(0xFF6B7280);
const _textMuted    = Color(0xFF9CA3AF);
const _borderColor  = Color(0xFFE5E7EB);
const _supportEmail = 'support@truyencv.io';

/// ⚠️ BƯỚC DUY NHẤT CẦN LÀM SAU KHI TẠO CATEGORY TRÊN WP ADMIN:
/// Vào: https://truyencv.io/wp-json/wp/v2/categories?slug=app-notification
/// → Lấy "id" → điền vào đây
const _kNotifCategoryId = 976;

// ─── Model ────────────────────────────────────────────────────────────────────

class AppNotification {
  final int id;
  final String title;
  final String excerpt;   // tóm tắt ngắn (1–2 dòng)
  final String content;   // nội dung đầy đủ (HTML stripped)
  final DateTime date;
  final String? imageUrl;

  const AppNotification({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.date,
    this.imageUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    String _strip(String html) => html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAllMapped(RegExp(r'&#(\d+);'),
            (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .trim();

    final imageUrl =
        json['_embedded']?['wp:featuredmedia']?[0]?['source_url'] as String?;

    return AppNotification(
      id:       json['id'] as int,
      title:    _strip((json['title']?['rendered'] as String?) ?? ''),
      excerpt:  _strip((json['excerpt']?['rendered'] as String?) ?? ''),
      content:  _strip((json['content']?['rendered'] as String?) ?? ''),
      date:     DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      imageUrl: imageUrl,
    );
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final _notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  // Chưa config category ID → trả về rỗng (hiện empty state)
  if (_kNotifCategoryId == 0) return [];

  final dio = ref.read(cachedDioProvider);
  final res = await dio.get('/wp/v2/posts', queryParameters: {
    'categories': _kNotifCategoryId,
    'status':     'publish',
    'per_page':   20,
    'orderby':    'date',
    'order':      'desc',
    '_embed':     'wp:featuredmedia',
  });

  final list = res.data as List;
  return list
      .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen>
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
        title: const Text(
          'Thông Báo',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: _textPrimary),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _accent,
          unselectedLabelColor: _textMuted,
          indicatorColor: _accent,
          indicatorWeight: 2.5,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(text: 'Thông Báo'),
            Tab(text: 'Đăng Truyện'),
            Tab(text: 'Yêu Cầu'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          const _NotificationsTab(),
          _PostGuideTab(onGoToSupport: () => _tabCtrl.animateTo(2)),
          const _SupportTab(),
        ],
      ),
    );
  }
}

// ─── Tab 1: Thông Báo (live từ WP) ───────────────────────────────────────────

class _NotificationsTab extends ConsumerWidget {
  const _NotificationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_notificationsProvider);

    return async.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),

      error: (_, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('Không tải được thông báo',
                style: TextStyle(fontSize: 14, color: _textSub)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => ref.invalidate(_notificationsProvider),
              icon: const Icon(Icons.refresh_rounded, size: 18, color: _accent),
              label: const Text('Thử lại',
                  style: TextStyle(color: _accent)),
            ),
          ],
        ),
      ),

      data: (notifs) {
        if (notifs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_off_outlined,
                    size: 72, color: Color(0xFFD1D5DB)),
                SizedBox(height: 16),
                Text('Chưa có thông báo nào',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _textSub)),
                SizedBox(height: 6),
                Text('Thông báo từ hệ thống sẽ xuất hiện ở đây',
                    style: TextStyle(fontSize: 13, color: _textMuted)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => ref.invalidate(_notificationsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: notifs.length,
            itemBuilder: (_, i) => _NotifCard(notif: notifs[i]),
          ),
        );
      },
    );
  }
}

// ─── Notification Card ────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final AppNotification notif;
  const _NotifCard({required this.notif});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: icon + ngày
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.campaign_rounded,
                          color: _accent, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text('Thông báo hệ thống',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _accent)),
                    const Spacer(),
                    Text(_formatDate(notif.date),
                        style: const TextStyle(
                            fontSize: 11, color: _textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                // Title
                Text(
                  notif.title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      height: 1.4),
                ),
                if (notif.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    notif.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: _textSub, height: 1.5),
                  ),
                ],
                const SizedBox(height: 10),
                // Read more
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Xem chi tiết',
                        style: TextStyle(
                            fontSize: 12,
                            color: _accent.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: _accent.withValues(alpha: 0.8)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom sheet nội dung đầy đủ ─────────────────────────────────────────

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign_rounded,
                        color: _accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Thông báo hệ thống',
                            style: TextStyle(
                                fontSize: 11,
                                color: _accent,
                                fontWeight: FontWeight.w500)),
                        Text(_formatDate(notif.date),
                            style: const TextStyle(
                                fontSize: 11, color: _textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notif.title,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                            height: 1.4)),
                    const SizedBox(height: 14),
                    Text(notif.content,
                        style: const TextStyle(
                            fontSize: 14,
                            color: _textSub,
                            height: 1.7)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date helper ───────────────────────────────────────────────────────────

  static String _formatDate(DateTime date) {
    final now  = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60)  return '${diff.inMinutes} phút trước';
    if (diff.inHours   < 24)  return '${diff.inHours} giờ trước';
    if (diff.inDays    == 1)  return 'Hôm qua';
    if (diff.inDays    < 7)   return '${diff.inDays} ngày trước';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ─── Tab 2: Đăng Truyện (hướng dẫn) ─────────────────────────────────────────

class _PostGuideTab extends StatelessWidget {
  final VoidCallback onGoToSupport;
  const _PostGuideTab({required this.onGoToSupport});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.menu_book_rounded, color: _accent, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hướng dẫn đăng truyện lên TruyenCV',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const _GuideStep(
            step: 1,
            title: 'Chuẩn bị nội dung truyện',
            content:
                '• TUYỆT ĐỐI không đăng truyện có bản quyền.\n'
                '• Tôn trọng bản quyền của các tác phẩm.\n'
                '• Truyện tự sáng tác được ưu tiên cao.\n'
                '• Truyện cần tối thiểu 20 chương mới có thể đăng lên TruyenCV.\n'
                '• Ảnh bìa kích thước tối thiểu 300×400px.',
          ),
          const _GuideStep(
            step: 2,
            title: 'Gửi yêu cầu đăng truyện',
            content:
                '• Vào tab "Yêu Cầu" → chọn loại "Đăng truyện".\n'
                '• Điền tên truyện, tác giả, thể loại và link nguồn.\n'
                '• Đính kèm ảnh bìa nếu có.',
          ),
          const _GuideStep(
            step: 3,
            title: 'Chờ Admin duyệt',
            content:
                '• Admin sẽ xem xét trong vòng 1–3 ngày làm việc.\n'
                '• Truyện được duyệt sẽ được đăng lên hệ thống.\n'
                '• Bạn sẽ nhận thông báo qua email khi có kết quả.',
          ),
          const _GuideStep(
            step: 4,
            title: 'Quy tắc nội dung',
            content:
                '• Không đăng nội dung vi phạm bản quyền.\n'
                '• Không có nội dung 18+ hoặc bạo lực cực đoan.\n'
                '• TruyenCV có quyền từ chối mà không cần giải thích.',
          ),

          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 12),

          Center(
            child: OutlinedButton.icon(
              onPressed: onGoToSupport,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.send_outlined, size: 16),
              label: const Text('Gửi yêu cầu đăng truyện',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final int step;
  final String title;
  final String content;
  const _GuideStep(
      {required this.step, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$step',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary)),
                const SizedBox(height: 6),
                Text(content,
                    style: const TextStyle(
                        fontSize: 13, color: _textSub, height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab 3: Yêu Cầu / Hỗ Trợ ────────────────────────────────────────────────

const _kRequestTypes = <_RequestType>[
  _RequestType('Báo lỗi truyện',       Icons.bug_report_outlined,     'Báo lỗi'),
  _RequestType('Yêu cầu thêm truyện',  Icons.add_circle_outline,      'Yêu cầu thêm truyện'),
  _RequestType('Hỗ trợ tài khoản',     Icons.manage_accounts_outlined, 'Hỗ trợ tài khoản'),
  _RequestType('Đăng truyện',          Icons.upload_file_outlined,     'Đăng truyện'),
  _RequestType('Vấn đề khác',          Icons.help_outline_rounded,     'Vấn đề khác'),
];

class _RequestType {
  final String label;
  final IconData icon;
  final String emailSubject;
  const _RequestType(this.label, this.icon, this.emailSubject);
}

class _SupportTab extends StatefulWidget {
  const _SupportTab();

  @override
  State<_SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<_SupportTab> {
  int _selectedType  = 4;
  final _titleCtrl   = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _sending      = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title   = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vui lòng nhập đầy đủ tiêu đề và nội dung'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _sending = true);

    final type    = _kRequestTypes[_selectedType];
    final subject = '[TruyenCV App] ${type.emailSubject}: $title';
    final body    = 'Loại yêu cầu: ${type.label}\nTiêu đề: $title\n\nNội dung:\n$content';
    final uri = Uri.parse(
      'mailto:$_supportEmail'
      '?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Không thể mở email. Liên hệ: support@truyencv.io'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4)));
    }
    if (mounted) setState(() => _sending = false);
  }

  void _showTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Chọn loại yêu cầu',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary)),
              ),
            ),
            const SizedBox(height: 8),
            ..._kRequestTypes.asMap().entries.map((entry) {
              final i   = entry.key;
              final t   = entry.value;
              final sel = _selectedType == i;
              return ListTile(
                leading: Icon(t.icon,
                    color: sel ? _accent : _textSub, size: 22),
                title: Text(t.label,
                    style: TextStyle(
                        color: sel ? _accent : _textPrimary,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                trailing: sel
                    ? const Icon(Icons.check_circle_rounded,
                        color: _accent, size: 20)
                    : null,
                onTap: () {
                  setState(() => _selectedType = i);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = _kRequestTypes[_selectedType];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Loại yêu cầu'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showTypePicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: Icon(type.icon, color: _accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(type.label,
                          style: const TextStyle(
                              fontSize: 14, color: _textPrimary))),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _textMuted, size: 22),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _label('Tiêu đề'),
          const SizedBox(height: 8),
          _inputField(controller: _titleCtrl, hint: 'Mô tả ngắn vấn đề...', maxLines: 1),
          const SizedBox(height: 20),
          _label('Nội dung chi tiết'),
          const SizedBox(height: 8),
          _inputField(
              controller: _contentCtrl,
              hint: 'Mô tả chi tiết vấn đề bạn gặp phải...',
              maxLines: 5),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _accent.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? 'Đang mở email...' : 'Gửi yêu cầu',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Phản hồi trong 24h làm việc',
                style: TextStyle(fontSize: 12, color: _textMuted)),
          ),
        ],
      ),
    );
  }

  static Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)));

  static Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
  }) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        textInputAction:
            maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _borderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _borderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 1.5)),
          contentPadding: EdgeInsets.symmetric(
              horizontal: 16, vertical: maxLines == 1 ? 14 : 16),
        ),
      );
}
