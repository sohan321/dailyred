#!/usr/bin/env bash
# Installs everything needed to build the Daily Red ROM on x86_64 Linux
# (including WSL 2 on Windows), into ./.toolchain (no sudo, no apt, nothing
# written outside this project). Only a host C/C++ compiler (gcc, g++), curl,
# tar and shasum are needed, e.g. a stock Ubuntu with build-essential's
# compilers but no `make` or -dev packages:
#
#   - xPack GNU Arm Embedded GCC (arm-none-eabi-gcc + binutils + newlib),
#     the same release setup-macos.sh uses, for pokefirered's `modern` target
#   - GNU make, built from source into .toolchain/bin
#   - zlib + libpng (static), needed by pokefirered/tools/gbagfx
#
# Re-running is safe: finished steps are skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="$ROOT/.toolchain"
DL="$TC/downloads"
mkdir -p "$DL" "$TC/bin"

GCC_VER="14.2.1-1.1"
MAKE_VER="4.4.1"
MAKE_SHA="dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3"
ZLIB_VER="1.3.1"
ZLIB_SHA="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
LIBPNG_VER="1.6.44"

case "$(uname -m)" in
  x86_64)  GCC_HOST="linux-x64" ;;
  aarch64) GCC_HOST="linux-arm64" ;;
  *) echo "Unsupported CPU: $(uname -m)"; exit 1 ;;
esac

for tool in cc c++ ar curl tar shasum; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (e.g. sudo apt install build-essential curl)"; exit 1; }
done

check() { # file sha
  local actual
  actual="$(shasum -a 256 "$1" | awk '{print $1}')"
  [ "$actual" = "$2" ] || { echo "Checksum mismatch: $1 ($actual)"; exit 1; }
}

# --- arm-none-eabi GCC --------------------------------------------------------
GCC_NAME="xpack-arm-none-eabi-gcc-$GCC_VER"
if [ ! -x "$TC/arm-none-eabi/bin/arm-none-eabi-gcc" ]; then
  tarball="$GCC_NAME-$GCC_HOST.tar.gz"
  url="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v$GCC_VER/$tarball"
  echo ">> Downloading $tarball"
  curl -fL --retry 3 -o "$DL/$tarball" "$url"
  curl -fsL -o "$DL/$tarball.sha" "$url.sha"
  check "$DL/$tarball" "$(awk '{print $1}' "$DL/$tarball.sha")"
  echo ">> Checksum OK, extracting"
  tar -xzf "$DL/$tarball" -C "$TC"
  rm -f "$TC/arm-none-eabi"
  ln -s "$GCC_NAME" "$TC/arm-none-eabi"
  rm -f "$DL/$tarball"
fi
"$TC/arm-none-eabi/bin/arm-none-eabi-gcc" --version | head -1
# Fail early if the compiler can't actually run.
echo 'int f(void){return 0;}' | "$TC/arm-none-eabi/bin/arm-none-eabi-gcc" -x c -c -o /dev/null -

# --- GNU make (only if the system has none) ------------------------------------
if ! command -v make >/dev/null && [ ! -x "$TC/bin/make" ]; then
  echo ">> Building GNU make $MAKE_VER"
  curl -fL --retry 3 -o "$DL/make.tar.gz" "https://ftp.gnu.org/gnu/make/make-$MAKE_VER.tar.gz"
  check "$DL/make.tar.gz" "$MAKE_SHA"
  rm -rf "$DL/make-$MAKE_VER"
  tar -xzf "$DL/make.tar.gz" -C "$DL"
  # build.sh bootstraps make without needing an existing make.
  (cd "$DL/make-$MAKE_VER" && ./configure -q --prefix="$TC" --disable-nls && ./build.sh >/dev/null)
  cp "$DL/make-$MAKE_VER/make" "$TC/bin/make"
fi
echo ">> make: $(command -v make || echo "$TC/bin/make")"

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
    cc -O2 -fPIC -DZ_HAVE_UNISTD_H -c "$src/$f.c" -o "$src/obj/$f.o"
  done
  ar rcs "$TC/libpng/lib/libz.a" "$src"/obj/*.o
  cp "$src/zlib.h" "$src/zconf.h" "$TC/libpng/include/"
fi

if [ ! -f "$TC/libpng/lib/libpng.a" ]; then
  echo ">> Building libpng $LIBPNG_VER"
  src="$DL/libpng-$LIBPNG_VER"
  rm -rf "$src"
  curl -fL --retry 3 -o "$src.tar.gz" \
    "https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VER.tar.gz"
  tar -xzf "$src.tar.gz" -C "$DL"
  # Fixed-point gamma math, so the static library doesn't need libm (gbagfx's
  # Makefile links only -lpng -lz; on macOS libm is part of libSystem).
  sed '/#define PNG_FLOATING_ARITHMETIC_SUPPORTED/d' \
    "$src/scripts/pnglibconf.h.prebuilt" > "$src/pnglibconf.h"
  mkdir -p "$src/obj"
  # Disable the optional SIMD paths so no extra arch-specific sources are needed.
  for f in png pngerror pngget pngmem pngpread pngread pngrio pngrtran pngrutil \
           pngset pngtrans pngwio pngwrite pngwtran pngwutil; do
    cc -O2 -fPIC -DPNG_ARM_NEON_OPT=0 -DPNG_INTEL_SSE_OPT=0 -I"$src" -I"$TC/libpng/include" \
       -c "$src/$f.c" -o "$src/obj/$f.o"
  done
  ar rcs "$TC/libpng/lib/libpng.a" "$src"/obj/*.o
  cp "$src/png.h" "$src/pngconf.h" "$src/pnglibconf.h" "$TC/libpng/include/"
fi
echo ">> libpng: $TC/libpng/lib/libpng.a (+ libz.a)"

echo
echo "Toolchain ready. Build with: scripts/build-rom.sh"
