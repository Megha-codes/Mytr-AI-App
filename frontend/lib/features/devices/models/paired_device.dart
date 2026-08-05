/// A paired desk device (architecture-v3.md §2.2) — the physical display
/// unit, distinct from CGM sensors/wearables managed elsewhere in Profile.
class PairedDevice {
  final String deviceId;
  final String? name;
  final String kind;
  final DateTime? lastSeenAt;
  final String? firmwareVersion;
  final DateTime? pairedAt;

  const PairedDevice({
    required this.deviceId,
    this.name,
    required this.kind,
    this.lastSeenAt,
    this.firmwareVersion,
    this.pairedAt,
  });

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name! : 'Desk device';

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      deviceId: json['device_id'] as String,
      name: json['name'] as String?,
      kind: json['kind'] as String? ?? 'DESK',
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at'] as String) : null,
      firmwareVersion: json['firmware_version'] as String?,
      pairedAt: json['paired_at'] != null ? DateTime.parse(json['paired_at'] as String) : null,
    );
  }
}
