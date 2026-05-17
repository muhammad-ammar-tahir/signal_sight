import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  final String wsUrl;
  WebSocketChannel? _channel;
  final StreamController<String> _streamController = StreamController<String>.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;

  WebSocketService({this.wsUrl = 'ws://10.123.0.46:8000/ws'});

  Stream<String> get messages => _streamController.stream;

  void connect() async {
    if (_isConnected) return;
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          _streamController.add(message);
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
        onError: (error) {
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _streamController.close();
    _isConnected = false;
  }
}
