#!/usr/bin/env bash
# Installs everything needed to build the Daily Red ROM natively on 64-bit
# Windows, into ./.toolchain (no admin rights, no WSL, no MSYS2, nothing
# written outside this project). Run it from Git Bash, which comes with Git
# for Windows and provides bash, sed, curl, tar, unzip and sha256sum:
#
#   - w64devkit: a portable MinGW-w64 GCC, for pokefirered's host tools
#     (gbagfx, preproc, scaninc, ...)
#   - GNU make from MSYS2, which runs on Git Bash's own MSYS runtime. (w64devkit
#     has a make too, but it cuts commands off at 8 KB, which breaks the link.)
#   - xPack GNU Arm Embedded GCC (arm-none-eabi-gcc + binutils + newlib),
#     the same release setup-macos.sh uses, for pokefirered's `modern` target
#   - zlib + libpng (static), needed by pokefirered/tools/gbagfx
#
# Re-running is safe: finished steps are skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="$ROOT/.toolchain"
DL="$TC/downloads"
mkdir -p "$DL" "$TC/bin"

GCC_VER="14.2.1-1.1"
W64_VER="2.10.0"
W64_SHA="18d0a4c71a166f8401ab6305781bec5882b40b5e06ba9807c61cb5f3b3c6325e"
MAKE_PKG="make-4.4.1-3-x86_64.pkg.tar.zst"
MAKE_SHA="af0bdba17f06fe037f0194069adaa31a8fe45f1a11381501896aea1fae37bd5d"
ZLIB_VER="1.3.1"
ZLIB_SHA="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
LIBPNG_VER="1.6.44"

case "$(uname -s)" in
  MINGW64*|MSYS*) ;;
  *) echo "Run this from Git Bash on Windows (on Linux/WSL use setup-linux.sh)."; exit 1 ;;
esac
[ "$(uname -m)" = x86_64 ] || { echo "Unsupported CPU: $(uname -m)"; exit 1; }

for tool in curl tar unzip sha256sum cygpath node; do
  command -v "$tool" >/dev/null || { echo "Missing $tool: run this from Git Bash (Git for Windows)"; exit 1; }
done

check() { # file sha
  local actual
  actual="$(sha256sum "$1" | awk '{print $1}')"
  [ "$actual" = "$2" ] || { echo "Checksum mismatch: $1 ($actual)"; exit 1; }
}

# --- w64devkit (host gcc, g++, ar, make) --------------------------------------
if [ ! -x "$TC/w64devkit/bin/gcc.exe" ]; then
  exe="w64devkit-x64-$W64_VER.7z.exe"
  echo ">> Downloading $exe"
  curl -fL --retry 3 -o "$DL/$exe" \
    "https://github.com/skeeto/w64devkit/releases/download/v$W64_VER/$exe"
  check "$DL/$exe" "$W64_SHA"
  echo ">> Checksum OK, extracting"
  rm -rf "$TC/w64devkit"
  # A 7-Zip self-extractor: -y = no prompts, -o = output directory.
  "$DL/$exe" -y -o"$(cygpath -w "$TC")" >/dev/null
  rm -f "$DL/$exe"
fi
W64="$TC/w64devkit/bin"
"$W64/gcc" --version | head -1

# --- GNU make (MSYS2 package) -------------------------------------------------
if [ ! -x "$TC/bin/make.exe" ]; then
  echo ">> Downloading $MAKE_PKG"
  curl -fL --retry 3 -o "$DL/$MAKE_PKG" "https://repo.msys2.org/msys/x86_64/$MAKE_PKG"
  check "$DL/$MAKE_PKG" "$MAKE_SHA"
  # Git Bash's tar has no zstd, so let Node unpack it.
  node -e '
    const fs = require("fs"), zlib = require("zlib");
    if (!zlib.zstdDecompressSync) { console.error("Node.js 22.15 or newer is needed"); process.exit(1); }
    fs.writeFileSync(process.argv[2], zlib.zstdDecompressSync(fs.readFileSync(process.argv[1])));
  ' "$(cygpath -w "$DL/$MAKE_PKG")" "$(cygpath -w "$DL/make.tar")"
  tar -xf "$DL/make.tar" -C "$DL" usr/bin/make.exe
  mv "$DL/usr/bin/make.exe" "$TC/bin/make.exe"
  rm -rf "$DL/usr" "$DL/make.tar" "$DL/$MAKE_PKG"
