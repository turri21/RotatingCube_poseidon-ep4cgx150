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

`default_nettype none

module guest_top
(
	input         CLOCK_27,
`ifdef USE_CLOCK_50
	input         CLOCK_50,
`endif

	output        LED,
	output [VGA_BITS-1:0] VGA_R,
	output [VGA_BITS-1:0] VGA_G,
	output [VGA_BITS-1:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,

`ifdef USE_HDMI
	output        HDMI_RST,
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_PCLK,
	output        HDMI_DE,
	inout         HDMI_SDA,
	inout         HDMI_SCL,
	input         HDMI_INT,
`endif

	input         SPI_SCK,
	inout         SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,    // data_io
	input         SPI_SS3,    // OSD
	input         CONF_DATA0, // SPI_SS for user_io

`ifdef USE_QSPI
	input         QSCK,
	input         QCSn,
	inout   [3:0] QDAT,
`endif
`ifndef NO_DIRECT_UPLOAD
	input         SPI_SS4,
`endif

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE,

`ifdef DUAL_SDRAM
	output [12:0] SDRAM2_A,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_DQML,
	output        SDRAM2_DQMH,
	output        SDRAM2_nWE,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nCS,
	output  [1:0] SDRAM2_BA,
	output        SDRAM2_CLK,
	output        SDRAM2_CKE,
`endif

	output        AUDIO_L,
	output        AUDIO_R,
`ifdef I2S_AUDIO
	output        I2S_BCK,
	output        I2S_LRCK,
	output        I2S_DATA,
`endif
`ifdef I2S_AUDIO_HDMI
	output        HDMI_MCLK,
	output        HDMI_BCK,
	output        HDMI_LRCK,
	output        HDMI_SDATA,
`endif
`ifdef SPDIF_AUDIO
	output        SPDIF,
`endif
`ifdef USE_AUDIO_IN
	input         AUDIO_IN,
`endif
`ifdef USE_MIDI_PINS
	output        MIDI_OUT,
	input         MIDI_IN,
`endif
`ifdef SIDI128_EXPANSION
	input         UART_CTS,
	output        UART_RTS,
	inout         EXP7,
	inout         MOTOR_CTRL,
`endif
	input         UART_RX,
	output        UART_TX
);

`ifdef NO_DIRECT_UPLOAD
localparam bit DIRECT_UPLOAD = 0;
wire SPI_SS4 = 1;
`else
localparam bit DIRECT_UPLOAD = 1;
`endif

`ifdef USE_QSPI
localparam bit QSPI = 1;
assign QDAT = 4'hZ;
`else
localparam bit QSPI = 0;
`endif

`ifdef VGA_8BIT
localparam VGA_BITS = 8;
`else
localparam VGA_BITS = 6;
`endif

