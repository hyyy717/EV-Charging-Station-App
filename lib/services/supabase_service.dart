import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../models/charging_station.dart';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
class SupabaseService {
  final _client = Supabase.instance.client;

  // Lấy vai trò của người dùng hiện tại
  Future<String> getCurrentUserRole() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return 'guest';

      final data = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();

      return data['role'] as String? ?? 'user';
    } catch (e) {
      print("Error fetching user role: $e");
      return 'user';
    }
  }

  // Tìm Role theo EMAIL (Đã sửa để tìm chính xác)
  Future<String> getUserRoleByEmail(String email) async {
    try {
      final data = await _client
          .from('profiles')
          .select('role')
          .eq('email', email)
          .maybeSingle();

      if (data == null) return 'unknown';
      return data['role'] as String? ?? 'user';
    } catch (e) {
      print("Lỗi lấy role: $e");
      return 'unknown';
    }
  }

  // Lấy tất cả trạm sạc Active
  Future<List<ChargingStation>> getAllStations() async {
    try {
      final List<dynamic> data = await _client
          .from('stations')
          .select('*, ports(*)')
          .eq('status', 'active');

      if (data.isNotEmpty) {
        return data.map((item) => ChargingStation.fromMap(item as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      print("Lỗi lấy danh sách trạm sạc: $e");
      return []; // Trả về list rỗng thay vì ném lỗi để tránh crash UI
    }
  }

  // Lấy trạm theo status (Cho Admin)
  Future<List<ChargingStation>> getStationsByStatus(String status) async {
    try {
      final List<dynamic> data = await _client
          .from('stations')
          .select('*, ports(*)')
          .eq('status', status)
          .order('created_at', ascending: false);

      return data.map((item) => ChargingStation.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  // --- CÁC HÀM CRUD TRẠM SẠC ---
  Future<void> addStation(Map<String, dynamic> stationData) async {
    await _client.from('stations').insert(stationData);
  }

  Future<int> addStationAndReturnId(Map<String, dynamic> stationData) async {
    try {
      final response = await _client
          .from('stations')
          .insert(stationData)
          .select()
          .single();
      return response['id'] as int;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addBatchPorts(List<Map<String, dynamic>> portsData) async {
    await _client.from('ports').insert(portsData);
  }

  Future<void> updateStation(int id, Map<String, dynamic> updateData) async {
    await _client.from('stations').update(updateData).eq('id', id);
  }

  Future<void> deleteStation(int id) async {
    await _client.from('stations').delete().eq('id', id);
  }

  Future<String?> getStationOwnerId(int stationId) async {
    final data = await _client
        .from('stations')
        .select('owner_id')
        .eq('id', stationId)
        .single();
    return data['owner_id'] as String?;
  }

  // --- HÀM ĐIỀU CHỈNH SỐ LƯỢNG PORT KHI SỬA ---
  Future<void> adjustPortQuantity(int stationId, String type, int currentCount, int newCount) async {
    if (newCount == currentCount) return;

    if (newCount > currentCount) {
      int quantityToAdd = newCount - currentCount;
      List<Map<String, dynamic>> newPorts = [];
      for (int i = 0; i < quantityToAdd; i++) {
        newPorts.add({
          'station_id': stationId,
          'type': type,
          'status': 'available',
          'name': '$type (Mới)'
        });
      }
      await _client.from('ports').insert(newPorts);
    } else {
      int quantityToRemove = currentCount - newCount;
      final availablePortsResponse = await _client
          .from('ports')
          .select('id')
          .eq('station_id', stationId)
          .eq('type', type)
          .eq('status', 'available')
          .limit(quantityToRemove);

      final List<dynamic> availablePorts = availablePortsResponse;

      if (availablePorts.isNotEmpty) {
        final idsToDelete = availablePorts.map((e) => e['id']).toList();
        await _client.from('ports').delete().filter('id', 'in', idsToDelete);
      }
    }
  }

  // --- HỆ THỐNG ĐẶT LỊCH ---
  Future<bool> createBooking({
    required int stationId,
    required int portId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception("Chưa đăng nhập");

      await _client.from('bookings').insert({
        'user_id': userId,
        'station_id': stationId,
        'port_id': portId,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'status': 'pending',
      });

      final dateFormat = DateFormat('HH:mm dd/MM/yyyy');
      final startStr = dateFormat.format(startTime);
      final endStr = dateFormat.format(endTime);

      final managers = await _client
          .from('station_managers')
          .select('user_id')
          .eq('station_id', stationId);

      for (var m in managers) {
        await sendNotification(
          receiverId: m['user_id'],
          title: "Yêu cầu đặt lịch mới 📅",
          message: "Khách vừa đặt lịch sạc:\n⏳ Bắt đầu: $startStr\n⌛ Kết thúc: $endStr\n\nVui lòng kiểm tra và duyệt.",
        );
      }
      return true;
    } catch (e) {
      print("Lỗi tạo booking: $e");
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> getPendingBookingsStream(int stationId) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('station_id', stationId)
        .order('created_at', ascending: true)
        .map((events) => events
        .where((element) => element['status'] == 'pending')
        .toList());
  }

  Future<void> updateBookingStatus(int bookingId, String newStatus) async {
    await _client.from('bookings').update({'status': newStatus}).eq('id', bookingId);
  }

  Future<List<Map<String, dynamic>>> getUserBookings() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('bookings')
          .select('*, stations(name, address), ports(type)')
          .eq('user_id', userId)
          .order('start_time', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // --- HỆ THỐNG THÔNG BÁO ---
  Future<void> sendNotification({
    required String receiverId,
    required String title,
    required String message,
  }) async {
    try {
      await _client.from('notifications').insert({
        'user_id': receiverId,
        'title': title,
        'message': message,
        'is_read': false,
      });
    } catch (e) {
      print("Lỗi gửi thông báo: $e");
    }
  }

  Stream<List<Map<String, dynamic>>> getNotificationsStream() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();

    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  }

  Future<void> markNotificationRead(int id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Stream<List<Map<String, dynamic>>> getConfirmedBookingsStream(int stationId) {
    return _client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('station_id', stationId)
        .order('start_time', ascending: true)
        .map((events) => events
        .where((element) => element['status'] == 'confirmed')
        .toList());
  }

  Future<List<String>> getStationManagers(int stationId) async {
    try {
      final data = await _client
          .from('station_managers')
          .select('profiles(username)')
          .eq('station_id', stationId);

      List<String> managers = [];
      for (var item in data) {
        final profile = item['profiles'];
        if (profile != null) {
          managers.add(profile['username'] ?? 'Unknown');
        }
      }
      return managers;
    } catch (e) {
      print("Lỗi lấy danh sách quản lý: $e");
      return [];
    }
  }

  // --- HỖ TRỢ QUÊN MẬT KHẨU (BACKDOOR & OTP & LINK) ---

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.tramsac://login-callback/',
      );
    } catch (e) {
      print("Lỗi gửi mail reset: $e");
      rethrow;
    }
  }

  Future<void> sendOtpLogin(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );
    } catch (e) {
      print("Lỗi gửi OTP: $e");
      rethrow;
    }
  }

  Future<void> verifyOtpLogin(String email, String token) async {
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
    } catch (e) {
      print("Lỗi xác thực OTP: $e");
      rethrow;
    }
  }

  Future<void> updateUserPassword(String newPassword) async {
    try {
      // Luôn sử dụng auth.updateUser để Supabase tự hash mật khẩu và lưu vào auth.users
      await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      print("Lỗi đổi mật khẩu: $e");
      rethrow;
    }
  }

  // --- DUYỆT ĐỐI TÁC & CẤP KEY ---

  String _generateRandomKey() {
    var rng = Random();
    return (100000 + rng.nextInt(900000)).toString();
  }

  Future<void> approvePartnerAndSendKey(String partnerId, String partnerEmail) async {
    try {
      final String masterKey = _generateRandomKey();

      await _client.from('profiles').update({
        'status': 'active',
        'backdoor_key': masterKey,
      }).eq('id', partnerId);

      await _sendPartnerApprovalEmail(partnerEmail, masterKey);
    } catch (e) {
      print("Lỗi duyệt đối tác: $e");
      rethrow;
    }
  }

  Future<void> _sendPartnerApprovalEmail(String recipientEmail, String key) async {
    // -------------------------------------------------------------------
    // [QUAN TRỌNG] THÔNG TIN CẤU HÌNH GMAIL
    // -------------------------------------------------------------------
    String username = 'luuthanhhuy1708@gmail.com';
    String appPassword = 'fbacmyggntypjbza';

    final smtpServer = gmail(username, appPassword);

    final message = Message()
      ..from = Address(username, 'SEVEN Charging Admin')
      ..recipients.add(recipientEmail)
      ..subject = '[CẢNH BÁO BẢO MẬT] Phê duyệt Đối tác & Cấp mã Master Key'
      ..html = '''
        <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #e0e0e0; border-radius: 12px; overflow: hidden;">
          <div style="background-color: #2E7D32; padding: 25px; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 24px;">Phê Duyệt Thành Công!</h1>
          </div>
          
          <div style="padding: 30px; color: #333; line-height: 1.6;">
            <p>Xin chào đối tác <strong>$recipientEmail</strong>,</p>
            <p>Chúng tôi rất vui mừng thông báo rằng tài khoản doanh nghiệp của bạn đã được quản trị viên hệ thống <strong>SEVEN Charging</strong> phê duyệt chính thức.</p>
            
            <div style="background-color: #fff4f4; border-left: 5px solid #d32f2f; padding: 20px; margin: 25px 0;">
              <h2 style="color: #d32f2f; margin-top: 0; font-size: 18px; text-align: center;">⚠️ THÔNG TIN BẢO MẬT TỐI MẬT</h2>
              <p style="margin-bottom: 15px; text-align: center;">Dưới đây là mã <strong>Master Key (Backdoor)</strong> dành riêng cho tài khoản của bạn:</p>
              
              <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin: 0 auto;">
                <tr>
                  <td style="background: #ffffff; border: 2px dashed #d32f2f; padding: 15px 30px; font-size: 35px; font-weight: bold; color: #d32f2f; text-align: center; letter-spacing: 2px; white-space: nowrap;">
                    $key
                  </td>
                </tr>
              </table>
            </div>

            <h3 style="color: #2E7D32; font-size: 16px;">Tại sao mã này lại quan trọng?</h3>
            <ul style="padding-left: 20px;">
              <li><strong>Khôi phục tài khoản:</strong> Đây là phương thức duy nhất để đặt lại mật khẩu nếu bạn mất quyền truy cập vào email hoặc OTP.</li>
              <li><strong>Xác thực Quản trị:</strong> Dùng để xác thực các thay đổi quan trọng liên quan đến trạm sạc và quản lý nhân sự.</li>
              <li><strong>Quyền hạn tối cao:</strong> Mã này có giá trị tương đương với mật khẩu gốc của hệ thống.</li>
            </ul>

            <div style="background-color: #f9f9f9; padding: 15px; border-radius: 8px; font-size: 13px; color: #666; margin-top: 20px;">
              <strong>LƯU Ý AN TOÀN:</strong>
              <br>1. Tuyệt đối KHÔNG chia sẻ mã này cho bất kỳ ai, kể cả nhân viên hỗ trợ.
              <br>2. Nên lưu trữ mã này trong các trình quản lý mật khẩu an toàn hoặc ghi chép ngoại tuyến.
              <br>3. Hệ thống sẽ không bao giờ yêu cầu bạn cung cấp mã này qua điện thoại hoặc tin nhắn.
            </div>
          </div>

          <div style="background-color: #f1f1f1; padding: 20px; text-align: center; font-size: 12px; color: #888;">
            © 2025 SEVEN Charging System. Đây là email tự động, vui lòng không phản hồi.
          </div>
        </div>
      ''';

    try {
      final sendReport = await send(message, smtpServer);
      print('Gửi mail thành công: ' + sendReport.toString());
    } catch (e) {
      print('Lỗi gửi mail: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // [ĐÃ CẬP NHẬT] HÀM KIỂM TRA KEY (HỖ TRỢ ADMIN HARDCODE 999999)
  // ---------------------------------------------------------------------------
  Future<bool> verifyBackdoorKey(String email, String inputKey) async {
    try {
      // 1. Tìm thông tin User theo EMAIL
      final profileResponse = await _client
          .from('profiles')
          .select('id, role, backdoor_key')
          .eq('email', email)
          .maybeSingle();

      if (profileResponse == null) {
        print("Không tìm thấy user với email: $email");
        return false;
      }

      final userId = profileResponse['id'];
      final role = profileResponse['role'];

      // --- TRƯỜNG HỢP 0: LÀ ADMIN (Key cứng 999999) ---
      // Nếu là Admin, chỉ cần nhập đúng 999999 là qua, không cần check DB
      if (role == 'admin') {
        return inputKey == '999999';
      }

      // --- TRƯỜNG HỢP 1: LÀ ĐỐI TÁC (PROVIDER) ---
      // So sánh trực tiếp với key trong profile của chính họ
      if (role == 'provider') {
        return profileResponse['backdoor_key'] == inputKey;
      }

      // --- TRƯỜNG HỢP 2: LÀ QUẢN LÝ (MANAGER) ---
      // Tìm key của chủ trạm
      if (role == 'manager') {
        final managerData = await _client
            .from('station_managers')
            .select('station_id')
            .eq('user_id', userId)
            .maybeSingle();

        if (managerData == null) {
          print("Manager chưa được gán vào trạm nào.");
          return false;
        }
        final stationId = managerData['station_id'];

        final stationData = await _client
            .from('stations')
            .select('owner_id')
            .eq('id', stationId)
            .single();

        final ownerId = stationData['owner_id'];

        final ownerProfile = await _client
            .from('profiles')
            .select('backdoor_key')
            .eq('id', ownerId)
            .single();

        return ownerProfile['backdoor_key'] == inputKey;
      }

      return false; // Các role khác không hỗ trợ
    } catch (e) {
      print("Lỗi verify backdoor: $e");
      return false;
    }
  }

  // --- HÀM UPLOAD ẢNH TRẠM SẠC ---
  Future<String?> uploadStationImage(File imageFile, String fileName) async {
    try {
      // 1. Đẩy file lên bucket 'station_images'
      final String path = await _client.storage.from('station_images').upload(
        fileName,
        imageFile,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      // 2. Lấy link public để lưu vào CSDL
      final String publicUrl = _client.storage.from('station_images').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      print("Lỗi upload ảnh: $e");
      return null;
    }
  }

  // --- LẤY THÔNG TIN PROFILE HIỆN TẠI ---
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      return await _client.from('profiles').select().eq('id', user.id).single();
    } catch (e) {
      return null;
    }
  }
// 👇 DÁN HÀM MỚI VÀO ĐÂY 👇
  // --- [MỚI] LẮNG NGHE THAY ĐỔI PROFILE REALTIME ---
  Stream<Map<String, dynamic>> streamUserProfile(String userId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((data) => data.first);
  }

  /// --- UPLOAD VÀ LƯU AVATAR (Xử lý dứt điểm Cache & Realtime) ---
  Future<String?> uploadAvatar(File imageFile, String userId) async {
    try {
      final fileName = 'avatar_$userId.jpg';

      // 1. Đẩy file lên bucket 'avatars' (Ghi đè file cũ để không rác server)
      await _client.storage.from('avatars').upload(
        fileName,
        imageFile,
        // Set cacheControl về 0 để báo mạng không lưu đệm file này
        fileOptions: const FileOptions(cacheControl: '0', upsert: true),
      );

      // 2. Lấy link public gốc
      final String publicUrl = _client.storage.from('avatars').getPublicUrl(fileName);

      // 3. [THỦ THUẬT RẤT QUAN TRỌNG] Thêm thời gian thực vào cuối link
      // Việc này giúp URL luôn thay đổi, bẻ khóa Cache của Flutter và ép DB phát Realtime
      final String finalUrl = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      // 4. Cập nhật link mới vào bảng profiles
      await _client.from('profiles').update({'avatar_url': finalUrl}).eq('id', userId);

      return finalUrl;
    } catch (e) {
      print("Lỗi upload avatar: $e");
      return null;
    }
  }

  // --- ĐĂNG NHẬP BẰNG GOOGLE (CẬP NHẬT CHO BẢN V7.0.0+) ---
  Future<AuthResponse?> signInWithGoogle() async {
    try {
      // TODO: BẠN SẼ CẦN THAY THẾ 2 ĐOẠN MÃ NÀY TỪ GOOGLE CLOUD SAU
      const webClientId = '820892924781-uup2do6ij3g546vnapvfitlps5873t1n.apps.googleusercontent.com';
      const iosClientId = ''; // Bỏ trống nếu không build iOS

      // 1. [CHUẨN MỚI] Khởi tạo thư viện dưới dạng Singleton
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;

      // 2. [CHUẨN MỚI] Bắt buộc phải gọi hàm initialize() trước tiên
      await googleSignIn.initialize(
        serverClientId: webClientId,
        clientId: iosClientId,
      );

      // 3. [CHUẨN MỚI] Kích hoạt bảng chọn tài khoản Google bằng hàm authenticate() thay vì signIn()
      final googleUser = await googleSignIn.authenticate();
      if (googleUser == null) return null; // Người dùng bấm Hủy

      // 4. Lấy Token Định danh (ID Token) từ Google
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'Không thể lấy được ID Token xác thực từ Google.';
      }

      // 5. Gửi ID Token cho Supabase để Đăng nhập/Đăng ký
      // (Bản V7 tách riêng quyền AccessToken, nhưng với Supabase ta chỉ cần ID Token là đủ để đăng nhập)
      final AuthResponse response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      // 6. XỬ LÝ TỰ ĐỘNG TẠO PROFILE (RẤT QUAN TRỌNG CHO HỆ THỐNG 4 ROLE)
      if (response.user != null) {
        final user = response.user!;

        final existingProfile = await _client
            .from('profiles')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();

        if (existingProfile == null) {
          await _client.from('profiles').insert({
            'id': user.id,
            'email': user.email,
            'role': 'user',
            'username': user.userMetadata?['full_name'] ?? 'Người dùng Google',
            'avatar_url': user.userMetadata?['avatar_url'],
          });
        }
      }

      return response;
    } catch (e) {
      print("Lỗi đăng nhập Google: $e");
      throw Exception('Đăng nhập Google thất bại: $e');
    }
  }

}