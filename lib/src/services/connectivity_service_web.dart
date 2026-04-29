import 'package:flutter/foundation.dart';
import 'package:aiq_core_data_store_flutter/aiq_core_data_store_flutter.dart';
import 'connectivity_service.dart';

/// Web-safe no-op stub for [ConnectivityService].
///
/// On web, connectivity is assumed to be always online. The browser
/// handles connectivity natively; this stub avoids calling the
/// connectivity_plus native check/subscribe methods that may fail on web.
class ConnectivityServiceWeb extends ConnectivityService {
  @override
  bool get isOnline => true;

  @override
  int get pendingWrites => 0;

  @override
  Future<ConnectivityService> init({WriteQueue? writeQueue}) async {
    debugPrint('[ConnectivityServiceWeb] connectivity stub active on web — assuming online');
    return this;
  }

  @override
  void updatePendingCount(int count) {
    // no-op on web
  }

  @override
  void dispose() {
    // no-op on web
  }
}
