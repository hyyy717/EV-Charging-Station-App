import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../models/charging_station.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class AddStationScreen extends StatefulWidget {
  final bool isVietnamese;
  final ChargingStation? stationToEdit;

  const AddStationScreen({
    super.key,
    required this.isVietnamese,
    this.stationToEdit,
  });

  @override
  State<AddStationScreen> createState() => _AddStationScreenState();
}

class _AddStationScreenState extends State<AddStationScreen> {
  final _formKey = GlobalKey<FormState>();
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = false;

  String _name = '';
  String _address = '';
  double? _latitude;
  double? _longitude;
  String _provider = '';

  int _carPorts = 0;
  int _bikePorts = 0;

  // Lưu số lượng cũ để so sánh
  int _oldCarPorts = 0;
  int _oldBikePorts = 0;

  // --- [THÊM MỚI] BIẾN XỬ LÝ ẢNH ---
  File? _selectedImage;
  String? _currentImageUrl;
  final ImagePicker _picker = ImagePicker();
  // ---------------------------------

  bool get _isEditing => widget.stationToEdit != null;
  String get _title => _isEditing
      ? (widget.isVietnamese ? 'Cập nhật Trạm Sạc' : 'Update Station')
      : (widget.isVietnamese ? 'Đăng ký Trạm Mới' : 'Register New Station');
  String get _buttonSave => widget.isVietnamese ? 'Gửi Yêu Cầu' : 'Submit Request';

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _name = widget.stationToEdit!.name;
      _address = widget.stationToEdit!.address;
      _provider = widget.stationToEdit!.provider ?? '';
      _latitude = widget.stationToEdit!.latitude;
      _longitude = widget.stationToEdit!.longitude;

      // --- [THÊM MỚI] LOAD ẢNH CŨ NẾU CÓ ---
      _currentImageUrl = widget.stationToEdit!.imageUrl;

      // Load số lượng trụ sạc hiện tại
      final ports = widget.stationToEdit!.ports ?? [];
      _carPorts = ports.where((p) => p.type == 'Car').length;
      _bikePorts = ports.where((p) => p.type == 'Bike').length;

