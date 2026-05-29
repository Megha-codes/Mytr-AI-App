/// Which physical CGM device is connected (or attempted).
enum CgmDeviceType {
  dexcomG6,
  dexcomG7,
  libreTwo,
  libreThree,
  manual,
}

extension CgmDeviceTypeLabel on CgmDeviceType {
  String get displayName => switch (this) {
    CgmDeviceType.dexcomG6   => 'Dexcom G6',
    CgmDeviceType.dexcomG7   => 'Dexcom G7',
    CgmDeviceType.libreTwo   => 'FreeStyle Libre 2',
    CgmDeviceType.libreThree => 'FreeStyle Libre 3',
    CgmDeviceType.manual     => 'Manual Entry',
  };

  bool get isContinuous => this != CgmDeviceType.manual;
}
