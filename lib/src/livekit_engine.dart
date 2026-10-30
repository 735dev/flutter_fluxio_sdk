import 'dart:async';

import 'package:flutter/widgets.dart' hide ConnectionState;
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
            roomOptions: const RoomOptions(
              adaptiveStream: true,
              defaultAudioOutputOptions: AudioOutputOptions(speakerOn: true),
            ),
          );

  final Room _room;
  EventsListener<RoomEvent>? _listener;
  final _changes = StreamController<FluxioSnapshot>.broadcast();
  var _microphoneOn = true;
  var _cameraOn = false;
  var _opened = false;
  var _leftByUs = false;
  var _closed = false;
  var _reportedDisconnect = false;

  @override
  Stream<FluxioSnapshot> get changes => _changes.stream;

  @override
  Future<void> open(FluxioJoin join) async {
    _microphoneOn = join.audio;
    _cameraOn = join.video;
    _listener ??= _room.createListener()
      ..on<RoomDisconnectedEvent>(_onDisconnected)
      ..on<ParticipantConnectedEvent>((_) => _emitConnected())
      ..on<ParticipantDisconnectedEvent>((_) => _emitConnected())
      ..on<TrackSubscribedEvent>((_) => _emitConnected())
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
          microphone: TrackOption(enabled: join.audio),
          camera: TrackOption(enabled: join.video),
        ),
      );
    } catch (_) {
      // A failed handshake is the thrown error. It is not a later drop.
      _reportedDisconnect = true;
      rethrow;
    }
    _opened = true;
    _emitConnected();
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
    _microphoneOn = enabled;
    _emitConnected();
  }

  @override
  Future<void> setCamera(bool enabled) async {
    await _room.localParticipant?.setCameraEnabled(enabled);
    _cameraOn = enabled;
    _emitConnected();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _leftByUs = true;
    try {
      await _room.disconnect();
    } finally {
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
        return VideoTrackRenderer(track);
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
