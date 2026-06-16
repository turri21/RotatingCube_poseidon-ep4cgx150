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

// I2S Transmitter
// Standard left-justified I2S: LRCLK low = left, high = right.
// MSB is clocked out on the first falling edge of SCLK after LRCLK toggles.


`default_nettype none

module i2s
#(
    parameter I2S_Freq  = 48_000,   // sample rate in Hz
    parameter AUDIO_DW  = 16        // bits per channel
)
(
    input                    reset,
    input                    clk,
    input  [31:0]            clk_rate,  // clk frequency in Hz
    output reg               sclk,
    output reg               lrclk,
    output reg               sdata,
    input  [AUDIO_DW-1:0]   left_chan,
    input  [AUDIO_DW-1:0]   right_chan
);

// ---------------------------------------------------------------------------
// Bit-clock generation
// Target SCLK = I2S_Freq * 2 channels * AUDIO_DW bits * 2 (edges per bit)
// We accumulate a phase counter and toggle sclk each time it overflows.
// ---------------------------------------------------------------------------
localparam integer SCLK_RATE = I2S_Freq * 2 * AUDIO_DW * 2;

reg [31:0] phase_acc;
reg        sclk_tick;   // one pulse per SCLK edge

always @(posedge clk) begin
    sclk_tick <= 1'b0;
    if (reset) begin
        phase_acc <= 32'd0;
    end else begin
        if (phase_acc + SCLK_RATE >= clk_rate) begin
            phase_acc <= phase_acc + SCLK_RATE - clk_rate;
            sclk_tick <= 1'b1;
        end else begin
            phase_acc <= phase_acc + SCLK_RATE;
        end
    end
end

// ---------------------------------------------------------------------------
// Shift register and framing
// Bit counter runs 0..AUDIO_DW-1 per channel half-frame.
// LRCLK: 0 = left, 1 = right  (standard I2S polarity).
// Data is latched on the rising edge of SCLK and shifted out MSB-first.
// ---------------------------------------------------------------------------
reg [AUDIO_DW-1:0] shift;
reg [$clog2(AUDIO_DW)-1:0] bit_cnt;

always @(posedge clk) begin
    if (reset) begin
        sclk    <= 1'b1;
        lrclk   <= 1'b0;
        sdata   <= 1'b0;
        shift   <= '0;
        bit_cnt <= '0;
    end else if (sclk_tick) begin
        sclk <= ~sclk;

        if (sclk) begin
            // ---- Falling edge of SCLK: advance framing, output next bit ----
            if (bit_cnt == AUDIO_DW - 1) begin
                // End of this channel's frame — toggle LRCLK
                bit_cnt <= '0;
                lrclk   <= ~lrclk;
                // Pre-load the channel that is *about* to start transmitting.
                // After toggle: lrclk will be ~lrclk, so we load based on new value.
                shift <= lrclk ? left_chan : right_chan;
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
                shift   <= {shift[AUDIO_DW-2:0], 1'b0};  // shift left, MSB first
            end
            sdata <= shift[AUDIO_DW-1];
        end
        // Rising edge of SCLK: receiver latches sdata — nothing to do here.
    end
end

endmodule

`default_nettype wire
