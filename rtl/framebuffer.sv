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

// Double-buffered 360x240 1-bit framebuffer.
//
// Uses explicit altsyncram instantiation (not inference) so Quartus
// reliably maps to M10K regardless of data width.
//
// Two banks, each a 1-bit wide x 86400 deep simple-dual-port M10K array.
// Writer goes to back bank, reader from front bank — zero CDC conflicts.
//
// Read latency: 1 cycle (registered output mode on altsyncram).
// Caller must delay VGA sync by 1 cycle (as before).
//
// swap_req/swap_ack: double-buffer swap with 2-FF CDC crossing.

module framebuffer #(
    parameter SCREEN_W = 360,
    parameter SCREEN_H = 240
)(
    input  logic        wclk,
    input  logic        we,
    input  logic [16:0] waddr,
    input  logic        wdata,

    input  logic        swap_req,
    output logic        swap_ack,

    input  logic        rclk,
    input  logic [16:0] raddr,
    output logic        rdata
);

    localparam DEPTH = SCREEN_W * SCREEN_H;  // 86400

    // ----------------------------------------------------------------
    // back_is_b (wclk domain): 1 = writer→B reader→A, 0 = writer→A reader→B
    // ----------------------------------------------------------------
    logic back_is_b;

    // Sync to rclk
    logic r1, r2;
    always_ff @(posedge rclk) { r2, r1 } <= { r1, back_is_b };
    wire front_is_b = r2;

    // Sync back to wclk for swap_ack
    logic w1, w2, w2p;
    always_ff @(posedge wclk) begin
        { w2, w1 } <= { w1, r2 };
        w2p      <= w2;
        swap_ack <= w2 ^ w2p;
    end

    always_ff @(posedge wclk)
        if (swap_req) back_is_b <= ~back_is_b;

    // ----------------------------------------------------------------
    // Per-bank write enables
    // ----------------------------------------------------------------
    wire we_a = we & ~back_is_b;
    wire we_b = we &  back_is_b;

    // ----------------------------------------------------------------
    // Bank A — altsyncram simple dual-port, 1-bit x 86400
    // ----------------------------------------------------------------
    wire rdata_a, rdata_b;

    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (1),
        .widthad_a                   (17),
        .numwords_a                  (DEPTH),
        .width_b                     (1),
        .widthad_b                   (17),
        .numwords_b                  (DEPTH),
        .lpm_type                    ("altsyncram"),
        .width_byteena_a             (1),
        .outdata_reg_b               ("CLOCK1"),
        .indata_aclr_a               ("NONE"),
        .wrcontrol_aclr_a            ("NONE"),
        .address_aclr_a              ("NONE"),
        .rdcontrol_reg_b             ("CLOCK1"),
        .address_reg_b               ("CLOCK1"),
        .outdata_aclr_b              ("NONE"),
        .read_during_write_mode_mixed_ports ("DONT_CARE"),
        .ram_block_type              ("M10K"),
        .intended_device_family      ("Cyclone V"),
        .power_up_uninitialized      ("FALSE"),
        .init_file                   ("UNUSED")
    ) ram_a (
        .clock0    (wclk),
        .wren_a    (we_a),
        .address_a (waddr),
        .data_a    (wdata),
        .clock1    (rclk),
        .address_b (raddr),
        .q_b       (rdata_a),
        // unused
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0),
        .addressstall_b(1'b0), .byteena_a(1'b1), .byteena_b(1'b1),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .data_b(1'b0), .eccstatus(), .q_a(), .rden_a(1'b1), .rden_b(1'b1),
        .wren_b(1'b0)
    );

    // ----------------------------------------------------------------
    // Bank B — identical parameters
    // ----------------------------------------------------------------
    altsyncram #(
        .operation_mode              ("DUAL_PORT"),
        .width_a                     (1),
        .widthad_a                   (17),
        .numwords_a                  (DEPTH),
        .width_b                     (1),
        .widthad_b                   (17),
        .numwords_b                  (DEPTH),
        .lpm_type                    ("altsyncram"),
        .width_byteena_a             (1),
        .outdata_reg_b               ("CLOCK1"),
        .indata_aclr_a               ("NONE"),
        .wrcontrol_aclr_a            ("NONE"),
        .address_aclr_a              ("NONE"),
        .rdcontrol_reg_b             ("CLOCK1"),
        .address_reg_b               ("CLOCK1"),
        .outdata_aclr_b              ("NONE"),
        .read_during_write_mode_mixed_ports ("DONT_CARE"),
        .ram_block_type              ("M10K"),
        .intended_device_family      ("Cyclone V"),
        .power_up_uninitialized      ("FALSE"),
        .init_file                   ("UNUSED")
    ) ram_b (
        .clock0    (wclk),
        .wren_a    (we_b),
        .address_a (waddr),
        .data_a    (wdata),
        .clock1    (rclk),
        .address_b (raddr),
        .q_b       (rdata_b),
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0),
        .addressstall_b(1'b0), .byteena_a(1'b1), .byteena_b(1'b1),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .data_b(1'b0), .eccstatus(), .q_a(), .rden_a(1'b1), .rden_b(1'b1),
        .wren_b(1'b0)
    );

    // ----------------------------------------------------------------
    // Output mux — select front bank
    // front_is_b is in rclk domain; delay 1 cycle to align with
    // altsyncram registered output
    // ----------------------------------------------------------------
    logic front_is_b_d;
    always_ff @(posedge rclk) front_is_b_d <= front_is_b;

    assign rdata = front_is_b_d ? rdata_b : rdata_a;

endmodule
