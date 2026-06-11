/// Which physical CGM device is connected (or attempted).
enum CgmDeviceType {
  libreTwo,
  libreThree,
  manual,
}

extension CgmDeviceTypeLabel on CgmDeviceType {
  String get displayName => switch (this) {
    CgmDeviceType.libreTwo   => 'FreeStyle Libre 2',
    CgmDeviceType.libreThree => 'FreeStyle Libre 3',
    CgmDeviceType.manual     => 'Manual Entry',
  };

  bool get isContinuous => this != CgmDeviceType.manual;
}
