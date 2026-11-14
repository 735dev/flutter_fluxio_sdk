import 'dart:convert';
import 'dart:io';

/// One saved RTMP destination. [urlMasked] never contains the stream key.
class FluxioDestination {
  const FluxioDestination({
    required this.id,
    required this.label,
    required this.urlMasked,
  });

  final String id;
  final String label;
  final String urlMasked;
}

/// Whether the room is broadcasting inside Fluxio and out to RTMP.
class FluxioStreamState {
  const FluxioStreamState({
    required this.internal,
    required this.externalActive,
    required this.layout,
    required this.destinations,
  });

  final bool internal;
  final bool externalActive;
  final String? layout;
  final List<FluxioDestination> destinations;
}

class FluxioApiException implements Exception {
  FluxioApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class FluxioRequest {
  FluxioRequest(this.method, this.path, {this.body, this.host = true});

  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final bool host;
}

typedef FluxioTransport = Future<({int status, String body})> Function(FluxioRequest call);

/// Host controls for a room stream. Keep [apiKey] and [hostKey] on a server
/// you control. A public app must not ship them.
class FluxioStreams {
  FluxioStreams({
    required String baseUrl,
    required this.apiKey,
    required this.hostKey,
    FluxioTransport? transport,
  }) : baseUrl = _base(baseUrl),
       _transport = transport;

  final String baseUrl;
  final String apiKey;
  final String hostKey;
  final FluxioTransport? _transport;

  Future<FluxioStreamState> status(String room) {
    return _state(FluxioRequest('GET', _stream(room)));
  }

  Future<FluxioStreamState> setInternal(String room, {required bool enabled}) {
    return _state(FluxioRequest('POST', '${_stream(room)}/internal', body: {'enabled': enabled}));
  }

  Future<FluxioStreamState> addDestination(
    String room, {
    required String label,
    required String url,
  }) {
    final cleanLabel = label.trim();
    final cleanUrl = url.trim();
    if (cleanLabel.isEmpty || cleanUrl.isEmpty) {
      throw ArgumentError('destino');
    }
    return _state(FluxioRequest('POST', '${_stream(room)}/destinations', body: {
      'label': cleanLabel,
      'url': cleanUrl,
    }));
  }

  Future<FluxioStreamState> removeDestination(String room, String destinationId) {
    return _state(FluxioRequest('DELETE', '${_stream(room)}/destinations/${Uri.encodeComponent(destinationId)}'));
  }

  Future<FluxioStreamState> startExternal(String room, {String layout = 'gallery'}) {
    if (layout != 'gallery' && layout != 'presentation') {
      throw ArgumentError('layout');
    }
    return _state(FluxioRequest('POST', '${_stream(room)}/external/start', body: {'layout': layout}));
  }

  Future<FluxioStreamState> stopExternal(String room) {
    return _state(FluxioRequest('POST', '${_stream(room)}/external/stop', body: {}));
  }

  /// Token for someone who only watches. Does not send the API key or the host key.
  Future<String> viewerToken({
    required String room,
    required String identity,
    required String name,
  }) async {
    final response = await _send(FluxioRequest(
      'POST',
      '/v1/sdk/token',
      body: {
        'room_name': room,
        'identity': identity,
        'name': name,
        'role': 'viewer',
      },
      host: false,
    ));
    final data = response['data'];
    if (data is! String || data.isEmpty) {
      throw FluxioApiException('No llegó el token de audiencia.');
    }
    return data;
  }

  String _stream(String room) => '/v1/sdk/rooms/${Uri.encodeComponent(room)}/stream';

  Future<FluxioStreamState> _state(FluxioRequest call) async {
    return _readState(await _send(call));
  }

  Future<Map<String, dynamic>> _send(FluxioRequest call) async {
    final raw = _transport == null ? await _http(call) : await _transport(call);
    final decoded = raw.body.isEmpty ? <String, dynamic>{} : jsonDecode(raw.body);
    if (raw.status < 200 || raw.status >= 300) {
      throw FluxioApiException(_message(decoded), statusCode: raw.status);
    }
    if (decoded is! Map<String, dynamic>) {
      throw FluxioApiException('Respuesta inválida.');
    }
    return decoded;
  }

  Future<({int status, String body})> _http(FluxioRequest call) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(call.method, Uri.parse('$baseUrl${call.path}'));
      if (call.host) {
        request.headers.set('X-API-Key', apiKey);
        request.headers.set('X-Host-Key', hostKey);
      }
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (call.body != null) {
        request.add(utf8.encode(jsonEncode(call.body)));
      }
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      return (status: response.statusCode, body: text);
    } finally {
      client.close(force: true);
    }
  }

  static String _base(String raw) {
    var url = raw.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      throw ArgumentError('baseUrl');
    }
    return url;
  }

  static String _message(Object? decoded) {
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is Map && detail['message'] is String) return detail['message'] as String;
      if (detail is String && detail.isNotEmpty) return detail;
    }
    return 'No se pudo completar la transmisión.';
  }

  static FluxioStreamState _readState(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map) throw FluxioApiException('Respuesta inválida.');
    final external = data['external'];
    final items = data['destinations'];
    return FluxioStreamState(
      internal: data['internal'] == true,
      externalActive: external is Map && external['active'] == true,
      layout: external is Map && external['layout'] is String ? external['layout'] as String : null,
      destinations: [
        if (items is List)
          for (final item in items)
            if (item is Map)
              FluxioDestination(
                id: '${item['id'] ?? ''}',
                label: '${item['label'] ?? ''}',
                urlMasked: '${item['url_masked'] ?? ''}',
              ),
      ],
    );
  }
}
