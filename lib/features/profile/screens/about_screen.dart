import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  static const _teal = Color(0xFF22D3EE);
  static const _bg   = Color(0xFFF8F9FA);

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Về chúng tôi',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // App identity
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _teal,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 12),
                  const Text('TruyenCV',
                      style: TextStyle(
                          fontFamily: 'Orbitron',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A))),
                  if (_version.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Phiên bản $_version',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF9CA3AF))),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Mô tả
            _Section(
              title: 'Giới thiệu',
              child: const Text(
                'TruyenCV là ứng dụng đọc truyện chữ tiếng Việt miễn phí, '
                'cung cấp kho truyện phong phú với nhiều thể loại: '
                'Tiên Hiệp, Ngôn Tình, Hệ Thống, Kiếm Hiệp và nhiều hơn nữa.\n\n'
                'Chúng tôi cam kết mang đến trải nghiệm đọc truyện tốt nhất '
                'với giao diện thân thiện và nội dung được kiểm duyệt.',
                style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151),
                    height: 1.6),
              ),
            ),
            const SizedBox(height: 12),

            // Nội dung & phân loại
            _Section(
              title: 'Phân loại nội dung',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.verified_user_outlined,
                      color: const Color(0xFF10B981),
                      text: 'Không chứa nội dung dành riêng cho người lớn'),
                  const SizedBox(height: 8),
                  _InfoRow(icon: Icons.family_restroom_rounded,
                      color: const Color(0xFF3B82F6),
                      text: 'Phù hợp từ 16 tuổi trở lên (16+)'),
                  const SizedBox(height: 8),
                  _InfoRow(icon: Icons.shield_outlined,
                      color: _teal,
                      text: 'Nội dung được kiểm duyệt theo tiêu chuẩn cộng đồng'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Nhà phát triển
            _Section(
              title: 'Nhà phát triển',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.web_rounded,
                      color: _teal,
                      text: 'truyencv.io'),
                  const SizedBox(height: 8),
                  _InfoRow(icon: Icons.email_outlined,
                      color: const Color(0xFF6366F1),
                      text: 'support@truyencv.io'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Chính sách & Điều khoản
            _Section(
              title: 'Chính sách & Điều khoản',
              child: Column(
                children: [
                  _LinkButton(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Chính sách bảo mật',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => _launch('https://truyencv.io/chinh-sach-bao-mat'),
                  ),
                  const SizedBox(height: 8),
                  _LinkButton(
                    icon: Icons.gavel_rounded,
                    label: 'Điều khoản sử dụng',
                    color: const Color(0xFFF59E0B),
                    onTap: () => _launch('https://truyencv.io/dieu-khoan-su-dung'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Copyright
            Center(
              child: Text(
                '© ${DateTime.now().year} TruyenCV. All rights reserved.',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Shared components ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.8)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF374151), height: 1.4)),
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _LinkButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: color)),
            ),
            Icon(Icons.open_in_new_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}
