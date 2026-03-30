import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class TwoFactorService {
  final _supabase = Supabase.instance.client;

  // ==========================================
  // PHẦN 1: XỬ LÝ 2FA EMAIL (CHO USER)
  // ==========================================

  /// 1. Tạo mã 6 số ngẫu nhiên, lưu vào DB (hạn 3 phút) và gửi Email
  Future<void> sendEmailOTP(String email) async {
    // a. Tạo mã 6 số ngẫu nhiên
    final random = Random();
    String otpCode = (100000 + random.nextInt(900000)).toString(); // VD: 482910

    // b. Tính toán thời gian hết hạn: Hiện tại + 3 phút
    DateTime expiresAt = DateTime.now().add(const Duration(minutes: 3));

    // c. Lưu vào bảng email_otps trên Supabase
    await _supabase.from('email_otps').insert({
      'email': email,
      'otp_code': otpCode,
      'expires_at': expiresAt.toIso8601String(),
    });

    // d. Gọi API EmailJS để gửi thư chứa mã (Miễn phí)
    // LƯU Ý: Bạn cần tạo tài khoản EmailJS (miễn phí) và thay các mã bên dưới
    const String serviceId = 'service_hxzvnnb'; // Thay bằng ID của bạn
    const String templateId = 'template_g5r9idr'; // Thay bằng ID của bạn
    const String publicKey = 'D7Uw5aBdm5BtHTmrr'; // Thay bằng Key của bạn

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': publicKey,
          'template_params': {
            'to_email': email,
            'otp_code': otpCode,
          }
        }),
      );

      // [BẮT LỖI THỰC TẾ CỦA EMAILJS]
      if (response.statusCode == 200) {
        print("Đã gửi Email OTP thành công đến $email");
      } else {
        // Nếu thất bại, quăng lỗi chi tiết từ EmailJS ra màn hình
        throw Exception("Lỗi EmailJS (${response.statusCode}): ${response.body}");
      }
    } catch (e) {
      throw Exception("Không thể gửi thư: $e");
    }
  }

  /// 2. Kiểm tra mã Email OTP người dùng nhập vào
  Future<bool> verifyEmailOTP(String email, String userInputCode) async {
    // Tìm mã OTP mới nhất của email này
    final response = await _supabase
        .from('email_otps')
        .select()
        .eq('email', email)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return false; // Không tìm thấy mã

    String dbCode = response['otp_code'];
    DateTime expiresAt = DateTime.parse(response['expires_at']);

    // Kiểm tra xem đã hết hạn (3 phút) chưa
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception("Mã xác thực đã hết hạn! Vui lòng yêu cầu mã mới.");
    }

    // So sánh mã
    return dbCode == userInputCode;
  }

  // ==========================================
  // PHẦN 2: XỬ LÝ 2FA AUTHENTICATOR & RECOVERY (CHO ADMIN/PROVIDER)
  // ==========================================

  /// 1. Sinh 10 mã khôi phục ngẫu nhiên (Lưu vào DB)
  Future<List<String>> generateAndSaveRecoveryCodes(String userId) async {
    List<String> codes = [];
    final random = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

    // Xóa mã cũ nếu có
    await _supabase.from('recovery_codes').delete().eq('user_id', userId);

    for (int i = 0; i < 10; i++) {
      // Tạo mã dạng: SV-A1B2-C3D4
      String part1 = String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
      String part2 = String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
      String fullCode = "SV-$part1-$part2";

      codes.add(fullCode);

      // Lưu vào Supabase
      await _supabase.from('recovery_codes').insert({
        'user_id': userId,
        'code': fullCode,
      });
    }
    return codes;
  }

  /// 2. Kiểm tra mã khôi phục (Dùng khi mất điện thoại)
  Future<bool> verifyRecoveryCode(String userId, String inputCode) async {
    final response = await _supabase
        .from('recovery_codes')
        .select()
        .eq('user_id', userId)
        .eq('code', inputCode.trim().toUpperCase()) // Fix lỗi gõ chữ thường
        .eq('is_used', false) // Chỉ lấy mã chưa dùng
        .maybeSingle();

    if (response != null) {
      // Tìm thấy mã đúng -> Đốt mã này đi (Cập nhật is_used = true)
      await _supabase
          .from('recovery_codes')
          .update({'is_used': true})
          .eq('id', response['id']);
      return true;
    }
    return false;
  }
}