import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/auth/auth_provider.dart';

// Provider lấy version app (cached)
final _appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const _teal = Color(0xFF22D3EE);
  static const _bg   = Color(0xFFF8F9FA);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Tài khoản',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
      ),
      body: authAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(
                color: _teal, strokeWidth: 2)),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (auth) => _ProfileBody(auth: auth),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  final AuthState auth;
  const _ProfileBody({required this.auth});

  static const _teal = Color(0xFF22D3EE);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = auth.user;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          _buildHeader(context, ref, user),
          const SizedBox(height: 12),

          // ── HỖ TRỢ ──────────────────────────────────────────────────────────
          _SectionLabel('HỖ TRỢ'),
          _MenuGroup(children: [
            _MenuItem(
              iconBg: const Color(0xFF10B981),
              icon: Icons.headset_mic_rounded,
              label: 'Liên hệ hỗ trợ',
              onTap: () => _launch('mailto:support@truyencv.io'),
            ),
            _MenuItem(
              iconBg: const Color(0xFF6366F1),
              icon: Icons.help_outline_rounded,
              label: 'FAQ',
              onTap: () => context.push('/faq'),
            ),
          ]),
          const SizedBox(height: 12),

          // ── ỨNG DỤNG ────────────────────────────────────────────────────────
          _SectionLabel('ỨNG DỤNG'),
          _MenuGroup(children: [
            _MenuItem(
              iconBg: _teal,
              icon: Icons.info_outline_rounded,
              label: 'Về chúng tôi',
              onTap: () => context.push('/about'),
            ),
            _MenuItem(
              iconBg: const Color(0xFF8B5CF6),
              icon: Icons.privacy_tip_outlined,
              label: 'Chính sách bảo mật',
              onTap: () => _launch('https://truyencv.io/chinh-sach-bao-mat'),
            ),
            _MenuItem(
              iconBg: const Color(0xFF64748B),
              icon: Icons.description_outlined,
              label: 'Điều khoản sử dụng',
              onTap: () => _launch('https://truyencv.io/dieu-khoan-su-dung'),
            ),
            // Google Play 6.3.2: phải có web form xóa tài khoản
            if (user != null)
              _MenuItem(
                iconBg: const Color(0xFFEF4444),
                icon: Icons.manage_accounts_outlined,
                label: 'Yêu cầu xóa dữ liệu',
                onTap: () => _launch('https://truyencv.io/xoa-tai-khoan'),
              ),
          ]),
          const SizedBox(height: 12),

          // ── Logged-in actions ─────────────────────────────────────────────
          if (user != null) ...[
            _buildLogoutButton(context, ref),
            const SizedBox(height: 4),
            _buildDeleteButton(context, ref),
          ],

          const SizedBox(height: 24),

          // ── App version ───────────────────────────────────────────────────
          Consumer(
            builder: (context, ref, _) {
              final version = ref.watch(_appVersionProvider);
              return version.maybeWhen(
                data: (v) => Center(
                  child: Text('TruyenCV v$v',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFD1D5DB))),
                ),
                orElse: () => const SizedBox.shrink(),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, WidgetRef ref, dynamic user) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          // Avatar
          _buildAvatar(user),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: user == null
                ? _buildGuestInfo(context)
                : _buildUserInfo(user),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(dynamic user) {
    if (user == null) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person_rounded,
            size: 34, color: Color(0xFF9CA3AF)),
      );
    }
    return CircleAvatar(
      radius: 30,
      backgroundImage: user.avatarUrl != null
          ? CachedNetworkImageProvider(user.avatarUrl!)
          : null,
      backgroundColor: _teal.withValues(alpha: 0.15),
      child: user.avatarUrl == null
          ? Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _teal))
          : null,
    );
  }

  Widget _buildGuestInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ẩn Danh',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 2),
        const Text('Chưa đăng nhập',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ElevatedButton(
            onPressed: () => context.push('/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Đăng nhập',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfo(dynamic user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(user.displayName,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 2),
        if (user.email != null)
          Text(user.email!,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280))),
        const SizedBox(height: 2),
        Text('ID thành viên: ${user.id}',
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${user.rankName} · Lv.${user.level}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0E7490)),
          ),
        ),
      ],
    );
  }

  // ── Logout / Delete ──────────────────────────────────────────────────────────

  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton(
        onPressed: () async {
          final ok = await _confirm(
            context,
            title: 'Đăng xuất',
            content: 'Bạn có muốn đăng xuất khỏi tài khoản không?',
            confirmLabel: 'Đăng xuất',
          );
          if (ok) await ref.read(authProvider.notifier).logout();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Đăng xuất',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextButton(
        onPressed: () async {
          // Dialog chi tiết — nói rõ data nào bị xóa (Google Play 6.3.2)
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Xóa tài khoản'),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hành động này KHÔNG THỂ hoàn tác. Dữ liệu bị xóa vĩnh viễn bao gồm:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Text('• Thông tin tài khoản (tên, email)'),
                  Text('• Lịch sử đọc truyện'),
                  Text('• Danh sách truyện theo dõi'),
                  Text('• Bình luận và đánh giá'),
                  SizedBox(height: 12),
                  Text('Bạn có chắc chắn muốn xóa tài khoản?',
                      style: TextStyle(color: Colors.red)),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Hủy')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Xóa tài khoản',
                        style: TextStyle(color: Colors.red,
                            fontWeight: FontWeight.bold))),
              ],
            ),
          ) == true;

          if (!ok || !context.mounted) return;

          await ref.read(authProvider.notifier).deleteAccount();
          if (!context.mounted) return;

          // Kiểm tra kết quả — có lỗi thì báo, không lỗi thì báo thành công
          final auth = ref.read(authProvider).valueOrNull;
          if (auth?.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Xóa tài khoản thất bại: ${auth!.error}'),
              backgroundColor: Colors.red.shade700,
            ));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Tài khoản đã được xóa thành công.'),
              backgroundColor: Colors.green,
            ));
          }
        },
        style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
        child: const Text('Xóa tài khoản'),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirmLabel,
                      style: const TextStyle(color: Colors.red))),
            ],
          ),
        ) ==
        true;
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.8)),
    );
  }
}

// ─── Menu group (card) ────────────────────────────────────────────────────────

class _MenuGroup extends StatelessWidget {
  final List<Widget> children;
  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 54,
                  color: Colors.grey.shade100),
          ],
        ],
      ),
    );
  }
}

// ─── Menu item ────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final Color iconBg;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem(
      {required this.iconBg,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A))),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }
}
