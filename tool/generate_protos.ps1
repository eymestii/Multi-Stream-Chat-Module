# Genera el código Dart del contrato gRPC en lib/src/generated.
# Uso (PowerShell, desde la carpeta del proyecto):
#   powershell -ExecutionPolicy Bypass -File tool\generate_protos.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$out = "lib/src/generated"

if (-not (Get-Command protoc -ErrorAction SilentlyContinue)) {
  Write-Error "Falta 'protoc'. Instálalo (ver README, sección Requisitos)."
}

# En Windows el plugin es un .bat y protoc no siempre lo encuentra solo,
# por eso se le pasa la ruta explícita con --plugin.
$plugin = Get-Command protoc-gen-dart -ErrorAction SilentlyContinue
if (-not $plugin) {
  $candidate = Join-Path $env:LOCALAPPDATA "Pub\Cache\bin\protoc-gen-dart.bat"
  if (Test-Path $candidate) { $pluginPath = $candidate }
  else {
    Write-Error "Falta 'protoc-gen-dart'. Ejecuta: dart pub global activate protoc_plugin ^22.2.0"
  }
} else {
  $pluginPath = $plugin.Source
}

New-Item -ItemType Directory -Force -Path $out | Out-Null
protoc "--plugin=protoc-gen-dart=$pluginPath" "--dart_out=grpc:$out" -Iprotos `
  protos/streamchat.proto google/protobuf/timestamp.proto

Write-Host "Listo: código generado en $out"
