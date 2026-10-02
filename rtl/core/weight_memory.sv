// weight_memory.sv
// On-chip storage for W[dst][src], N_MAX x N_MAX signed 8-bit.
//
// NB = 1 : one memory, word address dst*N_MAX + src, one read per cycle.
// NB > 1 : NB banks, bank = dst % NB, local address = (dst / NB)*N_MAX + src.
//          One read per bank per cycle, so NB consecutive destinations
//          for the same source are read together.
//
// Reads are synchronous (1-cycle latency) and writes are synchronous, so each
// bank maps to block RAM or distributed RAM. There is no reset on the storage.

`timescale 1ns/1ps

module weight_memory #(
    parameter int N_MAX = 64,
    parameter int NB    = 4,
    parameter int AW    = $clog2(N_MAX),
    parameter int NBW   = (NB <= 1) ? 1 : $clog2(NB),
    parameter int LAW   = $clog2(N_MAX * N_MAX / NB)
) (
    input  logic                  clk,

    input  logic                  wr_en,
    input  logic [AW-1:0]         wr_dst,
    input  logic [AW-1:0]         wr_src,
    input  logic [7:0]            wr_data,

    input  logic [NB-1:0][LAW-1:0] rd_addr,     // per-bank local address
    output logic [NB-1:0][7:0]     rd_data      // valid one cycle after rd_addr
);

    // local address of a (dst, src) pair inside its bank
    logic [LAW-1:0] wr_laddr;
    logic [NBW-1:0] wr_bank;

    generate
        if (NB == 1) begin : g_one
            assign wr_bank  = '0;
            assign wr_laddr = {wr_dst, wr_src};
        end else begin : g_many
            assign wr_bank  = wr_dst[NBW-1:0];
            assign wr_laddr = {wr_dst[AW-1:NBW], wr_src};
        end
    endgenerate

    genvar b;
    generate
        for (b = 0; b < NB; b++) begin : g_bank
            logic [7:0] mem [N_MAX * N_MAX / NB];
            always_ff @(posedge clk) begin
                if (wr_en && (wr_bank == NBW'(b)))
                    mem[wr_laddr] <= wr_data;
                rd_data[b] <= mem[rd_addr[b]];
            end
        end
    endgenerate

endmodule
