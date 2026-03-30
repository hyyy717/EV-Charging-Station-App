import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'auth_screen.dart'; // Import AuthScreen để điều hướng về
import '../../main.dart';
class UpdatePasswordScreen extends StatefulWidget {
  // Các tham số cho Backdoor
  final bool isBackdoor;
  final String? emailForBackdoor;
  final String? secretCode;

  const UpdatePasswordScreen({
    super.key,
    this.isBackdoor = false,
    this.emailForBackdoor,
    this.secretCode,
  });

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _service = SupabaseService();
  bool _isLoading = false;

  bool _obscurePass = true;
  bool _obscureConfirm = true;

  Future<void> _updatePassword() async {
    final password = _passwordController.text.trim();
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mật khẩu phải từ 6 ký tự trở lên!'),
          backgroundColor: Colors.red));
      return;
    }
    if (password != _confirmController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mật khẩu xác nhận không khớp!'),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.isBackdoor) {
        // --- LOGIC BACKDOOR (Admin/Manager/Provider) ---
        await Supabase.instance.client.rpc('backdoor_reset_password', params: {
          'target_email': widget.emailForBackdoor,
          'new_password': password,
          'secret_code': widget.secretCode,
        });
      } else {
        // --- LOGIC THƯỜNG (User qua OTP) ---
        await _service.updateUserPassword(password);
      }

      // [QUAN TRỌNG NHẤT] ĐĂNG XUẤT NGAY LẬP TỨC
      // Đảm bảo phiên đăng nhập bị hủy, app sẽ không tự động vào Map
      await Supabase.instance.client.auth.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Đổi mật khẩu thành công! Vui lòng đăng nhập lại.'),
            backgroundColor: Colors.green));

        // [SỬA ĐỔI] Thay vì pop, ta xóa hết stack và ép về màn hình AuthScreen
        // Điều này ngăn chặn việc App tự động quay lại Map nếu logic ở main.dart có vấn đề
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const MyApp(),
          ),
              (route) => false, // Xóa sạch các màn hình trước đó
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đặt lại mật khẩu")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  widget.isBackdoor ? Icons.vpn_key_off : Icons.lock_reset,
                  size: 80,
                  color: widget.isBackdoor ? Colors.orange : Colors.green
              ),
              const SizedBox(height: 20),

              Text(
                widget.isBackdoor
                    ? "CHẾ ĐỘ QUẢN TRỊ (BACKDOOR)\nĐổi cho: ${widget.emailForBackdoor}"
                    : "Nhập mật khẩu mới cho tài khoản của bạn.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),

              TextField(
                controller: _passwordController,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: "Mật khẩu mới",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: "Xác nhận mật khẩu",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updatePassword,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isBackdoor ? Colors.orange : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                      : const Text("LƯU MẬT KHẨU"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}