enum FluxioLink { connecting, connected, disconnected }

/// Why the room ended. [clientLeave] is the user hanging up.
/// [dropped] is the socket closing on its own.
enum FluxioDisconnect { clientLeave, dropped }

class FluxioPeer {
  const FluxioPeer({
    required this.identity,
    required this.local,
    required this.cameraOn,
    required this.microphoneOn,
    this.speaking = false,
  });

  final String identity;
  final bool local;
  final bool cameraOn;
  final bool microphoneOn;

  /// Talking right now (LiveKit active speaker). Voice channels draw a ring with it; calls may ignore it.
  final bool speaking;
}

class FluxioSnapshot {
  const FluxioSnapshot({
    required this.link,
    required this.peers,
    required this.microphoneOn,
    required this.cameraOn,
    this.disconnect,
  });

  const FluxioSnapshot.connecting({
    required this.microphoneOn,
    required this.cameraOn,
  }) : link = FluxioLink.connecting,
       peers = const [],
       disconnect = null;

  final FluxioLink link;
  final List<FluxioPeer> peers;
  final bool microphoneOn;
  final bool cameraOn;
  final FluxioDisconnect? disconnect;
}
