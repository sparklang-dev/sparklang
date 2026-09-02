// classify_score.v — HDL tier-3 for parallel label scoring
//
// Models hardware-parallel classification: N label score lanes
// compare against a confidence threshold in one clock.
// Synthesizable style (no vendor IP). FPGA build is optional /
// out-of-band — this is NOT a taped-out chip.
//
// Spark software classify may eventually offload here; today the
// asm VM does dry-run classify in software.

`timescale 1ns / 1ps

module classify_score #(
    parameter integer N_LABELS = 4,
    parameter integer SCORE_W  = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         valid_i,
    input  wire [N_LABELS*SCORE_W-1:0]  scores_i,
    input  wire [SCORE_W-1:0]           min_conf_i,
    output reg                          valid_o,
    output reg  [$clog2(N_LABELS)-1:0]  label_o,
    output reg  [SCORE_W-1:0]           best_o,
    output reg                          pass_o
);
    integer i;
    reg [SCORE_W-1:0] s;
    reg [SCORE_W-1:0] best;
    reg [$clog2(N_LABELS)-1:0] best_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_o  <= 1'b0;
            label_o  <= {($clog2(N_LABELS)){1'b0}};
            best_o   <= {SCORE_W{1'b0}};
            pass_o   <= 1'b0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                best = {SCORE_W{1'b0}};
                best_idx = {($clog2(N_LABELS)){1'b0}};
                for (i = 0; i < N_LABELS; i = i + 1) begin
                    s = scores_i[i*SCORE_W +: SCORE_W];
                    if (s > best) begin
                        best = s;
                        best_idx = i[$clog2(N_LABELS)-1:0];
                    end
                end
                label_o <= best_idx;
                best_o  <= best;
                pass_o  <= (best >= min_conf_i);
            end
        end
    end
endmodule
