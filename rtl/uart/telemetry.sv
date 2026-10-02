// telemetry.sv
// Activity accumulation, coherent snapshots, and the 119-byte telemetry
// packet v2 (docs/specification.md section 6), sent through uart_tx.
//
// Snapshot rules:
//   - A timer fires every PERIOD cycles.
//   - On a timer tick, if a packet is still being sent or a capture is
//     already waiting, that snapshot is DROPPED: dropped_total += 1 and the
//     "dropped" flag is set in the next packet. Activity keeps accumulating.
//   - Otherwise a capture is requested. The capture happens in a cycle where
//     the neural engine is idle, so every field describes the same committed
//     step. All fields are copied in that single cycle.
//   - Activity counters (2-bit, saturating, one per neuron) are copied and cleared in the
//     capture cycle. If a commit happened in that same cycle (not possible
//     with fly_core, but handled anyway) its spikes start the new counts.

`timescale 1ns/1ps

module telemetry #(
    parameter int DIV      = 868,          // UART bit time in clocks
    parameter int PERIOD   = 2_000_000,    // snapshot period in clocks
    parameter int SYSTOLIC = 1             // reported in flags bit 4
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        commit,            // pulse with the new spike vector
    input  logic [255:0] spikes,
    input  logic        engine_idle,       // no timestep in progress
    input  logic        running,
    input  logic        food_present,
    input  logic        threat_present,
    input  logic [31:0] step_count,
    input  logic [31:0] cycles_last,
    input  logic [5:0]  fly_x, fly_y, food_x, food_y, threat_x, threat_y,
    input  logic [2:0]  heading,
    input  logic [2:0]  last_action,
    input  logic [15:0] eaten,
    input  logic [15:0] caught,
    input  logic [15:0] jumps,
    input  logic [5:0][7:0] last_motor,
    input  logic [4:0]  probe_group,
    input  logic [7:0][15:0] probe_v,

    output logic        txd,
    output logic        drop_pulse,        // a snapshot was dropped (for an LED)
    output logic [15:0] dropped_total,
    output logic [15:0] seq_sent           // packets started
);
    localparam int PKT_LEN  = 119;
    localparam int BODY_LEN = 117;          // bytes before the CRC
    localparam int PAY_LEN  = BODY_LEN - 4; // bytes 4..116
    localparam int PW = $clog2(PERIOD + 1);

    // ------------------------------------------------------------------
    // Activity counters
    // ------------------------------------------------------------------
    logic [255:0][1:0] act;
    logic              capture;

    for (genvar i = 0; i < 256; i++) begin : g_act
        always_ff @(posedge clk) begin
            if (rst)
                act[i] <= '0;
            else if (capture)
                act[i] <= (commit && spikes[i]) ? 2'd1 : 2'd0;
            else if (commit && spikes[i] && act[i] != 2'd3)
                act[i] <= act[i] + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Timer, capture request, drop accounting
    // ------------------------------------------------------------------
    logic [PW-1:0] timer;
    logic          pending;
    logic          sending;
    logic          drop_flag;            // since the previous captured packet
    wire           tick = (timer == PW'(PERIOD - 1));

    assign capture = pending && engine_idle && !sending;

    always_ff @(posedge clk) begin
        if (rst) begin
            timer         <= '0;
            pending       <= 1'b0;
            drop_flag     <= 1'b0;
            dropped_total <= '0;
            drop_pulse    <= 1'b0;
        end else begin
            drop_pulse <= 1'b0;
            timer <= tick ? '0 : timer + 1'b1;
            if (capture) begin
                pending   <= 1'b0;
                drop_flag <= 1'b0;
            end
            if (tick) begin
                if (sending || pending) begin
                    drop_flag  <= 1'b1;
                    drop_pulse <= 1'b1;
                    if (dropped_total != 16'hFFFF)
                        dropped_total <= dropped_total + 1'b1;
                end else begin
                    pending <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Snapshot registers (all loaded in the capture cycle)
    // ------------------------------------------------------------------
    logic [15:0]       s_seq, s_dropped, s_eaten, s_caught, s_jumps;
    logic [31:0]       s_step, s_cycles;
    logic [7:0]        s_flags, s_probe, s_ha;
    logic [5:0]        s_fly_x, s_fly_y, s_food_x, s_food_y, s_threat_x, s_threat_y;
    logic [5:0][7:0]   s_motor;
    logic [255:0][1:0] s_act;
    logic [7:0][15:0]  s_pot;

    always_ff @(posedge clk) begin
        if (capture) begin
            s_seq     <= seq_sent;
            s_step    <= step_count;
            s_flags   <= {3'b0, SYSTOLIC != 0, drop_flag, threat_present, food_present, running};
            s_dropped <= dropped_total;
            s_cycles  <= cycles_last;
            s_fly_x    <= fly_x;    s_fly_y    <= fly_y;
            s_food_x   <= food_x;   s_food_y   <= food_y;
            s_threat_x <= threat_x; s_threat_y <= threat_y;
            s_ha      <= {1'b0, last_action, 1'b0, heading};
            s_eaten   <= eaten;
            s_caught  <= caught;
            s_jumps   <= jumps;
            s_motor   <= last_motor;
            s_act     <= act;
            s_probe   <= {probe_group, 3'b0};
            s_pot     <= probe_v;
        end
    end

    // ------------------------------------------------------------------
    // Packet serializer with CRC-16/CCITT-FALSE over bytes 2..116
    // ------------------------------------------------------------------
    function automatic logic [15:0] crc_byte(input logic [15:0] crc, input logic [7:0] b);
        logic [15:0] c;
        c = crc ^ {b, 8'h00};
        for (int k = 0; k < 8; k++)
            c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
        return c;
    endfunction

    logic [6:0]  idx;          // byte being offered, 0..118
    logic [15:0] crc;
    logic [7:0]  pbyte;
    logic        u_valid, u_ready;

    // Bytes 0..116 as one little-endian vector: byte k occupies bits 8k+7..8k.
    // Multi-byte fields are little-endian on the wire, so each field drops in
    // as-is. Activity: neuron 4k+m in bits 2m+1..2m of byte 36+k.
    wire [8*BODY_LEN-1:0] body = {
        s_pot,                                    // bytes 101..116
        s_probe,                                  // byte  100 (first probed neuron)
        s_act,                                    // bytes 36..99
        s_motor,                                  // bytes 30..35 (ESC,BACK,FWD,STL,STR,FEED)
        s_jumps, s_caught, s_eaten,               // bytes 28..29, 26..27, 24..25
        s_ha,                                     // byte  23 (heading | action << 4)
        2'b0, s_threat_y, 2'b0, s_threat_x,       // bytes 22, 21
        2'b0, s_food_y,   2'b0, s_food_x,         // bytes 20, 19
        2'b0, s_fly_y,    2'b0, s_fly_x,          // bytes 18, 17
        s_cycles,                                 // bytes 13..16
        s_dropped,                                // bytes 11..12
        s_flags,                                  // byte  10
        s_step,                                   // bytes 6..9
        s_seq,                                    // bytes 4..5
        8'(PAY_LEN), 8'h02, 8'h5A, 8'hA5          // bytes 3, 2 (version 2), 1, 0
    };
    // byte select (a 117:1 mux, written as an indexed part-select)
    assign pbyte = (idx < 7'(BODY_LEN)) ? body[{idx, 3'b000} +: 8]
                 : (idx == 7'(BODY_LEN)) ? crc[7:0] : crc[15:8];

    assign u_valid = sending;

    always_ff @(posedge clk) begin
        if (rst) begin
            sending  <= 1'b0;
            idx      <= '0;
            crc      <= 16'hFFFF;
            seq_sent <= '0;
        end else if (capture) begin
            sending  <= 1'b1;
            idx      <= '0;
            crc      <= 16'hFFFF;
            seq_sent <= seq_sent + 1'b1;
        end else if (sending && u_ready) begin
            if (idx >= 2 && idx < 7'(BODY_LEN))
                crc <= crc_byte(crc, pbyte);
            if (idx == 7'(PKT_LEN - 1))
                sending <= 1'b0;
            else
                idx <= idx + 1'b1;
        end
    end

    uart_tx #(.DIV(DIV)) u_tx (
        .clk, .rst, .in_valid(u_valid), .in_ready(u_ready), .in_data(pbyte), .txd);

endmodule