fi
"$TC/bin/make" --version | head -1

# --- arm-none-eabi GCC --------------------------------------------------------
if [ ! -x "$TC/arm-none-eabi/bin/arm-none-eabi-gcc.exe" ]; then
  zip="xpack-arm-none-eabi-gcc-$GCC_VER-win32-x64.zip"
  url="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v$GCC_VER/$zip"
  echo ">> Downloading $zip"
  curl -fL --retry 3 -o "$DL/$zip" "$url"
  curl -fsL -o "$DL/$zip.sha" "$url.sha"
  check "$DL/$zip" "$(awk '{print $1}' "$DL/$zip.sha")"
  echo ">> Checksum OK, extracting"
  rm -rf "$TC/arm-none-eabi" "$TC/xpack-arm-none-eabi-gcc-$GCC_VER"
  unzip -q "$DL/$zip" -d "$TC"
  # No symlink (Git Bash would copy the whole tree): just rename it.
  mv "$TC/xpack-arm-none-eabi-gcc-$GCC_VER" "$TC/arm-none-eabi"
  rm -f "$DL/$zip"
fi
"$TC/arm-none-eabi/bin/arm-none-eabi-gcc" --version | head -1
# Fail early if the compiler can't actually run.
echo 'int f(void){return 0;}' | "$TC/arm-none-eabi/bin/arm-none-eabi-gcc" -x c -c -o /dev/null -

# --- zlib + libpng (static), installed side by side in .toolchain/libpng ------
if [ ! -f "$TC/libpng/lib/libz.a" ]; then
  echo ">> Building zlib $ZLIB_VER"
  curl -fL --retry 3 -o "$DL/zlib.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz"
  check "$DL/zlib.tar.gz" "$ZLIB_SHA"
  src="$DL/zlib-$ZLIB_VER"
  rm -rf "$src"
  tar -xzf "$DL/zlib.tar.gz" -C "$DL"
  mkdir -p "$TC/libpng/include" "$TC/libpng/lib" "$src/obj"
  for f in adler32 compress crc32 deflate gzclose gzlib gzread gzwrite infback \
           inffast inflate inftrees trees uncompr zutil; do
    "$W64/gcc" -O2 -c "$src/$f.c" -o "$src/obj/$f.o"
  done
  "$W64/ar" rcs "$TC/libpng/lib/libz.a" "$src"/obj/*.o
  cp "$src/zlib.h" "$src/zconf.h" "$TC/libpng/include/"
fi

if [ ! -f "$TC/libpng/lib/libpng.a" ]; then
  echo ">> Building libpng $LIBPNG_VER"
  src="$DL/libpng-$LIBPNG_VER"
  rm -rf "$src"
  curl -fL --retry 3 -o "$src.tar.gz" \
    "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VER.tar.gz"
  tar -xzf "$src.tar.gz" -C "$DL"
  # Fixed-point gamma math, so the static library doesn't need libm (same as
  # setup-linux.sh).
  sed '/#define PNG_FLOATING_ARITHMETIC_SUPPORTED/d' \
    "$src/scripts/pnglibconf.h.prebuilt" > "$src/pnglibconf.h"
  mkdir -p "$src/obj"
  for f in png pngerror pngget pngmem pngpread pngread pngrio pngrtran pngrutil \
           pngset pngtrans pngwio pngwrite pngwtran pngwutil; do
    "$W64/gcc" -O2 -DPNG_ARM_NEON_OPT=0 -DPNG_INTEL_SSE_OPT=0 -I"$src" -I"$TC/libpng/include" \
       -c "$src/$f.c" -o "$src/obj/$f.o"
  done
  "$W64/ar" rcs "$TC/libpng/lib/libpng.a" "$src"/obj/*.o
  cp "$src/png.h" "$src/pngconf.h" "$src/pnglibconf.h" "$TC/libpng/include/"
fi
echo ">> libpng: $TC/libpng/lib/libpng.a (+ libz.a)"

echo
echo "Toolchain ready. Build with: scripts/build-rom.sh"
