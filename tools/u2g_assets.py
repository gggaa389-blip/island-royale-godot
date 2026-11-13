#!/usr/bin/env python3
"""
Unity -> Godot 4 asset pipeline (Phase 1)
- builds guid -> asset map
- copies + optimises textures and models for mobile
- converts Unity .mat -> Godot .tres StandardMaterial3D
"""
import os, re, json, shutil, sys
from PIL import Image

SRC = os.environ.get("UNITY_ASSETS")
if SRC is None:
    for cand in ("/home/user/unity_src/Assets",
                 "/home/user/unity_src/claude-opus-5-5-test2/Assets"):
        if os.path.isdir(cand):
            SRC = cand
            break
DST = "/home/user/godot_game"
TEX_DST = os.path.join(DST, "assets/textures")
MOD_DST = os.path.join(DST, "assets/models")
MAT_DST = os.path.join(DST, "assets/materials")
for d in (TEX_DST, MOD_DST, MAT_DST):
    os.makedirs(d, exist_ok=True)

MAX_TEX = int(os.environ.get("MAX_TEX", "1024"))   # mobile cap
log = lambda *a: print(*a, flush=True)

# ---------------------------------------------------------------- guid map
def build_guid_map():
    gmap = {}
    for root, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if d != ".fbm"]
        for fn in files:
            if fn.endswith(".meta"):
                asset = os.path.join(root, fn[:-5])
                if not os.path.exists(asset):
                    continue
                try:
                    with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as f:
                        for line in f:
                            m = re.match(r"guid:\s*([0-9a-fA-F]{32})", line)
                            if m:
                                gmap[m.group(1)] = asset
                                break
                except OSError:
                    pass
    return gmap

# ---------------------------------------------------------------- helpers
def safe_name(p, prefix=""):
    """flat unique destination filename"""
    rel = os.path.relpath(p, SRC).replace(os.sep, "_")
    rel = re.sub(r"[^A-Za-z0-9._-]", "_", rel)
    return prefix + rel

def copy_model(src):
    dst = os.path.join(MOD_DST, safe_name(src))
    if not os.path.exists(dst):
        shutil.copy2(src, dst)
    # external FBX textures live in <name>.fbm next to the model
    fbm = os.path.splitext(src)[0] + ".fbm"
    if os.path.isdir(fbm):
        dfbm = dst + ".fbm"
        os.makedirs(dfbm, exist_ok=True)
        for fn in os.listdir(fbm):
            s = os.path.join(fbm, fn)
            d = os.path.join(dfbm, fn)
            if os.path.exists(d) or not os.path.isfile(s):
                continue
            if fn.lower().endswith((".png", ".jpg", ".jpeg", ".tga")):
                optimise_texture(s, d)
            else:
                shutil.copy2(s, d)
    return dst

def optimise_texture(src, dst):
    """downscale + drop alpha when unused; keeps size sane for mobile"""
    try:
        im = Image.open(src)
    except Exception:
        shutil.copy2(src, dst)
        return
    im.load()
    w, h = im.size
    if max(w, h) > MAX_TEX:
        r = MAX_TEX / float(max(w, h))
        im = im.resize((max(1, int(w * r)), max(1, int(h * r))), Image.LANCZOS)
    # flatten modes Godot dislikes
    if im.mode in ("I;16", "I", "F"):
        im = im.convert("L")
    elif im.mode == "P":
        im = im.convert("RGBA")
    elif im.mode not in ("RGB", "RGBA", "L", "LA"):
        im = im.convert("RGBA")
    ext = os.path.splitext(dst)[1].lower()
    if ext in (".jpg", ".jpeg"):
        if im.mode == "RGBA":
            im = im.convert("RGB")
        im.save(dst, "JPEG", quality=88, optimize=True)
    else:
        im.save(dst, "PNG", optimize=True)

def copy_texture(src):
    dst = os.path.join(TEX_DST, safe_name(src))
    if not os.path.exists(dst):
        optimise_texture(src, dst)
    return dst

# ---------------------------------------------------------------- materials
def parse_simple_yaml(path):
    """light parser for Unity .mat files -> dict"""
    doc = {"m_TexEnvs": {}, "m_Floats": {}, "m_Colors": {}, "m_Ints": {}}
    cur = None
    last_tex_key = [None]
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.rstrip("\n")
            if not s.strip():
                continue
            ind = len(s) - len(s.lstrip())
            t = s.strip()
            m = re.match(r"^m_Name:\s*(.*)$", t)
            if m:
                doc["m_Name"] = m.group(1).strip()
                continue
            m = re.match(r"^m_Shader:\s*\{fileID:\s*(-?\d+),\s*guid:\s*([0-9a-fA-F]+),\s*type:\s*\d+\}", t)
            if m:
                doc["shader_fileID"] = int(m.group(1))
                doc["shader_guid"] = m.group(2)
                continue
            if t in ("m_TexEnvs:", "m_Floats:", "m_Colors:", "m_Ints:"):
                cur = t[:-1]
                continue
            if t.startswith("m_") and t.endswith(":"):
                cur = None
                continue
            if cur in ("m_TexEnvs", "m_Floats", "m_Colors", "m_Ints"):
                # list entries:  - _Name: value
                m = re.match(r"^-?\s*(-?\w+):\s*(.*)$", t)
                if m:
                    key, val = m.group(1), m.group(2).strip()
                    if cur == "m_TexEnvs":
                        if val == "" and not key.startswith("m_"):
                            doc[cur][key] = {}
                            last_tex_key[0] = key
                        elif key == "m_Texture" and val.startswith("{"):
                            mm = re.search(r"guid:\s*([0-9a-fA-F]{32})", val)
                            mf = re.search(r"fileID:\s*(-?\d+)", val)
                            if last_tex_key[0]:
                                doc[cur].setdefault(last_tex_key[0], {})
                                doc[cur][last_tex_key[0]]["guid"] = mm.group(1) if mm else None
                                doc[cur][last_tex_key[0]]["fileID"] = int(mf.group(1)) if mf else 0
                        elif val.startswith("{"):
                            mm = re.search(r"guid:\s*([0-9a-fA-F]{32})", val)
                            if mm:
                                doc[cur][key] = val
                        else:
                            doc[cur][key] = val
                    else:
                        doc[cur][key] = val
    # second pass: texture scale/offset rows
    return doc

