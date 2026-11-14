/// Credentials the app server already minted. This object has no API key.
class FluxioJoin {
  FluxioJoin({
    required String token,
    required String serverUrl,
    this.video = false,
    this.audio = true,
    this.watch = false,
  }) : token = _token(token),
       serverUrl = _serverUrl(serverUrl);

  /// Audience join. The token must be a viewer token. Camera and microphone stay off.
  FluxioJoin.watch({
    required String token,
    required String serverUrl,
  }) : token = _token(token),
       serverUrl = _serverUrl(serverUrl),
       video = false,
       audio = false,
       watch = true;

  final String token;
  final String serverUrl;

  /// Camera stays off unless the caller turns it on before joining.
  final bool video;

  /// Microphone stays on unless the caller turns it off before joining.
  final bool audio;

  /// True when this join only watches a stream and must not publish.
  final bool watch;

  static String _token(String raw) {
    final token = raw.trim();
    if (token.isEmpty || token.contains(RegExp(r'\s'))) {
      throw ArgumentError('token');
    }
    return token;
  }

  static String _serverUrl(String raw) {
    var url = raw.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('serverUrl');
    }
    return url;
  }
}
