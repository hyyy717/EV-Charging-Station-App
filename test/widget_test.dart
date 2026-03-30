import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_sac/main.dart';
import 'package:tram_sac/screens/auth/auth_screen.dart'; // Import màn hình Auth

void main() {
  testWidgets('App builds and shows AuthScreen when logged out', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Đợi StreamBuilder của AuthGate lắng nghe xong
    await tester.pumpAndSettle();

    // Kiểm tra xem AuthScreen có hiển thị không
    // (Vì khi test, Supabase session mặc định là null)
    expect(find.byType(AuthScreen), findsOneWidget);
  });
}