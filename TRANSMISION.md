# Transmitir con Fluxio

Guía para integrar la transmisión en otra aplicación. Hay dos salidas. Las dos gastan minutos de transmisión, no minutos de reunión.

- **Dentro de Fluxio.** Un enlace o una pantalla donde la gente solo mira. No entra a la reunión y no publica cámara ni micrófono.
- **Hacia fuera.** La misma sala sale a YouTube, Twitch u otra dirección `rtmp://` o `rtmps://`. Hasta 3 destinos.

Dev ya tiene la API. Producción no.

| Qué | Dev |
| --- | --- |
| API | `https://dev.fluxiovideo.online/api` |
| LiveKit | `wss://dev.fluxiovideo.store` |
| Página para mirar | `https://dev-front.fluxiovideo.online/watch?room=SALA` |

En la sala de la web, el dueño abre **Transmitir** y pulsa **Encender transmisión dentro de Fluxio**. Hasta que ese botón queda en vivo, el enlace responde que la sala no está transmitiendo.

## Qué no se manda al teléfono

La API key de la organización y la llave del dueño (`host_key`) se quedan en un servidor nuestro. Una app que se instala no las lleva.

La llave del dueño sale una sola vez, al crear la sala:

`POST /v1/sdk/rooms`

Cabecera `X-API-Key`. Cuerpo: `room_name`, `identity`, `name`, `access_policy` (`public` o `private`).

Guarda `data.host_key`.

Quien mira pide un token sin esas llaves. El token dura unos 2 minutos y solo sirve para entrar. Después la sesión sigue.

## Audiencia dentro de Fluxio

El servidor enciende la sala:

`POST /v1/sdk/rooms/SALA/stream/internal`

Cabeceras `X-API-Key` y `X-Host-Key`. Cuerpo: `{ "enabled": true }`.

Para apagar, el mismo llamado con `"enabled": false`.

Quien va a mirar pide el token:

`POST /v1/sdk/token`

```json
{
  "room_name": "SALA",
  "identity": "viewer-ana",
  "name": "Ana",
  "role": "viewer"
}
```

`data` es el token. Se conecta a `wss://dev.fluxiovideo.store` sin publicar. Si la transmisión interna está apagada, la respuesta dice que la sala no está transmitiendo.

En Flutter, el SDK `0.2.0` lo hace así. `viewerToken` no envía las llaves. `FluxioRoom.watch` no enciende cámara ni micrófono.

```dart
final control = FluxioStreams(
  baseUrl: 'https://dev.fluxiovideo.online/api',
  apiKey: apiKey,
  hostKey: hostKey,
);

await control.setInternal('SALA', enabled: true);

final token = await control.viewerToken(
  room: 'SALA',
  identity: 'viewer-ana',
  name: 'Ana',
);

FluxioRoom.watch(
  token: token,
  serverUrl: 'wss://dev.fluxiovideo.store',
  onDisconnected: alCortar,
  builder: (context, sala, media) => /* la imagen */,
);
```

`FluxioStreams` vive en el servidor, o en una herramienta interna. `FluxioRoom.watch` vive en la pantalla de la audiencia y solo recibe el token.

## Salida a YouTube, Twitch u otro RTMP

También con API key y llave del dueño.

1. Guardar el destino. Hasta 3. No se aceptan direcciones locales ni de red privada.

`POST /v1/sdk/rooms/SALA/stream/destinations`

```json
{ "label": "YouTube", "url": "rtmps://a.rtmp.youtube.com/live2/LA-CLAVE" }
```

La respuesta trae `url_masked`. La clave no vuelve a salir. La lista de salas tampoco la devuelve.

2. Empezar.

`POST /v1/sdk/rooms/SALA/stream/external/start`

```json
{ "layout": "gallery" }
```

`gallery` muestra a todos. `presentation` pone la pantalla compartida al frente.

3. Parar.

`POST /v1/sdk/rooms/SALA/stream/external/stop`

El estado de las dos salidas:

`GET /v1/sdk/rooms/SALA/stream`

Quitar un destino, solo si la salida externa está parada:

`DELETE /v1/sdk/rooms/SALA/stream/destinations/{id}`

En Flutter:

```dart
await control.addDestination('SALA', label: 'YouTube', url: url);
await control.startExternal('SALA', layout: 'gallery');
await control.stopExternal('SALA');
```

La salida externa usa el egress de LiveKit que ya está en el servidor de dev. Si ese proceso no está arriba, el arranque responde que no se pudo abrir. La audiencia interna no lo necesita.

## Errores que vas a ver

| Código | Qué pasó |
| --- | --- |
| 403 `host_key_required` | Faltó `X-Host-Key` |
| 403 `host_key_invalid` | La llave no es la de esa sala |
| 400 `invalid_stream_url` | La dirección no es `rtmp://` o `rtmps://`, o apunta a una red privada |
| 400 `no_destinations` | Se pidió salir hacia fuera sin destinos |
| 400 `too_many_destinations` | Ya hay 3 destinos |
| 409 `destination_exists` | Esa dirección ya está guardada |
| 409 `stream_active` | Hay que parar la salida antes de quitar un destino |
| 503 `stream_unavailable` | El egress no pudo abrir o cerrar la salida |

`FluxioApiException.message` trae el texto en español.

## Minutos

Mientras la audiencia interna o la salida externa están encendidas, la sala marca `is_streaming`. Esos minutos salen del cupo de transmisión del plan, no del cupo de reunión.

El plan gratis no tiene minutos de transmisión y no puede comprarlos. Startup los paga por minuto. Business y Enterprise traen un cupo incluido.
