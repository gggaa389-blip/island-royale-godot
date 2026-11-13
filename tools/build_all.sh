#!/usr/bin/env bash
# ============================================================================
#  Unity (Island BR) -> Godot 4 -> Android APK   :  full reproducible pipeline
#  Large files do NOT survive workspace snapshots, so this re-downloads the
#  source every run (takes ~15 s) and rebuilds everything from scratch.
#  Usage:  GITHUB_TOKEN=xxx bash tools/build_all.sh [skip_download]
# ============================================================================
set -o pipefail
HERE=/home/user
TOOLS=$HERE/tools
SRC=$HERE/unity_src
DST=$HERE/godot_game
GODOT=$TOOLS/godot
export JAVA_HOME=$TOOLS/jdk17
export ANDROID_HOME=$TOOLS/android-sdk
export ANDROID_SDK_ROOT=$TOOLS/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx600m -Dorg.gradle.daemon=false"
log(){ echo; echo "===== $* ====="; }

DRIVE_ID=1fToNIlJSdIdtPKfHeRJi_HEtdrOnrbWB
DRIVE_URL="https://drive.usercontent.google.com/download?id=$DRIVE_ID&export=download&confirm=t"

# ---------------------------------------------------------------- 0. deps
log "installing python deps"
python3 -c "import UnityPy" 2>/dev/null || pip3 install --quiet UnityPy 2>&1 | tail -1
python3 -c "import numpy"   2>/dev/null || pip3 install --quiet numpy   2>&1 | tail -1
python3 -c "import PIL"     2>/dev/null || pip3 install --quiet pillow  2>&1 | tail -1
echo "deps ready"

# ---------------------------------------------------------------- 0. toolchain
if [ ! -x "$GODOT" ] || [ ! -d "$ANDROID_HOME" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  log "toolchain missing -> installing"
  bash "$TOOLS/setup_env.sh" 2>&1 | tail -20
fi

# ---------------------------------------------------------------- 1. source
if [ "$1" != "skip_download" ]; then
  log "downloading Unity source (~841 MB)"
  rm -rf "$SRC"; mkdir -p "$SRC"
  curl -sL --retry 3 -m 900 -o "$SRC/project.zip" "$DRIVE_URL" || { echo "DOWNLOAD FAILED"; exit 1; }
  ( cd "$SRC" && unzip -q -o project.zip && rm -f project.zip ) || { echo "EXTRACT FAILED"; exit 1; }
  echo "source ready: $(du -sh "$SRC" | cut -f1)"
fi

# ---------------------------------------------------------------- 2. assets
log "converting assets (textures / models / materials)"
MAX_TEX=${MAX_TEX:-1024} python3 "$TOOLS/u2g_assets.py" 2>&1 | tail -6

log "extracting terrain heightmap + splatmaps"
python3 "$TOOLS/u2g_terrain.py" 2>&1 | tail -4

log "converting prefabs + island placements"
python3 "$TOOLS/u2g_scene.py" 2>&1 | tail -4

# ------------------------------------------------------- 2b. slim the build
log "keeping 3 lightweight Mixamo characters + 9 animation clips"
cd "$DST/assets/models"
python3 - <<'PYEOF'
import glob, os
KEEP_CHARS = {"YBot", "Swat", "BigVegas"}
KEEP_ANIMS = {"E_Victory", "N_Death1", "R_Idle", "R_JumpLoop", "R_Reload",
              "Run", "S_Glide", "U_Fall", "U_Throw"}
removed = 0
for f in glob.glob("*.fbx"):
    b = os.path.splitext(f)[0]
    keep = False
    if "_Characters_" in b:
        keep = any(b.endswith(c) for c in KEEP_CHARS)
    elif "_Animations_" in b:
        keep = any(b.endswith(a) for a in KEEP_ANIMS)
    if not keep:
        os.remove(f)
        if os.path.exists(f + ".import"):
            os.remove(f + ".import")
        removed += 1
print("  removed %d unused character/animation FBX" % removed)
PYEOF

log "dropping textures of characters we no longer ship"
cd "$DST/assets/textures"
python3 - <<'PYEOF'
import glob, os
KEEP = ("YBot", "Swat", "BigVegas")
removed = 0
for f in glob.glob("*.*"):
    if f.endswith(".import"):
        continue
    if ("Characters_" in f or f.startswith(("Remy_", "Amy_", "Ortiz_", "Timmy_",
        "Michelle_", "Kate_", "Kaya_", "Claire_", "Aj_", "Ty_", "Ninja_", "Doozy_",
        "Vanguard_", "SportyGranny_", "Jackie_", "Ch")) ):
        if not any(k in f for k in KEEP):
            os.remove(f)
            if os.path.exists(f + ".import"):
                os.remove(f + ".import")
            removed += 1
print("  removed %d unused character textures" % removed)
PYEOF

log "pointing island character prefabs at the kept models"
cd "$DST/assets/prefabs"
for pair in "Kate:YBot" "Remy:Swat" "YBot:BigVegas"; do
  n="${pair%%:*}"; m="${pair##*:}"
  cat > "Mixamo_$n.tscn" <<EOF
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/models/ThirdParty_Mixamo_Characters_$m.fbx" id="m1"]

[node name="Mixamo_$n" type="Node3D" instance=ExtResource("m1")]
EOF
done
echo "  Mixamo_Kate/Remy/YBot repointed"

# ---------------------------------------------------------------- 3. import
log "godot headless import"
( cd "$DST" && "$GODOT" --headless --editor --quit 2>&1 | tail -6 )

# ---------------------------------------------------------------- 4. export APK
log "exporting APK"
( cd "$DST" && "$GODOT" --headless --export-debug "Android" "$DST/build/game.apk" 2>&1 | tail -12 )
if [ -f "$DST/build/game.apk" ]; then
  "$ANDROID_HOME/build-tools/34.0.0/apksigner" verify --print-certs "$DST/build/game.apk" 2>&1 | head -4
  ls -lh "$DST/build/game.apk"
else
  echo "APK EXPORT FAILED"; exit 1
fi

# ---------------------------------------------------------------- 5. github
if [ -n "$GITHUB_TOKEN" ]; then
  log "pushing to GitHub"
  bash "$TOOLS/push_github.sh" 2>&1 | tail -20
fi
log "PIPELINE FINISHED"
