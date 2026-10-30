/// Credentials the app server already minted. This object has no API key.
class FluxioJoin {
  FluxioJoin({
    required String token,
    required String serverUrl,
    this.video = false,
    this.audio = true,
  }) : token = _token(token),
       serverUrl = _serverUrl(serverUrl);

  final String token;
  final String serverUrl;

  /// Camera stays off unless the caller turns it on before joining.
  final bool video;

  /// Microphone stays on unless the caller turns it off before joining.
  final bool audio;

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
