import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tram_sac/models/charging_station.dart';
import 'package:tram_sac/services/supabase_service.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:screen_protector/screen_protector.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../auth/authenticator_setup_screen.dart';
// --- IMPORT CÁC MÀN HÌNH CON ---
import 'station_detail_screen.dart';
import '../auth/auth_screen.dart';
import '../provider/add_station_screen.dart';
import '../admin/station_list_screen.dart';
import 'booking_history_screen.dart';
import '../admin/admin_users_screen.dart';
import '../common/notification_screen.dart';
import '../provider/my_stations_screen.dart';
import '../common/general_info_screen.dart';
// -------------------------------

class MapScreen extends StatefulWidget {
  final bool isVietnamese;
  final VoidCallback toggleLanguage;

  const MapScreen({
    super.key,
    required this.isVietnamese,
    required this.toggleLanguage,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final SupabaseService _supabaseService = SupabaseService();
  final MapController _mapController = MapController();
  final TextEditingController _searchTextController = TextEditingController();

  List<ChargingStation> _allStations = [];
  List<ChargingStation> _searchSuggestions = [];
  bool _isLoading = true;
  String? _errorMessage;

  bool _isAdmin = false;
  String _userEmail = 'Đang tải...';
  String? _avatarUrl;
  bool _isProvider = false;

  String _searchQuery = "";
  bool _filterCar = true;
  bool _filterBike = true;
  bool _onlyAvailable = false;

  final Distance _distance = const Distance();

  bool _isConnected = true;
  bool _isVpnActive = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  late RealtimeChannel _stationsChannel;
  late RealtimeChannel _portsChannel;

  bool _isControlsExpanded = false;

  @override
  void initState() {
    super.initState();
    _initializeMap();

    // 1. Lắng nghe thay đổi bảng STATIONS
    _stationsChannel = Supabase.instance.client
        .channel('public:stations')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'stations',
      callback: (payload) {
        _initializeMap();
      },
    )
        .subscribe();

    // 2. Lắng nghe thay đổi bảng PORTS
    _portsChannel = Supabase.instance.client
        .channel('public:ports')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'ports',
      callback: (payload) {
        print("Phát hiện thay đổi trạng thái trụ sạc -> Reload Map");
        _initializeMap();
      },
    )
        .subscribe();

    _checkUserRole();
    _checkInitialConnection();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    _secureScreen();
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_stationsChannel);
    Supabase.instance.client.removeChannel(_portsChannel);

