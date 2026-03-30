import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';

class CreateManagerScreen extends StatefulWidget {
  final int stationId;
  final String stationName;
  final bool isVietnamese;

  const CreateManagerScreen({
    super.key,
    required this.stationId,
    required this.stationName,
    required this.isVietnamese,
  });

  @override
  State<CreateManagerScreen> createState() => _CreateManagerScreenState();
}

class _CreateManagerScreenState extends State<CreateManagerScreen> {
  final _formKey = GlobalKey<FormState>();

  final _mainClient = Supabase.instance.client;
  final _supabaseService = SupabaseService();

  String _email = '';
  String _password = '';
  bool _isLoading = false;

  // [MỚI] Biến trạng thái ẩn/hiện mật khẩu
  bool _obscurePassword = true;

  Future<void> _createManager() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    // Tạo client tạm thời để tạo user mới mà không ảnh hưởng session hiện tại
    final tempClient = SupabaseClient(
      'https://nlhbnrcvaltprqehybbm.supabase.co',
      'sb_publishable_nCApQ8GgDL5DN7Ye6K2_Dw_4bkghSCk',
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );

    try {
      final authRes = await tempClient.auth.signUp(
        email: _email,
        password: _password,
        data: {
          'role': 'manager',
          'status': 'active',
        },
      );

      await tempClient.dispose();

      final newUserId = authRes.user?.id;

      if (newUserId != null) {
        await _mainClient.from('station_managers').insert({
          'station_id': widget.stationId,
          'user_id': newUserId,
        });

        final ownerId = await _supabaseService.getStationOwnerId(widget.stationId);
        if (ownerId != null) {
          await _supabaseService.sendNotification(
            receiverId: ownerId,
            title: widget.isVietnamese ? "Tài khoản Quản lý mới 👤" : "New Manager Account",
            message: widget.isVietnamese
                ? "Admin đã cấp tài khoản quản lý cho trạm ${widget.stationName}.\n\nEmail: $_email\nMật khẩu: $_password\n\nVui lòng gửi thông tin này cho nhân viên vận hành."
                : "Admin created a manager account for station ${widget.stationName}.\n\nEmail: $_email\nPassword: $_password",
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.isVietnamese
                  ? "Tạo tài khoản thành công! Admin vẫn đang đăng nhập."
                  : "Account created successfully! Admin remains logged in."),
              backgroundColor: Colors.green,
            ),
          );

          _formKey.currentState?.reset();
          setState(() {
            _email = '';
            _password = '';
          });
        }
      }
    } on AuthException catch (e) {
      String errorMessage = e.message;
      if (e.code == 'user_already_exists' || e.message.contains('already registered')) {
        errorMessage = widget.isVietnamese
            ? 'Email này đã được đăng ký. Vui lòng dùng email khác.'
            : 'Email already registered.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi: $errorMessage"), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVietnamese ? "Cấp quyền Quản lý" : "Grant Manager"),
      ),
      // [FIX LỖI OVERFLOW]: Bọc nội dung trong SingleChildScrollView
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isVietnamese
                      ? "Tạo tài khoản cho trạm: ${widget.stationName}"
                      : "Create account for station: ${widget.stationName}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 20),

                // Email
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: "Email Manager",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) => val != null && val.contains('@') ? null : 'Email không hợp lệ',
                  onSaved: (val) => _email = val!,
                ),
                const SizedBox(height: 16),

                // [SỬA] Mật khẩu có icon mắt
                TextFormField(
                  decoration: InputDecoration(
                    labelText: widget.isVietnamese ? "Mật khẩu" : "Password",
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    // Icon ẩn hiện
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword, // Dùng biến
                  validator: (val) => val != null && val.length >= 6 ? null : 'Mật khẩu quá ngắn (tối thiểu 6 ký tự)',
                  onSaved: (val) => _password = val!,
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _createManager,
                    icon: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.person_add),
                    label: Text(
                      widget.isVietnamese ? "TẠO TÀI KHOẢN" : "CREATE ACCOUNT",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}