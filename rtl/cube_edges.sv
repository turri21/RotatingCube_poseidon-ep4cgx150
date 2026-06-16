// Sequences the 12 edges of a cube through line_draw.

module cube_edges (
    input  logic        clk,
    input  logic        reset,

    input  logic        draw_start,

    input  logic signed [10:0] vx [0:7],
    input  logic signed [10:0] vy [0:7],

    output logic        ld_start,
    output logic signed [10:0] ld_x0, ld_y0,
    output logic signed [10:0] ld_x1, ld_y1,
    input  logic        ld_done,

    input  logic signed [10:0] ld_px, ld_py,
    input  logic        ld_pvalid,

    output logic [16:0] fb_waddr,
    output logic        fb_we,

    output logic        frame_done
);

    localparam NUM_EDGES = 12;
    localparam SCREEN_W  = 360;
    localparam SCREEN_H  = 240;

    // Edge table
    logic [2:0] ea [0:11] = '{0,1,2,3, 4,5,6,7, 0,1,2,3};
    logic [2:0] eb [0:11] = '{1,2,3,0, 5,6,7,4, 4,5,6,7};

    logic [3:0] edge_idx;
    typedef enum logic [1:0] { IDLE, NEXT_EDGE, DRAWING } state_t;
    state_t state;

    // ------------------------------------------------------------------
    // Pixel write path
    // The multiply ld_py * 720 is registered (1 cycle latency).
    // We pipeline fb_we to match so they always arrive together.
    // ------------------------------------------------------------------
    logic        we_pipe;
    logic [16:0] addr_pipe;

    always_ff @(posedge clk) begin
        // Stage A: check bounds, start multiply
        we_pipe   <= 1'b0;
        if (ld_pvalid &&
            $signed(ld_px) >= 0 && $signed(ld_px) < $signed(11'(SCREEN_W)) &&
            $signed(ld_py) >= 0 && $signed(ld_py) < $signed(11'(SCREEN_H))) begin
            addr_pipe <= 17'(unsigned'(ld_py)) * 17'd360 + 17'(unsigned'(ld_px));
            we_pipe   <= 1'b1;
        end

        // Stage B: output (multiply result now stable)
        fb_waddr <= addr_pipe;
        fb_we    <= we_pipe;
    end

    // ------------------------------------------------------------------
    // Edge sequencer FSM
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        ld_start   <= 1'b0;
        frame_done <= 1'b0;

        if (reset) begin
            state    <= IDLE;
            edge_idx <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (draw_start) begin
                        edge_idx <= '0;
                        state    <= NEXT_EDGE;
                    end
                end

                NEXT_EDGE: begin
                    if (edge_idx == NUM_EDGES) begin
                        frame_done <= 1'b1;
                        state      <= IDLE;
                    end else begin
                        ld_x0    <= vx[ea[edge_idx]];
                        ld_y0    <= vy[ea[edge_idx]];
                        ld_x1    <= vx[eb[edge_idx]];
                        ld_y1    <= vy[eb[edge_idx]];
                        ld_start <= 1'b1;
                        state    <= DRAWING;
                    end
                end

                DRAWING: begin
                    if (ld_done) begin
                        edge_idx <= edge_idx + 1'b1;
                        state    <= NEXT_EDGE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
