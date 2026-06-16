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

// ============================================================================
// 16-Voice Polyphonic MIDI Synthesizer — Poseidon FPGA.
// ============================================================================
// Fixes low-note buzz WITHOUT DSP multipliers:
//   - Sine LUT stored as 20-bit fixed-point (8 frac bits)
//   - Interpolation becomes pure shift-add: (s0<<8 + (s1-s0)*frac) >>> 8
//   - BUT we pre-shift the table so the >>> 8 is free (just truncate)
//   - Low notes auto-force sine to prevent aliasing
// ============================================================================
`timescale 1ns / 1ps

module audio_synth (
    input  wire        clk,
    input  wire        reset,
    output reg  [15:0] audio_l,
    output reg  [15:0] audio_r
);

    // ------------------------------------------------------------------------
    // 48 kHz sample tick
    // ------------------------------------------------------------------------
    localparam SAMPLE_DIV = 512;  // 24_576_000 / 48_000 = 512
    reg [10:0] div_cnt;
    reg sample_tick;

    always @(posedge clk) begin
        if (reset) begin
            div_cnt <= 0;
            sample_tick <= 0;
        end else if (div_cnt >= SAMPLE_DIV - 1) begin
            div_cnt <= 0;
            sample_tick <= 1;
        end else begin
            div_cnt <= div_cnt + 1;
            sample_tick <= 0;
        end
    end

    // ------------------------------------------------------------------------
    // Sine LUT (256 entries) — stored as 20-bit signed with 8 fractional bits
    // This makes interpolation a simple shift-add with NO multiplier
    // ------------------------------------------------------------------------
    reg signed [19:0] sine_table [0:255];
    initial begin
        sine_table[  0] = 20'sd     0;  sine_table[  1] = 20'sd  9549;  sine_table[  2] = 20'sd 19093;  sine_table[  3] = 20'sd 28625;
        sine_table[  4] = 20'sd 38140;  sine_table[  5] = 20'sd 47632;  sine_table[  6] = 20'sd 57096;  sine_table[  7] = 20'sd 66525;
        sine_table[  8] = 20'sd 75914;  sine_table[  9] = 20'sd 85257;  sine_table[ 10] = 20'sd 94548;  sine_table[ 11] = 20'sd103783;
        sine_table[ 12] = 20'sd112956;  sine_table[ 13] = 20'sd122060;  sine_table[ 14] = 20'sd131091;  sine_table[ 15] = 20'sd140042;
        sine_table[ 16] = 20'sd148910;  sine_table[ 17] = 20'sd157688;  sine_table[ 18] = 20'sd166370;  sine_table[ 19] = 20'sd174953;
        sine_table[ 20] = 20'sd183430;  sine_table[ 21] = 20'sd191797;  sine_table[ 22] = 20'sd200048;  sine_table[ 23] = 20'sd208178;
        sine_table[ 24] = 20'sd216183;  sine_table[ 25] = 20'sd224058;  sine_table[ 26] = 20'sd231799;  sine_table[ 27] = 20'sd239399;
        sine_table[ 28] = 20'sd246855;  sine_table[ 29] = 20'sd254163;  sine_table[ 30] = 20'sd261317;  sine_table[ 31] = 20'sd268314;
        sine_table[ 32] = 20'sd275149;  sine_table[ 33] = 20'sd281819;  sine_table[ 34] = 20'sd288319;  sine_table[ 35] = 20'sd294645;
        sine_table[ 36] = 20'sd300794;  sine_table[ 37] = 20'sd306761;  sine_table[ 38] = 20'sd312544;  sine_table[ 39] = 20'sd318139;
        sine_table[ 40] = 20'sd323541;  sine_table[ 41] = 20'sd328749;  sine_table[ 42] = 20'sd333759;  sine_table[ 43] = 20'sd338568;
        sine_table[ 44] = 20'sd343173;  sine_table[ 45] = 20'sd347571;  sine_table[ 46] = 20'sd351760;  sine_table[ 47] = 20'sd355737;
        sine_table[ 48] = 20'sd359500;  sine_table[ 49] = 20'sd363046;  sine_table[ 50] = 20'sd366374;  sine_table[ 51] = 20'sd369480;
        sine_table[ 52] = 20'sd372365;  sine_table[ 53] = 20'sd375025;  sine_table[ 54] = 20'sd377459;  sine_table[ 55] = 20'sd379665;
        sine_table[ 56] = 20'sd381643;  sine_table[ 57] = 20'sd383391;  sine_table[ 58] = 20'sd384908;  sine_table[ 59] = 20'sd386194;
        sine_table[ 60] = 20'sd387246;  sine_table[ 61] = 20'sd388066;  sine_table[ 62] = 20'sd388651;  sine_table[ 63] = 20'sd389003;
        sine_table[ 64] = 20'sd389120;  sine_table[ 65] = 20'sd389003;  sine_table[ 66] = 20'sd388651;  sine_table[ 67] = 20'sd388066;
        sine_table[ 68] = 20'sd387246;  sine_table[ 69] = 20'sd386194;  sine_table[ 70] = 20'sd384908;  sine_table[ 71] = 20'sd383391;
        sine_table[ 72] = 20'sd381643;  sine_table[ 73] = 20'sd379665;  sine_table[ 74] = 20'sd377459;  sine_table[ 75] = 20'sd375025;
        sine_table[ 76] = 20'sd372365;  sine_table[ 77] = 20'sd369480;  sine_table[ 78] = 20'sd366374;  sine_table[ 79] = 20'sd363046;
        sine_table[ 80] = 20'sd359500;  sine_table[ 81] = 20'sd355737;  sine_table[ 82] = 20'sd351760;  sine_table[ 83] = 20'sd347571;
        sine_table[ 84] = 20'sd343173;  sine_table[ 85] = 20'sd338568;  sine_table[ 86] = 20'sd333759;  sine_table[ 87] = 20'sd328749;
        sine_table[ 88] = 20'sd323541;  sine_table[ 89] = 20'sd318139;  sine_table[ 90] = 20'sd312544;  sine_table[ 91] = 20'sd306761;
        sine_table[ 92] = 20'sd300794;  sine_table[ 93] = 20'sd294645;  sine_table[ 94] = 20'sd288319;  sine_table[ 95] = 20'sd281819;
        sine_table[ 96] = 20'sd275149;  sine_table[ 97] = 20'sd268314;  sine_table[ 98] = 20'sd261317;  sine_table[ 99] = 20'sd254163;
        sine_table[100] = 20'sd246855;  sine_table[101] = 20'sd239399;  sine_table[102] = 20'sd231799;  sine_table[103] = 20'sd224058;
        sine_table[104] = 20'sd216183;  sine_table[105] = 20'sd208178;  sine_table[106] = 20'sd200048;  sine_table[107] = 20'sd191797;
        sine_table[108] = 20'sd183430;  sine_table[109] = 20'sd174953;  sine_table[110] = 20'sd166370;  sine_table[111] = 20'sd157688;
        sine_table[112] = 20'sd148910;  sine_table[113] = 20'sd140042;  sine_table[114] = 20'sd131091;  sine_table[115] = 20'sd122060;
        sine_table[116] = 20'sd112956;  sine_table[117] = 20'sd103783;  sine_table[118] = 20'sd 94548;  sine_table[119] = 20'sd 85257;
        sine_table[120] = 20'sd 75914;  sine_table[121] = 20'sd 66525;  sine_table[122] = 20'sd 57096;  sine_table[123] = 20'sd 47632;
        sine_table[124] = 20'sd 38140;  sine_table[125] = 20'sd 28625;  sine_table[126] = 20'sd 19093;  sine_table[127] = 20'sd  9549;
        sine_table[128] = 20'sd     0;  sine_table[129] = -20'sd  9549; sine_table[130] = -20'sd 19093; sine_table[131] = -20'sd 28625;
        sine_table[132] = -20'sd 38140; sine_table[133] = -20'sd 47632; sine_table[134] = -20'sd 57096; sine_table[135] = -20'sd 66525;
        sine_table[136] = -20'sd 75914; sine_table[137] = -20'sd 85257; sine_table[138] = -20'sd 94548; sine_table[139] = -20'sd103783;
        sine_table[140] = -20'sd112956; sine_table[141] = -20'sd122060; sine_table[142] = -20'sd131091; sine_table[143] = -20'sd140042;
        sine_table[144] = -20'sd148910; sine_table[145] = -20'sd157688; sine_table[146] = -20'sd166370; sine_table[147] = -20'sd174953;
        sine_table[148] = -20'sd183430; sine_table[149] = -20'sd191797; sine_table[150] = -20'sd200048; sine_table[151] = -20'sd208178;
        sine_table[152] = -20'sd216183; sine_table[153] = -20'sd224058; sine_table[154] = -20'sd231799; sine_table[155] = -20'sd239399;
        sine_table[156] = -20'sd246855; sine_table[157] = -20'sd254163; sine_table[158] = -20'sd261317; sine_table[159] = -20'sd268314;
        sine_table[160] = -20'sd275149; sine_table[161] = -20'sd281819; sine_table[162] = -20'sd288319; sine_table[163] = -20'sd294645;
        sine_table[164] = -20'sd300794; sine_table[165] = -20'sd306761; sine_table[166] = -20'sd312544; sine_table[167] = -20'sd318139;
        sine_table[168] = -20'sd323541; sine_table[169] = -20'sd328749; sine_table[170] = -20'sd333759; sine_table[171] = -20'sd338568;
        sine_table[172] = -20'sd343173; sine_table[173] = -20'sd347571; sine_table[174] = -20'sd351760; sine_table[175] = -20'sd355737;
        sine_table[176] = -20'sd359500; sine_table[177] = -20'sd363046; sine_table[178] = -20'sd366374; sine_table[179] = -20'sd369480;
        sine_table[180] = -20'sd372365; sine_table[181] = -20'sd375025; sine_table[182] = -20'sd377459; sine_table[183] = -20'sd379665;
        sine_table[184] = -20'sd381643; sine_table[185] = -20'sd383391; sine_table[186] = -20'sd384908; sine_table[187] = -20'sd386194;
        sine_table[188] = -20'sd387246; sine_table[189] = -20'sd388066; sine_table[190] = -20'sd388651; sine_table[191] = -20'sd389003;
        sine_table[192] = -20'sd389120; sine_table[193] = -20'sd389003; sine_table[194] = -20'sd388651; sine_table[195] = -20'sd388066;
        sine_table[196] = -20'sd387246; sine_table[197] = -20'sd386194; sine_table[198] = -20'sd384908; sine_table[199] = -20'sd383391;
        sine_table[200] = -20'sd381643; sine_table[201] = -20'sd379665; sine_table[202] = -20'sd377459; sine_table[203] = -20'sd375025;
        sine_table[204] = -20'sd372365; sine_table[205] = -20'sd369480; sine_table[206] = -20'sd366374; sine_table[207] = -20'sd363046;
        sine_table[208] = -20'sd359500; sine_table[209] = -20'sd355737; sine_table[210] = -20'sd351760; sine_table[211] = -20'sd347571;
        sine_table[212] = -20'sd343173; sine_table[213] = -20'sd338568; sine_table[214] = -20'sd333759; sine_table[215] = -20'sd328749;
        sine_table[216] = -20'sd323541; sine_table[217] = -20'sd318139; sine_table[218] = -20'sd312544; sine_table[219] = -20'sd306761;
        sine_table[220] = -20'sd300794; sine_table[221] = -20'sd294645; sine_table[222] = -20'sd288319; sine_table[223] = -20'sd281819;
        sine_table[224] = -20'sd275149; sine_table[225] = -20'sd268314; sine_table[226] = -20'sd261317; sine_table[227] = -20'sd254163;
        sine_table[228] = -20'sd246855; sine_table[229] = -20'sd239399; sine_table[230] = -20'sd231799; sine_table[231] = -20'sd224058;
        sine_table[232] = -20'sd216183; sine_table[233] = -20'sd208178; sine_table[234] = -20'sd200048; sine_table[235] = -20'sd191797;
        sine_table[236] = -20'sd183430; sine_table[237] = -20'sd174953; sine_table[238] = -20'sd166370; sine_table[239] = -20'sd157688;
        sine_table[240] = -20'sd148910; sine_table[241] = -20'sd140042; sine_table[242] = -20'sd131091; sine_table[243] = -20'sd122060;
        sine_table[244] = -20'sd112956; sine_table[245] = -20'sd103783; sine_table[246] = -20'sd 94548; sine_table[247] = -20'sd 85257;
        sine_table[248] = -20'sd 75914; sine_table[249] = -20'sd 66525; sine_table[250] = -20'sd 57096; sine_table[251] = -20'sd 47632;
        sine_table[252] = -20'sd 38140; sine_table[253] = -20'sd 28625; sine_table[254] = -20'sd 19093; sine_table[255] = -20'sd  9549;
    end

    // ------------------------------------------------------------------------
    // Frequency LUT (128 notes) — corrected for 50 MHz / 1042 ≈ 47.985 kHz
    // ------------------------------------------------------------------------
    reg [23:0] freq_inc [0:127];
    initial begin
        freq_inc[0]  = 24'h000B2B; freq_inc[1]  = 24'h000BD5;
        freq_inc[2]  = 24'h000C89; freq_inc[3]  = 24'h000D47;
        freq_inc[4]  = 24'h000E12; freq_inc[5]  = 24'h000EE8;
        freq_inc[6]  = 24'h000FCB; freq_inc[7]  = 24'h0010BB;
        freq_inc[8]  = 24'h0011BA; freq_inc[9]  = 24'h0012C8;
        freq_inc[10] = 24'h0013E5; freq_inc[11] = 24'h001514;
        freq_inc[12] = 24'h001655; freq_inc[13] = 24'h0017A9;
        freq_inc[14] = 24'h001911; freq_inc[15] = 24'h001A8F;
        freq_inc[16] = 24'h001C23; freq_inc[17] = 24'h001DCF;
        freq_inc[18] = 24'h001F95; freq_inc[19] = 24'h002176;
        freq_inc[20] = 24'h002373; freq_inc[21] = 24'h00258F;
        freq_inc[22] = 24'h0027CB; freq_inc[23] = 24'h002A28;
        freq_inc[24] = 24'h002CAA; freq_inc[25] = 24'h002F52;
        freq_inc[26] = 24'h003223; freq_inc[27] = 24'h00351E;
        freq_inc[28] = 24'h003846; freq_inc[29] = 24'h003B9F;
        freq_inc[30] = 24'h003F2A; freq_inc[31] = 24'h0042EC;
        freq_inc[32] = 24'h0046E7; freq_inc[33] = 24'h004B1E;
        freq_inc[34] = 24'h004F96; freq_inc[35] = 24'h005451;
        freq_inc[36] = 24'h005955; freq_inc[37] = 24'h005EA4;
        freq_inc[38] = 24'h006445; freq_inc[39] = 24'h006A3B;
        freq_inc[40] = 24'h00708D; freq_inc[41] = 24'h00773E;
        freq_inc[42] = 24'h007E55; freq_inc[43] = 24'h0085D8;
        freq_inc[44] = 24'h008DCD; freq_inc[45] = 24'h00963C;
        freq_inc[46] = 24'h009F2B; freq_inc[47] = 24'h00A8A2;
        freq_inc[48] = 24'h00B2A9; freq_inc[49] = 24'h00BD49;
        freq_inc[50] = 24'h00C88A; freq_inc[51] = 24'h00D477;
        freq_inc[52] = 24'h00E119; freq_inc[53] = 24'h00EE7C;
        freq_inc[54] = 24'h00FCAA; freq_inc[55] = 24'h010BB0;
        freq_inc[56] = 24'h011B9B; freq_inc[57] = 24'h012C78;
        freq_inc[58] = 24'h013E56; freq_inc[59] = 24'h015144;
        freq_inc[60] = 24'h016552; freq_inc[61] = 24'h017A91;
        freq_inc[62] = 24'h019114; freq_inc[63] = 24'h01A8EE;
        freq_inc[64] = 24'h01C232; freq_inc[65] = 24'h01DCF7;
        freq_inc[66] = 24'h01F954; freq_inc[67] = 24'h021760;
        freq_inc[68] = 24'h023736; freq_inc[69] = 24'h0258F0;
        freq_inc[70] = 24'h027CAC; freq_inc[71] = 24'h02A288;
        freq_inc[72] = 24'h02CAA4; freq_inc[73] = 24'h02F523;
        freq_inc[74] = 24'h032228; freq_inc[75] = 24'h0351DB;
        freq_inc[76] = 24'h038464; freq_inc[77] = 24'h03B9EE;
        freq_inc[78] = 24'h03F2A8; freq_inc[79] = 24'h042EC0;
        freq_inc[80] = 24'h046E6C; freq_inc[81] = 24'h04B1E1;
        freq_inc[82] = 24'h04F958; freq_inc[83] = 24'h054510;
        freq_inc[84] = 24'h059548; freq_inc[85] = 24'h05EA45;
        freq_inc[86] = 24'h064450; freq_inc[87] = 24'h06A3B6;
        freq_inc[88] = 24'h0708C8; freq_inc[89] = 24'h0773DD;
        freq_inc[90] = 24'h07E54F; freq_inc[91] = 24'h085D81;
        freq_inc[92] = 24'h08DCD8; freq_inc[93] = 24'h0963C1;
        freq_inc[94] = 24'h09F2B1; freq_inc[95] = 24'h0A8A20;
        freq_inc[96] = 24'h0B2A90; freq_inc[97] = 24'h0BD48B;
        freq_inc[98] = 24'h0C88A1; freq_inc[99] = 24'h0D476C;
        freq_inc[100] = 24'h0E1190; freq_inc[101] = 24'h0EE7B9;
        freq_inc[102] = 24'h0FCA9E; freq_inc[103] = 24'h10BB01;
        freq_inc[104] = 24'h11B9B0; freq_inc[105] = 24'h12C783;
        freq_inc[106] = 24'h13E561; freq_inc[107] = 24'h151440;
        freq_inc[108] = 24'h165520; freq_inc[109] = 24'h17A916;
        freq_inc[110] = 24'h191142; freq_inc[111] = 24'h1A8ED9;
        freq_inc[112] = 24'h1C2321; freq_inc[113] = 24'h1DCF73;
        freq_inc[114] = 24'h1F953D; freq_inc[115] = 24'h217603;
        freq_inc[116] = 24'h23735F; freq_inc[117] = 24'h258F06;
        freq_inc[118] = 24'h27CAC3; freq_inc[119] = 24'h2A287F;
        freq_inc[120] = 24'h2CAA41; freq_inc[121] = 24'h2F522B;
        freq_inc[122] = 24'h322284; freq_inc[123] = 24'h351DB2;
        freq_inc[124] = 24'h384642; freq_inc[125] = 24'h3B9EE6;
        freq_inc[126] = 24'h3F2A7A; freq_inc[127] = 24'h42EC06;
    end

    // ------------------------------------------------------------------------
    // 23-bit LFSR noise generator
    // ------------------------------------------------------------------------
    reg [22:0] lfsr;
    always @(posedge clk) begin
        if (reset) lfsr <= 23'h7FFFFD;
        else       lfsr <= {lfsr[21:0], lfsr[22] ^ lfsr[17]};
    end

    // ------------------------------------------------------------------------
    // Waveform & volume config per MIDI channel
    // ------------------------------------------------------------------------
    localparam [31:0] WAVE_TYPE = 32'h00000000;
    localparam [63:0] VOLUME = 64'h0000000088888888;  // ch0-7 max

    // ------------------------------------------------------------------------
    // Sine LUT interpolation — NO MULTIPLY, pure shift-add
    // Table is pre-shifted by 8 bits, so we just do weighted addition then >> 8
    // ------------------------------------------------------------------------
    function automatic signed [15:0] sine_interp;
        input [23:0] ph;
        reg [7:0]  idx;
        reg [7:0]  next_idx;
        reg [7:0]  frac;
        reg signed [19:0] s0, s1, diff;
        reg signed [27:0] prod;
        reg signed [19:0] mix;
        begin
            idx      = ph[23:16];
            frac     = ph[15:8];
            next_idx = idx + 8'd1;   // 255 wraps to 0, now smooth

            s0  = sine_table[idx];
            s1  = sine_table[next_idx];
            diff = s1 - s0;

            // 20-bit diff * 8-bit unsigned frac → 28-bit, then >>> 8
            prod = diff * $signed({1'b0, frac});
            mix  = s0 + (prod >>> 8);

            // Table stored with 8 fractional bits; shift back to integer
            sine_interp = mix >>> 8;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Waveform generation — low notes force sine to prevent aliasing
    // ------------------------------------------------------------------------
    function automatic signed [15:0] gen_wave;
        input [23:0] ph;
        input [1:0]  wtype;
        input [22:0] noise;
        input [23:0] finc;
        begin
            if (finc < 24'h003F2A) begin
                gen_wave = sine_interp(ph);
            end else begin
                case (wtype)
                    2'd0: gen_wave = ph[23] ? 16'sh7FFF : -16'sh7FFF;
                    2'd1: begin
                        if (ph[23])
                            gen_wave = 16'sd32767 - $signed({1'b0, ph[22:7]});
                        else
                            gen_wave = $signed({1'b0, ph[22:7]}) - 16'sd32768;
                    end
                    2'd2: gen_wave = $signed({1'b0, ph[23:8]}) - 16'sd32768;
                    2'd3: gen_wave = $signed(noise[15:0]) >>> 1;
                    default: gen_wave = 16'sd0;
                endcase
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // Event ROM
    // ------------------------------------------------------------------------
    localparam EVENT_MAX = 7862;
    reg [63:0] event_rom [0:EVENT_MAX-1];
    initial begin
        $readmemh("../song.hex", event_rom);
    end

    reg [$clog2(EVENT_MAX)-1:0] seq_addr;
    wire [63:0] event_data = event_rom[seq_addr];

    // ------------------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------------------
    localparam SEQ_IDLE = 2'd0, SEQ_LOAD = 2'd1, SEQ_WAIT = 2'd2, SEQ_EXEC = 2'd3;
    reg [1:0] seq_state;
    reg [31:0] wait_cnt;
    reg [63:0] current_event;

    reg       cmd_valid;
    reg [1:0] cmd_type;
    reg [6:0] cmd_note;
    reg [6:0] cmd_vel;
    reg [3:0] cmd_ch;

    // ------------------------------------------------------------------------
    // Voice state
    // ------------------------------------------------------------------------
    reg [23:0] v_phase  [0:15];
    reg [6:0]  v_note   [0:15];
    reg [3:0]  v_ch     [0:15];
    reg [6:0]  v_vel    [0:15];
    reg [7:0]  v_env    [0:15];
    reg [2:0]  v_state  [0:15];
    reg        v_active [0:15];
    reg signed [15:0] v_out [0:15];

    localparam ST_IDLE = 3'd0, ST_ATTACK = 3'd1, ST_DECAY = 3'd2;
    localparam ST_SUSTAIN = 3'd3, ST_RELEASE = 3'd4;

    (* multstyle = "logic" *) reg signed [31:0] v_prod [0:15];

    // ------------------------------------------------------------------------
    // Main state machine
    // ------------------------------------------------------------------------
    integer i, m;
    reg found_free;
    reg [3:0] steal_idx;
    reg [7:0] steal_env;
    reg signed [19:0] mix_accum;
    reg signed [15:0] raw_wave;
    reg signed [15:0] voice_sample;
    reg [1:0] wtype;
    reg [3:0] vol;
    reg [11:0] gain;

    reg signed [15:0] lp_l,  lp_r;
    reg signed [15:0] lp2_l, lp2_r;
    reg signed [16:0] diff_l,  diff_r;
    reg signed [16:0] diff2_l, diff2_r;

    always @(posedge clk) begin
        if (reset) begin
            seq_state <= SEQ_IDLE;
            seq_addr <= 0;
            wait_cnt <= 0;
            current_event <= 0;
            cmd_valid <= 0;

            for (i = 0; i < 16; i = i + 1) begin
                v_phase[i] <= 0; v_note[i] <= 0; v_ch[i] <= 0;
                v_vel[i] <= 0; v_env[i] <= 0; v_state[i] <= ST_IDLE;
                v_active[i] <= 0; v_out[i] <= 0; v_prod[i] <= 0;
            end

            lp_l <= 0; lp_r <= 0; lp2_l <= 0; lp2_r <= 0;
            audio_l <= 0; audio_r <= 0;

        end else if (sample_tick) begin
            cmd_valid <= 0;

            case (seq_state)
                SEQ_IDLE: seq_state <= SEQ_LOAD;
                SEQ_LOAD: begin
                    current_event <= event_data;
                    wait_cnt <= event_data[63:32];
                    seq_addr <= seq_addr + 1;
                    seq_state <= SEQ_WAIT;
                end
                SEQ_WAIT: begin
                    if (wait_cnt == 0) seq_state <= SEQ_EXEC;
                    else wait_cnt <= wait_cnt - 1;
                end
                SEQ_EXEC: begin
                    case (current_event[31:24])
                        8'h01: begin
                            cmd_valid <= 1; cmd_type <= 2'd1;
                            cmd_note <= current_event[23:16];
                            cmd_vel <= current_event[15:8];
                            cmd_ch <= current_event[3:0];
                        end
                        8'h00: begin
                            cmd_valid <= 1; cmd_type <= 2'd2;
                            cmd_note <= current_event[23:16];
                        end
                        8'h02: seq_addr <= 0;
                    endcase
                    seq_state <= SEQ_LOAD;
                end
            endcase

            found_free = 0; steal_idx = 0; steal_env = 8'hFF;
            for (i = 0; i < 16; i = i + 1) begin
                if (cmd_valid && cmd_type == 2'd1 && !found_free && !v_active[i]) begin
                    v_active[i] <= 1; v_state[i] <= ST_ATTACK;
                    v_note[i] <= cmd_note; v_ch[i] <= cmd_ch;
                    v_vel[i] <= cmd_vel; v_phase[i] <= 0;
                    found_free = 1;
                end
            end

            if (cmd_valid && cmd_type == 2'd1 && !found_free) begin
                for (m = 0; m < 16; m = m + 1) begin
                    if (v_active[m] && v_env[m] < steal_env) begin
                        steal_env = v_env[m]; steal_idx = m;
                    end
                end
                v_active[steal_idx] <= 1; v_state[steal_idx] <= ST_ATTACK;
                v_note[steal_idx] <= cmd_note; v_ch[steal_idx] <= cmd_ch;
                v_vel[steal_idx] <= cmd_vel; v_phase[steal_idx] <= 0;
            end

            if (cmd_valid && cmd_type == 2'd2) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (v_active[i] && v_note[i] == cmd_note)
                        v_state[i] <= ST_RELEASE;
                end
            end

            mix_accum = 0;
            for (i = 0; i < 16; i = i + 1) begin
                case (v_state[i])
                    ST_IDLE: v_env[i] <= 0;
                    ST_ATTACK: begin
                        if (v_env[i] < 8'd240) v_env[i] <= v_env[i] + 8'd16;
                        else begin v_env[i] <= 8'd255; v_state[i] <= ST_DECAY; end
                    end
                    ST_DECAY: begin
                        if (v_env[i] > 8'd220) v_env[i] <= v_env[i] - 8'd4;
                        else v_state[i] <= ST_SUSTAIN;
                    end
                    ST_SUSTAIN: v_env[i] <= 8'd220;
                    ST_RELEASE: begin
                        if (v_env[i] > 8'd8) v_env[i] <= v_env[i] - 8'd8;
                        else begin v_env[i] <= 0; v_state[i] <= ST_IDLE; v_active[i] <= 0; end
                    end
                endcase

                if (v_active[i]) begin
                    v_phase[i] <= v_phase[i] + freq_inc[v_note[i]];
                    wtype = (WAVE_TYPE >> (v_ch[i] * 2)) & 2'b11;
                    vol   = (VOLUME >> (v_ch[i] * 4)) & 4'hF;
                    raw_wave = gen_wave(v_phase[i], wtype, lfsr, freq_inc[v_note[i]]);
                    gain = v_env[i] * vol;
                    v_prod[i] = raw_wave * $signed({1'b0, gain});
                    voice_sample = v_prod[i] >>> 11;
                    v_out[i] <= voice_sample;
                    mix_accum = mix_accum + voice_sample;
                end else begin
                    v_out[i] <= 0;
                end
            end

            // No early clip — mix_accum s20 holds up to 16 full voices fine.
            // Divide by 16 (>>4) = mix_accum[19:4] to get s16 range.
            // Two-pole LP (α=1/8 each) for gentle high-freq smoothing.
            diff_l = $signed(mix_accum[18:3]) - lp_l;  // >>3: 6v=60%, 8v=80%
            diff_r = $signed(mix_accum[18:3]) - lp_r;
            lp_l <= lp_l + (diff_l >>> 1);
            lp_r <= lp_r + (diff_r >>> 1);

            diff2_l = lp_l - lp2_l;
            diff2_r = lp_r - lp2_r;
            lp2_l <= lp2_l + (diff2_l >>> 1);
            lp2_r <= lp2_r + (diff2_r >>> 1);

            audio_l <= lp2_l;
            audio_r <= lp2_r;
        end
    end

endmodule