      _oldCarPorts = _carPorts;
      _oldBikePorts = _bikePorts;
    }
  }

  // --- [THÊM MỚI] HÀM CHỌN ẢNH TỪ THƯ VIỆN ---
  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }
  // -------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isVietnamese ? 'Vui lòng nhập tọa độ.' : 'Please enter coordinates.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      // Kiểm tra xem có thay đổi số lượng không
      bool hasPortChange = (_carPorts != _oldCarPorts) || (_bikePorts != _oldBikePorts);

      // --- [THÊM MỚI] XỬ LÝ UPLOAD ẢNH LÊN SUPABASE ---
      String? finalImageUrl = _currentImageUrl;
      if (_selectedImage != null) {
        final fileName = 'station_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final uploadedUrl = await _supabaseService.uploadStationImage(_selectedImage!, fileName);
        if (uploadedUrl != null) {
          finalImageUrl = uploadedUrl;
        }
      }
      // ------------------------------------------------

      final stationData = {
        'name': _name,
        'address': _address,
        'latitude': _latitude,
        'longitude': _longitude,
        'provider': _provider.isEmpty ? null : _provider,
        'owner_id': userId,
        'image_url': finalImageUrl, // [THÊM MỚI] GẮN LINK ẢNH VÀO DỮ LIỆU LƯU
        // Nếu sửa mà có thay đổi port -> Set về Pending để Admin duyệt lại
        'status': (_isEditing && hasPortChange) ? 'pending' : (_isEditing ? 'active' : 'pending'),
      };

      int stationId;

      if (_isEditing) {
        // --- LOGIC SỬA ---
        await _supabaseService.updateStation(widget.stationToEdit!.id, stationData);
        stationId = widget.stationToEdit!.id;

        // Gọi hàm điều chỉnh số lượng port
        if (hasPortChange) {
          await _supabaseService.adjustPortQuantity(stationId, 'Car', _oldCarPorts, _carPorts);
          await _supabaseService.adjustPortQuantity(stationId, 'Bike', _oldBikePorts, _bikePorts);
        }

      } else {
        // --- LOGIC THÊM MỚI ---
        stationId = await _supabaseService.addStationAndReturnId(stationData);

        List<Map<String, dynamic>> portsToAdd = [];
        for (int i = 1; i <= _carPorts; i++) {
          portsToAdd.add({'station_id': stationId, 'type': 'Car', 'status': 'available', 'name': 'Ô tô $i'});
        }
        for (int i = 1; i <= _bikePorts; i++) {
          portsToAdd.add({'station_id': stationId, 'type': 'Bike', 'status': 'available', 'name': 'Xe máy $i'});
        }
        if (portsToAdd.isNotEmpty) {
          await _supabaseService.addBatchPorts(portsToAdd);
        }
      }

      if (mounted) {
        String msg = widget.isVietnamese ? 'Thành công!' : 'Success!';
        if (_isEditing && hasPortChange) {
          msg = widget.isVietnamese
              ? 'Cập nhật thành công! Trạm chờ duyệt lại do thay đổi cấu hình.'
              : 'Updated! Station pending approval due to config changes.';
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: ${e.toString()}'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isVietnamese ? "Thông tin Trạm" : "Station Info",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const SizedBox(height: 10),

              // --- [THÊM MỚI] KHU VỰC CHỌN ẢNH HIỂN THỊ TRÊN GIAO DIỆN ---
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: _selectedImage != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    )
                        : (_currentImageUrl != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(_currentImageUrl!, fit: BoxFit.cover),
                    )
                        : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 40, color: Colors.grey[500]),
                        const SizedBox(height: 8),
                        Text(widget.isVietnamese ? "Tải ảnh thực tế (Tùy chọn)" : "Upload image", style: TextStyle(color: Colors.grey[600])),
                      ],
                    )),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ----------------------------------------------------------

              TextFormField(
                initialValue: _name,
                decoration: InputDecoration(
                  labelText: widget.isVietnamese ? 'Tên trạm sạc' : 'Station Name',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.ev_station),
                ),
                validator: (val) => val == null || val.isEmpty ? (widget.isVietnamese ? 'Bắt buộc' : 'Required') : null,
                onSaved: (val) => _name = val!,
              ),
              const SizedBox(height: 12),

              TextFormField(
                initialValue: _address,
                decoration: InputDecoration(
                  labelText: widget.isVietnamese ? 'Địa chỉ' : 'Address',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.map),
                ),
                validator: (val) => val == null || val.isEmpty ? (widget.isVietnamese ? 'Bắt buộc' : 'Required') : null,
                onSaved: (val) => _address = val!,
              ),
              const SizedBox(height: 12),

              TextFormField(
                initialValue: _provider,
                decoration: InputDecoration(
                  labelText: widget.isVietnamese ? 'Tên đơn vị/Nhà cung cấp' : 'Provider Name',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.business),
                ),
                onSaved: (val) => _provider = val ?? '',
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _latitude?.toString(),
                      decoration: const InputDecoration(labelText: 'Vĩ độ (Lat)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => val == null || val.isEmpty ? '!' : null,
                      onSaved: (val) => _latitude = double.tryParse(val!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      initialValue: _longitude?.toString(),
                      decoration: const InputDecoration(labelText: 'Kinh độ (Long)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => val == null || val.isEmpty ? '!' : null,
                      onSaved: (val) => _longitude = double.tryParse(val!),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(thickness: 2),
              const SizedBox(height: 10),

              // --- PHẦN 2: CẤU HÌNH TRỤ SẠC (Luôn hiển thị) ---
              Text(
                widget.isVietnamese ? "Cấu hình Trụ Sạc" : "Charging Ports",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              ),
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                  child: Text(
                    widget.isVietnamese
                        ? "* Lưu ý: Thay đổi số lượng sẽ cần Admin duyệt lại trạm."
                        : "* Note: Changing quantity requires Admin re-approval.",
                    style: const TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
                  ),
                ),
              const SizedBox(height: 10),
              _buildCounter(
                  widget.isVietnamese ? "Trụ sạc Ô tô" : "Car Ports",
                  _carPorts,
                      (val) => setState(() => _carPorts = val),
                  Icons.directions_car
              ),
              _buildCounter(
                  widget.isVietnamese ? "Trụ sạc Xe máy" : "Bike Ports",
                  _bikePorts,
                      (val) => setState(() => _bikePorts = val),
                  Icons.two_wheeler
              ),

              const SizedBox(height: 30),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(_buttonSave, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounter(String label, int value, Function(int) onChanged, IconData icon) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey[700], size: 28),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () => value > 0 ? onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 30,
              child: Text(value.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.green),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ),
    );
  }
}