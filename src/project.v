/*
 * Tetris 8x20 para Tiny Tapeout (1 tile) - VGA 640x480 + audio
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_davispe1_tetris(
  input  wire [7:0] ui_in,    // [0] izquierda, [1] derecha, [2] rotar, [3] caida rapida
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
  wire [9:0] pix_x, pix_y;

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  // ---------------- Tablero: anillo de 160 bits ----------------
  // El tablero (8 columnas x 20 filas) vive en un registro de desplazamiento
  // circular que gira un bit por ciclo de reloj. Como 800 = 5 x 160, la fase
  // del anillo es una funcion fija de pix_x: ring[0] siempre es la celda
  // (fila q, columna pcol). La fila 0 es la de abajo.
  reg [159:0] ring;

  reg [2:0] m5;                 // (pix_x / 32) mod 5
  always @(*) begin
    case (pix_x[9:5])
      5'd0: m5 = 3'd0;
      5'd1: m5 = 3'd1;
      5'd2: m5 = 3'd2;
      5'd3: m5 = 3'd3;
      5'd4: m5 = 3'd4;
      5'd5: m5 = 3'd0;
      5'd6: m5 = 3'd1;
      5'd7: m5 = 3'd2;
      5'd8: m5 = 3'd3;
      5'd9: m5 = 3'd4;
      5'd10: m5 = 3'd0;
      5'd11: m5 = 3'd1;
      5'd12: m5 = 3'd2;
      5'd13: m5 = 3'd3;
      5'd14: m5 = 3'd4;
      5'd15: m5 = 3'd0;
      5'd16: m5 = 3'd1;
      5'd17: m5 = 3'd2;
      5'd18: m5 = 3'd3;
      5'd19: m5 = 3'd4;
      5'd20: m5 = 3'd0;
      5'd21: m5 = 3'd1;
      5'd22: m5 = 3'd2;
      5'd23: m5 = 3'd3;
      5'd24: m5 = 3'd4;
      default: m5 = 3'd0;
    endcase
  end
  wire [4:0] q    = {m5, pix_x[4:3]};            // fila de la celda en ring[0]
  wire [2:0] pcol = pix_x[2:0];                  // columna de la celda en ring[0]
  wire       last = (m5 == 3'd4) && (&pix_x[4:0]);   // ultima celda de la vuelta
  wire       ftick = (pix_x == 10'd799) && (pix_y == 10'd480);  // inicio de frame logico (coincide con last)
  wire       vbl  = pix_y[9] | (&pix_y[8:5]);        // lineas >= 480

  // ---------------- Estado ----------------
  localparam [2:0] S_IDLE = 3'd0, S_TEST = 3'd1, S_LOCK = 3'd2,
                   S_FIND = 3'd3, S_SHIFT = 3'd4, S_WIPE = 3'd5;
  localparam [2:0] A_NONE = 3'd0, A_DOWN = 3'd1, A_LEFT = 3'd2,
                   A_RIGHT = 3'd3, A_ROT = 3'd4;

  reg [2:0] state, act;
  reg [2:0] shape;            // 0 I, 1 O, 2 T, 3 S, 4 Z, 5 J, 6 L
  reg [1:0] rot;
  reg signed [3:0] px;        // columna de la caja 4x4 de la pieza
  reg signed [5:0] py;        // fila inferior de la caja 4x4
  reg       coll;             // la pieza candidata choca con el tablero
  reg [2:0] cnt;              // celdas de la pieza dentro del tablero
  reg       full, found;
  reg [4:0] crow;             // fila completa a eliminar
  reg [4:0] gt;               // temporizador de gravedad
  reg       fast;             // caida rapida activa
  reg [3:0] s1, s2;           // botones: muestra actual y ultima consumida
  reg [6:0] lfsr;
  reg [3:0] ones, tens;       // lineas eliminadas en BCD
  reg [3:0] snd_t;
  reg       snd_k;
  reg [7:0] rowbuf;           // fila del tablero que se esta dibujando

  // ---------------- Pieza: mascara 4x4 por forma y rotacion ----------------
  wire testing = (state == S_TEST);
  wire signed [3:0] cpx  = px + ((testing && act == A_LEFT)  ? -4'sd1 :
                                 (testing && act == A_RIGHT) ?  4'sd1 : 4'sd0);
  wire signed [5:0] cpy  = py - ((testing && act == A_DOWN) ? 6'sd1 : 6'sd0);
  wire [1:0]        crot = rot + ((testing && act == A_ROT) ? 2'd1 : 2'd0);

  reg [15:0] mask;   // bit = fila_relativa*4 + columna_relativa, fila 0 abajo
  always @(*) begin
    case ({shape, crot})
      5'b000_00: mask = 16'h0F00;
      5'b000_01: mask = 16'h4444;
      5'b000_10: mask = 16'h00F0;
      5'b000_11: mask = 16'h2222;
      5'b001_00: mask = 16'h6600;
      5'b001_01: mask = 16'h6600;
      5'b001_10: mask = 16'h6600;
      5'b001_11: mask = 16'h6600;
      5'b010_00: mask = 16'h2700;
      5'b010_01: mask = 16'h2620;
      5'b010_10: mask = 16'h0720;
      5'b010_11: mask = 16'h2320;
      5'b011_00: mask = 16'h6300;
      5'b011_01: mask = 16'h2640;
      5'b011_10: mask = 16'h0630;
      5'b011_11: mask = 16'h1320;
      5'b100_00: mask = 16'h3600;
      5'b100_01: mask = 16'h4620;
      5'b100_10: mask = 16'h0360;
      5'b100_11: mask = 16'h2310;
      5'b101_00: mask = 16'h1700;
      5'b101_01: mask = 16'h6220;
      5'b101_10: mask = 16'h0740;
      5'b101_11: mask = 16'h2230;
      5'b110_00: mask = 16'h4700;
      5'b110_01: mask = 16'h2260;
      5'b110_10: mask = 16'h0710;
      5'b110_11: mask = 16'h3220;
      default: mask = 16'h0000;
    endcase
  end

  // Coordenadas de pantalla (para dibujar) o de fase del anillo (para la logica)
  wire       in_bx  = (pix_x[9:7] == 3'b010);                         // x 256..383
  wire       in_by  = ~pix_y[9] && (pix_y[8:6] != 3'd0) && (pix_y[8:7] != 2'b11); // y 64..383
  wire [4:0] q_d    = 5'd23 - pix_y[8:4];
  wire [2:0] col_d  = pix_x[6:4];

  wire [4:0] t_row = vbl ? q    : q_d;
  wire [2:0] t_col = vbl ? pcol : col_d;
  wire [3:0] dc    = {1'b0, t_col} - cpx;
  wire [5:0] dr    = {1'b0, t_row} - cpy;
  wire       hit   = (dc[3:2] == 2'b00) && (dr[5:2] == 4'b0000) && mask[{dr[1:0], dc[1:0]}];

  // ---------------- Entrada del anillo ----------------
  reg ring_in;
  always @(*) begin
    case (state)
      S_LOCK:  ring_in = ring[0] | hit;
      S_SHIFT: ring_in = (q >= crow) ? ((q == 5'd19) ? 1'b0 : ring[8]) : ring[0];
      S_WIPE:  ring_in = 1'b0;
      default: ring_in = ring[0];
    endcase
  end

  always @(posedge clk) begin
    ring <= {ring_in, ring[159:1]};
  end

  // Resultado de las pasadas, incluyendo la celda actual
  wire       coll_f = coll | (hit & ring[0]);
  wire [2:0] cnt_f  = cnt + {2'b00, hit};
  wire       ok     = ~coll_f && (cnt_f == 3'd4);
  wire       full_f = ((pcol == 3'd0) ? 1'b1 : full) & ring[0];

  wire [3:0] e     = s1 ^ s2;                       // botones con cambio pendiente
  wire [4:0] limit = 5'd24 - {tens, 1'b0};          // frames por paso de caida
  wire [2:0] nshape = (lfsr[2:0] == 3'd7) ? {1'b0, lfsr[4:3]} : lfsr[2:0];

  always @(posedge clk) begin
    if (~rst_n) begin
      // Solo se reinicia lo imprescindible: el resto se inicializa al salir de S_WIPE
      state <= S_WIPE;
      lfsr  <= 7'd1;
    end else begin
      // Acumuladores de la pasada actual
      coll <= coll_f;
      cnt  <= cnt_f;
      full <= full_f;
      if (state == S_FIND && pcol == 3'd7 && full_f && ~found) begin
        found <= 1'b1;
        crow  <= q;
      end

      if (ftick) begin
        lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
        s1   <= ui_in[3:0];
        if (snd_t != 4'd0) snd_t <= snd_t - 4'd1;
      end

      if (last) begin
        coll <= 1'b0;
        cnt  <= 3'd0;

        case (state)
          S_IDLE: if (ftick) begin
            if (e[3]) begin
              fast  <= 1'b1;
              s2[3] <= s1[3];
            end
            if (fast || gt == limit) begin
              act   <= A_DOWN;
              gt    <= 5'd0;
              state <= S_TEST;
            end else begin
              gt <= gt + 5'd1;
              if (e[2])      begin act <= A_ROT;   state <= S_TEST; end
              else if (e[0]) begin act <= A_LEFT;  state <= S_TEST; end
              else if (e[1]) begin act <= A_RIGHT; state <= S_TEST; end
            end
          end

          S_TEST: begin
            state <= S_IDLE;
            if (act == A_ROT)   s2[2] <= s1[2];
            if (act == A_LEFT)  s2[0] <= s1[0];
            if (act == A_RIGHT) s2[1] <= s1[1];
            if (ok) begin
              px  <= cpx;
              py  <= cpy;
              rot <= crot;
            end else if (act == A_DOWN) begin
              state <= S_LOCK;
            end else if (act == A_NONE) begin
              state <= S_WIPE;          // la pieza nueva no cabe: fin del juego
              snd_k <= 1'b0;
              snd_t <= 4'd15;
            end
          end

          S_LOCK: begin
            state <= S_FIND;
            found <= 1'b0;
            fast  <= 1'b0;
            snd_k <= 1'b0;
            snd_t <= 4'd3;
          end

          S_FIND: begin
            if (found) begin
              state <= S_SHIFT;
            end else begin
              // Pieza nueva
              shape <= nshape;
              rot   <= 2'd0;
              px    <= 4'sd2;
              py    <= 6'sd16;
              act   <= A_NONE;
              state <= S_TEST;
            end
          end

          S_SHIFT: begin
            state <= S_FIND;
            found <= 1'b0;
            snd_k <= 1'b1;
            snd_t <= 4'd12;
            if (ones == 4'd9) begin
              ones <= 4'd0;
              tens <= (tens == 4'd9) ? 4'd0 : tens + 4'd1;
            end else begin
              ones <= ones + 4'd1;
            end
          end

          S_WIPE: if (ftick) begin
            ones  <= 4'd0;
            tens  <= 4'd0;
            fast  <= 1'b0;
            gt    <= 5'd0;
            shape <= nshape;
            rot   <= 2'd0;
            px    <= 4'sd2;
            py    <= 6'sd16;
            act   <= A_NONE;
            state <= S_TEST;
          end

          default: state <= S_IDLE;
        endcase
      end
    end
  end

  // ---------------- Dibujo ----------------
  // La fila visible se copia del anillo en la primera vuelta de cada linea
  wire first = (pix_x[9:5] < 5'd5);
  always @(posedge clk) begin
    if (first && (q == q_d)) rowbuf <= {ring[0], rowbuf[7:1]};
  end

  wire in_board = in_bx & in_by;
  wire cell_on  = rowbuf[col_d];
  wire edge_hi  = (pix_x[3:0] == 4'd0)  | (pix_y[3:0] == 4'd0);
  wire edge_lo  = (pix_x[3:0] == 4'd15) | (pix_y[3:0] == 4'd15);

  wire [2:0] ci  = q_d[2:0] ^ col_d;                 // color de bloques fijos por posicion
  wire [2:0] sc1 = shape + 3'd1;                     // color de la pieza por forma
  wire [5:0] blk_rgb = hit ? {sc1[2], sc1[2], sc1[1], sc1[1], sc1[0], sc1[0]}
                           : {ci[2], 1'b1, ci[1], 1'b1, ci[0], 1'b1};

  // Marco del tablero
  wire frame = ~pix_y[9] && (pix_y[8:6] != 3'd0) && (pix_y[8:3] <= 6'd48) &&
               (pix_x[9:3] >= 7'd31) && (pix_x[9:3] <= 7'd48) && ~in_board;

  // Lineas eliminadas: fuente 3x5 derivada de 7 segmentos
  wire       in_score = (pix_x[9:6] == 4'd7) && (pix_y[9:6] == 4'd1);   // x 448..511
  wire [3:0] dig      = pix_x[5] ? ones : tens;
  wire [1:0] cx       = pix_x[4:3];
  wire [2:0] cy       = pix_y[5:3];

  reg [6:0] seg;   // {a,b,c,d,e,f,g}
  always @(*) begin
    case (dig)
      4'd0:    seg = 7'b1111110;
      4'd1:    seg = 7'b0110000;
      4'd2:    seg = 7'b1101101;
      4'd3:    seg = 7'b1111001;
      4'd4:    seg = 7'b0110011;
      4'd5:    seg = 7'b1011011;
      4'd6:    seg = 7'b1011111;
      4'd7:    seg = 7'b1110000;
      4'd8:    seg = 7'b1111111;
      default: seg = 7'b1111011;
    endcase
  end
  wire sa = seg[6], sb = seg[5], sgc = seg[4], sd = seg[3], se = seg[2], sf = seg[1], sg = seg[0];
  wire lf = (cx == 2'd0), rt = (cx == 2'd2);
  reg  font;
  always @(*) begin
    case (cy)
      3'd0:    font = sa | (lf & sf) | (rt & sb);
      3'd1:    font = (lf & sf) | (rt & sb);
      3'd2:    font = sg | (lf & (sf | se)) | (rt & (sb | sgc));
      3'd3:    font = (lf & se) | (rt & sgc);
      3'd4:    font = sd | (lf & se) | (rt & sgc);
      default: font = 1'b0;
    endcase
  end
  wire score_px = in_score && (cx != 2'd3) && font;

  reg [5:0] rgb;
  always @(*) begin
    if (in_board) begin
      if (cell_on | hit) begin
        if (edge_hi)      rgb = 6'b11_11_11;
        else if (edge_lo) rgb = 6'b00_00_00;
        else              rgb = blk_rgb;
      end else begin
        rgb = (edge_hi) ? 6'b00_00_01 : 6'b00_00_00;
      end
    end
    else if (frame)    rgb = 6'b10_10_10;
    else if (score_px) rgb = 6'b11_11_11;
    else               rgb = (pix_x[5] ^ pix_y[5]) ? 6'b01_00_01 : 6'b00_00_01;
  end

  wire [1:0] R = video_active ? rgb[5:4] : 2'b00;
  wire [1:0] G = video_active ? rgb[3:2] : 2'b00;
  wire [1:0] B = video_active ? rgb[1:0] : 2'b00;

  reg [7:0] vga_q;
  always @(posedge clk) begin
    vga_q <= {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  end
  assign uo_out = vga_q;

  // ---------------- Sonido ----------------
  // snd_k = 1: linea eliminada (agudo, dos notas). snd_k = 0: golpe grave.
  wire tone  = snd_k ? (snd_t[3] ? pix_y[4] : pix_y[3]) : pix_y[6];
  wire audio = tone & (snd_t != 4'd0);

  assign uio_out = {audio, 7'b0};
  assign uio_oe  = 8'b1000_0000;

  wire _unused_ok = &{ena, ui_in[7:4], uio_in};

endmodule
