class Port {
  final String portID; // ID trong code là String
  final String type;
  final String status;
  final String name; // Thêm tên hiển thị (Ví dụ: Ô tô 1)

  Port({
    required this.portID,
    required this.type,
    required this.status,
    required this.name,
  });

  factory Port.fromMap(Map<String, dynamic> map) {
    return Port(
      // Map cột 'id' (int) từ SQL sang 'portID' (String)
      portID: map['id']?.toString() ?? '',
      type: map['type'] ?? 'Không rõ',
      status: map['status'] ?? 'Bảo trì',
      name: map['name'] ?? 'Trụ sạc',
    );
  }
}