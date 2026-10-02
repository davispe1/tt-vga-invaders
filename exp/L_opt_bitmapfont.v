/*
 * Space Invaders para Tiny Tapeout (1 tile) - VGA 640x480 + audio
 * SPDX-License-Identifier: Apache-2.0
 *
 * Formacion de 8x4 aliens, una bala del jugador y una enemiga.
 * No hay framebuffer: cada pixel se calcula al vuelo y las colisiones,
 * los bordes y el punto de disparo enemigo se detectan mientras se dibuja.
 */

`default_nettype none

module tt_um_davispe1_invaders(
  input  wire [7:0] ui_in,    // [0] izquierda, [1] derecha, [2] disparo
  output wire [7:0] uo_out,   // TinyVGA PMOD
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,  // uio_out[7] = audio
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,      // 25.175 MHz
  input  wire       rst_n
);

  // ---------------- Sincronia VGA ----------------
  wire hsync, vsync, video_active;
  wire [9:0] x, y;

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(x),
    .vpos(y)
  );

  // Primer pixel tras la zona visible: aqui se mueve todo, una vez por frame
  wire ftick = (y == 10'd480) && (x == 10'd0);

  // ---------------- Estado ----------------
  reg [31:0] alive;           // aliens vivos, bit = fila*8 + columna
  reg  [6:0] fx;              // x de la formacion en pasos de 8 px (modulo 1024)
  reg  [4:0] fy;              // y de la formacion en pasos de 16 px
  reg        dir;             // 1 = derecha
  reg        aframe;          // cuadro de animacion
  reg  [4:0] stimer;          // frames desde el ultimo paso (en game over: espera)
  reg  [4:0] kills;           // aliens eliminados en esta oleada
  reg        edge_l, edge_r;  // un alien toco el borde (se recoge al dibujar)
  reg        low;             // un alien llego a la fila del jugador
  reg  [6:0] plx;             // x del jugador en pasos de 8 px
  reg        pba;             // bala del jugador activa
  reg  [6:0] pbx;             // pasos de 8 px (la bala ocupa la mitad derecha)
  reg  [5:0] pby;             // pasos de 8 px
  reg        eba;             // bala enemiga activa
  reg  [6:0] ebx;
  reg  [5:0] eby;
  reg        efound;          // hay un alien que puede disparar este frame
  reg        fpar;            // paridad de frame (bala enemiga a media velocidad)
  reg        over;
  reg  [1:0] lives;
  reg  [3:0] ones, tens;      // puntaje BCD, se muestra con un 0 fijo detras
  reg  [6:0] lfsr;
  reg  [2:0] btn;
  reg  [3:0] snd_t;
  reg  [1:0] snd_k;           // 0 marcha, 1 disparo, 2 explosion, 3 golpe

  // ---------------- Formacion ----------------
  // Celdas de 32x32 px; el sprite ocupa 6x6 pixeles de 4x4 px.
  wire [9:0] rx   = x - {fx, 3'b000};
  wire [9:0] ry   = y - {1'b0, fy, 4'b0000};
  wire [2:0] acol = rx[7:5];
  wire [1:0] arow = ry[6:5];
  wire [2:0] scol = rx[4:2];
  wire [2:0] srow = ry[4:2];

  // Sprite simetrico: se guardan las columnas 0..3 (la 0 siempre vacia)
  wire [1:0] mcol = scol[2] ? ~scol[1:0] : scol[1:0];
  reg  [3:0] half;
  always @(*) begin
    case (srow)
      3'd0:    half = 4'b1000;                       //   ..##..
      3'd1:    half = 4'b1100;                       //   .####.
      3'd2:    half = 4'b1010;                       //   #.##.#
      3'd3:    half = 4'b1110;                       //   ######
      3'd4:    half = aframe ? 4'b1010 : 4'b0100;    //   #.##.#  / .#..#.
      3'd5:    half = aframe ? 4'b0100 : 4'b0010;    //   .#..#.  / #....#
      default: half = 4'b0000;
    endcase
  end

  wire al_px = video_active && (rx[9:8] == 2'b00) && (ry[9:7] == 3'b000) &&
               alive[{arow, acol}] && half[mcol];

  // ---------------- Jugador y balas ----------------
  wire [7:0] sx = x[9:2] - {plx, 1'b0};
  reg  [7:0] ship;
  always @(*) begin
    case (y[3:2])
      2'd0:    ship = 8'b0000_1000;                  //   ...#...
      2'd1:    ship = 8'b0001_1100;                  //   ..###..
      default: ship = 8'b0111_1111;                  //   #######
    endcase
  end
  wire ship_px = (y[9:4] == 6'd28) && (sx[7:3] == 5'd0) && ship[sx[2:0]];   // y 448..463

  wire pb_px = pba && x[2] && (x[9:3] == pbx) && ~y[9] && (y[8:3] == pby);
  wire eb_px = eba && x[2] && (x[9:3] == ebx) && ~y[9] && (y[8:3] == eby);

  wire kill = pb_px & al_px;      // bala del jugador sobre un alien
  wire hit  = eb_px & ship_px;    // bala enemiga sobre el jugador
  wire bb   = pb_px & eb_px;      // choque entre balas

  // ---------------- Logica del juego ----------------
  wire restart = ~rst_n | (ftick & over & btn[2] & (&stimer));
  wire newwave = restart | (kill & (&kills));

  always @(posedge clk) begin
    if (newwave) alive <= 32'hFFFF_FFFF;
    else if (kill) alive[{arow, acol}] <= 1'b0;
  end

  always @(posedge clk) begin
    if (restart) begin
      over   <= 1'b0;
      lives  <= 2'd3;
      ones   <= 4'd0;
      tens   <= 4'd0;
      plx    <= 7'd38;
      pba    <= 1'b0;
      eba    <= 1'b0;
      fpar   <= 1'b0;
      btn    <= 3'd0;
      snd_t  <= 4'd0;
      edge_l <= 1'b0;
      edge_r <= 1'b0;
      low    <= 1'b0;
      efound <= 1'b0;
      if (~rst_n) lfsr <= 7'd1;
    end else begin
      // ---- Eventos mientras se dibuja ----
      if (al_px) begin
        if (x[9:3] == 7'd0)   edge_l <= 1'b1;            // x 0..7
        if (x[9:3] == 7'd79)  edge_r <= 1'b1;            // x 632..639
        if (&y[8:6])          low    <= 1'b1;            // y 448..479
        // El ultimo alien dibujado en la columna elegida es el mas bajo: dispara el
        if (~eba && acol == lfsr[2:0] && scol == 3'd3) begin
          ebx    <= x[9:3];
          eby    <= y[8:3];
          efound <= 1'b1;
        end
      end

      if (kill) begin
        pba   <= 1'b0;
        kills <= kills + 5'd1;
        snd_k <= 2'd2;
        snd_t <= 4'd10;
        if (ones == 4'd9) begin
          ones <= 4'd0;
          tens <= (tens == 4'd9) ? 4'd0 : tens + 4'd1;
        end else begin
          ones <= ones + 4'd1;
        end
      end

      if (bb) begin
        pba <= 1'b0;
        eba <= 1'b0;
      end

      if (hit) begin
        eba   <= 1'b0;
        lives <= lives - 2'd1;
        snd_k <= 2'd3;
        snd_t <= 4'd15;
        if (lives == 2'd1) begin
          over   <= 1'b1;
          pba    <= 1'b0;
          stimer <= 5'd0;
        end
      end

      // ---- Una vez por frame ----
      if (ftick) begin
        lfsr   <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
        btn    <= ui_in[2:0];
        fpar   <= ~fpar;
        edge_l <= 1'b0;
        edge_r <= 1'b0;
        low    <= 1'b0;
        efound <= 1'b0;
        if (snd_t != 4'd0) snd_t <= snd_t - 4'd1;

        if (over) begin
          if (~&stimer) stimer <= stimer + 5'd1;
        end else begin
          // Formacion: un paso cada (32 - kills) frames
          if (stimer >= ~kills) begin
            stimer <= 5'd0;
            aframe <= ~aframe;
            if (dir ? edge_r : edge_l) begin
              fy  <= fy + 5'd1;
              dir <= ~dir;
            end else begin
              fx  <= dir ? fx + 7'd1 : fx - 7'd1;
            end
            if (snd_t == 4'd0) begin
              snd_k <= 2'd0;
              snd_t <= 4'd2;
            end
          end else begin
            stimer <= stimer + 5'd1;
          end

          // Jugador: 8 px cada 2 frames
          if (fpar) begin
            if (btn[0] && plx != 7'd0)       plx <= plx - 7'd1;
            else if (btn[1] && plx != 7'd76) plx <= plx + 7'd1;
          end

          // Bala del jugador
          if (pba) begin
            if (pby == 6'd0) pba <= 1'b0;
            else             pby <= pby - 6'd1;
          end else if (btn[2]) begin
            pba   <= 1'b1;
            pbx   <= plx + 7'd1;
            pby   <= 6'd55;
            snd_k <= 2'd1;
            snd_t <= 4'd5;
          end

          // Bala enemiga
          if (eba) begin
            if (fpar) begin
              if (&eby[5:2]) eba <= 1'b0;                // y >= 480
              else           eby <= eby + 6'd1;
            end
          end else if (efound && lfsr[3]) begin
            eba <= 1'b1;
          end

          if (low) begin
            over   <= 1'b1;
            pba    <= 1'b0;
            eba    <= 1'b0;
            stimer <= 5'd0;
          end
        end
      end
    end

    if (newwave) begin
      fx     <= 7'd24;
      fy     <= 5'd4;
      dir    <= 1'b1;
      aframe <= 1'b0;
      stimer <= 5'd0;
      kills  <= 5'd0;
    end
  end

  // ---------------- Texto: puntaje y vidas ----------------
  wire       top   = (y[9:6] == 4'd0);                       // y 0..63
  wire [1:0] slot  = x[6:5];
  wire       in_lv = (x[9:5] == 5'd19);                      // x 608..639
  wire       in_sc = (x[9:7] == 3'd0) && (slot != 2'd0);     // x 32..127
  wire [3:0] dig   = in_lv ? {2'b00, lives} :
                     (slot == 2'd1) ? tens :
                     (slot == 2'd2) ? ones : 4'd0;
  wire [1:0] cx    = x[4:3];
  wire [2:0] cy    = y[5:3];

  reg [2:0] frow;   // fila de la fuente 3x5, bit 2 = izquierda
  always @(*) begin
    case ({dig, cy})
      7'd1: frow = 3'b111;
      7'd2: frow = 3'b101;
      7'd3: frow = 3'b101;
      7'd4: frow = 3'b101;
      7'd5: frow = 3'b111;
      7'd9: frow = 3'b010;
      7'd10: frow = 3'b110;
      7'd11: frow = 3'b010;
      7'd12: frow = 3'b010;
      7'd13: frow = 3'b111;
      7'd17: frow = 3'b111;
      7'd18: frow = 3'b001;
      7'd19: frow = 3'b111;
      7'd20: frow = 3'b100;
      7'd21: frow = 3'b111;
      7'd25: frow = 3'b111;
      7'd26: frow = 3'b001;
      7'd27: frow = 3'b111;
      7'd28: frow = 3'b001;
      7'd29: frow = 3'b111;
      7'd33: frow = 3'b101;
      7'd34: frow = 3'b101;
      7'd35: frow = 3'b111;
      7'd36: frow = 3'b001;
      7'd37: frow = 3'b001;
      7'd41: frow = 3'b111;
      7'd42: frow = 3'b100;
      7'd43: frow = 3'b111;
      7'd44: frow = 3'b001;
      7'd45: frow = 3'b111;
      7'd49: frow = 3'b111;
      7'd50: frow = 3'b100;
      7'd51: frow = 3'b111;
      7'd52: frow = 3'b101;
      7'd53: frow = 3'b111;
      7'd57: frow = 3'b111;
      7'd58: frow = 3'b001;
      7'd59: frow = 3'b001;
      7'd60: frow = 3'b001;
      7'd61: frow = 3'b001;
      7'd65: frow = 3'b111;
      7'd66: frow = 3'b101;
      7'd67: frow = 3'b111;
      7'd68: frow = 3'b101;
      7'd69: frow = 3'b111;
      7'd73: frow = 3'b111;
      7'd74: frow = 3'b101;
      7'd75: frow = 3'b111;
      7'd76: frow = 3'b001;
      7'd77: frow = 3'b111;
      default: frow = 3'b000;
    endcase
  end
  wire font = (cx == 2'd0) ? frow[2] : (cx == 2'd1) ? frow[1] : frow[0];

  wire txt = top && (in_sc || in_lv) && (cx != 2'd3) && font;

  // ---------------- Color ----------------
  wire ground = (y[9:1] == 9'd237);                         // y 474..475

  reg [5:0] acolor;
  always @(*) begin
    case (arow)
      2'd0:    acolor = 6'b11_00_11;
      2'd3:    acolor = 6'b11_11_00;
      default: acolor = 6'b00_11_11;
    endcase
  end

  reg [5:0] rgb;
  always @(*) begin
    if (txt | pb_px)  rgb = 6'b11_11_11;
    else if (ship_px) rgb = over ? 6'b11_00_00 : 6'b00_11_00;
    else if (eb_px)   rgb = 6'b11_01_00;
    else if (al_px)   rgb = acolor;
    else if (ground)  rgb = 6'b00_10_00;
    else              rgb = 6'b00_00_00;
  end

  wire [1:0] R = video_active ? rgb[5:4] : 2'b00;
  wire [1:0] G = video_active ? rgb[3:2] : 2'b00;
  wire [1:0] B = video_active ? rgb[1:0] : 2'b00;

  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // ---------------- Sonido ----------------
  reg tone;
  always @(*) begin
    case (snd_k)
      2'd0:    tone = aframe ? y[6] : y[7];   // marcha: dos notas graves
      2'd1:    tone = y[3];                   // disparo: agudo
      2'd2:    tone = y[4];                   // explosion
      default: tone = y[8];                   // golpe: zumbido
    endcase
  end
  wire audio = tone & (snd_t != 4'd0);

  assign uio_out = {audio, 7'b0};
  assign uio_oe  = 8'b1000_0000;

  wire _unused_ok = &{ena, ui_in[7:3], uio_in};

endmodule
