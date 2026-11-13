#!/usr/bin/env python3
"""
Unity -> Godot 4 : prefab conversion + island placement extraction
Outputs compact placement data consumed by Godot at runtime (keeps workspace small).
"""
import os, re, json, struct, sys

SRC = os.environ.get("UNITY_ASSETS")
if SRC is None:
    for cand in ("/home/user/unity_src/Assets",
                 "/home/user/unity_src/claude-opus-5-5-test2/Assets"):
        if os.path.isdir(cand):
            SRC = cand
            break
DST = "/home/user/godot_game"
PREF_DST = os.path.join(DST, "assets/prefabs")
DATA_DST = os.path.join(DST, "assets/data")
for d in (PREF_DST, DATA_DST):
    os.makedirs(d, exist_ok=True)
log = lambda *a: print(*a, flush=True)

# ---------------------------------------------------------------- streaming parse
def iter_docs(path):
    """yield (class_id, file_id, type_name, lines[]) with low memory use"""
    cur = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("--- !u!"):
                if cur:
                    yield cur
                m = re.match(r"--- !u!(\d+) &(-?\d+)", line)
                cur = [int(m.group(1)), int(m.group(2)), None, []] if m else None
                continue
            if cur is None:
                continue
            if line and not line[0].isspace() and line.rstrip().endswith(":"):
                cur[2] = line.strip()[:-1]
                continue
            cur[3].append(line.rstrip("\n"))
    if cur:
        yield cur


def scalar(txt, key, default=None):
    m = re.search(r"^\s*%s:\s*(.+)$" % key, txt, re.M)
    return m.group(1).strip() if m else default


def vec3(txt, key, default=(0.0, 0.0, 0.0)):
    m = re.search(r"^\s*%s:\s*\{x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+),\s*z:\s*([-\d.eE+]+)\}" % key,
                  txt, re.M)
    if m:
        return tuple(float(g) for g in m.groups())
    return default


def guid_of(txt, key):
    m = re.search(r"^\s*%s:.*guid:\s*([0-9a-fA-F]{32})" % key, txt, re.M)
    return m.group(1) if m else None


# ---------------------------------------------------------------- prefab instances
def extract_placements(scene_path, gmap):
    """Island.unity -> list of {prefab, parent, pos, rot, scale}"""
    out = []
    seen_parents = {}
    for cls, fid, typ, lines in iter_docs(scene_path):
        if typ != "PrefabInstance":
            continue
        txt = "\n".join(lines)

        # source prefab guid
        pguid = guid_of(txt, "m_SourcePrefab")
        if not pguid:
            pguid = guid_of(txt, "target")
        if not pguid:
            continue

        # parent transform fileID (0 = scene root)
        pm = re.search(r"m_TransformParent:\s*\{fileID:\s*(-?\d+)\}", txt)
        parent = int(pm.group(1)) if pm else 0

        # root transform modifications
        pos, rot, scl = [0.0] * 3, [0.0, 0.0, 0.0, 1.0], [1.0] * 3
        for m in re.finditer(
                r"propertyPath:\s*(m_Local(?:Position|Rotation|Scale)\.[xyzw])\s*\n\s*value:\s*([-\d.eE+]+)", txt):
            prop, val = m.group(1), float(m.group(2))
            axis = prop[-1]
            idx = "xyzw".index(axis)
            if "Position" in prop:
                pos[idx] = val
            elif "Rotation" in prop:
                rot[idx] = val
            else:
                scl[idx] = val
        out.append({"g": pguid, "p": parent, "t": pos, "r": rot, "s": scl})
    log("      %d prefab instances" % len(out))
    return out


