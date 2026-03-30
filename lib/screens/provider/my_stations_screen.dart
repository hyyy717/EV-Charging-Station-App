import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/charging_station.dart';
import '../../services/supabase_service.dart'; // Import service
import 'add_station_screen.dart';

class MyStationsScreen extends StatefulWidget {
  final bool isVietnamese;

  const MyStationsScreen({super.key, required this.isVietnamese});

  @override
  State<MyStationsScreen> createState() => _MyStationsScreenState();
}

class _MyStationsScreenState extends State<MyStationsScreen> {
  final _supabase = Supabase.instance.client;
  final _supabaseService = SupabaseService(); // Khởi tạo service

  List<ChargingStation> _stations = [];
  bool _isLoading = true;

  String _searchKeyword = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMyStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMyStations() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final data = await _supabase
          .from('stations')
          .select('*, ports(*)')
          .eq('owner_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _stations = (data as List).map((item) => ChargingStation.fromMap(item)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editStation(ChargingStation station) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => AddStationScreen(
          isVietnamese: widget.isVietnamese,
          stationToEdit: station,
        ),
      ),
    );
    if (result == true) _fetchMyStations();
  }

  Future<void> _deleteStation(int id) async {
    // ... (Code xóa giữ nguyên)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận"),
        content: const Text("Bạn có chắc muốn xóa trạm này không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xóa", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.from('stations').delete().eq('id', id);
      _fetchMyStations();
    }
  }

  // --- [MỚI] HÀM HIỂN THỊ DANH SÁCH QUẢN LÝ ---
  void _showManagers(int stationId, String stationName) async {
    // Hiển thị loading tạm thời
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // Lấy dữ liệu từ Service
    final managers = await _supabaseService.getStationManagers(stationId);

    // Đóng loading
    if (mounted) Navigator.of(context).pop();

    // Hiển thị kết quả
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Quản lý: $stationName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: managers.isEmpty
                ? const Text("Chưa có tài khoản quản lý nào.")
                : ListView.builder(
              shrinkWrap: true,
              itemCount: managers.length,
              itemBuilder: (ctx, index) => ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: Text(managers[index], style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Đóng")),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredStations = _stations.where((s) {
      final keyword = _searchKeyword.toLowerCase();
      return s.name.toLowerCase().contains(keyword) || s.address.toLowerCase().contains(keyword);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.isVietnamese ? "Trạm Sạc Của Tôi" : "My Stations")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.isVietnamese ? "Tìm kiếm trạm..." : "Search stations...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchKeyword.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchKeyword = ""); })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                filled: true, fillColor: Colors.white,
              ),
              onChanged: (val) => setState(() => _searchKeyword = val),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredStations.isEmpty
                ? Center(child: Text(widget.isVietnamese ? "Không tìm thấy kết quả." : "No results found."))
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 80),
              itemCount: filteredStations.length,
              itemBuilder: (ctx, index) {
                final station = filteredStations[index];

                Color statusColor = Colors.grey;
                String statusText = "Chờ duyệt";
                if (station.status == 'active') {
                  statusColor = Colors.green;
                  statusText = "Đang hoạt động";
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: statusColor,
                      child: const Icon(Icons.ev_station, color: Colors.white),
                    ),
                    title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(station.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      onSelected: (value) {
                        if (value == 'info') _showManagers(station.id, station.name); // Gọi hàm xem info
                        if (value == 'edit') _editStation(station);
                        if (value == 'delete') _deleteStation(station.id);
                      },
                      itemBuilder: (ctx) => [
                        // [MỚI] Mục xem thông tin Manager
                        const PopupMenuItem(
                            value: 'info',
                            child: Row(children: [Icon(Icons.people, color: Colors.purple), SizedBox(width: 8), Text("Xem tài khoản QL")])
                        ),
                        const PopupMenuItem(
                            value: 'edit',
                            child: Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text("Sửa")])
                        ),
                        const PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text("Xóa")])
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => AddStationScreen(isVietnamese: widget.isVietnamese)),
          );
          if (result == true) _fetchMyStations();
        },
        backgroundColor: Colors.green,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}