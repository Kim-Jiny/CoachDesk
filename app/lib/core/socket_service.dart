import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_client.dart';
import 'constants.dart';

class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  io.Socket? get socket => _socket;

  /// Callbacks invoked each time the socket connects (including reconnects).
  final List<VoidCallback> _onConnectCallbacks = [];

  /// Derives the Socket.IO URL from the API base URL by removing /api suffix
  String get _socketUrl {
    String url = AppConstants.apiBaseUrl;
    if (url.endsWith('/api')) {
      url = url.substring(0, url.length - 4);
    }
    return url;
  }

  void connect() {
    if (_isConnected && _socket != null) return;

    final token = ApiClient.getAccessToken();
    if (token == null) return;

    final mode = ApiClient.isMemberMode ? 'member' : 'admin';

    // Dispose old socket to prevent leaks
    _socket?.dispose();
    _socket = null;
    _isConnected = false;

    _socket = io.io(
      _socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token, 'mode': mode})
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      debugPrint('[Socket] Connected (mode: $mode)');
      // Notify all registered connect callbacks
      for (final cb in _onConnectCallbacks) {
        cb();
      }
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      debugPrint('[Socket] Disconnected');
    });

    _socket!.onConnectError((error) {
      _isConnected = false;
      debugPrint('[Socket] Connection error: $error');
    });

    _socket!.onError((error) {
      debugPrint('[Socket] Error: $error');
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    debugPrint('[Socket] Disposed');
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  void off(String event, [Function(dynamic)? handler]) {
    if (handler != null) {
      _socket?.off(event, handler);
    } else {
      _socket?.off(event);
    }
  }

  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  /// Register a callback that fires on every socket connect.
  /// If already connected, fires immediately as well.
  void addConnectCallback(VoidCallback cb) {
    _onConnectCallbacks.add(cb);
    if (_isConnected && _socket != null) {
      cb();
    }
  }

  void removeConnectCallback(VoidCallback cb) {
    _onConnectCallbacks.remove(cb);
  }
}
