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

// 64-star parallax starfield rendered entirely in combinatorial logic
// during VGA scanout — no framebuffer needed for stars.
//
// Two clock domains:
//   clk_sys: scroll counters update on newframe_sys pulse
//   clk_vid: for each pixel, check 64 positions → star_hit + star_bright
//
// Star positions (scrolled_x, base_y) are registered in clk_sys and
// then double-registered (2-FF CDC) into clk_vid before comparison.
//
// The cube framebuffer is unchanged — stars are composited on top
// in RotatingCube.sv: if star_hit and FB pixel = 0, use star brightness.
// If FB pixel = 1 (cube edge), cube wins.

module starfield (
    // clk_sys domain
    input  logic        clk_sys,
    input  logic        reset,
    input  logic        newframe_sys,   // 1-cycle pulse each frame (clk_sys)

    // clk_vid domain — pixel comparator
    input  logic        clk_vid,
    input  logic  [8:0] scan_x,         // hc[9:1] — render-resolution x
    input  logic  [7:0] scan_y,         // vc[8:1] — render-resolution y

    output logic        star_hit,       // 1 = current pixel is a star
    output logic  [7:0] star_bright     // brightness of matched star (0 if no hit)
);

    localparam SCREEN_W  = 360;
    localparam NUM_STARS = 64;

    // ------------------------------------------------------------------
    // Star ROM (packed, Quartus-safe)
    // ------------------------------------------------------------------
    localparam [575:0] STAR_X_ROM = 576'h2088c567b4e82665142750207007425a915dae4398b5c2706208b9959f892ca360854275af228a7119bd9cd653740cd281793d0451120b2c184ac4759406708f9dc1f2ead11d1947;
    localparam [511:0] STAR_Y_ROM = 512'ha8c2bbe03d1c52c75f4ce9c3006f57e2b840616ca0dc7e386dbe43e2a73666d253ec76baa2efab5ea26114a9319e8d1fba9a181a276cc2723281176cbdbc3e1c;
    localparam [127:0] STAR_L_ROM = 128'hdc2c51920c41e7e81d4aa52be866c404;

    // Brightness per layer (limited-range safe)
    // Layer 0 = dimmest, layer 3 = brightest
    function automatic [7:0] layer_bright(input [1:0] l);
        case (l)
            2'd0: layer_bright = 8'd70;
            2'd1: layer_bright = 8'd120;
            2'd2: layer_bright = 8'd170;
            2'd3: layer_bright = 8'd220;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Scroll counters (clk_sys domain)
    // ------------------------------------------------------------------
    logic [5:0] scroll_ctr;
    logic [8:0] scroll_l0, scroll_l1, scroll_l2, scroll_l3;

    always_ff @(posedge clk_sys) begin
        if (reset) begin
            scroll_ctr <= '0;
            scroll_l0  <= '0; scroll_l1 <= '0;
            scroll_l2  <= '0; scroll_l3 <= '0;
        end else if (newframe_sys) begin
            scroll_ctr <= scroll_ctr + 1'b1;
            // Scroll speeds: layer0=1px/8f, layer1=1px/4f, layer2=1px/2f, layer3=1px/f
            if (scroll_ctr[2:0] == 3'd7)
                scroll_l0 <= (scroll_l0 == SCREEN_W-1) ? 9'd0 : scroll_l0 + 1'b1;
            if (scroll_ctr[1:0] == 2'd3)
                scroll_l1 <= (scroll_l1 == SCREEN_W-1) ? 9'd0 : scroll_l1 + 1'b1;
            if (scroll_ctr[0] == 1'd1)
                scroll_l2 <= (scroll_l2 == SCREEN_W-1) ? 9'd0 : scroll_l2 + 1'b1;
            // Layer 3: every frame
            scroll_l3 <= (scroll_l3 == SCREEN_W-1) ? 9'd0 : scroll_l3 + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // CDC: sync scroll values to clk_vid (2-FF per scroll register)
    // Scrolling is slow (pixels per second), so the 1-cycle glitch
    // window of a 2-FF sync is imperceptible.
    // ------------------------------------------------------------------
    logic [8:0] vs_l0_1, vs_l0_2;
    logic [8:0] vs_l1_1, vs_l1_2;
    logic [8:0] vs_l2_1, vs_l2_2;
    logic [8:0] vs_l3_1, vs_l3_2;

    always_ff @(posedge clk_vid) begin
        vs_l0_1 <= scroll_l0; vs_l0_2 <= vs_l0_1;
        vs_l1_1 <= scroll_l1; vs_l1_2 <= vs_l1_1;
        vs_l2_1 <= scroll_l2; vs_l2_2 <= vs_l2_1;
        vs_l3_1 <= scroll_l3; vs_l3_2 <= vs_l3_1;
    end

    // ------------------------------------------------------------------
    // Per-star scrolled x position (clk_vid, combinatorial)
    // ------------------------------------------------------------------
    function automatic [8:0] star_sx(input integer i);
        reg  [8:0] bx;
        reg  [1:0] l;
        reg  [8:0] sc;
        reg  [9:0] sum;
        begin
            bx  = STAR_X_ROM[i*9 +: 9];
            l   = STAR_L_ROM[i*2 +: 2];
            case (l)
                2'd0: sc = vs_l0_2;
                2'd1: sc = vs_l1_2;
                2'd2: sc = vs_l2_2;
                2'd3: sc = vs_l3_2;
            endcase
            sum = {1'b0,bx} + {1'b0,sc};
            star_sx = (sum >= SCREEN_W) ? sum[8:0] - 9'(SCREEN_W) : sum[8:0];
        end
    endfunction

    // ------------------------------------------------------------------
    // Pixel comparator — unrolled for all 64 stars
    // Registered output to meet timing at 27 MHz.
    // ------------------------------------------------------------------
    logic hit_r;
    logic [7:0] bright_r;

    // Build hit/brightness combinatorially then register
    logic hit_c;
    logic [7:0] bright_c;

    // We unroll the 64-star check using a generate loop.
    // Quartus handles generate + integer functions in always_comb fine.
    integer k;
    always_comb begin
        hit_c    = 1'b0;
        bright_c = 8'd0;
        for (k = 0; k < NUM_STARS; k = k + 1) begin
            if (scan_x == star_sx(k) &&
                scan_y == STAR_Y_ROM[k*8 +: 8]) begin
                hit_c    = 1'b1;
                bright_c = layer_bright(STAR_L_ROM[k*2 +: 2]);
            end
        end
    end

    always_ff @(posedge clk_vid) begin
        hit_r    <= hit_c;
        bright_r <= bright_c;
    end

    assign star_hit    = hit_r;
    assign star_bright = bright_r;

endmodule
