#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# chiaki-ng'nin Remote Play kütüphanesini (libchiaki) macOS için statik derler.
# Çıktı: third-party/build/macos/{include,lib}
# Gerekenler: Xcode, Homebrew ile cmake ninja pkg-config protobuf openssl@3 json-c libevent miniupnpc
set -e
cd "${0:A:h}/.."

ROOT="$PWD"
SRC="$ROOT/third-party/chiaki-ng"
BUILD="$ROOT/third-party/build/macos-cmake"
OUT="$ROOT/third-party/build/macos"
VENV="$ROOT/third-party/build/venv"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BREW="$(brew --prefix)"

# nanopb'nin kod üreteci Python'da protobuf paketini ister; sisteme dokunmamak için ayrı ortam.
if [[ ! -x "$VENV/bin/python3" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet protobuf grpcio-tools
fi

git -C "$SRC" submodule update --init --depth 1 third-party/nanopb third-party/jerasure third-party/gf-complete third-party/curl

# Arayüz, komut satırı, ses ve FFmpeg kapalı: yalnız bağlantı, kayıt ve görüntü akışı gerekiyor.
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_PREFIX_PATH="$BREW/opt/openssl@3;$BREW/opt/json-c;$BREW/opt/libevent;$BREW/opt/miniupnpc" \
  -DOPENSSL_ROOT_DIR="$BREW/opt/openssl@3" \
  -DOPENSSL_USE_STATIC_LIBS=ON \
  -DPython3_EXECUTABLE="$VENV/bin/python3" \
  -DPYTHON_EXECUTABLE="$VENV/bin/python3" \
  -DCHIAKI_ENABLE_GUI=OFF \
  -DCHIAKI_ENABLE_CLI=OFF \
  -DCHIAKI_ENABLE_TESTS=OFF \
  -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF \
  -DCHIAKI_ENABLE_PI_DECODER=OFF \
  -DCHIAKI_LIB_ENABLE_OPUS=OFF \
  -DCHIAKI_ENABLE_SPEEX=OFF \
  -DCHIAKI_ENABLE_SETSU=OFF \
  -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF \
  -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
  -DCHIAKI_ENABLE_BOREALIS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DCURL_ZSTD=OFF -DCURL_BROTLI=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DUSE_LIBRTMP=OFF -DCURL_DISABLE_LDAP=ON

cmake --build "$BUILD" --target chiaki-lib

rm -rf "$OUT"
mkdir -p "$OUT/include" "$OUT/lib"
cp -R "$SRC/lib/include/chiaki" "$OUT/include/"
cp -R "$BUILD/lib/include/chiaki/"* "$OUT/include/chiaki/" 2>/dev/null || true

# Kütüphanenin kendisi ve derleme sırasında üretilen statik bağımlılıklar.
find "$BUILD" -name "*.a" -exec cp {} "$OUT/lib/" \;
# Homebrew'dan gelen statik bağımlılıklar (uygulamaya gömülür, kullanıcıda Homebrew gerekmez).
cp "$BREW/opt/openssl@3/lib/libcrypto.a" "$BREW/opt/openssl@3/lib/libssl.a" \
   "$BREW/opt/json-c/lib/libjson-c.a" \
   "$BREW/opt/libevent/lib/libevent.a" \
   "$BREW/opt/miniupnpc/lib/libminiupnpc.a" "$OUT/lib/"

# Swift'ten "import CChiaki" ile kullanılmak üzere tek statik kütüphane + başlıklar + modül haritası.
FW="$ROOT/third-party/build/CChiaki.xcframework"
STAGE="$ROOT/third-party/build/xcframework-stage"
rm -rf "$FW" "$STAGE"
mkdir -p "$STAGE/include"
# macOS 27'de derlenmiş bağımlılıklar macOS 26'da olmayan pipe2/dup3'ü isteyebilir; yerlerine bizimkiler girer.
xcrun clang -c -O2 -arch arm64 -mmacosx-version-min=26.0 scripts/macos-compat.c -o "$STAGE/macos-compat.o"
libtool -static -o "$STAGE/libCChiaki.a" "$OUT"/lib/*.a "$STAGE/macos-compat.o"
# Uygulama macOS 26'yı hedefliyor; daha yeni macOS için derlenmiş parça varsa orada olmayan bir sembolü isteyebilir.
NEWER=$(otool -l "$STAGE/libCChiaki.a" | awk '/^.*\.a\(/ {o=$0} $1=="minos" && $2+0 > 26.0 {print o}' | sort -u)
[[ -z "$NEWER" ]] || { echo "Uyarı: macOS 26'dan yeni hedefle derlenmiş parçalar (macOS 26'da açılışı kontrol edin):"; echo "$NEWER" | head -20; }
cp -R "$OUT/include/chiaki" "$STAGE/include/"
{
  echo '#include <stdbool.h>'
  for h in common log session regist discovery controller video; do echo "#include \"chiaki/$h.h\""; done
} > "$STAGE/include/CChiaki.h"
cat > "$STAGE/include/module.modulemap" <<'MAP'
module CChiaki {
  umbrella header "CChiaki.h"
  export *
}
MAP
xcodebuild -create-xcframework -library "$STAGE/libCChiaki.a" -headers "$STAGE/include" -output "$FW" >/dev/null
rm -rf "$STAGE"

echo "Hazır: $FW"
ls "$OUT/lib"
