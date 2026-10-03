"""Generate the Verilog column ROM for an on-screen message in a 5-row proportional pixel font.

Usage: python gen_text_rom.py "LACSS 2026 PANAMA" [--alt "MADE BY DAVIS PESCHL"] [--preview out.png]
Each font pixel is 4x4 screen pixels; the ROM is indexed by x[8:2] (x < 512), centred on x = 320.
With --alt, the second message is shown while `over` is set (game-over screen).
"""
import argparse

GLYPHS = {
    "A": ["###", "#.#", "###", "#.#", "#.#"],
    "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": ["###", "#..", "#..", "#..", "###"],
    "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "###", "#..", "###"],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "P": ["###", "#.#", "###", "#..", "#.."],
    "S": ["###", "#..", "###", "..#", "###"],
    "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "0": ["###", "#.#", "#.#", "#.#", "###"],
    "2": ["###", "..#", "###", "#..", "###"],
    "6": ["###", "#..", "###", "#.#", "###"],
    " ": ["#", "#", "#", "#", "#"],  # width only; drawn blank
}


def columns(msg):
    """Return the message as a list of 5-bit columns (bit 4 = top row)."""
    cols = []
    for i, ch in enumerate(msg.upper()):
        g = GLYPHS[ch]
        if i:
            cols.append(0)
        for c in range(len(g[0])):
            v = 0
            if ch != " ":
                for r in range(5):
                    v |= (g[r][c] == "#") << (4 - r)
            cols.append(v)
    return cols


def placed(msg):
    cols = columns(msg)
    start = 80 - len(cols) // 2           # centre on x = 320 (column 80)
    assert start >= 32 and start + len(cols) <= 128, f"'{msg}' does not fit: {len(cols)} columns"
    return start, cols


def verilog(main, alt=None):
    s0, c0 = placed(main)
    lines = []
    if alt is None:
        lines.append(f"  // Mensaje centrado en x = 320: \"{main}\" ({len(c0)} columnas de 4 px)")
        lines.append("  reg [4:0] tcol;   // columna de la fuente, bit 4 = fila superior")
        lines.append("  always @(*) begin")
        lines.append("    case (x[8:2])")
        for i, v in enumerate(c0):
            if v:
                lines.append(f"      7'd{s0 + i}: tcol = 5'b{v:05b};")
    else:
        s1, c1 = placed(alt)
        lines.append(f"  // Mensajes centrados en x = 320: \"{main}\" jugando, \"{alt}\" en game over")
        lines.append("  reg [4:0] tcol;   // columna de la fuente, bit 4 = fila superior")
        lines.append("  always @(*) begin")
        lines.append("    case ({over, x[8:2]})")
        for i, v in enumerate(c0):
            if v:
                lines.append(f"      8'd{s0 + i}: tcol = 5'b{v:05b};")
        for i, v in enumerate(c1):
            if v:
                lines.append(f"      8'd{128 + s1 + i}: tcol = 5'b{v:05b};")
    lines.append("      default: tcol = 5'b00000;")
    lines.append("    endcase")
    lines.append("  end")
    return "\n".join(lines)


def preview(path, msgs):
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (640, 40 * len(msgs)), "black")
    d = ImageDraw.Draw(img)
    for k, m in enumerate(msgs):
        s, cols = placed(m)
        for i, v in enumerate(cols):
            for r in range(5):
                if v >> (4 - r) & 1:
                    x0, y0 = (s + i) * 4, 40 * k + 8 + r * 4
                    d.rectangle([x0, y0, x0 + 3, y0 + 3], fill="white")
    img.save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("msg")
    ap.add_argument("--alt")
    ap.add_argument("--preview")
    a = ap.parse_args()
    print(verilog(a.msg, a.alt))
    if a.preview:
        preview(a.preview, [m for m in (a.msg, a.alt) if m])
