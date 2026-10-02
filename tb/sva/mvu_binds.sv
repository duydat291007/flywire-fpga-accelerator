// mvu_binds.sv - attach the MVU assertion modules. Compile this file (and
// mvu_sva.sv) only in assertion-capable simulators (Verilator, XSim).
`timescale 1ns/1ps

module mvu_binds;
    bind mvu_serial mvu_if_sva #(.N_MAX(N_MAX)) u_if_sva (
        .clk, .rst, .busy, .done, .err_dim, .cmd_valid, .cmd_ready, .cmd_dim,
        .w_ready, .x_ready, .xb_ready, .res_valid, .res_ready, .res_data, .res_idx, .res_last);

    bind mvu_systolic mvu_if_sva #(.N_MAX(N_MAX)) u_if_sva (
        .clk, .rst, .busy, .done, .err_dim, .cmd_valid, .cmd_ready, .cmd_dim,
        .w_ready, .x_ready, .xb_ready, .res_valid, .res_ready, .res_data, .res_idx, .res_last);

    bind mvu_systolic mvu_systolic_sva #(
        .N_MAX(N_MAX), .WBUF(WBUF), .TW(TW), .SEL_W(SEL_W), .AW(AW)) u_sys_sva (
        .clk, .rst, .state(state), .ld_issue, .ld_active, .ld_src, .ld_dst0, .wl_v, .wl_sel, .buf_busy,
        .ld_started, .ld_done, .lc_count, .fin_count, .fin_buf, .total_q, .res_valid);

    bind systolic_array systolic_array_sva #(.ROWS(ROWS), .COLS(COLS)) u_arr_sva (
        .clk, .rst, .xv_in_flat(dbg_xv_in), .pv_in_flat(dbg_pv_in));
endmodule
