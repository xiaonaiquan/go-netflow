#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-amd64}"
OUT_REL="${2:-dist/netflow-linux-${ARCH}}"

case "${ARCH}" in
amd64)
  ;;
*)
  echo "unsupported arch: ${ARCH}"
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

missing=0
for bin in go gcc pkg-config ldd; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "missing command: ${bin}"
    missing=1
  fi
done

if [[ ${missing} -ne 0 ]]; then
  cat <<EOF
install on Ubuntu:
  sudo apt-get update
  sudo apt-get install -y build-essential pkg-config libpcap-dev
EOF
  exit 1
fi

if ! pkg-config --exists libpcap; then
  echo "libpcap headers/libs not found"
  echo "install: sudo apt-get install -y libpcap-dev"
  exit 1
fi

if [[ "${OUT_REL}" = /* ]]; then
  echo "output must be a relative path under repository"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_ABS="${ROOT_DIR}/${OUT_REL}"
mkdir -p "$(dirname "${OUT_ABS}")"

echo "building static binary: ${OUT_REL}"
CGO_ENABLED=1 GOOS=linux GOARCH="${ARCH}" CC=gcc \
  go build -trimpath -tags 'netgo osusergo' \
  -ldflags '-s -w -linkmode external -extldflags "-static"' \
  -o "${OUT_ABS}" ./cmd/main.go

set +e
LDD_OUT="$(ldd "${OUT_ABS}" 2>&1)"
LDD_CODE=$?
FILE_OUT="$(file -b "${OUT_ABS}" 2>&1)"
FILE_CODE=$?
READELF_OUT=""
READELF_CODE=127
HAS_INTERP=2
if command -v readelf >/dev/null 2>&1; then
  READELF_OUT="$(readelf -l "${OUT_ABS}" 2>&1)"
  READELF_CODE=$?
  echo "${READELF_OUT}" | grep -q "INTERP"
  HAS_INTERP=$?
fi
set -e

if [[ "${LDD_OUT}" == *"not a dynamic executable"* ]] || [[ "${LDD_OUT}" == *"statically linked"* ]] || [[ "${LDD_OUT}" == *"不是动态可执行文件"* ]]; then
  echo "static link check: ok"
  echo "done: ${OUT_ABS}"
  exit 0
fi

if [[ ${FILE_CODE} -eq 0 ]] && [[ "${FILE_OUT}" == *"statically linked"* ]]; then
  echo "static link check: ok"
  echo "done: ${OUT_ABS}"
  exit 0
fi

if [[ ${READELF_CODE} -eq 0 ]] && [[ ${HAS_INTERP} -ne 0 ]]; then
  echo "static link check: ok (no INTERP segment)"
  echo "done: ${OUT_ABS}"
  exit 0
fi

echo "${LDD_OUT}"
echo "ldd exit code: ${LDD_CODE}"
echo "${FILE_OUT}"
if [[ -n "${READELF_OUT}" ]]; then
  echo "${READELF_OUT}"
fi
echo "static link check: failed (binary is not fully static)"
exit 1
