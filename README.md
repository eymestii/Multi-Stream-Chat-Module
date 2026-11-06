# StreamChat Desktop

Cliente de escritorio (Flutter) para el servicio **ChatHub** del Websocket Module.
Muestra en un solo feed el chat de Twitch y Kick y permite escribir en cualquiera
de los canales que el servicio está escuchando.

La app no se conecta a Twitch ni a Kick: todo pasa por el servicio gRPC local
(`streamchat.v1.ChatHub`, puerto 50051 por defecto).

| Método del contrato | Para qué lo usa la app |
|---|---|
| `ListChannels` | Panel de canales y destino de la barra de envío. También sirve para comprobar que el servicio responde. Se refresca cada 30 s. |
| `StreamEvents` | Feed en tiempo real. Si la conexión se corta, reconecta con `resume_after_id` para no perder eventos. |
| `SendMessage` | Barra de envío. Usa `platform` y `channel_id` (el `broadcaster_user_id`) del canal elegido, más `reply_to_message_id` si estás respondiendo. |

---

## Requisitos

### 1. Flutter con soporte de escritorio

- Flutter **3.22 o superior** (incluye Dart 3.4+). Compruébalo con `flutter --version`.
- Activa el escritorio para tu sistema:
  ```bash
  flutter config --enable-windows-desktop   # o --enable-macos-desktop / --enable-linux-desktop
  ```
- Herramientas de compilación según el sistema:

| Sistema | Qué instalar |
|---|---|
| Windows | Visual Studio 2022 con la carga de trabajo **Desarrollo para el escritorio con C++** (no basta con VS Code). |
| macOS | Xcode y CocoaPods. |
| Linux | `clang cmake ninja-build pkg-config libgtk-3-dev` |

Ejecuta `flutter doctor` y resuelve lo que marque en la sección de escritorio.

### 2. Compilador de Protocol Buffers (`protoc`)

Lo necesitas para generar el código Dart a partir del contrato `.proto`.

