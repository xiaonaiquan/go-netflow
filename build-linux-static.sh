#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-amd64}"
OUT_REL="${2:-dist/netflow-linux-${ARCH}}"
DOCKER_IMAGE="${DOCKER_IMAGE:-golang:1.22-alpine3.20}"

case "${ARCH}" in
amd64)
  ;;
*)
  echo "unsupported arch: ${ARCH}"
  echo "this script currently supports amd64 only"
  echo "usage: $0 [amd64] [output]"
  exit 1
  ;;
esac

if [[ ! -r /etc/os-release ]]; then
  echo "cannot detect os, /etc/os-release not found"
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "this script only supports Ubuntu (detected: ${ID:-unknown})"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  cat <<EOF
docker not found.
Install Docker on Ubuntu first:
  sudo apt-get update
  sudo apt-get install -y docker.io
EOF
  exit 1
fi

if [[ "${OUT_REL}" = /* ]]; then
  echo "output must be a relative path under repository"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_ABS="${ROOT_DIR}/${OUT_REL}"
mkdir -p "$(dirname "${OUT_ABS}")"

echo "building static binary in Docker: ${OUT_REL}"
docker run --rm \
  -v "${ROOT_DIR}:/src" \
  -w /src \
  -e OUT_PATH="/src/${OUT_REL}" \
  "${DOCKER_IMAGE}" \
  sh -lc '
    set -euo pipefail
    apk add --no-cache build-base pkgconf linux-headers libpcap-dev libpcap-static
    go mod download
    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
      go build -trimpath \
      -ldflags "-s -w -linkmode external -extldflags \"-static\"" \
      -o "${OUT_PATH}" ./cmd/main.go
    echo "build done: ${OUT_PATH}"
    ldd "${OUT_PATH}" || true
  '

echo "done: ${OUT_ABS}"
