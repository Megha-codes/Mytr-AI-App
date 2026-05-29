enum RangeStatus { inRange, high, hyper, low, hypo }

class GlucoseReading {
  final int valueMgdl;
  final DateTime timestamp;
  final String? trend;
  final String? trendArrow;
  final bool isContinuous;
  final bool isLive;
  final String? deviceType;
  final List<Map<String, dynamic>> alerts;

  const GlucoseReading({
    required this.valueMgdl,
    required this.timestamp,
    this.trend,
    this.trendArrow,
    required this.isContinuous,
    required this.isLive,
    this.deviceType,
    this.alerts = const [],
  });

  bool get supportsTrend => isContinuous && trendArrow != null;

  RangeStatus getRangeStatus() {
    for (final alert in alerts) {
      switch (alert['type']) {
        case 'HYPO':
          return RangeStatus.hypo;
        case 'HYPER':
          return RangeStatus.hyper;
        case 'HIGH':
          return RangeStatus.high;
        case 'LOW':
          return RangeStatus.low;
      }
    }
    return RangeStatus.inRange;
  }

  factory GlucoseReading.fromJson(Map<String, dynamic> json) {
    final isLive = json['is_live'] as bool? ?? false;
    return GlucoseReading(
      valueMgdl: (json['value'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      trend: json['trend'] as String?,
      trendArrow: json['trend_arrow'] as String?,
      isContinuous: isLive,
      isLive: isLive,
      deviceType: json['device_type'] as String?,
      alerts: (json['alerts'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [],
    );
  }
}
