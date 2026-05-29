import 'cgm_device_type.dart';

/// Data returned by the backend on a successful CGM connection.
class CgmConnectedInfo {
  final CgmDeviceType deviceType;

  /// "ACTIVE" | "NO_ACTIVE_SENSOR" | "EXPIRED" | "WARMING_UP"
  final String sensorStatus;

  final int?      lastReadingMgdl;
  final DateTime? lastReadingTime;
  
  /// Trend direction: "STABLE" | "RISING" | "FALLING" | etc.
  final String?   trend;
  
  final int?      expiryDaysRemaining;
  final DateTime? sensorExpiryDate;

  const CgmConnectedInfo({
    required this.deviceType,
    required this.sensorStatus,
    this.lastReadingMgdl,
    this.lastReadingTime,
    this.trend,
    this.expiryDaysRemaining,
    this.sensorExpiryDate,
  });

  bool get isSensorActive => sensorStatus == 'ACTIVE';
  bool get isExpired      => sensorStatus == 'EXPIRED';
  bool get noSensor       => sensorStatus == 'NO_ACTIVE_SENSOR';

  factory CgmConnectedInfo.fromJson(Map<String, dynamic> json) {
    return CgmConnectedInfo(
      deviceType:       _parseDeviceType(json['device_type'] as String?),
      sensorStatus:     json['sensor_status']    as String? ?? 'ACTIVE',
      lastReadingMgdl:  json['last_reading_value'] as int?,
      lastReadingTime:  json['last_reading_time'] != null
          ? DateTime.tryParse(json['last_reading_time'] as String)
          : null,
      trend:            json['trend'] as String?,
      expiryDaysRemaining: json['sensor_days_remaining'] as int?,
      sensorExpiryDate: json['sensor_expiry_date'] != null
          ? DateTime.tryParse(json['sensor_expiry_date'] as String)
          : null,
    );
  }

  static CgmDeviceType _parseDeviceType(String? raw) => switch (raw) {
    'DEXCOM_G6'  => CgmDeviceType.dexcomG6,
    'DEXCOM_G7'  => CgmDeviceType.dexcomG7,
    'LIBRE_2'    => CgmDeviceType.libreTwo,
    'LIBRE_3'    => CgmDeviceType.libreThree,
    'MANUAL'     => CgmDeviceType.manual,
    _            => CgmDeviceType.dexcomG7, // safe fallback
  };
}
