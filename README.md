# flutter_fluxio_sdk

Cliente Flutter de una sala Fluxio. Recibe el `token` y el `serverUrl` (`wss://`) que ya entregó el servidor de la aplicación. No pide ni guarda la API key de la organización.

La cámara entra apagada y el micrófono encendido, salvo que quien llama pase otros valores. `livekit_client` vive en este paquete.

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
