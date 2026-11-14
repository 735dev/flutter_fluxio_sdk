import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import 'engine.dart';
import 'join.dart';
import 'snapshot.dart';

/// LiveKit transport. One instance connects once. A new room needs a new engine.
class LiveKitFluxioEngine implements FluxioEngine {
  LiveKitFluxioEngine({Room? room})
    : _room =
          room ??
          Room(
            roomOptions: RoomOptions(
              adaptiveStream: true,
              // Android: forcing the speakerphone here selects it explicitly and steals the audio from
              // Bluetooth or wired headphones. Routing is decided after connecting (_routeAudio).
              // iOS keeps the previous behaviour: the system already prefers connected headphones.
              defaultAudioOutputOptions: AudioOutputOptions(speakerOn: Platform.isIOS ? true : null),
            ),
          );

  final Room _room;
  EventsListener<RoomEvent>? _listener;
  final _changes = StreamController<FluxioSnapshot>.broadcast();
  var _microphoneOn = true;
  var _cameraOn = false;
  var _watch = false;
  var _opened = false;
  var _leftByUs = false;
  var _closed = false;
  var _reportedDisconnect = false;
  StreamSubscription<List<MediaDevice>>? _devices;
  var _deafened = false;

  @override
  Stream<FluxioSnapshot> get changes => _changes.stream;

  @override
  Future<void> open(FluxioJoin join) async {
    _watch = join.watch;
    _microphoneOn = join.watch ? false : join.audio;
    _cameraOn = join.watch ? false : join.video;
    // Voice-call audio keeps the microphone when Android sends the app to the background.
    await rtc.Helper.setAndroidAudioConfiguration(rtc.AndroidAudioConfiguration.communication);
    _listener ??= _room.createListener()
      ..on<RoomDisconnectedEvent>(_onDisconnected)
      ..on<ParticipantConnectedEvent>((_) => _emitConnected())
      ..on<ParticipantDisconnectedEvent>((_) => _emitConnected())
      ..on<ActiveSpeakersChangedEvent>((_) => _emitConnected())
      ..on<TrackSubscribedEvent>((event) {
        if (_deafened && event.track is AudioTrack) unawaited(event.track.disable());
        _emitConnected();
      })
      ..on<TrackUnsubscribedEvent>((_) => _emitConnected())
      ..on<TrackMutedEvent>((_) => _emitConnected())
      ..on<TrackUnmutedEvent>((_) => _emitConnected())
      ..on<LocalTrackPublishedEvent>((_) => _emitConnected())
      ..on<LocalTrackUnpublishedEvent>((_) => _emitConnected());
    try {
      await _room.connect(
        join.serverUrl,
        join.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: _microphoneOn),
          camera: TrackOption(enabled: _cameraOn),
        ),
      );
    } catch (_) {
      // A failed handshake is the thrown error. It is not a later drop.
      _reportedDisconnect = true;
      rethrow;
    }
    _opened = true;
    await _routeAudio();
    // Headphones connected or disconnected mid-call: route again (Bluetooth, then wired, then speaker).
    _devices ??= Hardware.instance.onDeviceChange.stream.listen((_) => _routeAudio());
    _emitConnected();
  }

  /// Android: Bluetooth headset first, then wired headset, otherwise the loudspeaker (a video call held at
  /// arm's length, not at the ear). Never fails the call over audio routing.
  Future<void> _routeAudio() async {
    if (!Platform.isAndroid || _closed) return;
    try {
      await rtc.Helper.setSpeakerphoneOnButPreferBluetooth();
    } catch (_) {}
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    if (_watch) return;
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
    _microphoneOn = enabled;
    _emitConnected();
  }

  @override
  Future<void> setCamera(bool enabled) async {
    if (_watch) return;
    await _room.localParticipant?.setCameraEnabled(enabled);
    _cameraOn = enabled;
    _emitConnected();
  }

  /// Deafen: stop hearing everybody else (voice channels). Not on [FluxioEngine] so fakes keep compiling.
  Future<void> setDeafened(bool deafened) async {
    _deafened = deafened;
    for (final remote in _room.remoteParticipants.values) {
      for (final publication in remote.audioTrackPublications) {
        final track = publication.track;
        if (track == null) continue;
        await (deafened ? track.disable() : track.enable());
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _leftByUs = true;
    try {
      await _room.disconnect();
    } finally {
      await _devices?.cancel();
      await _listener?.dispose();
      await _room.dispose();
    }
  }

  @override
  Widget? cameraView(String identity) {
    final participant = _participant(identity);
    if (participant == null) return null;
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (publication.source == TrackSource.camera &&
          track is VideoTrack &&
          !publication.muted) {
        return VideoTrackRenderer(
          track,
          fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }
    }
    return null;
  }

  Participant? _participant(String identity) {
    final local = _room.localParticipant;
    if (local?.identity == identity) return local;
    return _room.remoteParticipants[identity];
  }

  void _onDisconnected(RoomDisconnectedEvent event) {
    if (!_opened || _reportedDisconnect) return;
    _reportedDisconnect = true;
    final reason = _leftByUs || event.reason == DisconnectReason.clientInitiated
        ? FluxioDisconnect.clientLeave
        : FluxioDisconnect.dropped;
    if (!_changes.isClosed) {
      _changes.add(_snapshot(FluxioLink.disconnected, disconnect: reason));
    }
  }

  void _emitConnected() {
    if (!_opened || _reportedDisconnect) return;
    if (_room.connectionState != ConnectionState.connected) return;
    if (!_changes.isClosed) _changes.add(_snapshot(FluxioLink.connected));
  }

  FluxioSnapshot _snapshot(FluxioLink link, {FluxioDisconnect? disconnect}) {
    final peers = <FluxioPeer>[];
    final local = _room.localParticipant;
    if (local != null && local.identity.isNotEmpty) {
      peers.add(
        FluxioPeer(
          identity: local.identity,
          local: true,
          cameraOn: _cameraOn,
          microphoneOn: _microphoneOn,
          speaking: local.isSpeaking,
        ),
      );
    }
    final remotes = _room.remoteParticipants.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    for (final remote in remotes) {
      if (remote.identity.isEmpty) continue;
      peers.add(
        FluxioPeer(
          identity: remote.identity,
          local: false,
          cameraOn: _hasCamera(remote),
          microphoneOn: _hasMicrophone(remote),
          speaking: remote.isSpeaking,
        ),
      );
    }
    return FluxioSnapshot(
      link: link,
      peers: peers,
      microphoneOn: _microphoneOn,
      cameraOn: _cameraOn,
      disconnect: disconnect,
    );
  }

  bool _hasCamera(Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      if (publication.source == TrackSource.camera &&
          !publication.muted &&
          publication.subscribed) {
        return true;
      }
    }
    return false;
  }

  bool _hasMicrophone(Participant participant) {
    for (final publication in participant.audioTrackPublications) {
      if (publication.source == TrackSource.microphone &&
          !publication.muted &&
          publication.subscribed) {
        return true;
      }
    }
    return false;
  }
}
