import 'package:flutter/material.dart';
import 'package:tram_sac/services/two_factor_service.dart';

class EmailOtpScreen extends StatefulWidget {
  final String email;
  final bool isVietnamese;

  const EmailOtpScreen({super.key, required this.email, required this.isVietnamese});

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends State<EmailOtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isSendingResend = false;

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Vui lòng nhập đủ 6 số' : 'Please enter 6 digits'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      bool isValid = await TwoFactorService().verifyEmailOTP(widget.email, code);
      if (isValid && mounted) {
        Navigator.pushReplacementNamed(context, '/map');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Mã OTP không đúng!' : 'Invalid OTP!'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isSendingResend = true);
    try {
      await TwoFactorService().sendEmailOTP(widget.email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isVietnamese ? 'Đã gửi lại mã mới!' : 'New code sent!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi gửi mail: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSendingResend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(elevation: 0, backgroundColor: Colors.white, iconTheme: const IconThemeData(color: Colors.black87)),
      body: SafeArea(
        // [ĐÃ FIX]: Bọc SingleChildScrollView để không bị lỗi vàng đen khi mở bàn phím
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(Icons.mark_email_read, size: 80, color: Colors.green[700]),
                const SizedBox(height: 24),
                Text(widget.isVietnamese ? 'Xác thực Email' : 'Email Verification', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(widget.isVietnamese ? 'Mã 6 chữ số đã được gửi tới:\n${widget.email}' : 'A 6-digit code has been sent to:\n${widget.email}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Colors.grey)),
                const SizedBox(height: 30),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(counterText: "", hintText: "------", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                    onPressed: _verifyOtp,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: Text(widget.isVietnamese ? 'XÁC NHẬN MÃ' : 'VERIFY CODE', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
                _isSendingResend
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: _resendOtp, child: Text(widget.isVietnamese ? 'Chưa nhận được? Gửi lại mã' : 'Didn\'t receive? Resend code', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}