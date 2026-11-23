#!/usr/bin/env bash
# tool/setup_env.sh — bootstrap idempotente do ambiente Linux do SincroVolt (nuvem e CI).
#
# Adaptado do bootstrap do Desmalha. Instala/garante, com versões FIXADAS:
#   - Flutter 3.50.1 (tarball oficial de storage.googleapis.com, sha256 conferido),
#     que embute o Dart;
#   - FVM 4.1.2 (pub.dev), apontando para esse Flutter;
#   - opcional (SINCROVOLT_COM_ANDROID=1): JDK 17 (apt) e Android SDK (dl.google.com).
# Por padrão NÃO instala Android: nuvem e CI rodam núcleo, analyze e testes, que não
# precisam de SDK Android. Build de APK e aparelho ficam no Windows (docs/ambiente.md).
#
# Funciona de dois jeitos:
#   1. dentro do repo:  bash tool/setup_env.sh && source tool/env
#   2. colado no campo "Setup script" do ambiente de nuvem do Claude Code, onde roda como
#      root ANTES de a sessão existir e sem as variáveis do ambiente. Por isso todas as
#      versões estão aqui dentro e o repo é opcional; como root, os binários ganham links
#      em /usr/local/bin para valerem em qualquer shell da sessão.
#
# Rede usada (sem Android): storage.googleapis.com, pub.dev. Se um download falhar, o
# script PARA e diz o domínio. Não use mirror não oficial.
set -euo pipefail

# ---------------------------------------------------------------- constantes
FLUTTER_VERSION="3.50.1"   # tem de bater com o .fvmrc (o verificador confere)
FLUTTER_SHA256="4ad17fc8462fbcef2ba19ff4a78c0a16b7147fde1add8578e267ea62cdb92678"
FVM_VERSION="4.1.2"
ANDROID_PLATFORM="android-36"      # compileSdk padrão do Flutter 3.50.1
BUILD_TOOLS="36.0.0"
NDK_VERSION="28.2.13676358"        # ndkVersion padrão do Flutter 3.50.1
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# Sem telemetria do Flutter/Dart: medido no EVAPP-36, o primeiro `flutter` tentava
# www.google-analytics.com (fora do allowlist da nuvem, e desnecessário).
export FLUTTER_SUPPRESS_ANALYTICS=true
# O Flutter vai para o cache PADRÃO do FVM ($HOME/fvm). Não exportamos FVM_CACHE_PATH:
# medido no EVAPP-36, uma shell sem a variável fazia o fvm procurar em $HOME/fvm e baixar
# uma segunda cópia do SDK por git (github.com). Mesmo aviso do roteiro Windows do Desmalha.
FVM_CACHE="${FVM_CACHE_PATH:-$HOME/fvm}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
FLUTTER_DIR="$FVM_CACHE/versions/$FLUTTER_VERSION"
PUB_BIN="$HOME/.pub-cache/bin"
COM_ANDROID="${SINCROVOLT_COM_ANDROID:-0}"

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

# Repo é opcional: acha a raiz pelo .fvmrc a partir do script ou do diretório atual.
REPO_ROOT=""
for c in "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" "$PWD"; do
  if [ -n "$c" ] && [ -f "$c/.fvmrc" ] && grep -q '"flutter"' "$c/.fvmrc"; then REPO_ROOT="$c"; break; fi
done
if [ -n "$REPO_ROOT" ]; then
  fvmrc_version="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/.fvmrc")"
  [ "$fvmrc_version" = "$FLUTTER_VERSION" ] || \
    fail ".fvmrc pede Flutter '$fvmrc_version' mas este script fixa $FLUTTER_VERSION — alinhe os dois (versão só muda por card)."
  log "repo: $REPO_ROOT"
else
  log "rodando fora do repo (setup de ambiente de nuvem): só toolchain"
fi

