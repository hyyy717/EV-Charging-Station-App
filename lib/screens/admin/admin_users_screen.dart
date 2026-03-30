import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart'; // [MỚI] Import Service

class AdminUsersScreen extends StatefulWidget {
  final bool isVietnamese;

  const AdminUsersScreen({super.key, required this.isVietnamese});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _supabaseService = SupabaseService(); // [MỚI] Khởi tạo Service

  late TabController _tabController;
  bool _isLoading = false;

  // Danh sách người dùng
  List<Map<String, dynamic>> _pendingUsers = [];
  List<Map<String, dynamic>> _activePartners = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUsers();
  }

  // Tải danh sách user từ Supabase
  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      // 1. Lấy danh sách đang chờ (Pending)
      final pendingData = await _supabase
          .from('profiles')
          .select()
          .eq('role', 'provider') // Chỉ lấy Doanh nghiệp
          .eq('status', 'pending'); // Đang chờ

      // 2. Lấy danh sách đã hoạt động (Active)
      final activeData = await _supabase
          .from('profiles')
          .select()
          .eq('role', 'provider')
          .eq('status', 'active');

      if (mounted) {
        setState(() {
          _pendingUsers = List<Map<String, dynamic>>.from(pendingData);
          _activePartners = List<Map<String, dynamic>>.from(activeData);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Lỗi tải user: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // [MỚI] Hàm Duyệt User & Gửi Key (Thay thế logic cũ)
  Future<void> _approveUser(String userId, String email) async {
    // Hiện loading chặn màn hình để người dùng chờ gửi mail
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator())
    );

    try {
      // Gọi Service để: Update Active + Sinh Key + Gửi Mail
      await _supabaseService.approvePartnerAndSendKey(userId, email);

      if (mounted) {
        Navigator.pop(context); // Tắt loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isVietnamese
                ? 'Đã duyệt & Gửi mã Key qua email!'
                : 'Approved & Key sent to email!'),
            backgroundColor: Colors.green,
          ),
        );

        _fetchUsers(); // Tải lại danh sách để cập nhật UI
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tắt loading nếu lỗi
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Hàm XÓA VĨNH VIỄN tài khoản
  Future<void> _deleteUser(String userId) async {
    try {
      // Lệnh này sẽ kích hoạt Trigger trong Database để xóa sạch tài khoản
      await _supabase.from('profiles').delete().eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa tài khoản vĩnh viễn!'), backgroundColor: Colors.green),
        );
        _fetchUsers(); // Tải lại danh sách
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVietnamese ? 'Duyệt Đối tác' : 'Approve Partners'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: widget.isVietnamese ? 'Chờ duyệt (${_pendingUsers.length})' : 'Pending'),
            Tab(text: widget.isVietnamese ? 'Đang hoạt động' : 'Active'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildUserList(_pendingUsers, isPending: true),
          _buildUserList(_activePartners, isPending: false),
        ],
      ),
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> users, {required bool isPending}) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isPending ? Icons.inbox : Icons.check_circle_outline, size: 50, color: Colors.grey),
            const SizedBox(height: 10),
            Text(widget.isVietnamese ? 'Không có dữ liệu.' : 'No data found.'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (ctx, index) {
        final user = users[index];
        // Lấy email từ cột username (hoặc email nếu có)
        final email = user['email'] ?? user['username'] ?? 'Unknown';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPending ? Colors.orange : Colors.green,
              child: Icon(isPending ? Icons.priority_high : Icons.store, color: Colors.white),
            ),
            title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.isVietnamese ? 'Vai trò: Đối tác' : 'Role: Provider'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nút Duyệt (Chỉ hiện ở tab Chờ duyệt)
                if (isPending)
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 32),
                    // [QUAN TRỌNG] Gọi hàm _approveUser mới tại đây
                    onPressed: () => _approveUser(user['id'], email),
                    tooltip: 'Duyệt & Cấp Key',
                  ),

                // Nút Khóa/Xóa (Hiện ở cả 2 tab)
                IconButton(
                  icon: const Icon(Icons.block, color: Colors.red),
                  onPressed: () => _deleteUser(user['id']),
                  tooltip: 'Từ chối & Xóa',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}