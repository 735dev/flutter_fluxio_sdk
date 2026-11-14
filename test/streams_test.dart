import 'dart:convert';

import 'package:flutter_fluxio_sdk/flutter_fluxio_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('viewer token is requested without the host key', () async {
    final calls = <Map<String, Object?>>[];
    final api = FluxioStreams(
      baseUrl: 'https://dev.fluxiovideo.online/api/',
      apiKey: 'org-key',
      hostKey: 'host-key',
      transport: (call) async {
        calls.add({
          'method': call.method,
          'path': call.path,
          'host': call.host,
          'body': call.body,
        });
        return (status: 200, body: jsonEncode({'data': 'jwt-audiencia'}));
      },
    );

    final token = await api.viewerToken(room: 'sala 1', identity: 'ana', name: 'Ana');

    expect(token, 'jwt-audiencia');
    expect(calls.single['host'], isFalse);
    expect(calls.single['path'], '/v1/sdk/token');
    expect((calls.single['body'] as Map)['role'], 'viewer');
    expect(jsonEncode(calls), isNot(contains('org-key')));
    expect(jsonEncode(calls), isNot(contains('host-key')));
  });

  test('turning the room on reads the masked destination', () async {
    final api = FluxioStreams(
      baseUrl: 'https://dev.fluxiovideo.online/api',
      apiKey: 'org-key',
      hostKey: 'host-key',
      transport: (call) async {
        expect(call.host, isTrue);
        expect(call.path, '/v1/sdk/rooms/sala/stream/internal');
        return (
          status: 200,
          body: jsonEncode({
            'data': {
              'internal': true,
              'external': {'active': false, 'layout': null},
              'destinations': [
                {'id': 'd1', 'label': 'YouTube', 'url_masked': 'rtmps://a.rtmp.youtube.com/live2/••••key1'},
              ],
            },
          }),
        );
      },
    );

    final state = await api.setInternal('sala', enabled: true);

    expect(state.internal, isTrue);
    expect(state.externalActive, isFalse);
    expect(state.destinations.single.label, 'YouTube');
    expect(state.destinations.single.urlMasked, contains('••••'));
  });

  test('a server refusal surfaces the Spanish message', () async {
    final api = FluxioStreams(
      baseUrl: 'https://dev.fluxiovideo.online/api',
      apiKey: 'org-key',
      hostKey: 'host-key',
      transport: (_) async => (
        status: 403,
        body: jsonEncode({
          'detail': {'code': 'host_key_invalid', 'message': 'Llave del dueño inválida.'},
        }),
      ),
    );

    expect(
      () => api.status('sala'),
      throwsA(predicate((error) => error is FluxioApiException && error.message == 'Llave del dueño inválida.')),
    );
  });
}
