import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';
import '../auth/auth_screen.dart';

class ManagerHomeScreen extends StatefulWidget {
  final bool isVietnamese;
  final VoidCallback toggleLanguage;

  const ManagerHomeScreen({
    super.key,
    required this.isVietnamese,
    required this.toggleLanguage,
  });

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _service = SupabaseService();
  late TabController _tabController;

  List<Map<String, dynamic>> _ports = [];
  int? _stationId;
  String _stationName = "Đang tải...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchStationInfo();
  }

  Future<void> _fetchStationInfo() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      final managerData = await _supabase
          .from('station_managers')
          .select('station_id, stations(name)')
          .eq('user_id', userId)
          .maybeSingle();

      if (managerData == null) {
        if (mounted) {
          setState(() {
            _stationName = "Chưa được gán trạm";
            _isLoading = false;
          });
        }
        return;
      }

      _stationId = managerData['station_id'];
      final stationName = managerData['stations']['name'];

      // Tải dữ liệu lần đầu
      _reloadData();

      // Lắng nghe thay đổi thời gian thực (Realtime)
      if (_stationId != null) {
        _supabase
            .from('ports')
            .stream(primaryKey: ['id'])
            .eq('station_id', _stationId!)
            .order('id', ascending: true)
            .listen((List<Map<String, dynamic>> data) {
          if (mounted) {
            setState(() {
              _ports = data;
              _stationName = stationName;
              _isLoading = false;
            });
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadData() async {
    if (_stationId == null) return;
    // Không hiện loading ở đây để tránh nháy màn hình khi update ngầm
    try {
      final data = await _supabase
          .from('ports')
          .select()
          .eq('station_id', _stationId!)
          .order('id', ascending: true);

      if (mounted) {
        setState(() {
          _ports = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getPortName(int portId) {
    final port = _ports.firstWhere((p) => p['id'] == portId, orElse: () => {});
    return port['name'] ?? 'ID $portId';
  }

  // --- MENU CHỌN TRẠNG THÁI ---
  void _showPortOptions(Map<String, dynamic> port) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text("Cổng ${port['name']}"),
            subtitle: const Text("Chọn trạng thái mới"),
            leading: const Icon(Icons.settings),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: const Text("Sẵn sàng (Available)"),
            onTap: () {
              Navigator.pop(ctx); // Đóng menu trước
              _updatePortStatus(port['id'], 'available'); // Cập nhật sau
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_charging_full, color: Colors.blue),
            title: const Text("Đang sạc (Busy)"),
            onTap: () {
              Navigator.pop(ctx);
              _updatePortStatus(port['id'], 'busy');
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month, color: Colors.orange),
            title: const Text("Đã đặt lịch (Booked)"),
            onTap: () {
              Navigator.pop(ctx);
              _updatePortStatus(port['id'], 'booked');
            },
          ),
          ListTile(
            leading: const Icon(Icons.build, color: Colors.grey),
            title: const Text("Bảo trì / Sửa chữa (Maintenance)"),
            onTap: () {
              Navigator.pop(ctx);
              _updatePortStatus(port['id'], 'maintenance');
            },
          ),
        ],
      ),
    );
  }

  // --- [ĐÃ SỬA] HÀM CẬP NHẬT TRẠNG THÁI NGAY LẬP TỨC ---
  Future<void> _updatePortStatus(int portId, String status) async {
    // 1. Cập nhật giao diện NGAY LẬP TỨC (Optimistic UI)
    // Giúp người dùng thấy thay đổi liền mà không cần chờ Server
    setState(() {
      final index = _ports.indexWhere((p) => p['id'] == portId);
      if (index != -1) {
        // Tạo bản sao để tránh lỗi reference, cập nhật status mới vào list đang hiển thị
        final updatedPort = Map<String, dynamic>.from(_ports[index]);
        updatedPort['status'] = status;
        _ports[index] = updatedPort;
      }
    });

    try {
      // 2. Sau đó mới gửi lệnh lên Server (chạy ngầm)
      await _supabase.from('ports').update({'status': status}).eq('id', portId);

      // Không cần gọi _reloadData() nữa vì Stream sẽ tự động đồng bộ sau,
      // hoặc nếu mạng chậm thì UI đã đúng nhờ bước 1 rồi.
    } catch (e) {
      // Nếu lỗi thì báo và tải lại dữ liệu gốc (Rollback)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi cập nhật: $e")));
        _reloadData();
      }
    }
  }

  Future<void> _handleBooking(int bookingId, String status) async {
    await _service.updateBookingStatus(bookingId, status);
    if (mounted) {
      String msg = "";
      if (status == 'confirmed') msg = "Đã duyệt lịch hẹn!";
      if (status == 'cancelled') msg = "Đã hủy lịch hẹn.";
      if (status == 'completed') msg = "Đã hoàn tất đơn hàng!";

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: status == 'confirmed' || status == 'completed' ? Colors.green : Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stationName),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "Sơ đồ", icon: Icon(Icons.grid_view)),
            Tab(text: "Chờ duyệt", icon: Icon(Icons.pending_actions)),
            Tab(text: "Lịch hẹn", icon: Icon(Icons.event_available)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reloadData),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => AuthScreen(
                      isVietnamese: widget.isVietnamese,
                      toggleLanguage: widget.toggleLanguage
                  )), (route) => false
              );
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          // Sơ đồ
          RefreshIndicator(onRefresh: _reloadData, child: _buildPortGrid()),
          // Chờ duyệt
          _buildPendingRequests(),
          // Lịch hẹn
          _buildConfirmedList(),
        ],
      ),
    );
  }

  // --- SƠ ĐỒ TRẠM ---
  Widget _buildPortGrid() {
    if (_ports.isEmpty) {
      return ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Chưa có trụ sạc.")))]);
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.3),
        itemCount: _ports.length,
        itemBuilder: (ctx, index) {
          final port = _ports[index];
          final status = port['status'];

          // Màu mặc định (Sẵn sàng)
          Color bgColor = Colors.green[100]!;
          Color borderColor = Colors.green;
          Color iconColor = Colors.green[800]!;
          String statusText = "SẴN SÀNG";

          if (status == 'busy') {
            bgColor = Colors.blue[100]!;
            borderColor = Colors.blue;
            iconColor = Colors.blue[800]!;
            statusText = "ĐANG SẠC";
          }
          else if (status == 'booked') {
            bgColor = Colors.orange[100]!;
            borderColor = Colors.orange;
            iconColor = Colors.orange[800]!;
            statusText = "ĐÃ ĐẶT LỊCH";
          }
          else if (status == 'maintenance') {
            bgColor = Colors.grey[300]!;
            borderColor = Colors.grey;
            iconColor = Colors.grey[700]!;
            statusText = "BẢO TRÌ";
          }

          return InkWell(
            onTap: () => _showPortOptions(port),
            child: Container(
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor, width: 2)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(port['type'] == 'Car' ? Icons.directions_car : Icons.two_wheeler, size: 40, color: iconColor),
                  const SizedBox(height: 8),
                  Text(port['name'] ?? 'Port ${port['id']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(statusText, style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingRequests() {
    if (_stationId == null) return const SizedBox();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.getPendingBookingsStream(_stationId!),
      builder: (context, snapshot) => _buildBookingList(snapshot, isPending: true),
    );
  }

  Widget _buildConfirmedList() {
    if (_stationId == null) return const SizedBox();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.getConfirmedBookingsStream(_stationId!),
      builder: (context, snapshot) => _buildBookingList(snapshot, isPending: false),
    );
  }

  Widget _buildBookingList(AsyncSnapshot<List<Map<String, dynamic>>> snapshot, {required bool isPending}) {
    if (snapshot.hasError) return Center(child: Text("Lỗi: ${snapshot.error}"));
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

    final bookings = snapshot.data ?? [];
    if (bookings.isEmpty) {
      return Center(child: Text(isPending ? "Không có yêu cầu mới." : "Không có lịch hẹn sắp tới."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: bookings.length,
      itemBuilder: (ctx, index) {
        final booking = bookings[index];
        final start = DateTime.parse(booking['start_time']).toLocal();
        final end = DateTime.parse(booking['end_time']).toLocal();
        final format = DateFormat('HH:mm dd/MM');
        final portName = _getPortName(booking['port_id']);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isPending ? Colors.orange.withOpacity(0.5) : Colors.green.withOpacity(0.5))),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isPending ? "Yêu cầu đặt lịch" : "Lịch hẹn sạc", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: isPending ? Colors.orange[100] : Colors.green[100],
                          borderRadius: BorderRadius.circular(8)
                      ),
                      child: Text(isPending ? "Chờ duyệt" : "Đã duyệt",
                          style: TextStyle(color: isPending ? Colors.orange[800] : Colors.green[800], fontWeight: FontWeight.bold, fontSize: 12)
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.ev_station, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text("Vị trí: $portName", style: const TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text("${format.format(start)}  ➜  ${format.format(end)}"),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: isPending
                      ? [
                    OutlinedButton(
                      onPressed: () => _handleBooking(booking['id'], 'cancelled'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("Từ chối"),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _handleBooking(booking['id'], 'confirmed'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      child: const Text("DUYỆT"),
                    ),
                  ]
                      : [
                    TextButton(
                      onPressed: () => _handleBooking(booking['id'], 'cancelled'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("Khách vắng mặt"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _handleBooking(booking['id'], 'completed'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text("HOÀN TẤT"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}