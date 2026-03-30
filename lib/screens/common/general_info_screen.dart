import 'package:flutter/material.dart';

class GeneralInfoScreen extends StatelessWidget {
  final String title;
  final String contentKey; // Key để lấy nội dung tương ứng

  const GeneralInfoScreen({super.key, required this.title, required this.contentKey});

  @override
  Widget build(BuildContext context) {
    // Lấy nội dung dựa trên key
    final String content = _getContent(contentKey);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.green[800],
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề lớn trong bài viết
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 16),
            // Nội dung chi tiết
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 5,
                  )
                ],
              ),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6, // Giãn dòng cho dễ đọc
                  color: Colors.black87,
                ),
                textAlign: TextAlign.justify,
              ),
            ),
            const SizedBox(height: 30),
            // Footer trang trí
            Center(
              child: Column(
                children: [
                  Icon(Icons.eco, color: Colors.green[300], size: 40),
                  const SizedBox(height: 8),
                  Text(
                    "SEVEN Charging",
                    style: TextStyle(color: Colors.green[300], fontWeight: FontWeight.bold),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- KHO NỘI DUNG (Content) ---
  String _getContent(String key) {
    switch (key) {
    // 1. GIỚI THIỆU DỊCH VỤ
      case 'intro_what':
        return """SEVEN Charging là nền tảng công nghệ tiên phong kết nối người dùng xe điện với mạng lưới trạm sạc rộng khắp tại Việt Nam.

Chúng tôi không chỉ cung cấp bản đồ trạm sạc, mà còn mang đến giải pháp "Một chạm - Sạc ngay". Hệ thống tích hợp khả năng đặt lịch trước, thanh toán không tiền mặt và giám sát quá trình sạc theo thời gian thực.

Với SEVEN Charging, nỗi lo hết pin giữa đường sẽ trở thành quá khứ. Chúng tôi đồng hành cùng bạn trên mọi nẻo đường xanh.""";

      case 'intro_benefit':
        return """✅ Tiết kiệm thời gian: Không cần xếp hàng chờ đợi, bạn có thể đặt lịch hẹn giờ sạc chính xác.
        
✅ Minh bạch chi phí: Giá sạc được niêm yết rõ ràng, không phụ phí ẩn.

✅ An tâm tuyệt đối: Các trạm sạc đối tác đều được kiểm định chất lượng và an toàn cháy nổ.

✅ Hỗ trợ 24/7: Đội ngũ kỹ thuật luôn sẵn sàng hỗ trợ khi bạn gặp sự cố tại trạm.""";

      case 'intro_partner':
        return """Hệ thống đối tác của SEVEN Charging bao gồm:
        
- Các chuỗi trạm sạc tư nhân đạt chuẩn V-GREEN.
- Các bãi đỗ xe thông minh tại chung cư, trung tâm thương mại.
- Các hộ kinh doanh dịch vụ trạm sạc gia đình (Home Charger).

Chúng tôi liên tục mở rộng mạng lưới để đảm bảo dù bạn ở đâu, trạm sạc luôn ở ngay bên cạnh.""";

    // 2. CHÍNH SÁCH & QUY ĐỊNH
      case 'policy_terms':
        return """1. Người dùng cam kết cung cấp thông tin chính xác khi đăng ký tài khoản.
2. Không sử dụng ứng dụng cho các mục đích phá hoại, gian lận.
3. Giữ gìn vệ sinh và bảo vệ tài sản tại trạm sạc.
4. Tuân thủ hướng dẫn của nhân viên quản lý trạm.""";

      case 'policy_booking':
        return """- Bạn có thể đặt chỗ trước tối đa 24 giờ.
- Vui lòng đến đúng giờ. Hệ thống sẽ giữ chỗ cho bạn trong vòng 15 phút tính từ giờ hẹn.
- Sau 15 phút, nếu bạn không check-in, lịch đặt sẽ tự động bị hủy để nhường chỗ cho người khác.""";

      case 'policy_cancel':
        return """- Hủy trước 1 tiếng: Miễn phí hoàn toàn.
- Hủy trong vòng 1 tiếng trước giờ hẹn: Có thể bị tính phí phạt nhỏ (nếu áp dụng) để đảm bảo công bằng cho các tài xế khác.
- Nếu bạn vắng mặt (No-show) quá 3 lần, tài khoản có thể bị tạm khóa tính năng đặt trước.""";

      case 'policy_safety':
        return """⚠️ KHÔNG sạc khi trời đang mưa to sấm sét nếu trạm sạc không có mái che an toàn.
⚠️ Kiểm tra đầu sạc: Không sử dụng nếu thấy đầu sạc bị nứt, vỡ hoặc hở dây điện.
⚠️ Không hút thuốc hoặc mang vật liệu dễ cháy nổ lại gần khu vực trạm sạc.
⚠️ Rút sạc đúng cách: Ngắt kết nối trên ứng dụng trước khi rút đầu sạc ra khỏi xe.""";

    // 3. FAQ
      case 'faq_empty':
        return """Trên bản đồ ứng dụng, các trạm sạc có biểu tượng:
🟢 MÀU XANH LÁ: Đang trống (Sẵn sàng).
🟠 MÀU CAM: Đang bận (Đang sạc hoặc đã có người đặt).

Bạn cũng có thể lọc bản đồ để chỉ hiện các trạm đang trống.""";

      case 'faq_booking':
        return """Việc đặt trước là KHÔNG bắt buộc, nhưng chúng tôi KHUYẾN KHÍCH bạn nên đặt trước để đảm bảo có chỗ sạc ngay khi đến, đặc biệt là vào giờ cao điểm.""";

      case 'faq_payment':
        return """Hiện tại ứng dụng hỗ trợ thanh toán trực tiếp tại trạm hoặc thông qua ví điện tử tích hợp (đang phát triển). Vui lòng kiểm tra thông tin chi tiết tại từng trạm sạc.""";

      case 'faq_vehicle':
        return """Hệ thống SEVEN Charging hỗ trợ cả 2 loại phương tiện:
🚗 Ô tô điện (Các chuẩn sạc thông dụng Type 2, CCS2...)
🛵 Xe máy điện (VinFast, Dat Bike, Pega...)

Bạn vui lòng xem kỹ thông tin "Loại cổng sạc" trong chi tiết trạm để chọn đúng loại phù hợp với xe của mình.""";

    // 4. VỀ CHÚNG TÔI
      case 'about_vision':
        return """Tầm nhìn của chúng tôi là trở thành "Hệ điều hành" của hạ tầng giao thông xanh tại Việt Nam.

Chúng tôi mơ ước về một tương lai nơi không khí trong lành, tiếng ồn động cơ được thay thế bằng sự yên tĩnh của xe điện, và việc sạc xe trở nên dễ dàng như sạc một chiếc điện thoại.""";

      case 'about_mission':
        return """Sứ mệnh của SEVEN Charging là xóa bỏ rào cản về hạ tầng sạc, thúc đẩy người dân Việt Nam chuyển đổi sang phương tiện xanh nhanh chóng và an toàn hơn.""";

      case 'about_team':
        return """Chúng tôi là những kỹ sư trẻ đầy nhiệt huyết, đam mê công nghệ và yêu môi trường. Đội ngũ phát triển ứng dụng luôn nỗ lực từng ngày để mang lại trải nghiệm mượt mà nhất cho người dùng.""";

      case 'about_contact':
        return """Cần hỗ trợ? Hãy liên hệ với chúng tôi:

📞 Hotline: 1900 xxxx
📧 Email: support@sevencharging.com
🏢 Địa chỉ: Khu Công nghệ cao, TP. Hồ Chí Minh.

Chúng tôi luôn lắng nghe ý kiến đóng góp của bạn!""";

      default:
        return "Nội dung đang được cập nhật...";
    }
  }
}