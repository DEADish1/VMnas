#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
IMAGE_TAG="${CAMONAS_BUILDER_IMAGE:-camonas-iso-builder:latest}"
DIRECT="${CAMONAS_DIRECT_LIVE_BUILD:-0}"
BUILDER_PLATFORM="${CAMONAS_BUILDER_PLATFORM:-linux/amd64}"
DOCKER_BIN="${DOCKER_BIN:-}"

if [[ -z "${DOCKER_BIN}" ]]; then
  if command -v docker >/dev/null 2>&1; then
    DOCKER_BIN="$(command -v docker)"
  elif [[ -x "/Applications/Docker.app/Contents/Resources/bin/docker" ]]; then
    DOCKER_BIN="/Applications/Docker.app/Contents/Resources/bin/docker"
  fi
fi

if [[ "${DIRECT}" == "1" ]]; then
  if ! command -v lb >/dev/null 2>&1; then
    echo "Direct ISO build requires Debian live-build. On Debian run: sudo apt-get install -y live-build xorriso isolinux syslinux-common squashfs-tools" >&2
    exit 1
  fi
  mkdir -p "${OUT_DIR}"
  WORK_DIR="${ROOT_DIR}" OUT_DIR="${OUT_DIR}" "${ROOT_DIR}/server-os/docker-entrypoint.sh"
  echo "ISO output is in ${OUT_DIR}"
  exit 0
fi

if [[ -z "${DOCKER_BIN}" || ! -x "${DOCKER_BIN}" ]]; then
  cat >&2 <<EOF
Docker was not found, so Camo NAS cannot build the server ISO on this Mac yet.

Install and start Docker Desktop, then run:
  cd "${ROOT_DIR}"
  make iso

Or build directly on a Debian host with:
  cd "${ROOT_DIR}"
  CAMONAS_DIRECT_LIVE_BUILD=1 ./server-os/build-iso.sh
EOF
  exit 1
fi

mkdir -p "${OUT_DIR}"

"${DOCKER_BIN}" build --platform "${BUILDER_PLATFORM}" -t "${IMAGE_TAG}" "${ROOT_DIR}/server-os"
"${DOCKER_BIN}" run --rm --privileged --platform "${BUILDER_PLATFORM}" \
  -v "${ROOT_DIR}:/work" \
  -v "${OUT_DIR}:/out" \
  "${IMAGE_TAG}"

echo "ISO output will be in ${OUT_DIR}"
