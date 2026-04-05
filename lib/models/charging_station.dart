import 'package:tram_sac/models/port.dart';

class ChargingStation {
  final int id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? provider;
  final String? status;
  final String? imageUrl; // [THÊM MỚI] Biến lưu link ảnh
  final List<Port>? ports;

  ChargingStation({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.provider,
    this.status,
    this.imageUrl, // [THÊM MỚI]
    this.ports,
  });

  factory ChargingStation.fromMap(Map<String, dynamic> map) {
    return ChargingStation(
      id: map['id'] ?? 0,
      name: map['name'] ?? 'Không có tên',
      address: map['address'] ?? 'Không có địa chỉ',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      provider: map['provider'],
      status: map['status'],
      imageUrl: map['image_url'], // [THÊM MỚI] Map với cột image_url trong CSDL
      ports: map['ports'] != null
          ? (map['ports'] as List).map((x) => Port.fromMap(x)).toList()
          : [],
    );
  }
}