# ---------------------------------------------------------------- prefab -> godot scene
def convert_prefab(pref_path, gmap, model_map, mat_map):
    """Unity .prefab -> Godot .tscn (Node3D + instanced model children)"""
    gameobjects = {}
    transforms = {}
    filters = {}
    renderers = {}

    for cls, fid, typ, lines in iter_docs(pref_path):
        txt = "\n".join(lines)
        if typ == "GameObject":
            name = scalar(txt, "m_Name", "go")
            gameobjects[fid] = name
        elif typ == "Transform":
            m1 = re.search(r"m_GameObject:\s*\{fileID:\s*(-?\d+)\}", txt)
            m2 = re.search(r"m_Father:\s*\{fileID:\s*(-?\d+)\}", txt)
            if not m1:
                continue
            qm = re.search(r"m_LocalRotation:\s*\{x:\s*([-\d.eE+]+),\s*y:\s*([-\d.eE+]+),\s*z:\s*([-\d.eE+]+),\s*w:\s*([-\d.eE+]+)\}", txt)
            quat = tuple(float(g) for g in qm.groups()) if qm else (0.0, 0.0, 0.0, 1.0)
            transforms[fid] = (int(m1.group(1)), int(m2.group(1)) if m2 else 0,
                               vec3(txt, "m_LocalPosition"), quat, vec3(txt, "m_LocalScale"))
        elif typ == "MeshFilter":
            m1 = re.search(r"m_GameObject:\s*\{fileID:\s*(-?\d+)\}", txt)
            if m1:
                filters[int(m1.group(1))] = guid_of(txt, "m_Mesh")
        elif typ in ("MeshRenderer", "SkinnedMeshRenderer"):
            m1 = re.search(r"m_GameObject:\s*\{fileID:\s*(-?\d+)\}", txt)
            if m1:
                renderers[int(m1.group(1))] = re.findall(r"guid:\s*([0-9a-fA-F]{32})", txt)

    if not transforms:
        return None

    # unique node names, keyed by transform id (parents are referenced by NAME in Godot)
    name_map = {}
    used = set()
    for tf, (go, dad, pos, quat, scl) in transforms.items():
        base = re.sub(r"[^A-Za-z0-9_ -]", "_", gameobjects.get(go, "node"))[:40] or "node"
        nm = base
        k = 2
        while nm in used:
            nm = base + str(k)
            k += 1
        used.add(nm)
        name_map[tf] = nm

    # emit parents before children
    order = []
    emitted = set()

    def emit(tf, depth=0):
        if tf in emitted or tf not in transforms or depth > 64:
            return
        dad = transforms[tf][1]
        if dad and dad in transforms and dad != tf:
            emit(dad, depth + 1)
        if tf in emitted:
            return
        emitted.add(tf)
        order.append(tf)

    for tf in transforms:
        emit(tf)

    ext_map = {}
    ext_lines = []
    node_lines = []
    # Godot resolves node parents relative to the scene ROOT:
    #   root          -> no parent attribute
    #   child of root -> parent="."
    #   deeper        -> parent="a/b"
    root_tf = order[0] if order else None
    paths = {}
    for tf in order:
        go, dad, pos, quat, scl = transforms[tf]
        if tf == root_tf:
            paths[tf] = "."
        else:
            dp = paths.get(dad, ".")
            paths[tf] = name_map[tf] if dp == "." else dp + "/" + name_map[tf]

    for tf in order:
        go, dad, pos, quat, scl = transforms[tf]
        name = name_map[tf]
        attrs = []
        if tf != root_tf:
            pth = paths.get(dad, ".")
            attrs.append('parent="%s"' % pth)
        qx, qy, qz, qw = quat
        mesh_guid = filters.get(go)
        model = model_map.get(gmap.get(mesh_guid, "")) if mesh_guid else None
        # Godot 4 requires the scene instance on the [node] header line,
        # not as a property assignment.
        if model:
            if model not in ext_map:
                ext_map[model] = "m%d" % (len(ext_map) + 1)
            attrs.append('instance=ExtResource("%s")' % ext_map[model])
        node_lines.append('[node name="%s" type="Node3D"%s]' % (name, "".join(" " + a for a in attrs)))
        node_lines.append("transform = Transform3D(%s)" % ", ".join(
            "%.6g" % v for v in _basis_from_quat(qx, qy, qz, qw, scl, pos)))
        node_lines.append("")

    head = ['[gd_scene load_steps=%d format=3]' % (len(ext_map) + 2), ""]
    for model, rid in ext_map.items():
        rel = os.path.relpath(model, DST).replace(os.sep, "/")
        head.append('[ext_resource type="PackedScene" path="res://%s" id="%s"]' % (rel, rid))
    if ext_map:
        head.append("")

    name = os.path.splitext(os.path.basename(pref_path))[0]
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", name)
    path_out = os.path.join(PREF_DST, safe + ".tscn")
    with open(path_out, "w") as f:
        f.write("\n".join(head + node_lines))
    return path_out


def _basis_from_quat(x, y, z, w, s, t):
    # quaternion -> 3x3 basis (columns) scaled, then translation
    x2, y2, z2 = x + x, y + y, z + z
    xx, xy, xz = x * x2, x * y2, x * z2
    yy, yz, zz = y * y2, y * z2, z * z2
    wx, wy, wz = w * x2, w * y2, w * z2
    m = [1 - (yy + zz), xy + wz, xz - wy,
         xy - wz, 1 - (xx + zz), yz + wx,
         xz + wy, yz - wx, 1 - (xx + yy)]
    m = [m[i] for i in (0, 3, 6, 1, 4, 7, 2, 5, 8)]  # to column-major rows
    return (m[0] * s[0], m[1] * s[0], m[2] * s[0],
            m[3] * s[1], m[4] * s[1], m[5] * s[1],
            m[6] * s[2], m[7] * s[2], m[8] * s[2],
            t[0], t[1], t[2])


# ---------------------------------------------------------------- main
def main():
    log("[scene] loading maps ...")
    gmap = json.load(open(os.path.join(DST, "guid_map.json")))
    model_map = json.load(open(os.path.join(DST, "model_map.json")))

    scene = os.path.join(SRC, "Scenes/Island.unity")
    log("[scene] extracting island placements ...")
    pl = extract_placements(scene, gmap)

    # keep only prefabs that actually exist
    used = {}
    for p in pl:
        used[p["g"]] = used.get(p["g"], 0) + 1
    log("      %d distinct prefabs used" % len(used))

    prefab_paths = {g: p for p in gmap.values() if p.endswith(".prefab") for g, pp in [(None, p)]}
    prefab_by_guid = {}
    for g, p in gmap.items():
        if p.endswith(".prefab"):
            prefab_by_guid[g] = p
    log("      %d prefabs in project" % len(prefab_by_guid))

    log("[scene] converting used prefabs -> godot scenes ...")
    conv = {}
    for g, cnt in sorted(used.items(), key=lambda x: -x[1]):
        pp = prefab_by_guid.get(g)
        if not pp:
            continue
        try:
            out = convert_prefab(pp, gmap, model_map, None)
            if out:
                conv[g] = os.path.relpath(out, DST).replace(os.sep, "/")
        except Exception as e:
            log("      ! prefab %s: %s" % (os.path.basename(pp), e))
    log("      %d prefabs converted" % len(conv))

    json.dump({"placements": pl, "prefabs": conv},
              open(os.path.join(DATA_DST, "island_placements.json"), "w"))
    sz = os.path.getsize(os.path.join(DATA_DST, "island_placements.json")) / 1048576
    log("[scene] wrote island_placements.json (%.1f MB)" % sz)
    log("[scene] done.")


if __name__ == "__main__":
    main()
