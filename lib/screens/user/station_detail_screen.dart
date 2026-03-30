import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Cần import intl
import '../../models/charging_station.dart';
import '../../models/port.dart';
import '../../services/supabase_service.dart';

class StationDetailScreen extends StatefulWidget {
  final ChargingStation station;
  final bool isAdmin;

  const StationDetailScreen({
    super.key,
    required this.station,
    required this.isAdmin,
  });

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isDeleting = false;

  // --- HÀM DỊCH TRẠNG THÁI & MÀU SẮC ---
  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return {'text': 'Sẵn sàng', 'color': Colors.green, 'canBook': true};
      case 'busy':
        return {'text': 'Đang sạc', 'color': Colors.red, 'canBook': false};
      case 'maintenance':
        return {'text': 'Bảo trì', 'color': Colors.grey, 'canBook': false};
      case 'booked':
        return {'text': 'Đã đặt', 'color': Colors.orange, 'canBook': false};
      default:
        return {'text': status, 'color': Colors.black, 'canBook': false};
    }
  }

  // Hàm dịch loại xe
  String _translateType(String type) {
    if (type.toLowerCase() == 'car') return 'Ô tô';
    if (type.toLowerCase() == 'bike') return 'Xe máy';
    return type;
  }

  Future<void> _confirmAndDelete() async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận Xóa'),
        content: Text('Bạn có chắc chắn muốn xóa trạm sạc ${widget.station.name} không?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('XÓA', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (shouldDelete == true) {
      setState(() => _isDeleting = true);
      try {
        await _supabaseService.deleteStation(widget.station.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa thành công.'), backgroundColor: Colors.green));
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: ${e.toString()}'), backgroundColor: Colors.red));
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  void _showBookingDialog(Port port) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => BookingBottomSheet(
        stationId: widget.station.id,
        port: port,
        stationName: widget.station.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.station.name),
        actions: [
          if (widget.isAdmin && !_isDeleting)
            IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), onPressed: _confirmAndDelete),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoCard(),
              const SizedBox(height: 24),
              _buildPortsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      // [SỬA MỚI] Dùng ClipRRect để bo góc cho ảnh và toàn bộ nội dung
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HIỂN THỊ ẢNH TRẠM SẠC TẠI ĐÂY ---
            if (widget.station.imageUrl != null && widget.station.imageUrl!.isNotEmpty)
              Image.network(
                widget.station.imageUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(height: 100, color: Colors.grey[200], child: const Center(child: Icon(Icons.broken_image, color: Colors.grey))),
              ),
            // -------------------------------------

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.station.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _infoRow(Icons.location_on_outlined, widget.station.address),
                  const SizedBox(height: 8),
                  _infoRow(Icons.business_outlined, 'Nhà cung cấp: ${widget.station.provider ?? 'Không rõ'}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortsSection() {
    final ports = widget.station.ports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Danh sách cổng sạc', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (ports == null || ports.isEmpty)
          const Center(child: Text('Không có dữ liệu cổng sạc.', style: TextStyle(color: Colors.grey)))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ports.length,
            itemBuilder: (context, index) => _portListItem(ports[index]),
          ),
      ],
    );
  }

  Widget _portListItem(Port port) {
    // Lấy thông tin hiển thị (Màu sắc, Text tiếng Việt)
    final statusInfo = _getStatusInfo(port.status);
    final String statusText = statusInfo['text'];
    final Color statusColor = statusInfo['color'];
    final bool canBook = statusInfo['canBook'];

    final String typeText = _translateType(port.type);

    // Parse ID
    int? portIdInt = int.tryParse(port.portID);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Icon loại xe
            Icon(
                port.type.toLowerCase() == 'car' ? Icons.directions_car : Icons.two_wheeler,
                color: Colors.blueGrey[700],
                size: 36
            ),
            const SizedBox(width: 12),

            // Thông tin cổng
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      port.name.isNotEmpty ? port.name : 'Cổng ${port.portID}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                  Text(typeText, style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)
                    ),
                  ),
                ],
              ),
            ),

            // Nút Đặt Lịch (Chỉ hiện khi Sẵn sàng)
            if (canBook && portIdInt != null)
              ElevatedButton(
                onPressed: () => _showBookingDialog(port),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('Đặt lịch'),
              )
            else
            // Nếu bận/bảo trì -> Hiện chữ xám
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  statusText == 'Bảo trì' ? 'Đang bảo trì' : 'Đang bận',
                  style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [Icon(icon, size: 20, color: Colors.grey), const SizedBox(width: 10), Expanded(child: Text(text))]);
  }
}

// --- POPUP ĐẶT LỊCH (Đã sửa giao diện dùng Card thay vì BoxDecoration) ---
class BookingBottomSheet extends StatefulWidget {
  final int stationId;
  final Port port;
  final String stationName;

  const BookingBottomSheet({super.key, required this.stationId, required this.port, required this.stationName});

  @override
  State<BookingBottomSheet> createState() => _BookingBottomSheetState();
}

class _BookingBottomSheetState extends State<BookingBottomSheet> {
  final SupabaseService _service = SupabaseService();
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay.now().replacing(hour: TimeOfDay.now().hour + 1);
  bool _isLoading = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _startTime : _endTime);
    if (picked != null) setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  Future<void> _submitBooking() async {
    setState(() => _isLoading = true);

    final startDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startTime.hour, _startTime.minute);
    final endDateTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _endTime.hour, _endTime.minute);

    // Validate
    if (endDateTime.isBefore(startDateTime) || endDateTime.isAtSameMomentAs(startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giờ kết thúc phải sau giờ bắt đầu!'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
      return;
    }

    if (startDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể đặt lịch trong quá khứ!'), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
      return;
    }

    // Gửi yêu cầu đặt lịch
    final success = await _service.createBooking(
      stationId: widget.stationId,
      portId: int.parse(widget.port.portID),
      startTime: startDateTime,
      endTime: endDateTime,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context);
        // Thông báo thành công
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Gửi yêu cầu thành công! Vui lòng chờ quản lý duyệt.'),
            backgroundColor: Colors.green
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đặt lịch thất bại. Vui lòng thử lại.'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Đặt lịch - ${widget.stationName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Cổng: ${widget.port.name}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),

          // Chọn Ngày
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
            child: ListTile(
              title: const Text('Ngày đặt'),
              trailing: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              leading: const Icon(Icons.calendar_today, color: Colors.green),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 12),

          // Chọn Giờ
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickTime(true),
                  child: Card( // Dùng Card để bao bọc
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text('Bắt đầu', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(_startTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _pickTime(false),
                  child: Card( // Dùng Card để bao bọc
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text('Kết thúc', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(_endTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
            onPressed: _submitBooking,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('GỬI YÊU CẦU ĐẶT LỊCH', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}