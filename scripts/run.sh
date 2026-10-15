#!/usr/bin/env bash
# One command from a clean checkout to a running game: installs the toolchain,
# fetches pokefirered and the emulator, builds the ROM and serves the site.
# Steps that are already done are skipped, so it's also the everyday "play"
# command (the ROM build is incremental).
#
#   scripts/run.sh          # serve on http://localhost:8080
#   scripts/run.sh 3000     # another port
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "$(uname -s)" in
  MINGW*|MSYS*) scripts/setup-windows.sh ;;
  Darwin)       scripts/setup-macos.sh ;;
  *)            scripts/setup-linux.sh ;;
esac

[ -d pokefirered ] || scripts/get-pokefirered.sh
[ -f web/vendor/mgba_libretro.wasm ] || scripts/fetch-vendor.sh
scripts/build-rom.sh

echo
exec node scripts/serve.mjs "$@"
