import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkStatus { online, offline }

class ConnectivityNotifier extends Notifier<NetworkStatus> {
  @override
  NetworkStatus build() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.none)) {
        state = NetworkStatus.offline;
      } else {
        state = NetworkStatus.online;
      }
    });
    return NetworkStatus.online;
  }
}

final connectivityProvider = NotifierProvider<ConnectivityNotifier, NetworkStatus>(() {
  return ConnectivityNotifier();
});
