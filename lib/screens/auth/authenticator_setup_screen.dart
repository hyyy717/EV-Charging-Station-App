import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/two_factor_service.dart';

class AuthenticatorSetupScreen extends StatefulWidget {
  final bool isVietnamese;

  const AuthenticatorSetupScreen({super.key, required this.isVietnamese});

  @override
  State<AuthenticatorSetupScreen> createState() => _AuthenticatorSetupScreenState();
}

class _AuthenticatorSetupScreenState extends State<AuthenticatorSetupScreen> {
  final TextEditingController _otpController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _qrCodeUri;
  String? _factorId;
  List<String> _recoveryCodes = [];

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  Future<void> _startEnrollment() async {
    try {
      // 1. Unenroll thiết bị cũ nếu có (Fix dứt điểm lỗi positional argument)
      final factors = await _supabase.auth.mfa.listFactors();
      if (factors.totp.isNotEmpty) {
        // KHÔNG DÙNG "factorId:" nữa, truyền trực tiếp ID vào
        await _supabase.auth.mfa.unenroll(factors.totp.first.id);
      }

      // 2. Tạo QR mới với tên App (Fix lỗi thiếu issuer)
      final res = await _supabase.auth.mfa.enroll(issuer: 'Seven Charging');

      setState(() {
        _factorId = res.id;
        _qrCodeUri = res.totp?.uri ?? res.totp?.qrCode;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tạo QR: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _verifyAndComplete() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Vui lòng nhập đủ 6 số' : 'Enter 6 digits'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _supabase.auth.mfa.challengeAndVerify(factorId: _factorId!, code: code);
      final userId = _supabase.auth.currentUser!.id;
      final codes = await TwoFactorService().generateAndSaveRecoveryCodes(userId);
      setState(() {
        _recoveryCodes = codes;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Mã sai hoặc hết hạn!' : 'Invalid code!'), backgroundColor: Colors.red));
      }
    }
  }

  void _copyCodesToClipboard() {
    Clipboard.setData(ClipboardData(text: _recoveryCodes.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Đã copy mã khôi phục!' : 'Recovery codes copied!'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    // -------------------------------------------------------------
    // GIAO DIỆN 2: KHI ĐÃ XÁC THỰC THÀNH CÔNG VÀ HIỆN MÃ KHÔI PHỤC
    // -------------------------------------------------------------
    if (_recoveryCodes.isNotEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.verified_user_rounded, size: 80, color: Colors.green),
                const SizedBox(height: 16),
                Text(widget.isVietnamese ? 'LƯU MÃ KHÔI PHỤC' : 'SAVE RECOVERY CODES', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 8),
                Text(widget.isVietnamese ? 'Lưu lại các mã này ở nơi an toàn để đăng nhập khi mất điện thoại. Mỗi mã chỉ dùng được 1 lần.' : 'Save them safely. Each code is single-use.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 24),

                // Khung chứa mã khôi phục đẹp mắt
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.blueGrey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blueGrey[100]!)
                    ),
                    child: ListView.builder(
                      itemCount: _recoveryCodes.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("${index + 1}.", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(width: 20),
                            Text(_recoveryCodes[index], style: const TextStyle(fontSize: 22, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.black87)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            onPressed: _copyCodesToClipboard,
                            icon: Icon(Icons.copy, color: Colors.blue[800]),
                            label: Text(widget.isVietnamese ? 'Copy mã' : 'Copy', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: Colors.blue[800]!, width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
                            )
                        )
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Kích hoạt 2FA thành công!' : '2FA Enabled!'), backgroundColor: Colors.green));
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2
                        ),
                        child: Text(widget.isVietnamese ? 'TÔI ĐÃ LƯU' : 'I SAVED IT', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      );
    }

    // -------------------------------------------------------------
    // GIAO DIỆN 1: MÀN HÌNH QUÉT MÃ QR VÀ NHẬP MÃ TEST
    // -------------------------------------------------------------
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          title: Text(widget.isVietnamese ? 'Bảo mật 2 Lớp' : '2-Step Verification', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.black87)
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
        child: Column(
          children: [
            Icon(Icons.shield_rounded, size: 70, color: Colors.green[600]),
            const SizedBox(height: 16),
            Text(widget.isVietnamese ? '1. Quét mã QR' : '1. Scan this QR code', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.isVietnamese ? 'Mở ứng dụng Google Authenticator và quét' : 'Use Google Authenticator app', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),

            // Khung mã QR bo góc đổ bóng cực xịn
            if (_qrCodeUri != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 4))
                    ]
                ),
                child: QrImageView(data: _qrCodeUri!, version: QrVersions.auto, size: 220.0),
              ),

            const SizedBox(height: 40),
            Text(widget.isVietnamese ? '2. Nhập mã xác nhận' : '2. Enter 6-digit code', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, letterSpacing: 14, fontWeight: FontWeight.bold, color: Colors.green),
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "------",
                  hintStyle: TextStyle(color: Colors.grey[300]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                )
            ),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _verifyAndComplete,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4
                    ),
                    child: Text(widget.isVietnamese ? 'XÁC NHẬN & BẬT 2FA' : 'VERIFY & ENABLE 2FA', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1))
                )
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}