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

// Bresenham line-draw engine.
// One pixel output per clock in RUN state.
// Fixes: e2 as combinatorial wire; single err update accumulates both axes.

module line_draw #(
    parameter COORD_W = 11
)(
    input  logic                      clk,
    input  logic                      reset,
    input  logic                      start,
    input  logic signed [COORD_W-1:0] x0, y0,
    input  logic signed [COORD_W-1:0] x1, y1,
    output logic signed [COORD_W-1:0] px, py,
    output logic                      pvalid,
    output logic                      done
);

    typedef enum logic [1:0] { IDLE, RUN } state_t;
    state_t state;

    logic signed [COORD_W:0]   dx, dy;       // dy stored as -abs(dy)
    logic signed [COORD_W:0]   sx, sy;       // step direction ±1
    logic signed [COORD_W+1:0] err;
    logic signed [COORD_W-1:0] cx, cy, ex, ey;

    // e2 is purely combinatorial — avoids blocking-in-always_ff
    wire signed [COORD_W+1:0] e2 = err <<< 1;

    // Both-axis error accumulation: if both e2>=dy and e2<=dx fire together,
    // we need to add both dy and dx in one cycle.
    wire step_x = (e2 >= dy);
    wire step_y = (e2 <= dx);

    always_ff @(posedge clk) begin
        done   <= 1'b0;
        pvalid <= 1'b0;

        if (reset) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        cx  <= x0;
                        cy  <= y0;
                        ex  <= x1;
                        ey  <= y1;
                        dx  <=  (x1 >= x0) ? (x1 - x0) : (x0 - x1);
                        dy  <= -((y1 >= y0) ? (y1 - y0) : (y0 - y1));  // negative
                        sx  <= (x0 < x1) ? {{COORD_W{1'b0}}, 1'b1} : {(COORD_W+1){1'b1}};  // +1 or -1
                        sy  <= (y0 < y1) ? {{COORD_W{1'b0}}, 1'b1} : {(COORD_W+1){1'b1}};
                        // err = dx - abs(dy) = dx + dy  (dy is already negative)
                        err <= (x1 >= x0 ? x1-x0 : x0-x1)
                             - (y1 >= y0 ? y1-y0 : y0-y1);
                        state <= RUN;
                    end
                end

                RUN: begin
                    pvalid <= 1'b1;
                    px     <= cx;
                    py     <= cy;

                    if (cx == ex && cy == ey) begin
                        done  <= 1'b1;
                        state <= IDLE;
                    end else begin
                        // Accumulate error for whichever axes step
                        err <= err
                             + (step_x ? dy : '0)
                             + (step_y ? dx : '0);
                        if (step_x) cx <= cx + sx[COORD_W-1:0];
                        if (step_y) cy <= cy + sy[COORD_W-1:0];
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
