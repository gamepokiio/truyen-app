import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  static const _teal = Color(0xFF22D3EE);
  static const _bg   = Color(0xFFF8F9FA);

  static const _items = [
    _FaqItem(
      question: 'Làm thế nào để tạo tài khoản?',
      answer:
          'Mở tab "Tài khoản" → nhấn "Đăng nhập" → chọn "Đăng ký". '
          'Điền tên đăng nhập, email và mật khẩu. '
          'Sau khi đăng ký thành công bạn sẽ tự động đăng nhập.',
    ),
    _FaqItem(
      question: 'Làm thế nào để đặt lại mật khẩu?',
      answer:
          'Vào màn hình Đăng nhập → nhấn "Quên mật khẩu". '
          'Bạn sẽ được chuyển đến trang web của chúng tôi để thực hiện '
          'quy trình đặt lại mật khẩu qua email.',
    ),
    _FaqItem(
      question: 'Nội dung trên app có miễn phí không?',
      answer:
          'TruyenCV hoàn toàn miễn phí. Bạn có thể đọc tất cả truyện '
          'mà không cần trả phí. Một số tính năng nâng cao có thể yêu cầu tài khoản.',
    ),
    _FaqItem(
      question: 'Tôi có thể đọc truyện offline không?',
      answer:
          'Hiện tại TruyenCV yêu cầu kết nối internet để tải nội dung. '
          'Tính năng đọc offline đang được phát triển và sẽ có trong các phiên bản tới.',
    ),
    _FaqItem(
      question: 'Làm thế nào để báo cáo nội dung vi phạm?',
      answer:
          'Nếu bạn phát hiện nội dung vi phạm chính sách, hãy liên hệ chúng tôi qua '
          'email support@truyencv.io hoặc trang "Liên hệ hỗ trợ" trong phần Tài khoản. '
          'Chúng tôi sẽ xem xét và xử lý trong vòng 24 giờ.',
    ),
    _FaqItem(
      question: 'Dữ liệu cá nhân của tôi được bảo vệ như thế nào?',
      answer:
          'Chúng tôi chỉ thu thập thông tin cần thiết (email, tên đăng nhập) '
          'và không chia sẻ với bên thứ ba. Toàn bộ dữ liệu được mã hóa và lưu trữ an toàn. '
          'Xem thêm tại Chính sách bảo mật trên trang web của chúng tôi.',
    ),
    _FaqItem(
      question: 'Tôi muốn xóa tài khoản, phải làm sao?',
      answer:
          'Vào tab "Tài khoản" (đã đăng nhập) → cuộn xuống cuối trang → '
          'nhấn "Xóa tài khoản". Thao tác này không thể hoàn tác và sẽ '
          'xóa toàn bộ dữ liệu liên quan đến tài khoản của bạn.',
    ),
    _FaqItem(
      question: 'Cách liên hệ hỗ trợ?',
      answer:
          'Bạn có thể liên hệ qua:\n'
          '• Email: support@truyencv.io\n'
          '• Website: https://truyencv.io\n'
          'Chúng tôi phản hồi trong vòng 24–48 giờ làm việc.',
    ),
  ];

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
        title: const Text('Câu hỏi thường gặp',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._items.map((item) => _FaqTile(item: item)),
                const SizedBox(height: 12),
                // Contact card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _teal.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.headset_mic_rounded,
                          color: _teal, size: 28),
                      const SizedBox(height: 8),
                      const Text('Vẫn cần hỗ trợ thêm?',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                      const SizedBox(height: 4),
                      const Text('Đội ngũ chúng tôi luôn sẵn sàng giúp bạn',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280))),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final uri =
                                Uri.parse('mailto:support@truyencv.io');
                            if (await canLaunchUrl(uri)) {
                              launchUrl(uri);
                            }
                          },
                          icon: const Icon(Icons.email_outlined, size: 16),
                          label: const Text('Gửi email hỗ trợ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data class ───────────────────────────────────────────────────────────────

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

// ─── Tile ─────────────────────────────────────────────────────────────────────

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  static const _teal = Color(0xFF22D3EE);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: _teal,
          collapsedIconColor: const Color(0xFF9CA3AF),
          title: Text(item.question,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A))),
          children: [
            Text(item.answer,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    height: 1.6)),
          ],
        ),
      ),
    );
  }
}