command -v curl >/dev/null || fail "curl ausente."
command -v xz >/dev/null || { command -v apt-get >/dev/null && { SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"; $SUDO apt-get update -qq && $SUDO apt-get install -y -qq xz-utils; }; }
command -v xz >/dev/null || fail "xz ausente (necessário para o tarball do Flutter)."

# ------------------------------------------------- Flutter (tarball oficial)
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

# ------------------------------------------------------------------- FVM
log "FVM $FVM_VERSION"
if ! "$FLUTTER_DIR/bin/dart" pub global list 2>/dev/null | grep -q "^fvm $FVM_VERSION\$"; then
  "$FLUTTER_DIR/bin/dart" pub global activate fvm "$FVM_VERSION" >/dev/null \
    || fail "dart pub global activate fvm falhou — domínio pub.dev bloqueado?"
fi
command -v fvm >/dev/null || fail "fvm não ficou no PATH ($PUB_BIN)."
fvm --version

# ----------------------------------------------- Android (opcional, opt-in)
if [ "$COM_ANDROID" = "1" ]; then
  log "JDK 17"
  JDK17_HOME=""
  for d in /usr/lib/jvm/java-17-openjdk-amd64 /usr/lib/jvm/temurin-17-jdk-amd64; do
    [ -x "$d/bin/javac" ] && JDK17_HOME="$d" && break
  done
  if [ -z "$JDK17_HOME" ]; then
    SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq openjdk-17-jdk-headless unzip \
      || fail "apt-get openjdk-17 falhou — archive.ubuntu.com bloqueado?"
    JDK17_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
  fi
  export JAVA_HOME="$JDK17_HOME"

  log "Android SDK"
  SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [ ! -x "$SDKMANAGER" ]; then
    tmp="$(mktemp -d)"
    curl -fsSL --retry 3 -o "$tmp/cmdtools.zip" "$CMDLINE_TOOLS_URL" \
      || fail "download das cmdline-tools falhou — domínio dl.google.com bloqueado?"
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    unzip -q "$tmp/cmdtools.zip" -d "$tmp"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$tmp"
  fi
  yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
  "$SDKMANAGER" --install "platform-tools" "platforms;$ANDROID_PLATFORM" \
    "build-tools;$BUILD_TOOLS" "ndk;$NDK_VERSION" >/dev/null \
    || fail "sdkmanager --install falhou (rede/licenças?)."
  "$FLUTTER_DIR/bin/flutter" config --android-sdk "$ANDROID_HOME" >/dev/null
else
  log "Android PULADO (padrão). Para incluir: SINCROVOLT_COM_ANDROID=1 bash tool/setup_env.sh"
fi

# --------------------------------------------- PATH para as próximas shells
LINHAS="export PATH=\"$PUB_BIN:$FLUTTER_DIR/bin:\$PATH\""
[ "$COM_ANDROID" = "1" ] && LINHAS="$LINHAS
export JAVA_HOME=\"$JAVA_HOME\"
export ANDROID_HOME=\"$ANDROID_HOME\"
export ANDROID_SDK_ROOT=\"$ANDROID_HOME\"
export PATH=\"\$JAVA_HOME/bin:\$ANDROID_HOME/platform-tools:\$PATH\""

if [ -n "$REPO_ROOT" ]; then
  printf '# Gerado por tool/setup_env.sh — source tool/env\n%s\n' "$LINHAS" > "$REPO_ROOT/tool/env"
  log "escrito $REPO_ROOT/tool/env"
fi
if [ "$(id -u)" -eq 0 ]; then
  # nuvem: vale para toda shell, sem precisar de source
  printf '# SincroVolt — gerado por tool/setup_env.sh\n%s\n' "$LINHAS" > /etc/profile.d/sincrovolt.sh
  for b in flutter dart; do ln -sf "$FLUTTER_DIR/bin/$b" "/usr/local/bin/$b"; done
  ln -sf "$PUB_BIN/fvm" /usr/local/bin/fvm
  grep -q 'profile.d/sincrovolt.sh' "$HOME/.bashrc" 2>/dev/null || echo '. /etc/profile.d/sincrovolt.sh' >> "$HOME/.bashrc"
fi

# -------------------------------------------- dependências do repo (se houver)
if [ -n "$REPO_ROOT" ]; then
  log "pub get (núcleo e app)"
  (cd "$REPO_ROOT/packages/sincrovolt_core" && fvm dart pub get >/dev/null) || fail "pub get do sincrovolt_core falhou."
  (cd "$REPO_ROOT/apps/sincrovolt_app" && fvm flutter pub get >/dev/null) || fail "pub get do sincrovolt_app falhou."
fi

log "ambiente pronto (Flutter $FLUTTER_VERSION, FVM $FVM_VERSION, Android: $([ "$COM_ANDROID" = 1 ] && echo sim || echo não))"
