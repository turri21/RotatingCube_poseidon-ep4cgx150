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

// Scrolling text banner rendered on-the-fly during VGA scanout.
// No framebuffer — pure combinatorial font lookup.
// Text row now at top of screen: y=8..15 (adjust TEXT_Y as desired).
// Priority: text > cube > stars > background.

module text_scroller (
    input  logic        clk_sys,
    input  logic        reset,
    input  logic        newframe_sys,
    input  logic        clk_vid,
    input  logic  [8:0] scan_x,
    input  logic  [7:0] scan_y,
    output logic        text_hit,
    output logic  [7:0] text_r,
    output logic  [7:0] text_g,
    output logic  [7:0] text_b
);

    // ------------------------------------------------------------------------
    // Position: set TEXT_Y to the scanline where you want the text band.
    // Text is 8 pixels tall (TEXT_H).  y=8 puts it near the very top.
    // ------------------------------------------------------------------------
    localparam [7:0]  TEXT_Y   = 8'd8;      // was 8'd200
    localparam [7:0]  TEXT_H   = 8'd8;
    localparam [15:0] MSG_LEN = 16'd94;
    localparam [15:0] MSG_PIX = 16'd752;

    // Font ROM: 96 chars x 8 rows x 8 bits
    localparam [6143:0] FONT_ROM = 6144'h00000000000000000000000000000000000000000000000000000000000000000000000000000000007f664c1831637f001e0c0c1e3333330063361c1c3663630063777f6b636363000c1e3333333333003f333333333333001e0c0c0c0c2d3f001e33380e07331e006766363e66663f00381e3b3333331e000f06063e66663f001c36636363361c006363737b6f67630063636b7f7f7763007f66460606060f006766361e366667001e333330303078001e0c0c0c0c0c1e003333333f333333007c66730303663c000f06161e16467f007f46161e16467f001f36666666361f003c66030303663c003f66663e66663f0033333f33331e0c0000000000180c1cff000000000000000000000063361c08001e18181818181e00406030180c0603001e06060606061e007f664c1831637f001e0c0c1e3333330063361c1c3663630063777f6b636363000c1e3333333333003f333333333333001e0c0c0c0c2d3f001e33380e07331e006766363e66663f00381e3b3333331e000f06063e66663f001c36636363361c006363737b6f67630063636b7f7f7763007f66460606060f006766361e366667001e333330303078001e0c0c0c0c0c1e003333333f333333007c66730303663c000f06161e16467f007f46161e16467f001f36666666361f003c66030303663c003f66663e66663f0033333f33331e0c001e037b7b7b633e000c000c1830331e00060c1830180c0600003f00003f000000180c0603060c18060c0c00000c0c00000c0c00000c0c00000e18303e33331e001e33331e33331e000c0c0c1830333f001e33301c30331e001e3330301f033f0078307f33363c38001e33301c30331e003f33061c30331e003f0c0c0c0c0e0c003e676f7b73633e000103060c183060000c0c0000000000000000003f000000060c0c000000000000000c0c3f0c0c000000663cff3c660000060c1818180c0600180c0606060c180000000000030606006e333b6e1c361c0063660c18336300000c1f301e033e0c0036367f367f3636000000000000363600180018183c3c180000000000000000;

    // Message ROM: 79 ASCII chars packed as 8-bit each
    localparam [751:0] MSG_ROM = 752'h2d2d20216d617267656c6554206e6f20736b616572662041475046206c6c61206f742073676e697465657247202d2d202a202121212041475046204e4f444945534f5020524f46204f4d4544204542554320474e495441544f52202a2020;

    // Scroll counter (clk_sys)
    logic [15:0] scroll_x;

    always_ff @(posedge clk_sys) begin
        if (reset)
            scroll_x <= '0;
        else if (newframe_sys)
            scroll_x <= (scroll_x >= MSG_PIX - 1) ? 16'd0 : scroll_x + 1'b1;
    end

    // CDC to clk_vid (2-FF)
    logic [15:0] sc_s1, sc_s2;
    always_ff @(posedge clk_vid) begin
        sc_s1 <= scroll_x;
        sc_s2 <= sc_s1;
    end

    // Pixel lookup
    wire in_row = (scan_y >= TEXT_Y) && (scan_y < TEXT_Y + TEXT_H);

    // Scrolled pixel position within message (modulo MSG_PIX)
    wire [15:0] raw_px  = {7'b0, scan_x} + sc_s2;
    wire [15:0] px      = (raw_px >= MSG_PIX) ? raw_px - MSG_PIX : raw_px;
    wire  [6:0] char_n  = px[15:3];   // px / 8  (max 79 chars)
    wire  [2:0] col     = px[2:0];    // px % 8
    wire  [2:0] row_idx = scan_y[2:0];

    // ASCII lookup then font lookup
    wire  [7:0] ascii     = MSG_ROM[char_n * 8 +: 8];
    wire  [6:0] char_idx  = ascii - 8'd32;
    wire  [7:0] font_byte = FONT_ROM[char_idx * 64 + row_idx * 8 +: 8];

    // ------------------------------------------------------------------------
    // FIX: un-mirror the glyph — read bits left-to-right instead of right-to-left
    // ------------------------------------------------------------------------
    wire pixel_on = font_byte[col];   // was font_byte[7 - col]

    always_ff @(posedge clk_vid) begin
        if (in_row && pixel_on) begin
            text_hit <= 1'b1;
            text_r   <= 8'd220;   // bright yellow
            text_g   <= 8'd220;
            text_b   <= 8'd16;
        end else begin
            text_hit <= 1'b0;
            text_r   <= 8'd0;
            text_g   <= 8'd0;
            text_b   <= 8'd0;
        end
    end

endmodule