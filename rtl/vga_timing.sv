// Generates standard VGA sync signals for 720x480 @ 60 Hz
// Pixel clock: 27.000 MHz  (In case of Senhor, use Senhor's CLK_VIDEO)
//
// Horizontal: 720 active + 16 fp + 62 sync + 60 bp  = 858 total
// Vertical  : 480 active +  9 fp +  6 sync + 30 bp  = 525 total

module vga_timing #(
    parameter H_ACTIVE = 720,
    parameter H_FP     = 16,
    parameter H_SYNC   = 62,
    parameter H_BP     = 60,
    parameter V_ACTIVE = 480,
    parameter V_FP     = 9,
    parameter V_SYNC   = 6,
    parameter V_BP     = 30
)(
    input  logic        clk,    // 27 MHz pixel clock
    input  logic        reset,

    output logic [9:0]  hc,     // horizontal counter (0..total-1)
    output logic [9:0]  vc,     // vertical counter
    output logic        hsync,
    output logic        vsync,
    output logic        de,     // display enable (active region)
    output logic        newframe // 1-cycle pulse at start of each frame
);

    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    always_ff @(posedge clk) begin
        if (reset) begin
            hc       <= '0;
            vc       <= '0;
            newframe <= 1'b0;
        end else begin
            newframe <= 1'b0;
            if (hc == H_TOTAL - 1) begin
                hc <= '0;
                if (vc == V_TOTAL - 1) begin
                    vc       <= '0;
                    newframe <= 1'b1;
                end else begin
                    vc <= vc + 1'b1;
                end
            end else begin
                hc <= hc + 1'b1;
            end
        end
    end

    assign hsync = ~((hc >= H_ACTIVE + H_FP) && (hc < H_ACTIVE + H_FP + H_SYNC));
    assign vsync = ~((vc >= V_ACTIVE + V_FP) && (vc < V_ACTIVE + V_FP + V_SYNC));
    assign de    = (hc < H_ACTIVE) && (vc < V_ACTIVE);

endmodule