def gcol(v):
    m = re.match(r"\{r:\s*([\d.eE+-]+),\s*g:\s*([\d.eE+-]+),\s*b:\s*([\d.eE+-]+),\s*a:\s*([\d.eE+-]+)\}", v)
    if m:
        return "Color(%s, %s, %s, %s)" % tuple(x if "." in x or "e" in x.lower() else x + ".0" for x in m.groups())
    return None

def convert_material(mat_path, gmap, out_index):
    d = parse_simple_yaml(mat_path)
    name = d.get("m_Name") or os.path.splitext(os.path.basename(mat_path))[0]
    texs = d["m_TexEnvs"]
    floats = d["m_Floats"]
    colors = d["m_Colors"]

    ext = []
    body = []
    n = 0
    def add_tex(prop, slot):
        nonlocal n
        info = texs.get(prop)
        if not info or not info.get("guid"):
            return None
        src = gmap.get(info["guid"])
        if not src or not os.path.exists(src):
            return None
        gd = copy_texture(src)
        n += 1
        rid = "tex_%d" % n
        ext.append('[ext_resource type="Texture2D" path="res://%s" id="%s"]'
                   % (os.path.relpath(gd, DST).replace(os.sep, "/"), rid))
        return rid

    albedo = add_tex("_MainTex", "albedo")
    normal = add_tex("_BumpMap", "normal")
    if normal is None:
        normal = add_tex("_NormalMap", "normal")
    metallic_tex = add_tex("_MetallicGlossMap", "metallic")

    if albedo:
        body.append("albedo_texture = ExtResource(\"%s\")" % albedo)
    if normal:
        body.append("normal_enabled = true")
        body.append("normal_texture = ExtResource(\"%s\")" % normal)

    c = colors.get("_Color")
    if c:
        cc = gcol(c)
        if cc:
            body.append("albedo_color = %s" % cc)

    # standard shader: smoothness -> roughness, metallic
    if "_Glossiness" in floats:
        try:
            g = float(floats["_Glossiness"])
            body.append("roughness = %.3f" % max(0.0, min(1.0, 1.0 - g)))
        except ValueError:
            pass
    if "_Metallic" in floats:
        try:
            m = float(floats["_Metallic"])
            body.append("metallic = %.3f" % max(0.0, min(1.0, m)))
        except ValueError:
            pass
    if "_GlossMapScale" in floats and metallic_tex:
        pass

    # transparency
    if "_Mode" in floats:
        try:
            mode = int(float(floats["_Mode"]))
            if mode == 2 or mode == 3:
                body.append("transparency = 1")
        except ValueError:
            pass

    stem = re.sub(r"[^A-Za-z0-9_-]", "_", name)
    out = os.path.join(MAT_DST, stem + ".tres")
    k = 2
    while out in out_index:
        out = os.path.join(MAT_DST, "%s_%d.tres" % (stem, k)); k += 1
    out_index.add(out)
    with open(out, "w") as f:
        f.write('[gd_resource type="StandardMaterial3D" format=3]\n\n')
        for e in ext:
            f.write(e + "\n")
        if ext:
            f.write("\n")
        f.write("[resource]\n")
        f.write("\n".join(body) if body else "roughness = 0.85\n")
        f.write("\n")
    return out, name

# ---------------------------------------------------------------- main
def main():
    log("[1/4] building guid map ...")
    gmap = build_guid_map()
    log("      %d assets indexed" % len(gmap))
    json.dump(gmap, open(os.path.join(DST, "guid_map.json"), "w"))

    log("[2/4] copying + optimising models (cap %dpx textures) ..." % MAX_TEX)
    models = [p for p in gmap.values() if p.lower().endswith((".fbx", ".glb"))]
    model_dst = {}
    for i, m in enumerate(models, 1):
        try:
            model_dst[m] = copy_model(m)
        except Exception as e:
            log("      ! model %s: %s" % (os.path.basename(m), e))
    log("      %d models copied" % len(model_dst))
    json.dump(model_dst, open(os.path.join(DST, "model_map.json"), "w"))

    log("[3/4] converting materials ...")
    mats = [p for p in gmap.values() if p.endswith(".mat")]
    ok = 0
    used = set()
    for m in mats:
        try:
            convert_material(m, gmap, used)
            ok += 1
        except Exception as e:
            log("      ! material %s: %s" % (os.path.basename(m), e))
    log("      %d/%d materials converted" % (ok, len(mats)))

    log("[4/4] done.")
    for d, label in ((MOD_DST, "models"), (TEX_DST, "textures"), (MAT_DST, "materials")):
        sz = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(d) for f in fs)
        cnt = sum(len(fs) for _, _, fs in os.walk(d))
        log("      %-10s %4d files  %7.1f MB" % (label, cnt, sz / 1048576))

if __name__ == "__main__":
    main()
