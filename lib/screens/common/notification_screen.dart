import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import 'package:intl/intl.dart'; // Nhớ thêm intl vào pubspec.yaml

class NotificationScreen extends StatelessWidget {
  final bool isVietnamese;

  const NotificationScreen({super.key, required this.isVietnamese});

  @override
  Widget build(BuildContext context) {
    final service = SupabaseService();

    return Scaffold(
      appBar: AppBar(
        title: Text(isVietnamese ? 'Thông báo' : 'Notifications'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: service.getNotificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_off, size: 60, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(isVietnamese ? "Không có thông báo nào" : "No notifications"),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (ctx, index) {
              final notif = notifications[index];
              final isRead = notif['is_read'] as bool;
              final date = DateTime.parse(notif['created_at']).toLocal();

              return Card(
                color: isRead ? Colors.white : Colors.blue[50], // Chưa đọc thì màu xanh nhạt
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: Icon(
                    isRead ? Icons.mark_email_read : Icons.mark_email_unread,
                    color: isRead ? Colors.grey : Colors.blue,
                  ),
                  title: Text(
                    notif['title'] ?? '',
                    style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(notif['message'] ?? ''),
                      const SizedBox(height: 8),
                      Text(
                        DateFormat('HH:mm dd/MM/yyyy').format(date),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                  onTap: () {
                    // Bấm vào thì đánh dấu đã đọc
                    if (!isRead) {
                      service.markNotificationRead(notif['id']);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}