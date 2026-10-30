import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_fluxio_sdk/flutter_fluxio_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('joins with the camera off and never paints the token', (
    tester,
  ) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FluxioRoom(
          token: 'jwt-de-prueba',
          serverUrl: 'wss://live.example',
          engine: engine,
          builder: (context, snapshot, media) {
            return Column(
              children: [
                for (final peer in snapshot.peers)
                  Text(peer.identity, key: Key('persona-${peer.identity}')),
                Text(snapshot.microphoneOn ? 'mic-on' : 'mic-off'),
              ],
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(engine.opened?.video, isFalse);
    expect(engine.opened?.audio, isTrue);
    expect(engine.opened?.serverUrl, 'wss://live.example');
    expect(find.byKey(const Key('persona-Ana')), findsOneWidget);
    expect(find.text('mic-on'), findsOneWidget);
    expect(find.textContaining('jwt-de-prueba'), findsNothing);
    expect(find.textContaining('wss://'), findsNothing);
  });

  testWidgets('a drop is reported once', (tester) async {
    final engine = _FakeEngine();
    var drops = 0;
    await tester.pumpWidget(_room(engine, () => drops += 1));
    await tester.pump();
    engine.emit(FluxioDisconnect.dropped);
    await tester.pump();
    engine.emit(FluxioDisconnect.dropped);
    await tester.pump();
    expect(drops, 1);
  });

  testWidgets('hanging up is not a drop', (tester) async {
    final engine = _FakeEngine();
    var drops = 0;
    await tester.pumpWidget(_room(engine, () => drops += 1));
    await tester.pump();
    engine.emit(FluxioDisconnect.clientLeave);
    await tester.pump();
    expect(drops, 0);
  });
}

Widget _room(_FakeEngine engine, VoidCallback onDisconnected) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: FluxioRoom(
      token: 'jwt',
      serverUrl: 'wss://live.example',
      engine: engine,
      onDisconnected: onDisconnected,
      builder: (_, __, ___) => const SizedBox.shrink(),
    ),
  );
}

class _FakeEngine implements FluxioEngine {
  final _changes = StreamController<FluxioSnapshot>.broadcast();
  FluxioJoin? opened;
  var _microphoneOn = true;
  var _cameraOn = false;

  @override
  Stream<FluxioSnapshot> get changes => _changes.stream;

  @override
  Future<void> open(FluxioJoin join) async {
    opened = join;
    _microphoneOn = join.audio;
    _cameraOn = join.video;
    _changes.add(_connected());
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    _microphoneOn = enabled;
    _changes.add(_connected());
  }

  @override
  Future<void> setCamera(bool enabled) async {
    _cameraOn = enabled;
    _changes.add(_connected());
  }

  @override
  Future<void> close() async {}

  @override
  Widget? cameraView(String identity) => null;

  void emit(FluxioDisconnect reason) {
    _changes.add(
      FluxioSnapshot(
        link: FluxioLink.disconnected,
        peers: const [],
        microphoneOn: _microphoneOn,
        cameraOn: _cameraOn,
        disconnect: reason,
      ),
    );
  }

  FluxioSnapshot _connected() => FluxioSnapshot(
    link: FluxioLink.connected,
    microphoneOn: _microphoneOn,
    cameraOn: _cameraOn,
    peers: [
      FluxioPeer(
        identity: 'Ana',
        local: true,
        cameraOn: _cameraOn,
        microphoneOn: _microphoneOn,
      ),
    ],
  );
}
