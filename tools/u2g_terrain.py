#!/usr/bin/env python3
"""Extract Unity TerrainData -> compact height maps + splatmaps for Godot."""
import os, json
import numpy as np
from PIL import Image
import UnityPy

SRC = os.environ.get("UNITY_ASSETS")
if SRC is None:
    for cand in ("/home/user/unity_src/Assets",
                 "/home/user/unity_src/claude-opus-5-5-test2/Assets"):
        if os.path.isdir(cand):
            SRC = cand
            break
DST = "/home/user/godot_game/assets/terrain"
os.makedirs(DST, exist_ok=True)
log = lambda *a: print(*a, flush=True)


def downsample(a, n):
    """bilinear-ish resample of square array a to (n, n)"""
    r = a.shape[0]
    idx = (np.arange(n) * (r - 1) / (n - 1)).astype(np.float32)
    i0 = np.floor(idx).astype(int); i1 = np.minimum(i0 + 1, r - 1)
    w = idx - i0
    tmp = a[i0][:, :] * (1 - w)[:, None] + a[i1][:, :] * w[:, None]
    tmp2 = tmp[:, i0] * (1 - w)[None, :] + tmp[:, i1] * w[None, :]
    return tmp2


def main():
    p = os.path.join(SRC, "Generated/Terrain/IslandTerrain.asset")
    if not os.path.exists(p):
        log("      terrain asset not found, keeping existing data")
        return
    env = UnityPy.load(p)
    tt = [o for o in env.objects if o.type.name == "TerrainData"][0].read_typetree()
    hm = tt["m_Heightmap"]; sc = hm["m_Scale"]; res = hm["m_Resolution"]
    h = np.array(hm["m_Heights"], dtype=np.uint16).reshape(res, res).astype(np.float32)
    h = np.flipud(h) / 65535.0 * sc["y"]          # -> metres
    size_x = (res - 1) * sc["x"]; size_z = (res - 1) * sc["z"]
    log("      island %.0f x %.0f m, height %.1f - %.1f m" % (size_x, size_z, h.min(), h.max()))

    for n in (257, 513):
        small = downsample(h, n).astype(np.float32)
        small.tofile(os.path.join(DST, "height_%d.f32.bin" % n))
        log("      height_%d.f32.bin  %.0f KB" % (n, small.nbytes / 1024))

    json.dump({"size_x": size_x, "size_z": size_z, "height_scale": sc["y"],
               "res_257": 257, "res_513": 513, "src_res": res},
              open(os.path.join(DST, "height_meta.json"), "w"), indent=2)

    n = 0
    for obj in env.objects:
        if obj.type.name == "Texture2D":
            try:
                img = obj.read().image.convert("RGBA").resize((512, 512), Image.BILINEAR)
                img.save(os.path.join(DST, "splat_%d.png" % n))
                log("      splat_%d.png (512x512)" % n)
                n += 1
            except Exception as e:
                log("      ! texture: %s" % e)
    log("      terrain data OK")


if __name__ == "__main__":
    main()
