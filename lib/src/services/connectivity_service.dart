import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:aiq_core_data_store_flutter/aiq_core_data_store_flutter.dart';

class ConnectivityService {
  bool _isOnline = true;
  int _pendingWrites = 0;

  bool get isOnline => _isOnline;
  int get pendingWrites => _pendingWrites;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  WriteQueue? _writeQueue;

  Future<ConnectivityService> init({WriteQueue? writeQueue}) async {
    _writeQueue = writeQueue;
    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
    } catch (_) {
      _isOnline = true;
    }
    _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
    return this;
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final wasOffline = !_isOnline;
    _isOnline = online;
    if (online && wasOffline) {
      _flushPendingWrites();
    }
  }

  Future<void> _flushPendingWrites() async {
    if (_writeQueue == null) return;
    await _writeQueue!.flushAll();
    _pendingWrites = _writeQueue!.pendingCount;
  }

  void updatePendingCount(int count) {
    _pendingWrites = count;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
