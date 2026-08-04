#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARTS_DIR="${ROOT}/dist/iso-parts"
OUT="${ROOT}/dist/vmnas-server-trixie-amd64.iso"
SUM="${ROOT}/dist/vmnas-server-trixie-amd64.iso.sha256"

if ! compgen -G "${PARTS_DIR}/vmnas-server-trixie-amd64.iso.part-*" >/dev/null; then
  echo "No ISO parts found in ${PARTS_DIR}" >&2
  exit 1
fi

cat "${PARTS_DIR}"/vmnas-server-trixie-amd64.iso.part-* > "${OUT}"

if [[ -f "${SUM}" ]]; then
  expected="$(awk '{print $1}' "${SUM}")"
  actual="$(shasum -a 256 "${OUT}" | awk '{print $1}')"
  if [[ "${expected}" != "${actual}" ]]; then
    echo "Checksum mismatch for ${OUT}" >&2
    echo "Expected: ${expected}" >&2
    echo "Actual:   ${actual}" >&2
    exit 1
  fi
fi

echo "Rebuilt ${OUT}"