    _mapController.dispose();
    _searchTextController.dispose();
    _connectivitySubscription?.cancel();
    _clearSecureScreen();
    super.dispose();
  }

  Future<void> _checkUserRole() async {
    try {
      final profile = await _supabaseService.getCurrentUserProfile();
      if (mounted && profile != null) {
        setState(() {
          _isAdmin = profile['role'] == 'admin';
          _isProvider = profile['role'] == 'provider';
          _userEmail = profile['email'] ?? profile['username'] ?? 'User';
          _avatarUrl = profile['avatar_url'];
          _errorMessage = null;
        });
      }
    } catch (e) {
      // Bắt lỗi âm thầm để không làm sập luồng chạy của UI
      print("Lỗi khi lấy thông tin Profile: $e");
    }
  }

  Future<void> _checkInitialConnection() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) _updateConnectionStatus(results);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final bool isCurrentlyConnected = !results.contains(ConnectivityResult.none);
    final bool isVpnCurrentlyActive = results.contains(ConnectivityResult.vpn);
    if (mounted) {
      setState(() {
        _isConnected = isCurrentlyConnected;
        _isVpnActive = isVpnCurrentlyActive;
      });
    }
  }

  Future<void> _secureScreen() async {
    try { await ScreenProtector.preventScreenshotOn(); } catch (e) {}
  }

  Future<void> _clearSecureScreen() async {
    try { await ScreenProtector.preventScreenshotOff(); } catch (e) {}
  }

  // --- HÀM CHỌN VÀ UPLOAD AVATAR ---
  Future<void> _pickAndUploadAvatar() async {
    // 1. ÁP DỤNG Ý TƯỞNG CỦA BẠN: Ép kích thước ảnh tối đa là 500x500 pixel
    final XFile? pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 500,  // [MỚI] Chiều rộng tối đa
      maxHeight: 500, // [MỚI] Chiều cao tối đa
    );

    if (pickedFile != null) {
      // Hiện loading
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Gọi hàm upload
        final newUrl = await _supabaseService.uploadAvatar(File(pickedFile.path), user.id);

        // Tắt loading TRƯỚC khi hiện thông báo
        if (mounted) Navigator.pop(context);

        if (newUrl != null && mounted) {
          // THÀNH CÔNG
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật Avatar thành công!'), backgroundColor: Colors.green));
        } else if (mounted) {
          // [MỚI] BÁO LỖI ĐỎ NẾU THẤT BẠI THAY VÌ IM LẶNG
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi: Cập nhật thất bại. Hãy kiểm tra lại Database!'), backgroundColor: Colors.red));
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    }
  }

  Future<void> _initializeMap() async {
    if (!mounted) return;

    // Đảm bảo bật vòng xoay khi bắt đầu gọi dữ liệu
    setState(() {
      _isLoading = true;
    });

    try {
      List<ChargingStation> data = await _supabaseService.getAllStations();
      if (mounted) {
        setState(() {
          _allStations = data;
        });
      }
    } catch (e) {
      print("Lỗi tải trạm sạc: $e");
      if (mounted) {
        setState(() {
          _errorMessage = widget.isVietnamese ? "Lỗi tải dữ liệu: $e" : "Error loading data: $e";
        });
        // [CỰC KỲ QUAN TRỌNG] Báo lỗi ra màn hình để người dùng biết
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      // [BẮT BUỘC] Tắt vòng xoay trong finally để đảm bảo 100% nó biến mất
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<ChargingStation> _getFilteredStations() {
    return _allStations.where((station) {
      final nameLower = station.name.toLowerCase();
      final addressLower = station.address.toLowerCase();
      final queryLower = _searchQuery.toLowerCase();
      bool matchesKeyword = nameLower.contains(queryLower) || addressLower.contains(queryLower);
      if (!matchesKeyword) return false;

      final ports = station.ports ?? [];
      bool hasCar = ports.any((p) => p.type == 'Car');
      bool hasBike = ports.any((p) => p.type == 'Bike');
      bool matchesType = false;
      if (_filterCar && hasCar) matchesType = true;
      if (_filterBike && hasBike) matchesType = true;
      if (!_filterCar && !_filterBike) matchesType = false;
      if (!matchesType) return false;

      if (_onlyAvailable) {
        bool hasAvailablePort = ports.any((p) => p.status == 'available');
        if (!hasAvailablePort) return false;
      }
      return true;
    }).toList();
  }

  void _onSearchTextChanged(String query) {
    setState(() {
      _searchQuery = query;
    });

    if (query.isEmpty) {
      setState(() => _searchSuggestions = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    List<ChargingStation> matches = _allStations.where((s) {
      return s.name.toLowerCase().contains(lowerQuery) ||
          s.address.toLowerCase().contains(lowerQuery);
    }).toList();

    final center = _mapController.camera.center;
    matches.sort((a, b) {
      final distA = _distance.as(LengthUnit.Meter, center, LatLng(a.latitude, a.longitude));
      final distB = _distance.as(LengthUnit.Meter, center, LatLng(b.latitude, b.longitude));
      return distA.compareTo(distB);
    });

    setState(() {
      _searchSuggestions = matches.take(5).toList();
    });
  }

  void _onSuggestionSelected(ChargingStation station) {
    _mapController.move(LatLng(station.latitude, station.longitude), 15.0);
    FocusScope.of(context).unfocus();
    setState(() {
      _searchQuery = station.name;
      _searchTextController.text = station.name;
      _searchSuggestions = [];
    });
  }

  List<Marker> _buildMarkers() {
    return _getFilteredStations().map((station) {
      bool isFullyBusy = false;
      if (station.ports != null && station.ports!.isNotEmpty) {
        isFullyBusy = !station.ports!.any((p) => p.status == 'available');
      }

      return Marker(
        width: 80.0,
        height: 80.0,
        point: LatLng(station.latitude, station.longitude),
        child: GestureDetector(
          onTap: () async {
            final bool? shouldRefresh = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => StationDetailScreen(station: station, isAdmin: _isAdmin),
              ),
            );
            if (shouldRefresh == true) _initializeMap();
          },
          child: Column(
            children: [
              Icon(
                  Icons.ev_station,
                  color: isFullyBusy ? Colors.orange : Colors.green,
                  size: 40
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
                child: Text(station.name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              )
            ],
          ),
        ),
      );
    }).toList();
  }

  void _navigateToAddStation() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => AddStationScreen(isVietnamese: widget.isVietnamese)),
    );
    if (result == true) _initializeMap();
  }

  void _moveMap(double latDelta, double longDelta) {
    const double step = 2; // Bước di chuyển
    final currentCenter = _mapController.camera.center;
    final currentZoom = _mapController.camera.zoom;
    double scaleFactor = 100.0 / math.pow(2, currentZoom);

    final newCenter = LatLng(
        currentCenter.latitude + (latDelta * step * scaleFactor),
        currentCenter.longitude + (longDelta * step * scaleFactor)
    );

    _mapController.move(newCenter, currentZoom);
  }

  void _zoomMap(double change) {
    final currentCenter = _mapController.camera.center;
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(currentCenter, currentZoom + change);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCount = _getFilteredStations().length;
    const LatLng initialCenter = LatLng(16.0545, 108.2022);
    final bool showFab = _isAdmin || _isProvider;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildAppDrawer(),
      backgroundColor: Colors.white, // Nền trắng sạch
      resizeToAvoidBottomInset: false, // Tránh lỗi layout khi bàn phím hiện

      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: showFab
          ? Padding(
        padding: const EdgeInsets.only(bottom: 60.0), // Đẩy FAB lên tránh bị che
        child: FloatingActionButton(
          onPressed: _navigateToAddStation,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          tooltip: widget.isVietnamese ? 'Thêm Trạm' : 'Add Station',
          child: const Icon(Icons.add_location_alt),
        ),
      )
          : null,

      body: Stack(
        children: [
          // 1. LAYOUT CHÍNH (Header + Map)
          Column(
            children: [
              // Header Gradient (Khoảng trống để Stack đè lên)
              SizedBox(height: 130),

              // MAP Container
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(0, 20, 0, 0), // Đẩy map xuống chút
                  decoration: const BoxDecoration(
                    color: Colors.white,
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 5.5,
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.tram_sac'),
                      MarkerLayer(markers: _buildMarkers()),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 2. HEADER GRADIENT (Giống AuthScreen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140, // Chiều cao Header
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade800, Colors.green.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Row(
                          children: [
                            const Icon(Icons.ev_station_rounded, color: Colors.white, size: 24),
                            const SizedBox(width: 8),
                            const Text(
                              'SEVEN CHARGING',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. SEARCH BAR (Nằm đè lên ranh giới Header và Map)
          Positioned(
            top: 100, // Vị trí đè lên
            left: 20,
            right: 20,
            child: Column(
              children: [
                _buildFloatingSearchBox(),
                // Hiển thị gợi ý tìm kiếm
                if (_searchSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 1)],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchSuggestions.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final station = _searchSuggestions[index];
                        final dist = _distance.as(LengthUnit.Kilometer,
                            _mapController.camera.center,
                            LatLng(station.latitude, station.longitude)
                        );
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on, color: Colors.redAccent),
                          title: Text(station.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(station.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text("${dist.toStringAsFixed(1)} km", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          onTap: () => _onSuggestionSelected(station),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 4. TEXT KẾT QUẢ TÌM KIẾM
          Positioned(
            top: 170, // Dưới Search Bar
            left: 24,
            child: Text(
              widget.isVietnamese ? 'Tìm thấy $filteredCount trạm sạc' : 'Found $filteredCount stations',
              style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),

          // 5. NÚT ĐIỀU KHIỂN (Zoom/Move)
          Positioned(
            right: 20,
            bottom: 30,
            child: _buildCrossStyleControls(),
          ),

          // 6. OVERLAY BẢO MẬT
          _buildBlockingOverlay(),
        ],
      ),
    );
  }

  // --- MENU CẬP NHẬT MỚI (Drawer) ---
  Widget _buildAppDrawer() {
    final user = Supabase.instance.client.auth.currentUser;

    return Drawer(
      child: Container(
        color: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // --- GIAO DIỆN HEADER PROFILE (DÙNG STREAMBUILDER) ---
            if (user != null)
              StreamBuilder<Map<String, dynamic>>(
                // Lắng nghe Stream Profile từ Service
                stream: _supabaseService.streamUserProfile(user.id),
                builder: (context, snapshot) {
                  // Mặc định ban đầu
                  String currentEmail = _userEmail;
                  String? currentAvatarUrl = _avatarUrl;

                  if (snapshot.hasData && snapshot.data != null) {
                    final data = snapshot.data!;
                    currentEmail = data['email'] ?? data['username'] ?? 'User';
                    currentAvatarUrl = data['avatar_url'];
                  }

                  return Container(
                    padding: const EdgeInsets.only(top: 50, right: 20, bottom: 20, left: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade800, Colors.green.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _pickAndUploadAvatar,
                              child: CircleAvatar(
                                radius: 35,
                                backgroundColor: Colors.white,
                                // SỬ DỤNG LINK ẢNH TỪ STREAM
                                backgroundImage: currentAvatarUrl != null ? NetworkImage(currentAvatarUrl) : null,
                                child: currentAvatarUrl == null
                                    ? const Icon(Icons.person, size: 40, color: Colors.grey)
                                    : null,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 30, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(currentEmail, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(widget.isVietnamese ? 'Nhấn vào ảnh để đổi Avatar' : 'Tap image to change Avatar', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  );
                },
              ),
            // --- KẾT THÚC HEADER PROFILE ---

            // 1. GIỚI THIỆU DỊCH VỤ
            ExpansionTile(
              leading: const Icon(Icons.info_outline, color: Colors.blue),
              title: const Text("Giới thiệu dịch vụ", style: TextStyle(fontWeight: FontWeight.w600)),
              children: [
                _buildSubItem("SEVEN Charging là gì?", "intro_what"),
                _buildSubItem("Lợi ích khi đặt chỗ", "intro_benefit"),
                _buildSubItem("Đối tác của hệ thống", "intro_partner"),
              ],
            ),

            // 2. CHÍNH SÁCH & QUY ĐỊNH
            ExpansionTile(
              leading: const Icon(Icons.gavel, color: Colors.orange),
              title: const Text("Chính sách & Quy định", style: TextStyle(fontWeight: FontWeight.w600)),
              children: [
                _buildSubItem("Điều khoản sử dụng", "policy_terms"),
                _buildSubItem("Chính sách đặt chỗ", "policy_booking"),
                _buildSubItem("Quy định hủy đặt chỗ", "policy_cancel"),
                _buildSubItem("Quy định an toàn", "policy_safety"),
              ],
            ),

            // 3. CÂU HỎI THƯỜNG GẶP
            ExpansionTile(
              leading: const Icon(Icons.help_outline, color: Colors.purple),
              title: const Text("Câu hỏi thường gặp", style: TextStyle(fontWeight: FontWeight.w600)),
              children: [
                _buildSubItem("Làm sao biết trạm còn trống?", "faq_empty"),
                _buildSubItem("Có cần đặt trước không?", "faq_booking"),
                _buildSubItem("Thanh toán thế nào?", "faq_payment"),
                _buildSubItem("Hỗ trợ loại xe nào?", "faq_vehicle"),
              ],
            ),

            // 4. VỀ CHÚNG TÔI
            ExpansionTile(
              leading: const Icon(Icons.business, color: Colors.teal),
              title: const Text("Về chúng tôi", style: TextStyle(fontWeight: FontWeight.w600)),
              children: [
                _buildSubItem("Tầm nhìn", "about_vision"),
                _buildSubItem("Sứ mệnh", "about_mission"),
                _buildSubItem("Đội ngũ", "about_team"),
                _buildSubItem("Liên hệ hỗ trợ", "about_contact"),
              ],
            ),

            const Divider(),

            _buildDrawerItem(
              text: widget.isVietnamese ? 'Lịch sử đặt chỗ' : 'Booking History',
              icon: Icons.history,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => BookingHistoryScreen(isVietnamese: widget.isVietnamese)));
              },
            ),

            if (_isProvider) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Text(
                  widget.isVietnamese ? 'DÀNH CHO ĐỐI TÁC' : 'PARTNER PANEL',
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              _buildDrawerItem(
                text: widget.isVietnamese ? 'Trạm sạc của tôi' : 'My Stations',
                icon: Icons.list_alt,
                color: Colors.blue[800],
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => MyStationsScreen(isVietnamese: widget.isVietnamese)));
                },
              ),
              _buildDrawerItem(
                text: widget.isVietnamese ? 'Đăng ký Trạm Mới' : 'Register New Station',
                icon: Icons.add_business,
                color: Colors.green[700],
                onTap: () async {
                  Navigator.of(context).pop();
                  final result = await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => AddStationScreen(isVietnamese: widget.isVietnamese)));
                  if (result == true) _initializeMap();
                },
              ),
              _buildDrawerItem(
                text: widget.isVietnamese ? 'Cài đặt Bảo mật 2FA' : '2FA Security Setup',
                icon: Icons.qr_code_scanner,
                color: Colors.blueGrey[800],
                // [ĐÃ SỬA CHỖ NÀY]: Thêm 2 tham số arg1, arg2 để không bị lỗi arguments
                onTap: ([dynamic arg1, dynamic arg2]) {
                  Navigator.of(context).pop(); // Đóng menu
                  Navigator.push(context, MaterialPageRoute(builder: (ctx) => AuthenticatorSetupScreen(isVietnamese: widget.isVietnamese)));
                },
              ),
              _buildDrawerItem(
                text: widget.isVietnamese ? 'Thông báo hệ thống' : 'System Notifications',
                icon: Icons.notifications_active,
                color: Colors.red[700],
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => NotificationScreen(isVietnamese: widget.isVietnamese)));
                },
              ),
            ],

            if (_isAdmin) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Text(
                  widget.isVietnamese ? 'QUẢN TRỊ VIÊN' : 'ADMIN PANEL',
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              _buildDrawerItem(
                text: widget.isVietnamese ? 'Quản lý Trạm Sạc' : 'Manage Stations',
                icon: Icons.ev_station,
                color: Colors.blue[700],
                onTap: () async {
                  Navigator.of(context).pop();
                  final result = await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => StationListScreen(isVietnamese: widget.isVietnamese)));
                  if (result == true) _initializeMap();
                },
              ),
              _buildDrawerItem(
                text: widget.isVietnamese ? 'Duyệt Đối tác' : 'Approve Partners',
                icon: Icons.verified_user,
                color: Colors.orange[800],
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => AdminUsersScreen(isVietnamese: widget.isVietnamese)));
                },
              ),

              _buildDrawerItem(
                text: widget.isVietnamese ? 'Cài đặt Bảo mật 2FA' : '2FA Security Setup',
                icon: Icons.qr_code_scanner,
                color: Colors.blueGrey[800],
                onTap: () {
                  Navigator.of(context).pop(); // Đóng menu lại
                  Navigator.push(context, MaterialPageRoute(builder: (ctx) => AuthenticatorSetupScreen(isVietnamese: widget.isVietnamese)));
                },
              ),
            ],

            const SizedBox(height: 30),
            _buildDrawerItem(
              text: widget.isVietnamese ? 'Đăng xuất' : 'Logout',
              icon: Icons.logout,
              color: Colors.red,
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => AuthScreen(isVietnamese: widget.isVietnamese, toggleLanguage: widget.toggleLanguage)),
                      (route) => false,
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Helper để tạo mục con (Sub Item)
  Widget _buildSubItem(String title, String contentKey) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      contentPadding: const EdgeInsets.only(left: 50, right: 20),
      dense: true,
      onTap: () {
        Navigator.of(context).pop();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => GeneralInfoScreen(title: title, contentKey: contentKey),
          ),
        );
      },
    );
  }

  Widget _buildDrawerItem({required String text, IconData? icon, Color? color, bool hasArrow = false, required VoidCallback onTap}) {
    return ListTile(
      leading: icon != null ? Icon(icon, color: color ?? Colors.black87) : const SizedBox(width: 24),
      title: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: color ?? Colors.black87)),
      trailing: hasArrow ? const Icon(Icons.keyboard_arrow_down, color: Colors.black54) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      onTap: onTap,
    );
  }

  Widget _buildCrossStyleControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.bottomRight,
          child: SizedBox(
            height: _isControlsExpanded ? null : 0,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMiniBtn(Icons.add, () => _zoomMap(1.0), color: Colors.green),
                      const SizedBox(width: 8),
                      _buildCircleBtn(Icons.keyboard_arrow_up, () => _moveMap(1, 0)),
                      const SizedBox(width: 8),
                      _buildMiniBtn(Icons.remove, () => _zoomMap(-1.0), color: Colors.red),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCircleBtn(Icons.keyboard_arrow_left, () => _moveMap(0, -1)),
                      const SizedBox(width: 60),
                      _buildCircleBtn(Icons.keyboard_arrow_right, () => _moveMap(0, 1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildCircleBtn(Icons.keyboard_arrow_down, () => _moveMap(-1, 0)),
                ],
              ),
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: () {
            setState(() {
              _isControlsExpanded = !_isControlsExpanded;
            });
          },
          backgroundColor: Colors.white,
          child: Icon(
            _isControlsExpanded ? Icons.close : Icons.open_with,
            color: Colors.blue[800],
            size: 28,
          ),
        ),
      ],
    );
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback onPressed) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: onPressed,
          child: Icon(icon, color: Colors.grey[800], size: 32),
        ),
      ),
    );
  }

  Widget _buildMiniBtn(IconData icon, VoidCallback onPressed, {Color? color}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Icon(icon, color: color ?? Colors.grey[700], size: 24),
        ),
      ),
    );
  }

  Widget _buildFloatingSearchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchTextController,
              decoration: InputDecoration(
                  hintText: widget.isVietnamese ? 'Nhập tên hoặc địa chỉ...' : 'Enter name or address...',
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchTextController.clear();
                      _onSearchTextChanged("");
                    },
                  )
                      : null
              ),
              onChanged: _onSearchTextChanged,
            ),
          ),
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: Icon(Icons.filter_list, color: (_onlyAvailable || !_filterCar || !_filterBike) ? Colors.green : Colors.grey),
                onPressed: _showFilterDialog,
              ),
              if (_onlyAvailable || !_filterCar || !_filterBike)
                Container(margin: const EdgeInsets.only(top: 8, right: 8), width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))
            ],
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setStateDialog) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.isVietnamese ? 'Bộ lọc' : 'Filters', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          TextButton(
                              onPressed: () {
                                setState(() { _filterCar = true; _filterBike = true; _onlyAvailable = false; });
                                Navigator.pop(ctx);
                              },
                              child: Text(widget.isVietnamese ? 'Đặt lại' : 'Reset')
                          )
                        ],
                      ),
                      const Divider(),
                      CheckboxListTile(
                        title: Text(widget.isVietnamese ? 'Ô tô' : 'Car'),
                        secondary: const Icon(Icons.directions_car, color: Colors.blue),
                        value: _filterCar,
                        onChanged: (val) { setStateDialog(() => _filterCar = val ?? true); setState(() {}); },
                      ),
                      CheckboxListTile(
                        title: Text(widget.isVietnamese ? 'Xe máy' : 'Motorbike'),
                        secondary: const Icon(Icons.two_wheeler, color: Colors.orange),
                        value: _filterBike,
                        onChanged: (val) { setStateDialog(() => _filterBike = val ?? true); setState(() {}); },
                      ),
                      SwitchListTile(
                        title: Text(widget.isVietnamese ? 'Chỉ hiện trạm trống' : 'Available only'),
                        value: _onlyAvailable,
                        activeColor: Colors.green,
                        onChanged: (val) { setStateDialog(() => _onlyAvailable = val); setState(() {}); },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          child: Text(widget.isVietnamese ? 'ÁP DỤNG' : 'APPLY'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildBlockingOverlay() {
    String? message;
    IconData? icon;
    if (_isVpnActive) {
      message = widget.isVietnamese ? 'Phát hiện VPN/DNS đáng ngờ.' : 'Suspicious VPN/DNS detected.';
      icon = Icons.security;
    } else if (!_isConnected) {
      message = widget.isVietnamese ? 'Vui lòng kiểm tra kết nối internet.' : 'Check internet connection.';
      icon = Icons.wifi_off;
    }
    if (message == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 80),
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