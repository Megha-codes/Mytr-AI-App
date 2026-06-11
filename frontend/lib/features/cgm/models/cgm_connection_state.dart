import 'cgm_device_type.dart';
import 'cgm_connected_info.dart';

/// Status of the CGM connection flow.
enum CgmConnectionStatus {
  /// Nothing started yet — device picker is idle.
  idle,

  /// User has tapped this tile but not yet started auth.
  selected,

  /// Connect bottom sheet is animating / credentials form is opening.
  connecting,

  /// Credentials have been forwarded; waiting for backend to validate with CGM API.
  validating,

  /// Connection established and backend confirmed a valid sensor/token.
  connected,

  /// An error occurred — see [CgmConnectionState.error].
  connectionFailed,

  /// User tapped "Disconnect" and is confirming.
  disconnecting,

  /// User confirmed disconnect. Credentials wiped.
  disconnected,
}

/// Structured error codes returned from the backend or detected client-side.
enum CgmConnectError {
  // Libre
  libreSetupNotDone,
  libreInvalidCredentials,
  libreAccountNotFound,
  libreNoActiveSensor,
  libreRegionMismatch,
  libreServerUnavailable,

  // General
  networkUnavailable,
  backendUnavailable,
  timeout,
}

extension CgmConnectErrorMessage on CgmConnectError {
  String get userMessage => switch (this) {
    CgmConnectError.libreSetupNotDone        => 'Connections not enabled. Please open your LibreLink app and enable LibreLinkUp under Connected Apps.',
    CgmConnectError.libreInvalidCredentials  => 'Incorrect LibreLinkUp credentials. Note: Use your LibreLinkUp account login, not your FreeStyle or Abbott account.',
    CgmConnectError.libreAccountNotFound     => 'No LibreLinkUp account found with this email. Please create a LibreLinkUp account first.',
    CgmConnectError.libreNoActiveSensor      => 'Your Libre sensor has expired. Please apply a new sensor and let it warm up (60 minutes) before reconnecting.',
    CgmConnectError.libreRegionMismatch      => 'Region configuration error. Please contact support.',
    CgmConnectError.libreServerUnavailable   => 'Abbott\'s servers are temporarily unavailable. Please try again in a few minutes.',

    CgmConnectError.networkUnavailable       => 'No internet connection. Please check your connection and try again.',
    CgmConnectError.backendUnavailable       => 'Something went wrong on our end. Please try again in a moment.',
    CgmConnectError.timeout                  => 'This is taking longer than expected. Check your connection and try again.',
  };
}

/// Full state for the CGM connection flow.
class CgmConnectionState {
  final CgmConnectionStatus status;
  final CgmDeviceType?      connectedDevice;
  final CgmConnectedInfo?   connectedInfo;
  final CgmConnectError?    error;
  final String?            sensorStatus; // 'ACTIVE', 'EXPIRED', 'WARNING_LOW', etc.

  const CgmConnectionState({
    this.status = CgmConnectionStatus.idle,
    this.connectedDevice,
    this.connectedInfo,
    this.error,
    this.sensorStatus,
  });

  CgmConnectionState copyWith({
    CgmConnectionStatus? status,
    CgmDeviceType?      connectedDevice,
    CgmConnectedInfo?   connectedInfo,
    CgmConnectError?    error,
    String?             sensorStatus,
  }) {
    return CgmConnectionState(
      status:          status          ?? this.status,
      connectedDevice: connectedDevice ?? this.connectedDevice,
      connectedInfo:   connectedInfo   ?? this.connectedInfo,
      error:           error           ?? this.error,
      sensorStatus:    sensorStatus    ?? this.sensorStatus,
    );
  }

  bool get isLoading =>
      status == CgmConnectionStatus.connecting ||
      status == CgmConnectionStatus.validating;
}
