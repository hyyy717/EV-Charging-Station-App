import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/supabase_service.dart';
import 'update_password_screen.dart'; // Import màn hình đổi mật khẩu
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:tram_sac/services/two_factor_service.dart';
import 'email_otp_screen.dart';
import 'authenticator_setup_screen.dart';
class AuthScreen extends StatefulWidget {
  final bool isVietnamese;
  final VoidCallback toggleLanguage;

  const AuthScreen({
    super.key,
    required this.isVietnamese,
    required this.toggleLanguage,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isBusinessAccount = false;
  String _email = '';
  String _password = '';
  bool _isLoading = false;

  bool _obscurePassword = true;

  final _supabase = Supabase.instance.client;

  bool _isConnected = true;
  bool _isVpnActive = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialConnection() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) _updateConnectionStatus(results);
  }
// --- HÀM KIỂM SOÁT PHÂN LUỒNG 2FA ---
  // 1. HÀM PHÂN LUỒNG ĐĂNG NHẬP (ĐÃ BỎ 2FA CHO MANAGER)
  Future<void> _handleLoginSuccess(User user) async {
    try {
      final data = await _supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
      String role = data != null ? (data['role'] ?? 'user') : 'user';

      if (role == 'user') {
        // LUỒNG 1: USER -> GỬI EMAIL OTP
        await TwoFactorService().sendEmailOTP(user.email!);
        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.push(context, MaterialPageRoute(builder: (_) => EmailOtpScreen(email: user.email!, isVietnamese: widget.isVietnamese)));
        }
      } else if (role == 'manager') {
        // LUỒNG 2: MANAGER -> KHÔNG CẦN 2FA, VÀO THẲNG BẢNG ĐIỀU KHIỂN
        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pushReplacementNamed(context, '/manager');
        }
      } else {
        // LUỒNG 3: ADMIN / PROVIDER -> GOOGLE AUTHENTICATOR
        final factorsResponse = await _supabase.auth.mfa.listFactors();
        final totpFactors = factorsResponse.totp;

        if (totpFactors.isNotEmpty) {
          // Đã bật 2FA -> Hiện popup bắt nhập 6 số
          if (mounted) {
            setState(() => _isLoading = false);
            _showMfaChallengeDialog(context, totpFactors.first.id);
          }
        } else {
          // Chưa bật 2FA -> Cho vào thẳng app (vào Map để tự bật trong Menu)
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.pushReplacementNamed(context, '/map');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    }
  }
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final bool isCurrentlyConnected = !results.contains(ConnectivityResult.none);
    final bool isVpnCurrentlyActive = results.contains(ConnectivityResult.vpn);

