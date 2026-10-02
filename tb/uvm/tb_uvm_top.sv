// tb_uvm_top.sv - UVM top for the matrix-vector units.
// Select the DUT with parameters (xelab -generic_top "USE_SERIAL=1", etc.)
// and the test with +UVM_TESTNAME=mvu_random_test (+NOPS=n, +ntb_random_seed / -sv_seed).
`timescale 1ns/1ps

module tb_uvm_top #(
    parameter int USE_SERIAL = 0,
    parameter int ROWS = 4, parameter int COLS = 4,
    parameter int BANKED = 1, parameter int WBUF = 2
);
    import uvm_pkg::*;
    import mvu_uvm_pkg::*;

    logic clk = 0;
    always #5 clk = ~clk;

    mvu_if #(.N_MAX(64)) vif (clk);

    generate
        if (USE_SERIAL != 0) begin : g_dut
            mvu_serial #(.N_MAX(64)) dut (
                .clk, .rst(vif.rst),
                .w_valid(vif.w_valid), .w_ready(vif.w_ready), .w_dst(vif.w_dst), .w_src(vif.w_src),
                .w_data(vif.w_data), .x_valid(vif.x_valid), .x_ready(vif.x_ready), .x_idx(vif.x_idx),
                .x_data(vif.x_data), .xb_valid(vif.xb_valid), .xb_ready(vif.xb_ready),
                .xb_bits(vif.xb_bits), .cmd_valid(vif.cmd_valid), .cmd_ready(vif.cmd_ready),
                .cmd_dim(vif.cmd_dim), .res_valid(vif.res_valid), .res_ready(vif.res_ready),
                .res_data(vif.res_data), .res_idx(vif.res_idx), .res_last(vif.res_last),
                .busy(vif.busy), .done(vif.done), .err_dim(vif.err_dim));
        end else begin : g_dut
            mvu_systolic #(.N_MAX(64), .ROWS(ROWS), .COLS(COLS), .BANKED(BANKED), .WBUF(WBUF)) dut (
                .clk, .rst(vif.rst),
                .w_valid(vif.w_valid), .w_ready(vif.w_ready), .w_dst(vif.w_dst), .w_src(vif.w_src),
                .w_data(vif.w_data), .x_valid(vif.x_valid), .x_ready(vif.x_ready), .x_idx(vif.x_idx),
                .x_data(vif.x_data), .xb_valid(vif.xb_valid), .xb_ready(vif.xb_ready),
                .xb_bits(vif.xb_bits), .cmd_valid(vif.cmd_valid), .cmd_ready(vif.cmd_ready),
                .cmd_dim(vif.cmd_dim), .res_valid(vif.res_valid), .res_ready(vif.res_ready),
                .res_data(vif.res_data), .res_idx(vif.res_idx), .res_last(vif.res_last),
                .busy(vif.busy), .done(vif.done), .err_dim(vif.err_dim));
        end
    endgenerate

    initial begin
        uvm_config_db #(virtual mvu_if)::set(null, "uvm_test_top.*", "vif", vif);
        run_test("mvu_random_test");
    end

    initial begin
        #2_000_000_000;     // 2 s simulated: hard stop if anything hangs
        $fatal(1, "TIMEOUT");
    end
endmodule
