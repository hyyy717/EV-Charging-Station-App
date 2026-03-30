import 'package:flutter/material.dart';
import '../../models/charging_station.dart';
import '../../services/supabase_service.dart';
import '../provider/add_station_screen.dart';
import 'create_manager_screen.dart';

class StationListScreen extends StatefulWidget {
  final bool isVietnamese;

  const StationListScreen({super.key, required this.isVietnamese});

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  late TabController _tabController;

  List<ChargingStation> _pendingStations = [];
  List<ChargingStation> _activeStations = [];
  bool _isLoading = true;

  String _searchKeyword = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchStations() async {
    setState(() => _isLoading = true);
    try {
      final pendingList = await _supabaseService.getStationsByStatus('pending');
      final activeList = await _supabaseService.getStationsByStatus('active');

      if (mounted) {
        setState(() {
          _pendingStations = pendingList;
          _activeStations = activeList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải dữ liệu: $e')));
      }
    }
  }

  Future<void> _approveStation(int id) async {
    try {
      await _supabaseService.updateStation(id, {'status': 'active'});

      final ownerId = await _supabaseService.getStationOwnerId(id);
      if (ownerId != null) {
        await _supabaseService.sendNotification(
          receiverId: ownerId,
          title: "Trạm sạc đã được duyệt! ✅",
          message: "Trạm sạc của bạn đã được Admin phê duyệt và hiện đang hiển thị trên bản đồ.",
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã duyệt trạm thành công!'), backgroundColor: Colors.green),
        );
        _fetchStations();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _deleteStation(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa trạm "$name"?\n(Hành động này sẽ từ chối duyệt hoặc xóa vĩnh viễn trạm)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('XÓA', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final ownerId = await _supabaseService.getStationOwnerId(id);
        await _supabaseService.deleteStation(id);

        if (ownerId != null) {
          await _supabaseService.sendNotification(
            receiverId: ownerId,
            title: "Thông báo về trạm sạc ⚠️",
            message: "Trạm sạc '$name' của bạn đã bị Admin từ chối phê duyệt hoặc xóa khỏi hệ thống.",
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa và gửi thông báo.'), backgroundColor: Colors.green));
          _fetchStations();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi xóa: $e')));
      }
    }
  }

  void _grantManager(ChargingStation station) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CreateManagerScreen(
          stationId: station.id,
          stationName: station.name,
          isVietnamese: widget.isVietnamese,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVietnamese ? 'Quản lý Trạm Sạc' : 'Manage Stations'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: widget.isVietnamese ? 'Chờ duyệt (${_pendingStations.length})' : 'Pending'),
            Tab(text: widget.isVietnamese ? 'Đang hoạt động' : 'Active'),
          ],
        ),
        actions: [
          // Nút này dùng để Test thêm trạm của Admin nếu cần
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => AddStationScreen(isVietnamese: widget.isVietnamese)),
              );
              if (result == true) _fetchStations();
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Tìm kiếm theo tên, địa chỉ...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchKeyword.isNotEmpty
                    ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchKeyword = "");
                    }
                )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (val) {
                setState(() => _searchKeyword = val);
              },
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_pendingStations, isPending: true),
                _buildList(_activeStations, isPending: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<ChargingStation> stations, {required bool isPending}) {
    final filteredList = stations.where((s) {
      final nameLower = s.name.toLowerCase();
      final addressLower = s.address.toLowerCase();
      final keyword = _searchKeyword.toLowerCase();
      return nameLower.contains(keyword) || addressLower.contains(keyword);
    }).toList();

    if (filteredList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 50, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(widget.isVietnamese ? 'Không tìm thấy trạm nào' : 'No stations found', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
      itemCount: filteredList.length,
      itemBuilder: (ctx, index) {
        final station = filteredList[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isPending ? Colors.orange : Colors.green,
              child: Icon(isPending ? Icons.hourglass_empty : Icons.ev_station, color: Colors.white),
            ),
            title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(station.address, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nút DUYỆT (Chỉ tab Chờ duyệt)
                if (isPending)
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 32),
                    onPressed: () => _approveStation(station.id),
                    tooltip: 'Duyệt',
                  ),

                // Nút CẤP MANAGER (Chỉ tab Active)
                if (!isPending)
                  IconButton(
                    icon: const Icon(Icons.manage_accounts, color: Colors.deepPurple),
                    onPressed: () => _grantManager(station),
                    tooltip: 'Cấp tài khoản quản lý',
                  ),

                // --- ĐÃ BỎ NÚT SỬA (EDIT) CHO ADMIN ---

                // Nút XÓA (Cả 2 tab)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteStation(station.id, station.name),
                  tooltip: 'Xóa trạm',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}