| Sistema | Comando |
|---|---|
| Windows | `winget install protobuf`, o descarga `protoc-*-win64.zip` de [las releases de protobuf](https://github.com/protocolbuffers/protobuf/releases) y añade la carpeta `bin` al PATH |
| macOS | `brew install protobuf` |
| Linux | `sudo apt install protobuf-compiler` |

Comprueba con `protoc --version`.

### 3. Plugin de Dart para `protoc`

```bash
dart pub global activate protoc_plugin ^22.2.0
```

Añade la carpeta de ejecutables de pub al PATH:

- Windows: `%LOCALAPPDATA%\Pub\Cache\bin`
- macOS / Linux: `$HOME/.pub-cache/bin`

> La versión importa: `protoc_plugin` 22.x genera código para `protobuf` 4.x, que es lo que usa este proyecto.

### 4. El servicio en marcha

El Websocket Module tiene que estar corriendo y exponiendo ChatHub (por defecto en `localhost:50051`).

---

## Instalación

```bash
# 1. Entra en la carpeta del proyecto
cd streamchat_desktop

# 2. Crea las carpetas nativas de escritorio (no toca lib/ ni pubspec.yaml)
flutter create --platforms=windows,macos,linux .

# 3. Copia el contrato real del servicio (recomendado, ver nota abajo)
#    Websocket-Module/proto/streamchat.proto  ->  protos/streamchat.proto

# 4. Genera el código gRPC
./tool/generate_protos.sh                                        # macOS / Linux
powershell -ExecutionPolicy Bypass -File tool\generate_protos.ps1  # Windows

# 5. Dependencias y ejecución
flutter pub get
flutter run -d windows        # o -d macos / -d linux
```

Para generar un ejecutable distribuible:

```bash
flutter build windows   # queda en build/windows/x64/runner/Release/
flutter build macos     # queda en build/macos/Build/Products/Release/
flutter build linux     # queda en build/linux/x64/release/bundle/
```

### Sobre `protos/streamchat.proto`

El archivo incluido se reconstruyó a partir del resumen del contrato. Los mensajes que el resumen no detallaba (`Follow`, `Raid`, `Emote`, `MessageDeleted`…) están vacíos (*stubs*).

Esto funciona porque protobuf ignora los campos que no conoce. La app identifica igual qué tipo de evento llegó, ya que los números del `oneof` coinciden con los del servicio. Aun así, **lo correcto es copiar el `.proto` real** del Websocket Module y volver a generar el código. La app solo usa campos que aparecen en el resumen, así que compila con cualquiera de los dos.

Cada vez que cambie el contrato, repite el paso 4.

### macOS: permisos de red

Las apps de macOS corren en sandbox y no pueden abrir conexiones si no lo declaras. Añade esto en `macos/Runner/DebugProfile.entitlements` y en `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<!-- Solo si usas la detección por mDNS: -->
<key>com.apple.security.network.server</key>
<true/>
```

Si vas a usar mDNS, añade también en `macos/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Para encontrar el servicio de chat en tu red local.</string>
<key>NSBonjourServices</key>
<array><string>_streamchat._tcp</string></array>
```

---

## Autodetección del servicio

**Sí, la app encuentra el servicio sola.** Al arrancar busca en este orden y se queda con el primero que responda:

1. **Variable de entorno `STREAMCHAT_ADDRESS`** (`host:puerto`). Si está definida, tiene prioridad.
2. **La última dirección que funcionó.** La app la guarda para que el siguiente arranque sea inmediato.
3. **Este equipo**: `127.0.0.1` en el puerto 50051 y en los vecinos 50050 y 50053–50060. Las pruebas se hacen todas a la vez, así que la búsqueda tarda menos de un segundo.
4. **Red local por mDNS (Bonjour)**: busca servicios anunciados como `_streamchat._tcp`. Solo encuentra algo si el servicio se anuncia (ver más abajo).

**Cómo se valida un candidato.** Que un puerto esté abierto no basta. A cada candidato se le llama `ListChannels` con un límite de 800 ms, y solo se acepta si contesta un ChatHub de verdad. Así se descarta, por ejemplo, el módulo OAuth en `:50052` (además, ese puerto se omite a propósito).

**Si el servicio no está.** La app muestra "No se encontró el servicio de chat" y vuelve a buscar cada 5 segundos. En cuanto arranques el Websocket Module, se conecta sola.

**Si el servicio se cae o se reinicia.** La app reintenta en la misma dirección, esperando 2, 4 y 8 segundos entre intentos. Si sigue sin responder, vuelve a buscarlo desde cero, por si el servicio arrancó en otro puerto. Al reconectar envía `resume_after_id` con el último evento recibido.

**Para fijar la dirección a mano** tienes tres opciones:

- Desde la app: botón de ajustes junto al estado de la conexión → **Conectar**.
- Con la variable de entorno:
  ```bash
  STREAMCHAT_ADDRESS=127.0.0.1:50051 flutter run -d linux
  ```
  En PowerShell:
  ```powershell
  $env:STREAMCHAT_ADDRESS="127.0.0.1:50051"; flutter run -d windows
  ```
- Para volver al modo automático: el mismo diálogo → **Detectar automáticamente**.

### Opcional: anunciar el servicio por mDNS

Como el servicio es local, los pasos 1 a 3 son suficientes. mDNS solo hace falta si algún día el Websocket Module corre **en otra máquina** de la red. En ese caso, el servicio tiene que anunciarse. Ejemplo en Python con `zeroconf` (`pip install zeroconf`):

```python
import socket
from zeroconf import Zeroconf, ServiceInfo

ip = socket.gethostbyname(socket.gethostname())  # IP de la máquina en la LAN
info = ServiceInfo(
    "_streamchat._tcp.local.",
    "ChatHub._streamchat._tcp.local.",
    addresses=[socket.inet_aton(ip)],
    port=50051,
    properties={"proto": "streamchat.v1"},
)
zc = Zeroconf()
zc.register_service(info)
# Al apagar el servicio:
# zc.unregister_service(info); zc.close()
```

Recuerda que el servidor gRPC tiene que escuchar en `0.0.0.0:50051` (o `[::]:50051`), no solo en `127.0.0.1`, para aceptar conexiones de otras máquinas.

---

## Uso

- **Feed**: cada línea lleva una franja con el color de su plataforma (morado para Twitch, verde para Kick). Los filtros de arriba ocultan o muestran cada plataforma.
- **Leer mensajes anteriores**: al subir, el feed se queda quieto y aparece "Ver N mensajes nuevos" para volver abajo.
- **Escribir**: elige el canal en el panel izquierdo o en el selector de la barra de abajo, escribe y pulsa Enter. El mensaje no se añade a mano al feed: llega por `StreamEvents` como cualquier otro, igual que en Twitch o Kick.
- **Responder**: pasa el ratón sobre un mensaje y pulsa el botón de responder. Esc cancela la respuesta.
- **Eventos**: follows, subs, raids, bits y recompensas aparecen como tarjetas destacadas. Los baneos y el chat limpiado aparecen como avisos en gris. Los mensajes borrados se muestran como "mensaje eliminado".
- Si `SendMessage` devuelve `accepted = false`, se muestra el `drop_reason` del servicio.

---

## Estructura

```
protos/streamchat.proto          Contrato gRPC (reemplázalo por el real)
tool/generate_protos.sh|.ps1     Genera lib/src/generated/
lib/main.dart
lib/src/generated/               Código generado por protoc (no editar)
lib/src/models/chat_line.dart    Línea del feed normalizada
lib/src/services/
  service_discovery.dart         Autodetección y validación del servicio
  chat_service.dart              Stream, reconexión, canales y envío
  event_mapper.dart              ChatEvent -> línea del feed
lib/src/ui/
  theme.dart                     Colores y tipografía
  chat_screen.dart               Pantalla principal
  widgets/                       Panel lateral, mensaje, barra de envío, conexión
```

Si cambias el puerto por defecto o los puertos que se prueban, edita `ServiceDiscovery.defaultPort` y `ServiceDiscovery.localPorts`.

Con el `.proto` real puedes mostrar más detalle de los eventos (cantidad de bits, número de espectadores de un raid, emotes como imágenes). Para eso, lee los campos tipados en `event_mapper.dart` en vez de `raw_json`.

---

## Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| `Target of URI doesn't exist: ...streamchat.pbgrpc.dart` | Falta generar el código. Ejecuta el script de `tool/`. |
| `protoc-gen-dart: program not found` | El plugin no está en el PATH. En Windows usa el `.ps1`: busca el `.bat` del plugin por su cuenta. |
| `version solving failed` con `protobuf` | La versión de `protoc_plugin` no coincide. Instala la 22.x (`dart pub global activate protoc_plugin ^22.2.0`), regenera el código y ejecuta `flutter pub get`. |
| "No se encontró el servicio de chat" | El Websocket Module no está corriendo o usa otro puerto. Usa `STREAMCHAT_ADDRESS` o el diálogo de conexión. |
| "El servicio no reconoce la llamada" | El `.proto` de la app y el del servicio no coinciden (paquete o nombres distintos). Copia el real y regenera. |
| macOS no conecta | Faltan los permisos de red del sandbox (sección macOS). |
| Error al compilar en Windows | Falta Visual Studio con C++. Revisa `flutter doctor`. |
