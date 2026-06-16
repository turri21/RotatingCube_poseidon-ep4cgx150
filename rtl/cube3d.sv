// Rotating Cube demo core for Poseidon (port from Senhor FPGA).
//
//
// Copyright (c) 2026 turri21 <turri21@yahoo.com>

// Acknowledgements: 
// Parts of this core were generated with the assistance of Anthropic's Claude.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// 3-D rotation + perspective projection.
//
//
// Pipeline:
//   s0: latch sin/cos from LUT on angle change
//   s1: rotate 8 vertices (Ry then Rx) in fixed-point Q1.14
//   s2: perspective project via reciprocal LUT
//   s3: output register + 1-cycle valid pulse

module cube3d #(
    parameter SCREEN_W = 360,
    parameter SCREEN_H = 240,
    parameter SCALE    = 100
)(
    input  logic        clk,
    input  logic        reset,
    input  logic [7:0]  angle_x,
    input  logic [7:0]  angle_y,
    output logic signed [10:0] vx [0:7],
    output logic signed [10:0] vy [0:7],
    output logic               valid
);

    // ------------------------------------------------------------------
    // LUTs
    // sinlut: 256 x s16 Q1.14   sin(2pi*i/256)*16384
    // reclut: 512 x u16         round(65536/(i+64))  i=0..511
    // ------------------------------------------------------------------
    logic signed [15:0] sin_lut [0:255];
    initial $readmemh("../sinlut.hex", sin_lut);

    logic [15:0] rec_lut [0:511];
    initial $readmemh("../reclut.hex", rec_lut);

    // ------------------------------------------------------------------
    // Detect angle change
    // ------------------------------------------------------------------
    logic [7:0] ax_prev, ay_prev;
    logic       pipe_run;

    always_ff @(posedge clk) begin
        if (reset) begin
            ax_prev  <= 8'hFF;
            ay_prev  <= 8'hFF;
            pipe_run <= 1'b0;
        end else begin
            pipe_run <= (angle_x != ax_prev) || (angle_y != ay_prev);
            ax_prev  <= angle_x;
            ay_prev  <= angle_y;
        end
    end

    // ------------------------------------------------------------------
    // Stage 0: latch sin/cos
    // ------------------------------------------------------------------
    logic signed [15:0] sx0, cx0, sy0, cy0;
    logic s0v;

    always_ff @(posedge clk) begin
        s0v <= pipe_run;
        if (pipe_run) begin
            sx0 <= sin_lut[angle_x];
            cx0 <= sin_lut[angle_x + 8'd64];
            sy0 <= sin_lut[angle_y];
            cy0 <= sin_lut[angle_y + 8'd64];
        end
    end

    // ------------------------------------------------------------------
    // Vertex constants  (signed 8-bit, expanded to 32-bit in arithmetic)
    // ------------------------------------------------------------------
    localparam integer S = SCALE;

    // Sign-extend 8-bit constant to 32-bit signed wire via parameter
    // Quartus accepts $signed on a parameter/localparam directly.
    localparam signed [31:0] X0 = -S, Y0 = -S, Z0 = -S;
    localparam signed [31:0] X1 =  S, Y1 = -S, Z1 = -S;
    localparam signed [31:0] X2 =  S, Y2 =  S, Z2 = -S;
    localparam signed [31:0] X3 = -S, Y3 =  S, Z3 = -S;
    localparam signed [31:0] X4 = -S, Y4 = -S, Z4 =  S;
    localparam signed [31:0] X5 =  S, Y5 = -S, Z5 =  S;
    localparam signed [31:0] X6 =  S, Y6 =  S, Z6 =  S;
    localparam signed [31:0] X7 = -S, Y7 =  S, Z7 =  S;

    // ------------------------------------------------------------------
    // Stage 1: rotate  (Ry then Rx)
    //
    // cy0, sy0, cx0, sx0 are signed [15:0] (Q1.14).
    // Vertex coords are signed [31:0] constants.
    // Product of s16 * s32 = s48; we keep s32 and shift >>>14.
    //
    // Rotation formulas:
    //   After Ry:  xr =  cy*x + sy*z
    //              zr = -sy*x + cy*z
    //   After Rx:  xout = xr
    //              yout =  cx*y - sx*zr
    //              zout =  sx*y + cx*zr
    //
    // We need zr for both yout and zout, so compute it combinatorially
    // from the registered stage-0 values and latch everything together.
    // ------------------------------------------------------------------
    logic signed [31:0] rx1_0,ry1_0,rz1_0, rx1_1,ry1_1,rz1_1;
    logic signed [31:0] rx1_2,ry1_2,rz1_2, rx1_3,ry1_3,rz1_3;
    logic signed [31:0] rx1_4,ry1_4,rz1_4, rx1_5,ry1_5,rz1_5;
    logic signed [31:0] rx1_6,ry1_6,rz1_6, rx1_7,ry1_7,rz1_7;
    logic s1v;

    // Helper wires for intermediate zr values (combinatorial from s0 regs)
    // Using 48-bit intermediates to avoid overflow before the shift.
    wire signed [47:0] zr_w0 = $signed(sy0)*(-X0) + $signed(cy0)*Z0;  // actually -sy*x + cy*z but factor sign into mult
    wire signed [47:0] zr_w1 = (-$signed(sy0)*X1)  + $signed(cy0)*Z1;
    wire signed [47:0] zr_w2 = (-$signed(sy0)*X2)  + $signed(cy0)*Z2;
    wire signed [47:0] zr_w3 = (-$signed(sy0)*X3)  + $signed(cy0)*Z3;
    wire signed [47:0] zr_w4 = (-$signed(sy0)*X4)  + $signed(cy0)*Z4;
    wire signed [47:0] zr_w5 = (-$signed(sy0)*X5)  + $signed(cy0)*Z5;
    wire signed [47:0] zr_w6 = (-$signed(sy0)*X6)  + $signed(cy0)*Z6;
    wire signed [47:0] zr_w7 = (-$signed(sy0)*X7)  + $signed(cy0)*Z7;

    // zr after >>14 (s34)
    wire signed [33:0] zrs0 = zr_w0 >>> 14;
    wire signed [33:0] zrs1 = zr_w1 >>> 14;
    wire signed [33:0] zrs2 = zr_w2 >>> 14;
    wire signed [33:0] zrs3 = zr_w3 >>> 14;
    wire signed [33:0] zrs4 = zr_w4 >>> 14;
    wire signed [33:0] zrs5 = zr_w5 >>> 14;
    wire signed [33:0] zrs6 = zr_w6 >>> 14;
    wire signed [33:0] zrs7 = zr_w7 >>> 14;

    always_ff @(posedge clk) begin
        s1v <= s0v;
        // Vertex 0
        rx1_0 <= ($signed(cy0)*X0  + $signed(sy0)*Z0) >>> 14;
        rz1_0 <= zrs0[31:0];
        ry1_0 <= ($signed(cx0)*Y0  - $signed(sx0)*$signed(zrs0[31:0])) >>> 14;
        // Vertex 1
        rx1_1 <= ($signed(cy0)*X1  + $signed(sy0)*Z1) >>> 14;
        rz1_1 <= zrs1[31:0];
        ry1_1 <= ($signed(cx0)*Y1  - $signed(sx0)*$signed(zrs1[31:0])) >>> 14;
        // Vertex 2
        rx1_2 <= ($signed(cy0)*X2  + $signed(sy0)*Z2) >>> 14;
        rz1_2 <= zrs2[31:0];
        ry1_2 <= ($signed(cx0)*Y2  - $signed(sx0)*$signed(zrs2[31:0])) >>> 14;
        // Vertex 3
        rx1_3 <= ($signed(cy0)*X3  + $signed(sy0)*Z3) >>> 14;
        rz1_3 <= zrs3[31:0];
        ry1_3 <= ($signed(cx0)*Y3  - $signed(sx0)*$signed(zrs3[31:0])) >>> 14;
        // Vertex 4
        rx1_4 <= ($signed(cy0)*X4  + $signed(sy0)*Z4) >>> 14;
        rz1_4 <= zrs4[31:0];
        ry1_4 <= ($signed(cx0)*Y4  - $signed(sx0)*$signed(zrs4[31:0])) >>> 14;
        // Vertex 5
        rx1_5 <= ($signed(cy0)*X5  + $signed(sy0)*Z5) >>> 14;
        rz1_5 <= zrs5[31:0];
        ry1_5 <= ($signed(cx0)*Y5  - $signed(sx0)*$signed(zrs5[31:0])) >>> 14;
        // Vertex 6
        rx1_6 <= ($signed(cy0)*X6  + $signed(sy0)*Z6) >>> 14;
        rz1_6 <= zrs6[31:0];
        ry1_6 <= ($signed(cx0)*Y6  - $signed(sx0)*$signed(zrs6[31:0])) >>> 14;
        // Vertex 7
        rx1_7 <= ($signed(cy0)*X7  + $signed(sy0)*Z7) >>> 14;
        rz1_7 <= zrs7[31:0];
        ry1_7 <= ($signed(cx0)*Y7  - $signed(sx0)*$signed(zrs7[31:0])) >>> 14;
    end

    // ------------------------------------------------------------------
    // Stage 2: perspective projection
    //   z_cam = rz + Z_OFF,  clamped to [64,574]  → index = z_cam-64
    //   recip = rec_lut[index]   (u16, = round(65536/z_cam))
    //   screen_x = CX + (rx * FOV * recip) >> 16
    //
    // FOV=200 fits in 8 bits; rx fits in ~8 bits after rotation;
    // FOV*rx fits in s24. recip is u16. Product s40; >>16 gives s24,
    // truncated to s11 for screen coord.
    // ------------------------------------------------------------------
    localparam integer Z_OFF = 300;
    localparam integer FOV   = 140;
    localparam integer CX    = SCREEN_W / 2;
    localparam integer CY    = SCREEN_H / 2;

    // LUT index wires: clamp z_cam to [64,574] then subtract 64
    function automatic [8:0] zidx;
        input signed [31:0] rz;
        reg signed [31:0] zc;
        begin
            zc = rz + Z_OFF;
            if      (zc < 32'd64)  zidx = 9'd0;
            else if (zc > 32'd574) zidx = 9'd510;
            else                   zidx = zc[8:0] - 9'd64;
        end
    endfunction

    // Per-vertex recip wires (combinatorial LUT read from s1 registers)
    wire [15:0] r0 = rec_lut[zidx(rz1_0)];
    wire [15:0] r1 = rec_lut[zidx(rz1_1)];
    wire [15:0] r2 = rec_lut[zidx(rz1_2)];
    wire [15:0] r3 = rec_lut[zidx(rz1_3)];
    wire [15:0] r4 = rec_lut[zidx(rz1_4)];
    wire [15:0] r5 = rec_lut[zidx(rz1_5)];
    wire [15:0] r6 = rec_lut[zidx(rz1_6)];
    wire [15:0] r7 = rec_lut[zidx(rz1_7)];

    logic signed [10:0] pvx0,pvy0, pvx1,pvy1, pvx2,pvy2, pvx3,pvy3;
    logic signed [10:0] pvx4,pvy4, pvx5,pvy5, pvx6,pvy6, pvx7,pvy7;
    logic s2v;

    // project_x/y: (world * FOV * recip) >> 16, then add centre
    // Expand recip to signed by prepending 0 bit: {1'b0, r}
    `define PROJ(CENTRE, WORLD, RECIP) \
        (CENTRE) + (($signed(WORLD) * FOV * $signed({1'b0,RECIP})) >>> 16)

    always_ff @(posedge clk) begin
        s2v  <= s1v;
        pvx0 <= `PROJ(CX, rx1_0, r0);  pvy0 <= `PROJ(CY, ry1_0, r0);
        pvx1 <= `PROJ(CX, rx1_1, r1);  pvy1 <= `PROJ(CY, ry1_1, r1);
        pvx2 <= `PROJ(CX, rx1_2, r2);  pvy2 <= `PROJ(CY, ry1_2, r2);
        pvx3 <= `PROJ(CX, rx1_3, r3);  pvy3 <= `PROJ(CY, ry1_3, r3);
        pvx4 <= `PROJ(CX, rx1_4, r4);  pvy4 <= `PROJ(CY, ry1_4, r4);
        pvx5 <= `PROJ(CX, rx1_5, r5);  pvy5 <= `PROJ(CY, ry1_5, r5);
        pvx6 <= `PROJ(CX, rx1_6, r6);  pvy6 <= `PROJ(CY, ry1_6, r6);
        pvx7 <= `PROJ(CX, rx1_7, r7);  pvy7 <= `PROJ(CY, ry1_7, r7);
    end

    // ------------------------------------------------------------------
    // Stage 3: output register + valid pulse
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            valid <= 1'b0;
        end else begin
            valid <= s2v;
            if (s2v) begin
                vx[0]<=pvx0; vy[0]<=pvy0; vx[1]<=pvx1; vy[1]<=pvy1;
                vx[2]<=pvx2; vy[2]<=pvy2; vx[3]<=pvx3; vy[3]<=pvy3;
                vx[4]<=pvx4; vy[4]<=pvy4; vx[5]<=pvx5; vy[5]<=pvy5;
                vx[6]<=pvx6; vy[6]<=pvy6; vx[7]<=pvx7; vy[7]<=pvy7;
            end
        end
    end

endmodule
