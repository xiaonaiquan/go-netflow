#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-amd64}"
OUT="${2:-dist/netflow-linux-${ARCH}}"
CC_BIN="${CC:-musl-gcc}"

case "${ARCH}" in
amd64 | arm64)
  ;;
*)
  echo "unsupported arch: ${ARCH}"
  echo "usage: $0 [amd64|arm64] [output]"
  exit 1
  ;;
esac

if ! command -v go >/dev/null 2>&1; then
  echo "go not found in PATH"
  exit 1
fi

if ! command -v "${CC_BIN}" >/dev/null 2>&1; then
  cat <<EOF
${CC_BIN} not found.
Install static build toolchain first.

Ubuntu/Debian:
  sudo apt-get update && sudo apt-get install -y build-essential musl-tools libpcap-dev

CentOS/RHEL:
  sudo yum install -y gcc musl-gcc libpcap-devel libpcap-static
EOF
  exit 1
fi

mkdir -p "$(dirname "${OUT}")"

echo "building static binary: ${OUT}"
CGO_ENABLED=1 GOOS=linux GOARCH="${ARCH}" CC="${CC_BIN}" \
  go build -trimpath \
  -ldflags='-s -w -linkmode external -extldflags "-static"' \
  -o "${OUT}" ./cmd/main.go

echo "build done: ${OUT}"

if command -v ldd >/dev/null 2>&1; then
  set +e
  LDD_OUT="$(ldd "${OUT}" 2>&1)"
  LDD_CODE=$?
  set -e
  echo "${LDD_OUT}"
  if [ ${LDD_CODE} -ne 0 ] || [[ "${LDD_OUT}" == *"not a dynamic executable"* ]]; then
    echo "static link check: ok"
  else
    echo "static link check: warning (binary may still be dynamic)"
  fi
fi
