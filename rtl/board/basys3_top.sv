// basys3_top.sv
// Board top level for the Digilent Basys 3 (XC7A35T-1CPG236C, 100 MHz).
// Port names match Digilent's Basys-3-Master.xdc.
//
//   btnC  reset                          sw[0]   run (1) / pause (0)
//   btnU  single step when paused        sw[1]   food present
//   btnL  place food ahead of the fly    sw[2]   threat present
//   btnR  place threat beside the fly    sw[3]   slow mode (10 steps/s instead of 100)
//                                        sw[9:5] potential-probe group (8 neurons each)
//   RsTx  telemetry, FPGA -> laptop (USB-UART bridge), 115200 8N1
//
//   led[0]  toggles every timestep       led[4]  snapshot dropped (blink)
//   led[1]  running                      led[5]  weights loaded (booted)
//   led[2]  food present                 led[10..15] output groups active in the
//   led[3]  threat present                   last window: giant fiber, MDN, DNp09,
//                                            steer L, steer R, proboscis
//
// Everything runs in the single 100 MHz domain; slower behavior uses
// clock enables.

`timescale 1ns/1ps

module basys3_top #(
    parameter int ENGINE_SYSTOLIC = 1,
    parameter int ROWS            = 4,
    parameter int COLS            = 4,
    parameter int BANKED          = 1,
    parameter int WBUF            = 2,
    parameter     ROM_FILE        = "network_weights.mem",
    parameter int DEBOUNCE        = 1_000_000,     // 10 ms
    parameter int STEP_PERIOD     = 1_000_000,     // 100 steps/s
    parameter int SLOW_PERIOD     = 10_000_000,    // 10 steps/s
    parameter int TELEM_PERIOD    = 2_000_000,     // 50 packets/s
    parameter int UART_DIV        = 868,           // 115200 baud
    parameter int POR_CYCLES      = 255
) (
    input  logic        clk,
    input  logic        btnC,
    input  logic        btnU,
    input  logic        btnL,
    input  logic        btnR,
    input  logic [15:0] sw,
    output logic [15:0] led,
    output logic        RsTx
);

    // ------------------------------------------------------------------
    // Power-on reset (FPGA configuration initializes por_cnt to 0) and the
    // conditioned reset button
    // ------------------------------------------------------------------
    logic [7:0] por_cnt = 8'd0;
    wire        por = (por_cnt != 8'(POR_CYCLES));
    always_ff @(posedge clk)
        if (por) por_cnt <= por_cnt + 1'b1;

    logic btn_rst_level;
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_rst (
        .clk, .rst(por), .async_in(btnC), .level(btn_rst_level), .rise());

    logic rst;
    always_ff @(posedge clk) rst <= por || btn_rst_level;

    // ------------------------------------------------------------------
    // Other inputs
    // ------------------------------------------------------------------
    logic step_btn, food_btn, threat_btn;
    logic run_sw, food_sw, threat_sw, slow_sw;
    logic [4:0] probe_sw;

    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_u (.clk, .rst, .async_in(btnU), .level(), .rise(step_btn));
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_l (.clk, .rst, .async_in(btnL), .level(), .rise(food_btn));
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_r (.clk, .rst, .async_in(btnR), .level(), .rise(threat_btn));
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_s0 (.clk, .rst, .async_in(sw[0]), .level(run_sw),    .rise());
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_s1 (.clk, .rst, .async_in(sw[1]), .level(food_sw),   .rise());
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_s2 (.clk, .rst, .async_in(sw[2]), .level(threat_sw), .rise());
    input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic_s3 (.clk, .rst, .async_in(sw[3]), .level(slow_sw),   .rise());

    // The probe group is display-only, and any mix of old/new switch bits is a
    // valid group, so per-bit conditioning is sufficient here.
    for (genvar k = 0; k < 5; k++) begin : g_probe
        input_conditioner #(.DEBOUNCE(DEBOUNCE)) u_ic (
            .clk, .rst, .async_in(sw[5 + k]), .level(probe_sw[k]), .rise());
    end

    // ------------------------------------------------------------------
    // Step pacing: in run mode a timer requests one step per period; in
    // pause mode btnU requests exactly one step. Requests do not queue up:
    // at most one is pending.
    // ------------------------------------------------------------------
    localparam int SPW = $clog2(SLOW_PERIOD + 1);
    logic [SPW-1:0] pace;
    logic           step_pending;
    logic           step_ready;
    wire  [SPW-1:0] period_m1 = slow_sw ? SPW'(SLOW_PERIOD - 1) : SPW'(STEP_PERIOD - 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            pace         <= '0;
            step_pending <= 1'b0;
        end else begin
            if (run_sw)
                pace <= (pace >= period_m1) ? '0 : pace + 1'b1;
            else
                pace <= '0;
            if (step_pending && step_ready)
                step_pending <= 1'b0;
            else if ((run_sw && pace >= period_m1) || (!run_sw && step_btn))
                step_pending <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Neural core
    // ------------------------------------------------------------------
    logic        booted, step_busy, commit, step_done, food_q, threat_q;
    logic [31:0] step_count, cycles_last;
    logic [255:0] spikes;
    logic [7:0][15:0] probe_v;
    logic [5:0]  fly_x, fly_y, food_x, food_y, threat_x, threat_y;
    logic [2:0]  heading, last_action;
    logic [15:0] eaten, caught, jumps, lfsr;
    logic [5:0][7:0] last_motor;

    fly_core #(.ENGINE_SYSTOLIC(ENGINE_SYSTOLIC), .ROWS(ROWS), .COLS(COLS), .BANKED(BANKED),
               .WBUF(WBUF), .ROM_FILE(ROM_FILE)) u_core (
        .clk, .rst,
        .step_req(step_pending), .step_ready,
        .food_present(food_sw), .threat_present(threat_sw),
        .respawn_food_evt(food_btn), .respawn_threat_evt(threat_btn),
        .probe_group(probe_sw),
        .booted, .step_busy, .commit, .step_done, .step_count, .cycles_last, .spikes,
        .probe_v, .food_q, .threat_q,
        .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y, .heading,
        .eaten, .caught, .jumps, .lfsr, .last_action, .last_motor);

    // ------------------------------------------------------------------
    // Telemetry
    // ------------------------------------------------------------------
    logic        drop_pulse;
    logic [15:0] dropped_total, seq_sent;

    telemetry #(.DIV(UART_DIV), .PERIOD(TELEM_PERIOD), .SYSTOLIC(ENGINE_SYSTOLIC)) u_tel (
        .clk, .rst, .commit, .spikes, .engine_idle(!step_busy), .running(run_sw),
        .food_present(food_q), .threat_present(threat_q),
        .step_count, .cycles_last,
        .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y, .heading, .last_action,
        .eaten, .caught, .jumps, .last_motor, .probe_group(probe_sw), .probe_v,
        .txd(RsTx), .drop_pulse, .dropped_total, .seq_sent);

    // ------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------
    logic step_led;
    logic [23:0] drop_led_cnt;      // stretch drop pulses to ~0.17 s
    always_ff @(posedge clk) begin
        if (rst) begin
            step_led     <= 1'b0;
            drop_led_cnt <= '0;
        end else begin
            if (step_done) step_led <= ~step_led;
            if (drop_pulse) drop_led_cnt <= '1;
            else if (drop_led_cnt != 0) drop_led_cnt <= drop_led_cnt - 1'b1;
        end
    end

    always_comb begin
        led        = '0;
        led[0]     = step_led;
        led[1]     = run_sw;
        led[2]     = food_sw;
        led[3]     = threat_sw;
        led[4]     = (drop_led_cnt != 0);
        led[5]     = booted;
        for (int d = 0; d < 6; d++)
            led[10 + d] = (last_motor[d] != 0);
    end

endmodule
