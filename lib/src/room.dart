import 'dart:async';

import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'join.dart';
import 'livekit_engine.dart';
import 'snapshot.dart';

/// Microphone and camera switches for the screen that draws the call.
class FluxioMedia {
  const FluxioMedia({
    required this.toggleMicrophone,
    required this.toggleCamera,
  });

  final Future<void> Function() toggleMicrophone;
  final Future<void> Function() toggleCamera;
}

typedef FluxioRoomBuilder =
    Widget Function(
      BuildContext context,
      FluxioSnapshot snapshot,
      FluxioMedia media,
    );

/// Joins the room and rebuilds [builder] as people arrive and leave.
///
/// The widget closes the engine when it leaves the tree. A drop calls
/// [onDisconnected] once. Hanging up does not.
class FluxioRoom extends StatefulWidget {
  const FluxioRoom({
    super.key,
    required this.token,
    required this.serverUrl,
    this.video = false,
    this.audio = true,
    this.engine,
    this.onDisconnected,
    required this.builder,
  });

  final String token;
  final String serverUrl;
  final bool video;
  final bool audio;
  final FluxioEngine? engine;
  final VoidCallback? onDisconnected;
  final FluxioRoomBuilder builder;

  @override
  State<FluxioRoom> createState() => _FluxioRoomState();
}

class _FluxioRoomState extends State<FluxioRoom> {
  late final FluxioEngine _engine;
  StreamSubscription<FluxioSnapshot>? _subscription;
  late FluxioSnapshot _snapshot;
  var _left = false;
  var _reported = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? LiveKitFluxioEngine();
    _snapshot = FluxioSnapshot.connecting(
      microphoneOn: widget.audio,
      cameraOn: widget.video,
    );
    _subscription = _engine.changes.listen((snapshot) {
      scheduleMicrotask(() => _onSnapshot(snapshot));
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _engine.open(
        FluxioJoin(
          token: widget.token,
          serverUrl: widget.serverUrl,
          video: widget.video,
          audio: widget.audio,
        ),
      );
    } catch (_) {
      // open() can fail before the first frame. Report it after initState.
      scheduleMicrotask(_reportDrop);
    }
  }

  void _onSnapshot(FluxioSnapshot snapshot) {
    if (!mounted || _left) return;
    setState(() => _snapshot = snapshot);
    if (snapshot.disconnect == FluxioDisconnect.dropped) _reportDrop();
  }

  void _reportDrop() {
    if (_reported || _left || !mounted) return;
    _reported = true;
    widget.onDisconnected?.call();
  }

  Future<void> _toggleMicrophone() =>
      _engine.setMicrophone(!_snapshot.microphoneOn);

  Future<void> _toggleCamera() => _engine.setCamera(!_snapshot.cameraOn);

  @override
  void dispose() {
    _left = true;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel().then((_) => _engine.close()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FluxioScope(
      engine: _engine,
      child: widget.builder(
        context,
        _snapshot,
        FluxioMedia(
          toggleMicrophone: _toggleMicrophone,
          toggleCamera: _toggleCamera,
        ),
      ),
    );
  }
}

class _FluxioScope extends InheritedWidget {
  const _FluxioScope({required this.engine, required super.child});

  final FluxioEngine engine;

  @override
  bool updateShouldNotify(_FluxioScope oldWidget) => true;
}

/// Picture for one person, or [placeholder] when the camera is off.
class FluxioPeerVideo extends StatelessWidget {
  const FluxioPeerVideo({
    super.key,
    required this.identity,
    required this.placeholder,
  });

  final String identity;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_FluxioScope>();
    return scope?.engine.cameraView(identity) ?? placeholder;
  }
}
