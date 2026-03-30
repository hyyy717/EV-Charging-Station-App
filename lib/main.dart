import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/user/map_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/manager/manager_home_screen.dart';
import 'screens/auth/update_password_screen.dart'; // [MỚI] Import màn hình đổi mật khẩu

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://nlhbnrcvaltprqehybbm.supabase.co',
    anonKey: 'sb_publishable_nCApQ8GgDL5DN7Ye6K2_Dw_4bkghSCk',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isVietnamese = true;

  void _toggleLanguage() {
    setState(() {
      _isVietnamese = !_isVietnamese;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V-GREEN Charging',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      // [THÊM KHAI BÁO ROUTES NÀY VÀO ĐÂY]:
      routes: {
        '/map': (context) => MapScreen(isVietnamese: _isVietnamese, toggleLanguage: _toggleLanguage),
        '/manager': (context) => ManagerHomeScreen(isVietnamese: _isVietnamese, toggleLanguage: _toggleLanguage),
      },
      home: AuthGate(
        isVietnamese: _isVietnamese,
        toggleLanguage: _toggleLanguage,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  final bool isVietnamese;
  final VoidCallback toggleLanguage;

  const AuthGate({super.key, required this.isVietnamese, required this.toggleLanguage});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {

  @override
  void initState() {
    super.initState();
    // [GIỮ NGUYÊN] Lắng nghe sự kiện khi người dùng bấm Link từ Email
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        // Chuyển hướng sang màn hình Đổi Mật Khẩu
        Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => const UpdatePasswordScreen()),
        );
      }
      // [SỬA 1]: Thêm bắt sự kiện Đăng Xuất ở đây
      else if (event == AuthChangeEvent.signedOut) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (ctx) => AuthScreen(
                isVietnamese: widget.isVietnamese,
                toggleLanguage: widget.toggleLanguage,
              ),
            ),
                (route) => false,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // [SỬA 2]: GỠ BỎ HOÀN TOÀN StreamBuilder
    // Chỉ lấy session trực tiếp 1 lần duy nhất để không bị tự động nhảy trang (Bypass 2FA)
    final session = Supabase.instance.client.auth.currentSession;

    // 1. CHƯA ĐĂNG NHẬP -> VỀ MÀN HÌNH AUTH
    if (session == null) {
      return AuthScreen(
        isVietnamese: widget.isVietnamese,
        toggleLanguage: widget.toggleLanguage,
      );
    }

    // 2. ĐÃ ĐĂNG NHẬP -> KIỂM TRA PROFILE
    // [GIỮ NGUYÊN 100%] TOÀN BỘ LOGIC, GIAO DIỆN LỖI, VÀ FUTUREBUILDER CỦA BẠN KHÔNG THAY ĐỔI
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchUserProfile(session.user.id),
      builder: (context, profileSnapshot) {
        if (profileSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.green),
                  SizedBox(height: 20),
                  Text("Đang đồng bộ dữ liệu...", style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }

        if (profileSnapshot.hasError || !profileSnapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 60, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text("Không thể tải thông tin người dùng", style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    Text("${profileSnapshot.error ?? 'Dữ liệu trống'}", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      child: const Text("Đăng xuất & Thử lại"),
                    )
                  ],
                ),
              ),
            ),
          );
        }

        final userProfile = profileSnapshot.data!;
        final role = userProfile['role'] as String? ?? 'user';
        final status = userProfile['status'] as String? ?? 'active';

        if (status == 'banned' || (role == 'provider' && status == 'pending')) {
          Future.microtask(() => Supabase.instance.client.auth.signOut());
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (role == 'manager') {
          return ManagerHomeScreen(
            isVietnamese: widget.isVietnamese,
            toggleLanguage: widget.toggleLanguage,
          );
        } else {
          return MapScreen(
            isVietnamese: widget.isVietnamese,
            toggleLanguage: widget.toggleLanguage,
          );
        }
      },
    );
  }

  // [GIỮ NGUYÊN 100%]
  Future<Map<String, dynamic>> _fetchUserProfile(String userId) async {
    return await Supabase.instance.client
        .from('profiles')
        .select('role, status')
        .eq('id', userId)
        .single()
        .timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception("Kết nối quá hạn. Vui lòng kiểm tra mạng.");
    });
  }
}