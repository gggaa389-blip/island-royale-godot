#!/usr/bin/env bash
# Prepare: Godot 4.7.2 editor + export templates + Android SDK + JDK 17
set -o pipefail
TOOLS=/home/user/tools
mkdir -p "$TOOLS" "$HOME/.local/share/godot/export_templates"
cd "$TOOLS"
log(){ echo "[$(date +%H:%M:%S)] $*"; }

GODOT_VER=4.7.2

# ---------- 1. Godot editor ----------
if [ ! -f "$TOOLS/godot" ]; then
  log "Downloading Godot ${GODOT_VER} editor (74MB)..."
  curl -sL --retry 3 -o godot.zip \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip" \
    && unzip -q -o godot.zip && mv Godot_v*.x86_64 godot && chmod +x godot && rm -f godot.zip \
    && log "Godot editor OK" || log "GODOT EDITOR FAILED"
else
  log "Godot editor already present"
fi

# ---------- 2. Export templates (1.2GB) ----------
if [ ! -d "$HOME/.local/share/godot/export_templates/${GODOT_VER}.stable" ]; then
  log "Downloading export templates (1.2GB - this takes a while)..."
  curl -sL --retry 3 -o templates.tpz \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_export_templates.tpz" \
    && unzip -q -o templates.tpz && rm -f templates.tpz \
    && mv templates "$HOME/.local/share/godot/export_templates/${GODOT_VER}.stable" \
    && log "Export templates OK" || log "TEMPLATES FAILED"
else
  log "Export templates already present"
fi

# ---------- 3. JDK 17 ----------
if [ ! -x "$TOOLS/jdk17/bin/java" ]; then
  log "Downloading JDK 17 (Temurin)..."
  curl -sL --retry 3 -o jdk17.tar.gz \
    "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse" \
    && mkdir -p jdk17 && tar xzf jdk17.tar.gz -C jdk17 --strip-components=1 && rm -f jdk17.tar.gz \
    && log "JDK 17 OK: $($TOOLS/jdk17/bin/java -version 2>&1 | head -1)" || log "JDK FAILED"
else
  log "JDK 17 already present"
fi

# ---------- 4. Android SDK ----------
export ANDROID_HOME=$TOOLS/android-sdk
# Godot keeps the Android SDK path in the editor settings, which live outside
# the workspace and are wiped between turns - always point it at our SDK.
ES="$HOME/.config/godot/editor_settings-4.7.tres"
if [ -f "$ES" ]; then
  if grep -q 'export/android/android_sdk_path' "$ES"; then
    sed -i "s|export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$ANDROID_HOME\"|" "$ES"
  else
    echo "export/android/android_sdk_path = \"$ANDROID_HOME\"" >> "$ES"
  fi
fi
export ANDROID_SDK_ROOT=$ANDROID_HOME
mkdir -p "$ANDROID_HOME"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  log "Downloading Android commandline-tools..."
  OK=0
  for F in commandlinetools-linux-11076708_latest.zip commandlinetools-linux-13114758_latest.zip commandlinetools-linux-9477386_latest.zip; do
    if curl -sfL --retry 2 -o cmdline.zip "https://dl.google.com/android/repository/$F"; then OK=1; log "got $F"; break; fi
  done
  if [ "$OK" = 1 ]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    unzip -q -o cmdline.zip -d "$ANDROID_HOME/cmdline-tools" && rm -f cmdline.zip
    # zip root folder is named "cmdline-tools"; normalise to "latest"
    if [ -d "$ANDROID_HOME/cmdline-tools/cmdline-tools" ]; then
      mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    fi
    log "cmdline-tools OK"
  else
    log "CMDLINE-TOOLS FAILED"
  fi
fi

if [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  export PATH=$TOOLS/jdk17/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
  log "Installing Android platform 34 + build-tools 34 + platform-tools..."
  yes 2>/dev/null | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1
  sdkmanager --sdk_root="$ANDROID_HOME" "platform-tools" "platforms;android-34" "build-tools;34.0.0" 2>&1 | tail -5
  log "Android SDK install finished"
fi

# ---------- summary ----------
log "================ SUMMARY ================"
[ -f "$TOOLS/godot" ] && log "godot: $("$TOOLS/godot" --version 2>/dev/null || ./godot --version)"
log "templates dir: $(ls "$HOME/.local/share/godot/export_templates/" 2>/dev/null | tr '\n' ' ')"
[ -x "$TOOLS/jdk17/bin/java" ] && log "jdk17: OK"
[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] && log "sdkmanager: OK"
log "platforms: $(ls "$ANDROID_HOME/platforms" 2>/dev/null | tr '\n' ' ')"
log "build-tools: $(ls "$ANDROID_HOME/build-tools" 2>/dev/null | tr '\n' ' ')"
log "disk left: $(df -h /home/user | awk 'NR==2{print $4}')"
log "=============== DONE ================"
