import 'package:flutter_fluxio_sdk/flutter_fluxio_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a watch join never publishes', () {
    final join = FluxioJoin.watch(
      token: 'jwt',
      serverUrl: 'wss://live.example',
    );
    expect(join.watch, isTrue);
    expect(join.video, isFalse);
    expect(join.audio, isFalse);
  });

  test('camera starts off and the microphone starts on', () {
    final join = FluxioJoin(
      token: 'jwt',
      serverUrl: 'wss://live.example/sala/',
    );
    expect(join.token, 'jwt');
    expect(join.serverUrl, 'wss://live.example/sala');
    expect(join.video, isFalse);
    expect(join.audio, isTrue);
  });

  test('an empty token is rejected without echoing it', () {
    expect(
      () => FluxioJoin(token: '   ', serverUrl: 'wss://live.example'),
      throwsArgumentError,
    );
  });

  test('only a wss url without a query is accepted', () {
    expect(
      () => FluxioJoin(token: 'jwt', serverUrl: 'https://live.example'),
      throwsArgumentError,
    );
    expect(
      () => FluxioJoin(token: 'jwt', serverUrl: 'ws://live.example'),
      throwsArgumentError,
    );
    expect(
      () =>
          FluxioJoin(token: 'jwt', serverUrl: 'wss://user:secret@live.example'),
      throwsArgumentError,
    );
    expect(
      () =>
          FluxioJoin(token: 'jwt', serverUrl: 'wss://live.example/?token=jwt'),
      throwsArgumentError,
    );
  });
}
