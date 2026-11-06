#!/usr/bin/env bash
# Genera el código Dart del contrato gRPC en lib/src/generated.
# Uso: ./tool/generate_protos.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="lib/src/generated"

if ! command -v protoc >/dev/null 2>&1; then
  echo "Falta 'protoc'. Instálalo (ver README, sección Requisitos)." >&2
  exit 1
fi
if ! command -v protoc-gen-dart >/dev/null 2>&1; then
  echo "Falta 'protoc-gen-dart'. Ejecuta:" >&2
  echo "  dart pub global activate protoc_plugin ^22.2.0" >&2
  echo "y añade ~/.pub-cache/bin a tu PATH." >&2
  exit 1
fi

mkdir -p "$OUT"
protoc --dart_out=grpc:"$OUT" -Iprotos \
  protos/streamchat.proto google/protobuf/timestamp.proto

echo "Listo: código generado en $OUT"
