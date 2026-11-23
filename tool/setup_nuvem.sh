#!/usr/bin/env bash
# tool/setup_nuvem.sh — setup script do ambiente de nuvem SincroVolt (EVAPP-74).
# Colado no campo "Setup script" do ambiente, que aceita no máximo 100 linhas. Mesmas
# versões do tool/setup_env.sh (o verificador confere), só toolchain: sem Android (o
# script não lê as variáveis do ambiente) e sem pub get (roda fora do repo).
# Dentro do repo continua valendo: bash tool/setup_env.sh && source tool/env
set -euo pipefail
FLUTTER_VERSION="3.50.1"   # tem de bater com o .fvmrc e com tool/setup_env.sh
FLUTTER_SHA256="4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678"
FVM_VERSION="4.1.2"
export FLUTTER_SUPPRESS_ANALYTICS=true
FVM_CACHE="${FVM_CACHE_PATH:-$HOME/fvm}"
FLUTTER_DIR="$FVM_CACHE/versions/$FLUTTER_VERSION"
PUB_BIN="$HOME/.pub-cache/bin"
log()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null || fail "curl ausente."
command -v xz >/dev/null || { command -v apt-get >/dev/null && { SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"; $SUDO apt-get update -qq && $SUDO apt-get install -y -qq xz-utils; }; }
command -v xz >/dev/null || fail "xz ausente (necessário para o tarball do Flutter)."
log "Flutter $FLUTTER_VERSION"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 -o "$tmp/flutter.tar.xz" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    || fail "download do Flutter falhou — domínio storage.googleapis.com bloqueado?"
  echo "$FLUTTER_SHA256  $tmp/flutter.tar.xz" | sha256sum -c - >/dev/null \
    || fail "sha256 do tarball do Flutter não confere (download corrompido ou versão trocada)."
  tar -xf "$tmp/flutter.tar.xz" -C "$tmp"
  mkdir -p "$FVM_CACHE/versions"
  rm -rf "$FLUTTER_DIR"
  mv "$tmp/flutter" "$FLUTTER_DIR"
  rm -rf "$tmp"
fi
git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true
export PATH="$PUB_BIN:$FLUTTER_DIR/bin:$PATH"
"$FLUTTER_DIR/bin/flutter" config --no-analytics >/dev/null 2>&1 || true
"$FLUTTER_DIR/bin/dart" --disable-analytics >/dev/null 2>&1 || true
actual="$("$FLUTTER_DIR/bin/flutter" --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')"
[ "$actual" = "$FLUTTER_VERSION" ] || fail "flutter --version reporta '$actual', esperado $FLUTTER_VERSION."
echo "Flutter $actual OK"
log "FVM $FVM_VERSION"
if ! "$FLUTTER_DIR/bin/dart" pub global list 2>/dev/null | grep -q "^fvm $FVM_VERSION\$"; then
  "$FLUTTER_DIR/bin/dart" pub global activate fvm "$FVM_VERSION" >/dev/null \
    || fail "dart pub global activate fvm falhou — domínio pub.dev bloqueado?"
fi
command -v fvm >/dev/null || fail "fvm não ficou no PATH ($PUB_BIN)."
fvm --version
if [ "$(id -u)" -eq 0 ]; then
  printf '# SincroVolt — gerado pelo setup do ambiente de nuvem\nexport PATH="%s:%s/bin:$PATH"\n' "$PUB_BIN" "$FLUTTER_DIR" > /etc/profile.d/sincrovolt.sh
  for b in flutter dart; do ln -sf "$FLUTTER_DIR/bin/$b" "/usr/local/bin/$b"; done
  ln -sf "$PUB_BIN/fvm" /usr/local/bin/fvm
  grep -q 'profile.d/sincrovolt.sh' "$HOME/.bashrc" 2>/dev/null || echo '. /etc/profile.d/sincrovolt.sh' >> "$HOME/.bashrc"
fi
log "ambiente pronto (Flutter $FLUTTER_VERSION, FVM $FVM_VERSION, Android: não)"
