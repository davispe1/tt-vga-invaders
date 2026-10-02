import subprocess, re, os, sys
src = open("src/project.v").read()
TOP = "tt_um_davispe1_invaders"

def rep(s, a, b):
    assert a in s, f"pattern not found: {a[:60]}"
    return s.replace(a, b)

V = {}
V["A_baseline"] = src
V["B_no_text"] = rep(src, "wire txt = top && (in_sc || in_lv) && (cx != 2'd3) && font;", "wire txt = 1'b0;")
V["C_no_sound"] = rep(src, "wire audio = tone & (snd_t != 4'd0);", "wire audio = 1'b0;")
V["D_no_enemy_bullet"] = rep(src, "wire eb_px = eba && (x[9:2] == ebx) && ~y[9] && (y[8:3] == eby);", "wire eb_px = 1'b0;")
V["E_no_player_bullet"] = rep(src, "wire pb_px = pba && (x[9:2] == pbx) && ~y[9] && (y[8:3] == pby);", "wire pb_px = 1'b0;")
s = rep(src, "alive[{arow, acol}] && half[mcol]", "half[mcol]")
V["F_no_alive_array"] = rep(s, "else if (kill) alive[{arow, acol}] <= 1'b0;", "")
V["G_no_vga_reg"] = rep(src, "assign uo_out = vga_q;", "assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};")
V["H_no_ship"] = rep(src, "wire ship_px = (y[9:4] == 6'd28) && (sx[7:3] == 5'd0) && ship[sx[2:0]];", "wire ship_px = 1'b0;")
s = rep(src, "wire [9:0] rx   = x - {fx, 3'b000};", "wire [9:0] rx   = x - 10'd192;")
V["I_fixed_formation"] = rep(s, "wire [9:0] ry   = y - {1'b0, fy, 4'b0000};", "wire [9:0] ry   = y - 10'd64;")
V["J_no_sprite_rom"] = rep(src, "alive[{arow, acol}] && half[mcol]", "alive[{arow, acol}]")
for f in sorted(os.listdir("exp")):
    if f.endswith(".v"):
        V[f[:-2]] = open("exp/" + f).read()

DU = "-dont_use *_1 -dont_use *_4 -dont_use *_6 -dont_use *_8 -dont_use *_12 -dont_use *_16 -dont_use *clk* -dont_use *dly* -dont_use *probe* -dont_use *lpflow* -dont_use *buf_*"
res = {}
for name, code in V.items():
    open("v.v", "w").write(code)
    for du in (DU, ""):
        ys = f"""read_verilog -sv v.v src/hvsync_generator.v
synth -flatten -top {TOP}
dfflibmap -liberty hd.lib {du.replace('-dont_use *_1 ','-dont_use *dfxtp_1 ') if du else ''}
abc -liberty hd.lib {du}
opt_clean
stat -liberty hd.lib"""
        r = subprocess.run(["yowasp-yosys", "-p", ys.replace("\n", "; ")], capture_output=True, text=True)
        out = r.stdout + r.stderr
        m = re.findall(r"Chip area for module.*?:\s*([0-9.]+)", out)
        ff = re.findall(r"(\d+)\s+(?:[0-9.E+]+\s+)?sky130_fd_sc_hd__dfxtp", out)
        if m:
            res[name] = (float(m[-1]), sum(map(int, ff)) if ff else -1, "du" if du else "plain")
            break
        print(name, "FAILED", "
".join(l for l in out.splitlines() if "rea" in l or "dfxtp" in l or "rror" in l)[-1500:])
base = res["A_baseline"][0]
print(f"{'variant':28s} {'area':>9s} {'delta':>8s} {'FFs':>4s}")
for k, (a, ff, mode) in res.items():
    print(f"{k:28s} {a:9.0f} {a-base:8.0f} {ff:4d} {mode}")