    if (isCurrentlyConnected != _isConnected || isVpnCurrentlyActive != _isVpnActive) {
      if (mounted) {
        setState(() {
          _isConnected = isCurrentlyConnected;
          _isVpnActive = isVpnCurrentlyActive;
        });
      }
    }
  }

  void _trySubmit() async {
    final isValid = _formKey.currentState?.validate();
    FocusScope.of(context).unfocus();

    if (isValid != true) return;

    _formKey.currentState?.save();
    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final authResponse = await _supabase.auth.signInWithPassword(
          email: _email.trim(),
          password: _password.trim(),
        );

        final userId = authResponse.user?.id;
        if (userId != null) {
          final data = await _supabase
              .from('profiles')
              .select('status')
              .eq('id', userId)
              .maybeSingle();

          if (data != null) {
            final status = data['status'] as String? ?? 'active';

            if (status == 'pending') {
              await _supabase.auth.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(widget.isVietnamese ? 'Tài khoản đang chờ duyệt.' : 'Account is pending approval.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
              setState(() => _isLoading = false);
              return;
            }

            if (status == 'banned') {
              await _supabase.auth.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(widget.isVietnamese ? 'Tài khoản đã bị khóa.' : 'Account has been banned.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              setState(() => _isLoading = false);
              return;
            }
          }
        }
        if (authResponse.user != null) {
          await _handleLoginSuccess(authResponse.user!);
        }

      } else {
        final authResponse = await _supabase.auth.signUp(
          email: _email.trim(),
          password: _password.trim(),
          data: {
            'role': _isBusinessAccount ? 'provider' : 'user',
            'status': _isBusinessAccount ? 'pending' : 'active',
            'username': _email.trim(),
          },
        );

        if (authResponse.user != null && mounted) {
          String msg = "";
          Color color = Colors.green;

          if (_isBusinessAccount) {
            msg = widget.isVietnamese
                ? 'Đăng ký thành công! Vui lòng chờ duyệt.'
                : 'Registration successful! Please wait for approval.';
            color = Colors.orange;
          } else {
            msg = widget.isVietnamese
                ? 'Đăng ký thành công!'
                : 'Registration successful!';
            color = Colors.green;
          }

          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));

          setState(() {
            _isLogin = true;
            _isBusinessAccount = false;
            _isLoading = false;
          });
          _supabase.auth.signOut();
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        String msg = e.message;
        if (_isLogin && e.message.toLowerCase().contains('invalid login credentials')) {
          msg = widget.isVietnamese
              ? 'Sai email hoặc mật khẩu.'
              : 'Invalid credentials.';
        }
        if (!_isLogin && e.message.toLowerCase().contains('already registered')) {
          msg = widget.isVietnamese ? 'Email này đã được đăng ký.' : 'Email already exists.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- [FIX LỖI OVERFLOW] Bọc content trong SingleChildScrollView ---
  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController();
    if (_email.isNotEmpty) emailController.text = _email;
    bool isCheckingRole = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(widget.isVietnamese ? "Khôi phục mật khẩu" : "Reset Password"),
              // [FIX]: Thêm SingleChildScrollView
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.isVietnamese
                        ? "Nhập email tài khoản:"
                        : "Enter your account email:"),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    if (isCheckingRole) ...[
                      const SizedBox(height: 16),
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 8),
                      Center(child: Text(widget.isVietnamese ? "Đang kiểm tra tài khoản..." : "Checking account...")),
                    ]
                  ],
                ),
              ),
              actions: [
                if (!isCheckingRole)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(widget.isVietnamese ? "Hủy" : "Cancel"),
                  ),

                if (!isCheckingRole)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                    onPressed: () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email không hợp lệ"), backgroundColor: Colors.red));
                        return;
                      }

                      setDialogState(() => isCheckingRole = true);
                      final role = await SupabaseService().getUserRoleByEmail(email);
                      setDialogState(() => isCheckingRole = false);

                      if (!mounted) return;
                      Navigator.pop(ctx);

                      if (role == 'unknown') {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Không tìm thấy tài khoản này!"), backgroundColor: Colors.red));
                        return;
                      }

                      if (role == 'user') {
                        _handleOtpFlow(email);
                      } else {
                        _showBackdoorSecretDialog(context, email);
                      }
                    },
                    child: Text(widget.isVietnamese ? "Tiếp tục" : "Continue"),
                  ),
              ],
            );
          }
      ),
    );
  }

  // --- [FIX LỖI OVERFLOW] Bọc content trong SingleChildScrollView ---
  void _showBackdoorSecretDialog(BuildContext context, String email) {
    final codeController = TextEditingController();
    bool isChecking = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("🔐 Xác thực Quản Trị"),
              // [FIX]: Thêm SingleChildScrollView để tránh lỗi khi bàn phím hiện lên
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Tài khoản: $email"),
                    const SizedBox(height: 8),
                    const Text(
                      "Tài khoản quản trị/đối tác cần sử dụng Mã Key (Master Key) để đặt lại mật khẩu.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: codeController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Nhập Master Key",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.vpn_key),
                      ),
                    ),
                    if (isChecking) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: isChecking ? null : () async {
                    final inputKey = codeController.text.trim();
                    if (inputKey.isEmpty) return;

                    setDialogState(() => isChecking = true);
                    final isValid = await SupabaseService().verifyBackdoorKey(email, inputKey);
                    setDialogState(() => isChecking = false);

                    if (isValid) {
                      if (mounted) {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UpdatePasswordScreen(
                              isBackdoor: true,
                              emailForBackdoor: email,
                              secretCode: inputKey,
                            ),
                          ),
                        );
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(widget.isVietnamese ? "Mã Key không đúng!" : "Invalid Key!"),
                                backgroundColor: Colors.red
                            )
                        );
                      }
                    }
                  },
                  child: const Text("Xác thực"),
                )
              ],
            );
          }
      ),
    );
  }

  // --- [FIX LỖI OVERFLOW] Bọc content trong SingleChildScrollView ---
  Future<void> _handleOtpFlow(String email) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Đang gửi mã OTP..."), duration: Duration(seconds: 1)));

    try {
      await SupabaseService().sendOtpLogin(email);
      if (mounted) {
        _showOtpInputDialog(context, email);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Lỗi gửi OTP: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showOtpInputDialog(BuildContext context, String email) {
    final otpController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("🔑 Nhập mã OTP"),
            // [FIX]: Thêm SingleChildScrollView
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Mã xác nhận 6 số đã được gửi tới:\n$email", textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: "000000",
                      border: OutlineInputBorder(),
                      counterText: "",
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
              ElevatedButton(
                onPressed: isVerifying ? null : () async {
                  final otp = otpController.text.trim();
                  if (otp.length != 6) return;

                  setDialogState(() => isVerifying = true);

                  try {
                    await SupabaseService().verifyOtpLogin(email, otp);
                    if (mounted) {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UpdatePasswordScreen()),
                      );
                    }
                  } catch (e) {
                    setDialogState(() => isVerifying = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Mã OTP không đúng hoặc hết hạn!"), backgroundColor: Colors.red));
                  }
                },
                child: isVerifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                    : const Text("Xác nhận"),
              ),
            ],
          );
        },
      ),
    );
  }

  // Hàm hiển thị Popup nhập mã Google Authenticator
  void _showMfaChallengeDialog(BuildContext context, String factorId) async {
    final codeController = TextEditingController();
    bool isVerifying = false;

    if (!mounted) return;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(widget.isVietnamese ? "🔐 Xác thực 2 Bước" : "🔐 2-Step Verification"),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.isVietnamese
                          ? "Vui lòng nhập mã 6 số từ ứng dụng Google Authenticator."
                          : "Enter the 6-digit code from Google Authenticator."),
                      const SizedBox(height: 16),
                      TextField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ""),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      _supabase.auth.signOut();
                      Navigator.pop(ctx);
                    },
                    child: Text(widget.isVietnamese ? "Hủy & Đăng xuất" : "Cancel & Logout"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: isVerifying ? null : () async {
                      final code = codeController.text.trim();
                      if (code.length != 6) return;

                      setDialogState(() => isVerifying = true);
                      try {
                        await _supabase.auth.mfa.challengeAndVerify(factorId: factorId, code: code);

                        if (mounted) {
                          Navigator.pop(ctx);
                          // Nhập đúng 6 số -> Cho Admin/Provider vào Bản đồ
                          Navigator.pushReplacementNamed(context, '/map');
                        }
                      } catch (e) {
                        setDialogState(() => isVerifying = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(widget.isVietnamese ? "Mã sai hoặc hết hạn!" : "Invalid code!"), backgroundColor: Colors.red)
                        );
                      }
                    },
                    child: isVerifying
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                        : Text(widget.isVietnamese ? "Xác nhận" : "Verify"),
                  ),
                ],
              );
            }
        )
    );
  }
  @override
  Widget build(BuildContext context) {
    final String title = _isLogin
        ? (widget.isVietnamese ? 'Chào mừng trở lại' : 'Welcome Back')
        : (widget.isVietnamese ? 'Tạo tài khoản mới' : 'Create Account');

    final String btnText = _isLogin
        ? (widget.isVietnamese ? 'ĐĂNG NHẬP' : 'LOGIN')
        : (widget.isVietnamese ? 'ĐĂNG KÝ' : 'REGISTER');

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade800, Colors.green.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(50),
                  bottomRight: Radius.circular(50),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.ev_station_rounded, size: 80, color: Colors.white),
                    const SizedBox(height: 10),
                    const Text(
                      "SEVEN CHARGING",
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 180),

                      Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)
                                ),
                                const SizedBox(height: 30),

                                TextFormField(
                                  key: const ValueKey('email'),
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: const Icon(Icons.email_outlined),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                  ),
                                  validator: (val) {
                                    if (val == null || !val.contains('@')) {
                                      return widget.isVietnamese ? 'Email không hợp lệ' : 'Invalid email';
                                    }
                                    return null;
                                  },
                                  onSaved: (val) => _email = val ?? '',
                                ),
                                const SizedBox(height: 20),

                                TextFormField(
                                  key: const ValueKey('password'),
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: widget.isVietnamese ? 'Mật khẩu' : 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                  ),
                                  validator: (val) {
                                    if (val == null || val.length < 6) {
                                      return widget.isVietnamese ? 'Mật khẩu phải > 6 ký tự' : 'Password too short';
                                    }
                                    return null;
                                  },
                                  onSaved: (val) => _password = val ?? '',
                                ),

                                // KHỐI 1: CHỈ HIỆN Ở MÀN ĐĂNG KÝ (Nút gạt Doanh nghiệp)
                                if (!_isLogin) ...[
                                  const SizedBox(height: 20),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: SwitchListTile(
                                      activeColor: Colors.green,
                                      title: Text(
                                        widget.isVietnamese ? 'Đăng ký Doanh nghiệp' : 'Business Account',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      subtitle: Text(
                                        widget.isVietnamese ? 'Cần phê duyệt' : 'Requires approval',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                      value: _isBusinessAccount,
                                      onChanged: (val) => setState(() => _isBusinessAccount = val),
                                    ),
                                  ),
                                ],

                                // KHỐI 2: QUÊN MẬT KHẨU (Chỉ hiện ở màn Đăng nhập)
                                if (_isLogin)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => _showForgotPasswordDialog(context),
                                      child: Text(
                                        widget.isVietnamese ? "Quên mật khẩu?" : "Forgot Password?",
                                        style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(height: 30),

                                // KHỐI 3: NÚT ĐĂNG NHẬP / ĐĂNG KÝ CHÍNH
                                if (_isLoading)
                                  const Center(child: CircularProgressIndicator())
                                else
                                  ElevatedButton(
                                    onPressed: _trySubmit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[700],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 5,
                                    ),
                                    child: Text(btnText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                  ),

                                const SizedBox(height: 20),

                                const SizedBox(height: 20), // Giữ nguyên khoảng cách gốc của bạn

                                  // --- [KHỐI 4 MỚI: ĐÃ CẬP NHẬT] NÚT GOOGLE HÌNH TRÒN, HIỆN ĐẠI, LOGO ĐA MÀU SẮC ---
                                  // Chỉ hiện ở chế độ Đăng nhập/Đăng ký cá nhân
                                // --- [KHỐI 4 MỚI: ĐÃ FIX LỖI ẢNH SVG] NÚT GOOGLE HÌNH TRÒN ĐA MÀU SẮC ---
                                if (!_isBusinessAccount) ...[
                                  // 1. Thanh ngăn HOẶC
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Row(
                                      children: [
                                        Expanded(child: Divider(thickness: 1, color: Colors.grey[300])),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 15),
                                          child: Text(
                                            widget.isVietnamese ? 'HOẶC' : 'OR',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                        Expanded(child: Divider(thickness: 1, color: Colors.grey[300])),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 30),

                                  // 2. NÚT GOOGLE TRÒN CỰC KỲ NHỎ GỌN VÀ HIỆN ĐẠI
                                  Center(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        shape: const CircleBorder(),
                                        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                                        padding: const EdgeInsets.all(16),
                                        elevation: 1,
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.grey[200],
                                      ),
                                      onPressed: () async {
                                        // 1. Khai báo biến để "trói" chính xác cái vòng xoay này lại
                                        BuildContext? dialogContext;

                                        showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (ctx) {
                                              dialogContext = ctx; // Lưu lại ID của cái vòng xoay
                                              return const Center(child: CircularProgressIndicator());
                                            }
                                        );

                                        try {
                                          final response = await SupabaseService().signInWithGoogle();

                                          // 2. Tắt CHÍNH XÁC cái vòng xoay đó dù cho app đã nhảy sang màn hình khác
                                          if (dialogContext != null && dialogContext!.mounted) {
                                            Navigator.pop(dialogContext!);
                                          }

                                          // 3. Chuyển sang màn hình Map (Nếu main.dart chưa tự chuyển)
                                          if (response != null && response.user != null) {
                                            if (mounted) {
                                              await _handleLoginSuccess(response.user!);
                                            }
                                          }
                                        } catch (e) {
                                          // Tắt vòng xoay nếu có lỗi
                                          if (dialogContext != null && dialogContext!.mounted) {
                                            Navigator.pop(dialogContext!);
                                          }

                                          String errorStr = e.toString().toLowerCase();
                                          bool isCanceledByUser = errorStr.contains('cancel') || errorStr.contains('canceled');

                                          if (mounted && !isCanceledByUser) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                                          }
                                        }
                                      },
                                      // [ĐÃ SỬA]: Thay link SVG bằng link PNG chuẩn màu của Google
                                      child: Image.network(
                                        'https://img.icons8.com/color/48/000000/google-logo.png',
                                        height: 28,
                                        width: 28,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                ],

                                const SizedBox(height: 10),

                                // KHỐI 5: NÚT CHUYỂN ĐỔI MÀN HÌNH
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLogin = !_isLogin;
                                      _isBusinessAccount = false;
                                      _formKey.currentState?.reset();
                                    });
                                  },
                                  child: Text(
                                    _isLogin
                                        ? (widget.isVietnamese ? 'Chưa có tài khoản? Đăng ký ngay' : 'No account? Register now')
                                        : (widget.isVietnamese ? 'Đã có tài khoản? Đăng nhập' : 'Have an account? Login'),
                                    style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),

            _buildBlockingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockingOverlay() {
    if (!_isVpnActive && _isConnected) return const SizedBox.shrink();

    String message = _isVpnActive
        ? (widget.isVietnamese ? 'Phát hiện VPN/DNS đáng ngờ.' : 'Suspicious VPN/DNS detected.')
        : (widget.isVietnamese ? 'Vui lòng kiểm tra kết nối internet.' : 'Check internet connection.');

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isVpnActive ? Icons.security : Icons.wifi_off, color: Colors.white, size: 80),
                const SizedBox(height: 24),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}