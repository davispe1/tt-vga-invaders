"""Convert tools/logo.txt (#/. pixel grid) into the sky130 met4 art macro in macros/ (GDS + LEF).

Previews go to tools/out/. Requires: pip install gdstk pillow
"""
import sys
from pathlib import Path

import gdstk
from PIL import Image, ImageDraw

HERE = Path(__file__).parent
OUT = HERE.parent / "macros"
PREV = HERE / "out"
PREV.mkdir(exist_ok=True)
CELL = "davispe1_logo"
PIX = 0.5                      # µm per pixel
MET4 = (71, 20)                # met4.drawing
PRB = (235, 4)                 # prBoundary
MIN_AREA = 0.24                # met4 min area (µm²)

rows = [l.rstrip("\n") for l in (HERE / "logo.txt").read_text().splitlines() if l.strip()]
N = len(rows)
assert all(len(r) == N for r in rows), f"grid is not square: {[len(r) for r in rows]}"
orig = [[c == "#" for c in r] for r in rows]
g = [row[:] for row in orig]


def on(x, y):
    return 0 <= x < N and 0 <= y < N and g[y][x]


def border(x, y):
    return x in (0, N - 1) or y in (0, N - 1)


def neighbours(x, y):
    return sum(on(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)


def find_diag():
    out = []
    for y in range(N - 1):
        for x in range(N - 1):
            a, b, c, d = g[y][x], g[y][x + 1], g[y + 1][x], g[y + 1][x + 1]
            if a and d and not b and not c:
                out.append(((x, y), (x + 1, y + 1), [(x + 1, y), (x, y + 1)]))
            elif b and c and not a and not d:
                out.append(((x + 1, y), (x, y + 1), [(x, y), (x + 1, y + 1)]))
    return out


# Bridge every diagonal-only touch by adding the empty pixel with more filled neighbours
added = []
for _ in range(100):
    conflicts = find_diag()
    if not conflicts:
        break
    _, _, cands = conflicts[0]
    cands = [p for p in cands if not border(*p)]
    if not cands:
        sys.exit(f"cannot fix diagonal at {conflicts[0][:2]} without touching the border")
    x, y = max(cands, key=lambda p: neighbours(*p))
    g[y][x] = True
    added.append((x, y))
else:
    sys.exit("diagonal fixing did not converge")

# Build geometry: one rectangle per horizontal run, then merge
rects = []
for r in range(N):
    x = 0
    while x < N:
        if g[r][x]:
            s = x
            while x < N and g[r][x]:
                x += 1
            y0 = (N - 1 - r) * PIX
            rects.append(gdstk.rectangle((s * PIX, y0), (x * PIX, y0 + PIX)))
        else:
            x += 1
polys = gdstk.boolean(rects, [], "or", layer=MET4[0], datatype=MET4[1])

lib = gdstk.Library(unit=1e-6, precision=1e-9)
cell = lib.new_cell(CELL)
W = N * PIX
cell.add(gdstk.rectangle((0, 0), (W, W), layer=PRB[0], datatype=PRB[1]))
cell.add(*polys)
lib.write_gds(OUT / f"{CELL}.gds")
cell.write_svg(PREV / f"{CELL}.svg", background="#ffffff")

(OUT / f"{CELL}.lef").write_text(f"""# LEF file generated for {CELL}
VERSION 5.8 ;
NAMESCASESENSITIVE ON ;
DIVIDERCHAR "/" ;
BUSBITCHARS "[]" ;
UNITS
   DATABASE MICRONS 1000 ;
END UNITS

MACRO {CELL}
   CLASS BLOCK ;
   FOREIGN {CELL} 0 0 ;
   SIZE {W:.3f} BY {W:.3f} ;
   SYMMETRY X Y ;
   OBS
      LAYER met4 ;
         RECT 0.000 0.000 {W:.3f} {W:.3f} ;
   END
END {CELL}
""")
(PREV / "logo_fixed.txt").write_text("\n".join("".join("#" if c else "." for c in r) for r in g) + "\n")

# ---- Checks on the written GDS ----
rd = gdstk.read_gds(OUT / f"{CELL}.gds")
top = rd.cells[0]
art = [p for p in top.polygons if (p.layer, p.datatype) == MET4]
prb = [p for p in top.polygons if (p.layer, p.datatype) == PRB]
areas = sorted(p.area() for p in art)


def holes():
    """Empty regions (4-connected) that do not reach the grid edge."""
    seen, out = set(), []
    for y0 in range(N):
        for x0 in range(N):
            if g[y0][x0] or (x0, y0) in seen:
                continue
            stack, comp, edge = [(x0, y0)], [], False
            seen.add((x0, y0))
            while stack:
                x, y = stack.pop()
                comp.append((x, y))
                edge |= border(x, y)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < N and 0 <= ny < N and not g[ny][nx] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if not edge:
                out.append(len(comp) * PIX * PIX)
    return out


hole_areas = holes()
print(f"cell: {top.name}  size: {W} x {W} um  pixel: {PIX} um")
print(f"met4 polygons: {len(art)}  prBoundary: {len(prb)}")
print(f"pixels: {sum(map(sum, orig))} -> {sum(map(sum, g))}  (+{len(added)} bridges)")
print("bridges (x, y from top):", added)
print(f"smallest metal piece: {areas[0]:.3f} um^2 (min {MIN_AREA})  -> {'OK' if areas[0] >= MIN_AREA else 'FAIL'}")
print(f"enclosed holes: {len(hole_areas)}  smallest: {min(hole_areas) if hole_areas else '-'} um^2")
print(f"diagonal touches left: {len(find_diag())}")

# ---- Preview: original | fixed (bridges orange) | GDS read-back ----
S = 14
PAD = 24
LBL = 28
img = Image.new("RGB", (3 * N * S + 4 * PAD, N * S + PAD + LBL), "white")
d = ImageDraw.Draw(img)


def grid_panel(ox, grid, extra=()):
    for y in range(N):
        for x in range(N):
            col = (30, 30, 30) if grid[y][x] else (245, 245, 245)
            if (x, y) in extra:
                col = (239, 159, 39)
            d.rectangle([ox + x * S, LBL + y * S, ox + (x + 1) * S - 1, LBL + (y + 1) * S - 1], fill=col)


grid_panel(PAD, orig)
# mark original diagonal touches in red
g_backup = [r[:] for r in g]
g[:] = [r[:] for r in orig]
for p1, p2, _ in find_diag():
    for x, y in (p1, p2):
        d.rectangle([PAD + x * S + 2, LBL + y * S + 2, PAD + (x + 1) * S - 3, LBL + (y + 1) * S - 3], outline=(226, 75, 74), width=2)
g[:] = g_backup
grid_panel(2 * PAD + N * S, g, set(added))

ox = 3 * PAD + 2 * N * S
d.rectangle([ox, LBL, ox + N * S - 1, LBL + N * S - 1], fill=(222, 236, 250))
k = S / PIX
for p in art:
    pts = [(ox + px * k, LBL + (W - py) * k) for px, py in p.points]
    d.polygon(pts, fill=(55, 138, 221), outline=(12, 68, 124))
d.text((PAD, 8), "Original (rojo = toque diagonal)", fill=(0, 0, 0))
d.text((2 * PAD + N * S, 8), f"Corregido (naranja = {len(added)} pixeles anadidos)", fill=(0, 0, 0))
d.text((ox, 8), f"GDS met4 leido de vuelta ({len(art)} poligonos)", fill=(0, 0, 0))
img.save(PREV / "preview.png")
print("wrote:", ", ".join(str(p) for p in sorted(OUT.glob(f"{CELL}.*"))), PREV / "preview.png")
