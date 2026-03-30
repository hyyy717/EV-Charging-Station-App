import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';

class BookingHistoryScreen extends StatefulWidget {
  final bool isVietnamese;

  const BookingHistoryScreen({super.key, required this.isVietnamese});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBookings();
  }

  Future<void> _fetchBookings() async {
    final data = await _supabaseService.getUserBookings();
    if (mounted) {
      setState(() {
        _bookings = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVietnamese ? 'Lịch sử đặt chỗ' : 'Booking History'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookings.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text(widget.isVietnamese ? 'Bạn chưa có lịch đặt nào.' : 'No bookings found.'),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _bookings.length,
        itemBuilder: (ctx, index) {
          final booking = _bookings[index];
          final station = booking['stations'];
          final port = booking['ports'];

          // Parse thời gian
          final startTime = DateTime.parse(booking['start_time']).toLocal();
          final endTime = DateTime.parse(booking['end_time']).toLocal();
          final DateFormat timeFormat = DateFormat('HH:mm - dd/MM/yyyy');

          // Xác định trạng thái
          String status = booking['status'] ?? 'confirmed';
          Color statusColor = Colors.green;
          String statusText = widget.isVietnamese ? 'Đã đặt' : 'Confirmed';

          if (status == 'cancelled') {
            statusColor = Colors.red;
            statusText = widget.isVietnamese ? 'Đã hủy' : 'Cancelled';
          } else if (endTime.isBefore(DateTime.now())) {
            statusColor = Colors.grey;
            statusText = widget.isVietnamese ? 'Hoàn thành' : 'Completed';
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          station?['name'] ?? 'Unknown Station',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.ev_station, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text("Cổng: ${port?['type'] ?? 'Standard'}"),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        "${timeFormat.format(startTime)} \n-> ${timeFormat.format(endTime)}",
                        style: const TextStyle(height: 1.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    station?['address'] ?? '',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}