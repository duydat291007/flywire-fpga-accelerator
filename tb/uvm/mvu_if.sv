// mvu_if.sv - pin-level interface for the matrix-vector unit (UVM testbench).
`timescale 1ns/1ps

interface mvu_if #(parameter int N_MAX = 64) (input logic clk);
    localparam int AW = $clog2(N_MAX);

    logic             rst;
    logic             w_valid, w_ready;
    logic [AW-1:0]    w_dst, w_src;
    logic [7:0]       w_data;
    logic             x_valid, x_ready;
    logic [AW-1:0]    x_idx;
    logic [7:0]       x_data;
    logic             xb_valid, xb_ready;
    logic [N_MAX-1:0] xb_bits;
    logic             cmd_valid, cmd_ready;
    logic [AW:0]      cmd_dim;
    logic             res_valid, res_ready, res_last;
    logic [31:0]      res_data;
    logic [AW-1:0]    res_idx;
    logic             busy, done, err_dim;

    // Driver view: drive after the edge, sample at the edge
    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output rst, w_valid, w_dst, w_src, w_data, x_valid, x_idx, x_data, xb_valid, xb_bits,
               cmd_valid, cmd_dim, res_ready;
        input  w_ready, x_ready, xb_ready, cmd_ready, res_valid, res_data, res_idx, res_last,
               busy, done, err_dim;
    endclocking

    // Monitor view: everything is an input
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst, w_valid, w_ready, w_dst, w_src, w_data, x_valid, x_ready, x_idx, x_data,
              xb_valid, xb_ready, xb_bits, cmd_valid, cmd_ready, cmd_dim, res_valid, res_ready,
              res_data, res_idx, res_last, busy, done, err_dim;
    endclocking
endinterface
