import subprocess, re, os, sys, json
src = open("src/project.v").read()
TOP = "tt_um_davispe1_invaders"

def rep(s, a, b):
    assert a in s, f"pattern not found: {a[:60]}"
    return s.replace(a, b)

V = {}
K = open("exp/K_opt.v").read()
V["K_opt"] = K
V["K1_no_alive_write"] = rep(K, "else if (kill) alive[{arow, acol}] <= 1'b0;", "")
V["K2_no_alive_read"] = rep(K, "alive[{arow, acol}] && half[mcol]", "half[mcol]")
V["K3_no_bcd_inc"] = rep(K, "ones <= ones + 4'd1;", "ones <= ones;")
V["K4_fixed_speed"] = rep(K, "if (stimer >= ~kills) begin", "if (&stimer) begin")
V["K5_no_spawn_capture"] = rep(K, "        if (~eba && acol == lfsr[2:0] && scol == 3'd3) begin", "        if (1'b0) begin")
V["K6_no_edge_flags"] = rep(rep(K, "if (x[9:3] == 7'd0)   edge_l <= 1'b1;", ""), "if (x[9:3] == 7'd79)  edge_r <= 1'b1;", "")
V["K7_no_restart_logic"] = rep(K, "wire restart = ~rst_n | (ftick & over & btn[2] & (&stimer));", "wire restart = ~rst_n;")
V["K8_no_hit"] = rep(K, "wire hit  = eb_px & ship_px;", "wire hit  = 1'b0;")
V["K9_no_bb"] = rep(K, "wire bb   = pb_px & eb_px;", "wire bb   = 1'b0;")
V["K10_no_lives_digit"] = rep(K, "wire       in_lv = (x[9:5] == 5'd19);", "wire       in_lv = 1'b0;")
V["K11_no_colors"] = rep(K, "    else if (al_px)   rgb = acolor;", "    else if (al_px)   rgb = 6'b11_11_11;")
V["K12_no_pbx_store"] = rep(K, "x[2] && (x[9:3] == pbx)", "x[2] && (x[9:3] == plx + 7'd1)")
for f in sorted(os.listdir("exp")):
    if f.endswith(".v") and f not in ("K_opt.v", "L_opt_bitmapfont.v"):
        V[f[:-2]] = open("exp/" + f).read()

DU = "-dont_use *_1 -dont_use *_4 -dont_use *_6 -dont_use *_8 -dont_use *_12 -dont_use *_16 -dont_use *clk* -dont_use *dly* -dont_use *probe* -dont_use *lpflow* -dont_use *buf_*"
res = {}
for name, code in V.items():
    open("v.v", "w").write(code)
    for du in (DU, ""):
        dffdu = "-dont_use *dfxtp_1 -dont_use *dfxtp_4" if du else ""
        open("s.ys", "w").write(f"""read_verilog -sv v.v src/hvsync_generator.v
synth -flatten -top {TOP}
dfflibmap -liberty hd.lib {dffdu}
abc -liberty hd.lib {du}
opt_clean
tee -q -o stat.json stat -json -liberty hd.lib
""")
        if os.path.exists("stat.json"):
            os.remove("stat.json")
        r = subprocess.run(["yowasp-yosys", "-q", "-s", "s.ys"], capture_output=True, text=True)
        try:
            j = json.load(open("stat.json"))
            mod = j["modules"][next(iter(j["modules"]))] if "modules" in j else j
            area = mod.get("area") or j.get("design", {}).get("area")
            cells = mod.get("num_cells_by_type", {})
            ff = sum(v for k, v in cells.items() if "dfxtp" in k)
            res[name] = (float(area), ff, "du" if du else "plain")
            break
        except Exception as e:
            print(name, "FAILED", repr(e), (r.stdout + r.stderr)[-600:])
base = res["K_opt"][0]
print(f"{'variant':28s} {'area':>9s} {'delta':>8s} {'FFs':>4s}")
for k, (a, ff, mode) in res.items():
    print(f"{k:28s} {a:9.0f} {a-base:8.0f} {ff:4d} {mode}")
