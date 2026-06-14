import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A live subscription. Call [unsubscribe] to stop; on a broadcast channel use
/// [send] to publish and [track] to update presence.
class Subscription {
  final void Function() unsubscribe;
  final void Function(String event, Object? payload) send;
  final void Function(Map<String, dynamic> state) track;
  const Subscription({
    required this.unsubscribe,
    required this.send,
    required this.track,
  });
}

class _Sub {
  final String ref;
  final String kind; // postgres | mongo | broadcast
  final String? table;
  final String? collection;
  final String? channel;
  final List<String>? events;
  final Object? filter;
  final bool presence;
  final Map<String, dynamic>? state;
  final void Function(Map<String, dynamic>) onMessage;
  _Sub(this.ref, this.kind, this.onMessage,
      {this.table,
      this.collection,
      this.channel,
      this.events,
      this.filter,
      this.presence = false,
      this.state});
}

/// One WebSocket per client, multiplexing many subscriptions. Reconnects and
/// re-subscribes automatically. Speaks the ichibase realtime wire protocol.
class RealtimeClient {
  final String _baseUrl;
  final String? Function() _getToken;

  WebSocketChannel? _channel;
  bool _open = false;
  bool _connecting = false;
  bool _closedByUser = false;
  int _refSeq = 0;
  int _reconnectAttempts = 0;
  Timer? _heartbeat;
  final Map<String, _Sub> _subs = {};
  final List<String> _outbox = [];

  RealtimeClient(this._baseUrl, this._getToken);

  /// Subscribe to postgres/mongo changes or a broadcast channel. [kind] is
  /// `'postgres'` (set [table]), `'mongo'` (set [collection]), or
  /// `'broadcast'` (set [channel]).
  Subscription subscribe({
    required String kind,
    required void Function(Map<String, dynamic> message) onMessage,
    String? table,
    String? collection,
    String? channel,
    List<String>? events,
    Object? filter,
    bool presence = false,
    Map<String, dynamic>? state,
  }) {
    final ref = 's${++_refSeq}';
    _subs[ref] = _Sub(ref, kind, onMessage,
        table: table,
        collection: collection,
        channel: channel,
        events: events,
        filter: filter,
        presence: presence,
        state: state);
    _ensureConnected();
    if (_open) _sendSubscribe(ref);

    return Subscription(
      unsubscribe: () {
        _subs.remove(ref);
        if (_open) _send({'type': 'unsubscribe', 'ref': ref});
        if (_subs.isEmpty) disconnect();
      },
      send: (event, payload) {
        if (kind != 'broadcast') {
          throw StateError('send() is only valid on a broadcast subscription');
        }
        _send({'type': 'broadcast', 'channel': channel, 'event': event, 'payload': payload});
      },
      track: (s) {
        if (kind != 'broadcast') {
          throw StateError('track() is only valid on a broadcast subscription');
        }
        _send({'type': 'presence', 'channel': channel, 'state': s});
      },
    );
  }

  /// Close the socket and drop all subscriptions.
  void disconnect() {
    _closedByUser = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    _open = false;
    _channel?.sink.close();
    _channel = null;
  }

  // ── internals ──────────────────────────────────────────────────────
  Future<void> _ensureConnected() async {
    if (_channel != null || _connecting) return;
    _connecting = true;
    _closedByUser = false;
    final token = _getToken();
    final wsBase = _baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final url = '$wsBase/realtime${token != null ? '?token=${Uri.encodeQueryComponent(token)}' : ''}';
    final ch = WebSocketChannel.connect(Uri.parse(url));
    _channel = ch;
    try {
      await ch.ready;
    } catch (_) {
      _connecting = false;
      _channel = null;
      if (!_closedByUser && _subs.isNotEmpty) _scheduleReconnect();
      return;
    }
    _connecting = false;
    _open = true;
    _reconnectAttempts = 0;
    ch.stream.listen(_onFrame, onError: (_) {}, onDone: _onDone, cancelOnError: false);
    for (final ref in _subs.keys) {
      _sendSubscribe(ref);
    }
    for (final raw in _outbox) {
      ch.sink.add(raw);
    }
    _outbox.clear();
    _startHeartbeat();
  }

  void _onDone() {
    _open = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _channel = null;
    if (!_closedByUser && _subs.isNotEmpty) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final delayMs = (1000 * (1 << _reconnectAttempts)).clamp(1000, 15000).toInt();
    _reconnectAttempts++;
    Timer(Duration(milliseconds: delayMs), () {
      if (!_closedByUser && _subs.isNotEmpty) _ensureConnected();
    });
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
  }

  void _sendSubscribe(String ref) {
    final s = _subs[ref];
    if (s == null) return;
    final msg = <String, dynamic>{'type': 'subscribe', 'ref': ref, 'kind': s.kind};
    if (s.kind == 'postgres') {
      msg['table'] = s.table;
      if (s.events != null) msg['events'] = s.events;
      if (s.filter != null) msg['filter'] = s.filter;
    } else if (s.kind == 'mongo') {
      msg['collection'] = s.collection;
      if (s.events != null) msg['events'] = s.events;
      if (s.filter != null) msg['filter'] = s.filter;
    } else {
      msg['channel'] = s.channel;
      if (s.presence) msg['presence'] = true;
      if (s.state != null) msg['state'] = s.state;
    }
    _send(msg);
  }

  void _send(Map<String, dynamic> msg) {
    final raw = jsonEncode(msg);
    if (_open && _channel != null) {
      _channel!.sink.add(raw);
    } else {
      _outbox.add(raw);
    }
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> m;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      m = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final type = m['type'];
    if (type == 'change') {
      for (final s in _subs.values) {
        if ((s.kind == 'postgres' && m['table'] == _qualify(s.table)) ||
            (s.kind == 'mongo' && m['collection'] == s.collection)) {
          s.onMessage(m);
        }
      }
    } else if (type == 'broadcast') {
      for (final s in _subs.values) {
        if (s.kind == 'broadcast' && m['channel'] == s.channel) s.onMessage(m);
      }
    } else if (type == 'presence_state' || type == 'presence_diff') {
      for (final s in _subs.values) {
        if (s.kind == 'broadcast' && (m['channel'] == s.channel || m['channel'] == null)) {
          s.onMessage(m);
        }
      }
    }
    // subscribed / pong / token_refreshed / error — ignored here.
  }

  static String? _qualify(String? table) {
    if (table == null) return null;
    return table.contains('.') ? table : 'public.$table';
  }
}