`ifdef USE_HDMI
localparam bit HDMI = 1;
assign HDMI_RST = 1'b1;
`else
localparam bit HDMI = 0;
`endif

`ifdef BIG_OSD
localparam bit BIG_OSD = 1;
`define SEP "-;",
`else
localparam bit BIG_OSD = 0;
`define SEP
`endif



    //wire  [1:0] buttons;
    //wire [63:0] status;
    //wire        forced_scandoubler;

    `include "build_id.v"

//    OSD suggestion for MiST framework (if used).
//
//    parameter CONF_STR = {
//        "RotatingCube;;",
//        "-;",
//        "O21,Color,White,Cyan,Green,Yellow;",
//        "T0,Reset;",
//        "V,Poseidon-",`BUILD_DATE
//    };

    // ----------------------------------------------------------------
    // PLL 
    // ----------------------------------------------------------------
    wire clk_sys, clk_vid, clk_audio, pll_locked;
	 
	 assign clk_sys = CLOCK_50;
	 
    pll pll
    (
       .areset(1'b0),
       .inclk0(CLOCK_50), 
       .c0(clk_vid),       // 27 MHz
       .c1(clk_audio),     // 24.576 
       .locked(pll_locked)
    );

    wire reset = !pll_locked;
    //wire reset = status[0] | buttons[1] | !pll_locked;

    // ----------------------------------------------------------------
    // Rotation angle counters
    // ----------------------------------------------------------------
    localparam ROT_DIV = 500_000;

    logic [19:0] rot_ctr;
    logic [7:0]  angle_x, angle_y;

    always_ff @(posedge clk_sys) begin
        if (reset) begin
            rot_ctr <= '0;
            angle_x <= '0;
            angle_y <= '0;
        end else begin
            rot_ctr <= rot_ctr + 1'b1;
            if (rot_ctr == ROT_DIV - 1) begin
                rot_ctr <= '0;
                angle_y <= angle_y + 1'b1;
                if (angle_y == 8'd63) angle_x <= angle_x + 1'b1;
            end
        end
    end

    // ----------------------------------------------------------------
    // 3-D projection
    // ----------------------------------------------------------------
    wire signed [10:0] vx [0:7];
    wire signed [10:0] vy [0:7];
    wire               proj_valid;

    cube3d #(
        .SCREEN_W (360),
        .SCREEN_H (240),
        .SCALE    (100)
    ) cube3d_inst (
        .clk     (clk_sys),
        .reset   (reset),
        .angle_x (angle_x),
        .angle_y (angle_y),
        .vx      (vx),
        .vy      (vy),
        .valid   (proj_valid)
    );

    // ----------------------------------------------------------------
    // Framebuffer clear sequencer
    // proj_valid pulses for 1 cycle each time angles change.
    // We latch it so we don't miss it if clearing is still running.
    // Sequence: IDLE → on proj_valid, start clearing → when clear
    // done, pulse clear_done → cube_edges draws → repeat.
    // ----------------------------------------------------------------
    localparam FB_SIZE = 360 * 240;

    logic [16:0] clear_addr;
    logic        clearing;
    logic        clear_done;
    logic        fb_clear_we;
    logic        redraw_pending;   // latch: proj_valid arrived while busy

    always_ff @(posedge clk_sys) begin
        fb_clear_we <= 1'b0;
        clear_done  <= 1'b0;

        if (reset) begin
            clearing       <= 1'b0;
            clear_addr     <= '0;
            redraw_pending <= 1'b0;
        end else begin
            // Latch any proj_valid pulse
            if (proj_valid)
                redraw_pending <= 1'b1;

            if (!clearing && redraw_pending) begin
                // Start a new clear pass
                clearing       <= 1'b1;
                redraw_pending <= 1'b0;
                clear_addr     <= '0;
            end else if (clearing) begin
                fb_clear_we <= 1'b1;
                clear_addr  <= clear_addr + 1'b1;
                if (clear_addr == FB_SIZE - 1) begin
                    clearing   <= 1'b0;
                    clear_done <= 1'b1;
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Line drawer + edge sequencer
    // ----------------------------------------------------------------
    wire        ld_start;
    wire signed [10:0] ld_x0, ld_y0, ld_x1, ld_y1;
    wire        ld_done;
    wire signed [10:0] ld_px, ld_py;
    wire        ld_pvalid;

    line_draw #(.COORD_W(11)) line_draw_inst (
        .clk    (clk_sys),
        .reset  (reset),
        .start  (ld_start),
        .x0     (ld_x0), .y0 (ld_y0),
        .x1     (ld_x1), .y1 (ld_y1),
        .px     (ld_px), .py (ld_py),
        .pvalid (ld_pvalid),
        .done   (ld_done)
    );

    wire [18:0] edge_waddr;
    wire        edge_we;

    cube_edges edge_seq (
        .clk        (clk_sys),
        .reset      (reset),
        .draw_start (clear_done),
        .vx         (vx),
        .vy         (vy),
        .ld_start   (ld_start),
        .ld_x0      (ld_x0), .ld_y0 (ld_y0),
        .ld_x1      (ld_x1), .ld_y1 (ld_y1),
        .ld_done    (ld_done),
        .ld_px      (ld_px), .ld_py  (ld_py),
        .ld_pvalid  (ld_pvalid),
        .fb_waddr   (edge_waddr),
        .fb_we      (edge_we),
        .frame_done (frame_done)
    );

    // ----------------------------------------------------------------
    // Framebuffer write mux (clear takes priority over draw)
    // ----------------------------------------------------------------
    wire        frame_done;
    wire [16:0] fb_waddr = clearing ? clear_addr  : edge_waddr;
    wire        fb_we    = clearing ? fb_clear_we : edge_we;
    wire        fb_wdata = clearing ? 1'b0        : 1'b1;

    // ----------------------------------------------------------------
    // Double-buffer swap
    // Pulse swap_req after frame_done. The framebuffer's swap_ack
    // confirms the reader has switched, so we never write into the
    // buffer currently being displayed.
    // ----------------------------------------------------------------
    wire  fb_swap_ack;
    logic fb_swap_req;
    logic swap_pending;

    always_ff @(posedge clk_sys) begin
        fb_swap_req <= 1'b0;
        if (reset) begin
            swap_pending <= 1'b0;
        end else begin
            if (frame_done)   swap_pending <= 1'b1;
            if (swap_pending) begin
                fb_swap_req  <= 1'b1;
                swap_pending <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // VGA timing  (pixel clock domain)
    // ----------------------------------------------------------------
    wire [9:0]  hc, vc;
    wire        hsync_i, vsync_i, de_i, newframe;

    vga_timing timing_inst (
        .clk      (clk_vid),
        .reset    (reset),
        .hc       (hc),
        .vc       (vc),
        .hsync    (hsync_i),
        .vsync    (vsync_i),
        .de       (de_i),
        .newframe (newframe)
    );

    // CDC newframe (clk_vid, 1-cycle) → clk_sys
    // A 1-cycle 27MHz pulse is too short for a plain 2-FF sync at 50MHz.
    // Stretch it to 4 clk_vid cycles first, then sync.
    logic nf_stretch;
    logic [1:0] nf_cnt;
    always_ff @(posedge clk_vid) begin
        if (newframe)       begin nf_cnt <= 2'd3; nf_stretch <= 1'b1; end
        else if (nf_cnt>0)  begin nf_cnt <= nf_cnt - 1'b1; end
        else                begin nf_stretch <= 1'b0; end
    end

    logic nf_s1, nf_s2, nf_s2_prev, newframe_sys;
    always_ff @(posedge clk_sys) begin
        nf_s1        <= nf_stretch;
        nf_s2        <= nf_s1;
        nf_s2_prev   <= nf_s2;
        newframe_sys <= nf_s2 & ~nf_s2_prev;  // rising edge = one pulse per frame
    end

    // Starfield: on-the-fly pixel comparator in clk_vid domain
    wire       star_hit;
    wire [7:0] star_bright;

    starfield stars (
        .clk_sys      (clk_sys),
        .reset        (reset),
        .newframe_sys (newframe_sys),
        .clk_vid      (clk_vid),
        .scan_x       (hc[9:1]),
        .scan_y       (vc[8:1]),
        .star_hit     (star_hit),
        .star_bright  (star_bright)
    );

    // Text scroller
    wire        text_hit;
    wire  [7:0] text_r, text_g, text_b;

    text_scroller scroller (
        .clk_sys      (clk_sys),
        .reset        (reset),
        .newframe_sys (newframe_sys),
        .clk_vid      (clk_vid),
        .scan_x       (hc[9:1]),
        .scan_y       (vc[8:1]),
        .text_hit     (text_hit),
        .text_r       (text_r),
        .text_g       (text_g),
        .text_b       (text_b)
    );

    // ----------------------------------------------------------------
    // Framebuffer read
    // BRAM has 1-cycle read latency.  Delay sync signals by 1 cycle.
    // ----------------------------------------------------------------
    // Pixel-double: 720x480 output reads from 360x240 buffer
    // Divide scanout coordinates by 2 to map to render resolution
    wire [16:0] fb_raddr = {7'b0, vc[9:1]} * 17'd360 + {7'b0, hc[9:1]};
    wire        fb_rdata;

    framebuffer #(
        .SCREEN_W (360),
        .SCREEN_H (240)
    ) fb_inst (
        .wclk     (clk_sys),
        .we       (fb_we),
        .waddr    (fb_waddr),   // 17-bit for 360x240
        .wdata    (fb_wdata),
        .swap_req (fb_swap_req),
        .swap_ack (fb_swap_ack),
        .rclk     (clk_vid),
        .raddr    (fb_raddr),
        .rdata    (fb_rdata)
    );

    // ----------------------------------------------------------------
    // Output pipeline
    //
    // Cycle 0: hc/vc → fb_raddr + starfield scan_x/y
    // Cycle 1: fb_rdata valid; star_hit/star_bright valid (both 1 cycle)
    //          de_d1/hsync_d1/vsync_d1 aligned
    // Cycle 2: composite and register to output pins
    //
    // Compositing priority:
    //   1. Cube edge (fb_rdata=1) → cube color
    //   2. Star pixel (star_hit=1) → grey star brightness
    //   3. Background → black
    // All RGB forced to 0 outside de_d1 to prevent blanking bleed.
    // ----------------------------------------------------------------
    logic hsync_d1, vsync_d1, de_d1;
    always_ff @(posedge clk_vid) begin
        hsync_d1 <= hsync_i;
        vsync_d1 <= vsync_i;
        de_d1    <= de_i;
    end

    // ------------------------------------------------------------------------
    // Palette: use values that are multiples of 4 (up to 252) so that
    // after the [7:2] shift to RGB666 (Poseidon) the full 6-bit range is used.
    // ------------------------------------------------------------------------
    wire [1:0] color_sel = 2'd0;
	 //wire [1:0] color_sel = status[2:1];
    logic [7:0] col_r, col_g, col_b;
    always_comb begin
        case (color_sel)
            2'd0: begin col_r = 8'd252; col_g = 8'd252; col_b = 8'd252; end // White
            2'd1: begin col_r = 8'd0;   col_g = 8'd252; col_b = 8'd252; end // Cyan
            2'd2: begin col_r = 8'd0;   col_g = 8'd252; col_b = 8'd0;   end // Green
            2'd3: begin col_r = 8'd252; col_g = 8'd252; col_b = 8'd0;   end // Yellow
        endcase
    end

    wire show_text = text_hit & de_d1;
    wire show_cube = fb_rdata & de_d1 & ~text_hit;
    wire show_star = star_hit  & de_d1 & ~fb_rdata & ~text_hit;

    // Priority: text > cube > star > background
    wire [7:0] pix_r = show_text ? text_r :
                       show_cube ? col_r  :
                       show_star ? star_bright : 8'h00;
    wire [7:0] pix_g = show_text ? text_g :
                       show_cube ? col_g  :
                       show_star ? star_bright : 8'h00;
    wire [7:0] pix_b = show_text ? text_b :
                       show_cube ? col_b  :
                       show_star ? star_bright : 8'h00;

    // --------------------------------------------------------------------
    // Output register: shift 8-bit pixels down to 6-bit RGB666 (Poseidon).
    // Take [7:2] (the MSBs) so that full-scale 8-bit values map to
    // full-scale 6-bit values, rather than truncating the MSBs.
    // --------------------------------------------------------------------
    always_ff @(posedge clk_vid) begin
        VGA_HS <= hsync_d1;
        VGA_VS <= vsync_d1;
        VGA_R  <= pix_r[7:2];
        VGA_G  <= pix_g[7:2];
        VGA_B  <= pix_b[7:2];
    end
	 

	 wire [15:0] audio_left;
	 wire [15:0] audio_right;
	 
	 (* multstyle = "logic" *)
    audio_synth synth (
        .clk     (clk_audio),
        .reset   (reset),
        .audio_l (audio_left),
        .audio_r (audio_right)
    );
 
	 `ifdef I2S_AUDIO
	 i2s i2s (
	    .reset(1'b0),
		 .clk(clk_audio),
		 .clk_rate(32'd24_576_000),
		 .sclk(I2S_BCK),
		 .lrclk(I2S_LRCK),
		 .sdata(I2S_DATA),
		 .left_chan(audio_left),
		 .right_chan(audio_right)
	 );
	 `endif

endmodule

`default_nettype wire
