# flutter_fluxio_sdk

Cliente Flutter de una sala Fluxio. Recibe el `token` y el `serverUrl` (`wss://`) que ya entregó el servidor de la aplicación. No pide ni guarda la API key de la organización.

La cámara entra apagada y el micrófono encendido, salvo que quien llama pase otros valores. `livekit_client` vive en este paquete.

Quien solo mira usa `FluxioRoom.watch` con un token `role: viewer`. Ese ingreso no enciende cámara ni micrófono.

`FluxioStreams` habla con la API para encender la audiencia, guardar un RTMP y salir hacia fuera. La API key y la llave del dueño no van en una app pública: se usan desde un servidor. El token de audiencia (`viewerToken`) no envía esas llaves.

```dart
final control = FluxioStreams(
  baseUrl: 'https://dev.fluxiovideo.online/api',
  apiKey: apiKey,
  hostKey: hostKey,
);
await control.setInternal(sala, enabled: true);
final token = await control.viewerToken(room: sala, identity: 'ana', name: 'Ana');
```

La guía para un compañero está en [TRANSMISION.md](TRANSMISION.md).

```dart
FluxioRoom(
  token: credencial.token,
  serverUrl: credencial.serverUrl,
  video: camara,
  audio: microfono,
  onDisconnected: alCortar,
  builder: (context, sala, media) => /* la interfaz de la app */,
)
```
