// fly_world.sv  (world v2: heading-based fly for the FlyWire network)
// Integer world: fly position + 8-way heading, egocentric sensors, motor
// decoding, actions, threat pursuit, catch, button placements, LFSR.
// Bit-accurate with model/fly_model/world.py (World.sensors / World.update).
//
// The fly moves only according to output-neuron spike counts. Nothing here
// maps a switch, button, or target position directly to a movement choice.
//
// One update per committed timestep runs as a short micro-sequence (a few
// cycles), started by `update` and finished with a `done` pulse. Splitting
// the work over cycles keeps every stage short for 100 MHz timing.

`timescale 1ns/1ps

module fly_world
    import fly_cfg_pkg::*;
(
    input  logic        clk,
    input  logic        rst,

    // Presence flags, held constant for a whole timestep by the caller
    input  logic        food_present,
    input  logic        threat_present,

    // Button requests (pulses, any time); applied at the next update
    input  logic        respawn_food_evt,
    input  logic        respawn_threat_evt,

    input  logic        update,            // pulse: spikes hold the committed s[t+1]
    output logic        done,              // pulse: world update finished
    input  logic [N_NEURONS-1:0] spikes,

    // Sensor drive: [0] food L, [1] food R, [2] threat L, [3] threat R
    output logic [3:0][7:0] u_sens,

    output logic [5:0]  fly_x, fly_y, food_x, food_y, threat_x, threat_y,
    output logic [2:0]  heading,
    output logic [15:0] eaten,
    output logic [15:0] caught,
    output logic [15:0] jumps,
    output logic [15:0] lfsr,
    output logic [2:0]  last_action,       // 0 walk, 1 back, 2 jump, 3 eat, 4 blocked
    output logic [5:0][7:0] last_motor     // ESC, BACK, FWD, STEER_L, STEER_R, FEED
);

    localparam int WCW = (MOVE_WINDOW <= 1) ? 1 : $clog2(MOVE_WINDOW);
    localparam int TPW = (THREAT_PERIOD <= 1) ? 1 : $clog2(THREAT_PERIOD);
    localparam int M_ESC = 0, M_BACK = 1, M_FWD = 2, M_STL = 3, M_STR = 4, M_FEED = 5;

    // ------------------------------------------------------------------
    // Heading helpers: DX/DY in {-1, 0, +1}, y grows downward
    // ------------------------------------------------------------------
    function automatic logic signed [1:0] hdx(input logic [2:0] h);
        case (h)
            3'd0, 3'd1, 3'd7: return 2'sd1;
            3'd3, 3'd4, 3'd5: return -2'sd1;
            default:          return 2'sd0;
        endcase
    endfunction
    function automatic logic signed [1:0] hdy(input logic [2:0] h);
        case (h)
            3'd1, 3'd2, 3'd3: return 2'sd1;
            3'd5, 3'd6, 3'd7: return -2'sd1;
            default:          return 2'sd0;
        endcase
    endfunction
    // heading whose (DX, DY) = (sx, sy); (0, 0) maps to 0
    function automatic logic [2:0] head_of(input logic signed [1:0] sx, input logic signed [1:0] sy);
        case ({sy, sx})
            {-2'sd1, -2'sd1}: return 3'd5;
            {-2'sd1,  2'sd0}: return 3'd6;
            {-2'sd1,  2'sd1}: return 3'd7;
            { 2'sd0, -2'sd1}: return 3'd4;
            { 2'sd1, -2'sd1}: return 3'd3;
            { 2'sd1,  2'sd0}: return 3'd2;
            { 2'sd1,  2'sd1}: return 3'd1;
            default:          return 3'd0;
        endcase
    endfunction
    function automatic logic signed [1:0] sgn7(input logic signed [6:0] v);
        return (v > 0) ? 2'sd1 : (v < 0) ? -2'sd1 : 2'sd0;
    endfunction
    function automatic logic [5:0] absd(input logic signed [6:0] v);
        return v[6] ? 6'(-v) : 6'(v);
    endfunction
    // pos + k * d, clamped to the arena
    function automatic logic [5:0] clamp_add(input logic [5:0] pos, input logic signed [1:0] d,
                                             input logic [3:0] k);
        logic signed [7:0] p;
        p = $signed({2'b0, pos}) + ((d > 0) ? $signed({4'b0, k}) : (d < 0) ? -$signed({4'b0, k}) : 8'sd0);
        if (p < 0) return 6'd0;
        if (p > 8'sd63) return 6'd63;
        return 6'(p);
    endfunction
    // cells the fly can move along h before a wall, capped at cap
    function automatic logic [3:0] avail(input logic [5:0] x, input logic [5:0] y,
                                         input logic [2:0] h, input logic [3:0] cap);
        logic [5:0] ax, ay;
        logic [3:0] n;
        ax = (hdx(h) > 0) ? 6'd63 - x : (hdx(h) < 0) ? x : 6'd63;
        ay = (hdy(h) > 0) ? 6'd63 - y : (hdy(h) < 0) ? y : 6'd63;
        n = cap;
        if (ax < 6'(n)) n = 4'(ax);
        if (ay < 6'(n)) n = 4'(ay);
        return n;
    endfunction

    // ------------------------------------------------------------------
    // Sensors (combinational from the current world state)
    // ------------------------------------------------------------------
    wire signed [6:0] fdx = $signed({1'b0, food_x})   - $signed({1'b0, fly_x});
    wire signed [6:0] fdy = $signed({1'b0, food_y})   - $signed({1'b0, fly_y});
    wire signed [6:0] tdx = $signed({1'b0, threat_x}) - $signed({1'b0, fly_x});
    wire signed [6:0] tdy = $signed({1'b0, threat_y}) - $signed({1'b0, fly_y});
    wire [5:0] fdist = (absd(fdx) > absd(fdy)) ? absd(fdx) : absd(fdy);
    wire [5:0] tdist = (absd(tdx) > absd(tdy)) ? absd(tdx) : absd(tdy);

    // sign of DX*dy - DY*dx: -1 left, +1 right, 0 ahead/behind
    function automatic logic signed [1:0] side_of(input logic [2:0] h,
                                                  input logic signed [6:0] dx, input logic signed [6:0] dy);
        logic signed [7:0] a, b, c;
        a = (hdx(h) > 0) ? 8'(dy) : (hdx(h) < 0) ? -8'(dy) : 8'sd0;
        b = (hdy(h) > 0) ? 8'(dx) : (hdy(h) < 0) ? -8'(dx) : 8'sd0;
        c = a - b;
        return (c > 0) ? 2'sd1 : (c < 0) ? -2'sd1 : 2'sd0;
    endfunction

    // food_on is also used by the action logic (combinational, current state)
    wire food_on   = food_present   && (fdist <= 6'(TASTE_RADIUS));

    // Sensor drives, computed over two register stages so the distance and
    // side arithmetic never sits in one long path (BUG-010):
    //   stage 1 (every cycle): position differences and heading
    //   stage 2 (every cycle): |d|, side, range check, looming drive, and the
    //                          presence flags -> u_sens
    // Positions and heading therefore reach u_sens after 2 cycles, presence
    // after 1. The world is idle for many cycles before fly_core samples
    // u_sens (in S_CMD, one cycle after it latches the presence flags).
    logic signed [6:0] s_fdx, s_fdy, s_tdx, s_tdy;
    logic        [2:0] s_head;
    always_ff @(posedge clk) begin
        s_fdx  <= fdx;  s_fdy <= fdy;
        s_tdx  <= tdx;  s_tdy <= tdy;
        s_head <= heading;
    end
    wire [5:0] s_fdist = (absd(s_fdx) > absd(s_fdy)) ? absd(s_fdx) : absd(s_fdy);
    wire [5:0] s_tdist = (absd(s_tdx) > absd(s_tdy)) ? absd(s_tdx) : absd(s_tdy);
    wire signed [1:0] fside = side_of(s_head, s_fdx, s_fdy);
    wire signed [1:0] tside = side_of(s_head, s_tdx, s_tdy);
    wire s_food_on   = food_present   && (s_fdist <= 6'(TASTE_RADIUS));
    wire s_threat_on = threat_present && (s_tdist <= 6'(LOOM_RADIUS));
    wire [9:0] loom_raw = 10'(LOOM_BASE) + 10'(LOOM_GAIN) * 10'(6'(LOOM_RADIUS) - s_tdist);
    wire [7:0] loom = (loom_raw > 10'd255) ? 8'd255 : loom_raw[7:0];

    always_ff @(posedge clk) begin
        u_sens[0] <= (s_food_on && fside <= 0)   ? 8'(FOOD_DRIVE) : 8'd0;
        u_sens[1] <= (s_food_on && fside >= 0)   ? 8'(FOOD_DRIVE) : 8'd0;
        u_sens[2] <= (s_threat_on && tside <= 0) ? loom : 8'd0;
        u_sens[3] <= (s_threat_on && tside >= 0) ? loom : 8'd0;
    end

    // ------------------------------------------------------------------
    // Output-neuron counts for this step (index ranges from network.py)
    // ------------------------------------------------------------------
    logic [5:0][7:0] cnt;
    assign cnt[M_ESC]  = 8'($countones(spikes[233:232]));
    assign cnt[M_BACK] = 8'($countones(spikes[245:242]));
    assign cnt[M_FWD]  = 8'($countones(spikes[247:246]));
    assign cnt[M_STL]  = 8'($countones(spikes[249:248]));
    assign cnt[M_STR]  = 8'($countones(spikes[251:250]));
    assign cnt[M_FEED] = 8'($countones(spikes[255:252]));

    // ------------------------------------------------------------------
    // Micro-sequencer
    // ------------------------------------------------------------------
    typedef enum logic [3:0] {W_IDLE, W_DECIDE, W_JUMP, W_STEP, W_WEND, W_CATCH, W_PEND, W_LFSR} wst_t;
    wst_t wst;

    logic [WCW-1:0]  window_count;
    logic [TPW-1:0]  threat_phase;
    logic [5:0][7:0] acc;
    logic [2:0]      try_k;
    logic            go_back;
    logic            pend_food, pend_threat;

    // Offsets tried for a jump when a wall blocks: 0, +1, -1, +2, -2
    function automatic logic [2:0] jump_off(input logic [2:0] k);
        case (k)
            3'd0: return 3'd0;
            3'd1: return 3'd1;
            3'd2: return 3'd7;
            3'd3: return 3'd2;
            default: return 3'd6;
        endcase
    endfunction

    wire signed [8:0] steer   = $signed({1'b0, acc[M_STR]}) - $signed({1'b0, acc[M_STL]});
    wire signed [8:0] backdrv = $signed({1'b0, acc[M_BACK]}) - $signed({1'b0, acc[M_FWD]});
    wire [2:0] jh   = heading + jump_off(try_k);
    wire [3:0] jn   = avail(fly_x, fly_y, jh, 4'(JUMP_DIST));
    wire [2:0] sh   = go_back ? heading + 3'd4 : heading;
    wire [3:0] sn   = avail(fly_x, fly_y, sh, 4'd1);
    wire [2:0] side_h = heading + (lfsr[0] ? 3'd2 : 3'd6);
    wire lfsr_fb = lfsr[0] ^ lfsr[2] ^ lfsr[3] ^ lfsr[5];

    always_ff @(posedge clk) begin
        if (rst) begin
            wst          <= W_IDLE;
            done         <= 1'b0;
            fly_x        <= 6'(FLY_X0);    fly_y    <= 6'(FLY_Y0);
            heading      <= 3'(FLY_HEADING);
            food_x       <= 6'(FOOD_X0);   food_y   <= 6'(FOOD_Y0);
            threat_x     <= 6'(THREAT_X0); threat_y <= 6'(THREAT_Y0);
            eaten        <= '0;
            caught       <= '0;
            jumps        <= '0;
            lfsr         <= LFSR_SEED;
            window_count <= '0;
            threat_phase <= '0;
            acc          <= '0;
            last_motor   <= '0;
            last_action  <= '0;
            try_k        <= '0;
            go_back      <= 1'b0;
            pend_food    <= 1'b0;
            pend_threat  <= 1'b0;
        end else begin
            done <= 1'b0;
            // Requests arriving in the W_PEND cycle apply at the next update
            pend_food   <= (wst == W_PEND) ? respawn_food_evt   : (pend_food   | respawn_food_evt);
            pend_threat <= (wst == W_PEND) ? respawn_threat_evt : (pend_threat | respawn_threat_evt);

            case (wst)
                W_IDLE: if (update) begin
                    for (int m = 0; m < 6; m++) acc[m] <= acc[m] + cnt[m];
                    if (window_count == WCW'(MOVE_WINDOW - 1)) begin
                        wst <= W_DECIDE;
                    end else begin
                        window_count <= window_count + 1'b1;
                        wst <= W_CATCH;
                    end
                end

                W_DECIDE: begin
                    if (acc[M_ESC] >= 8'(ESCAPE_MIN)) begin
                        if (threat_present && (tdx != 0 || tdy != 0))
                            heading <= head_of(-sgn7(tdx), -sgn7(tdy));
                        jumps       <= jumps + 1'b1;
                        last_action <= 3'd2;
                        try_k       <= '0;
                        wst         <= W_JUMP;
                    end else if (acc[M_FEED] >= 8'(FEED_MIN) && food_on) begin
                        eaten       <= eaten + 1'b1;
                        food_x      <= lfsr[5:0];
                        food_y      <= lfsr[11:6];
                        last_action <= 3'd3;
                        wst         <= W_WEND;
                    end else begin
                        if (steer >= 9'(TURN_MARGIN))
                            heading <= heading + 3'd1;
                        else if (steer <= -9'sd0 - 9'(TURN_MARGIN))
                            heading <= heading - 3'd1;
                        else if (lfsr[2:0] == 3'd0)
                            heading <= lfsr[3] ? heading + 3'd1 : heading - 3'd1;
                        go_back <= (backdrv >= 9'(BACK_MARGIN));
                        wst     <= W_STEP;
                    end
                end

                W_JUMP: begin
                    if (jn != 0) begin
                        fly_x   <= 6'($signed({1'b0, fly_x}) + $signed(hdx(jh)) * $signed({1'b0, jn}));
                        fly_y   <= 6'($signed({1'b0, fly_y}) + $signed(hdy(jh)) * $signed({1'b0, jn}));
                        heading <= jh;
                        wst     <= W_WEND;
                    end else if (try_k == 3'd4) begin
                        wst <= W_WEND;
                    end else begin
                        try_k <= try_k + 1'b1;
                    end
                end

                W_STEP: begin
                    if (sn != 0) begin
                        fly_x       <= 6'($signed({1'b0, fly_x}) + $signed(hdx(sh)));
                        fly_y       <= 6'($signed({1'b0, fly_y}) + $signed(hdy(sh)));
                        last_action <= go_back ? 3'd1 : 3'd0;
                    end else begin
                        heading     <= heading + 3'd4;
                        last_action <= 3'd4;
                    end
                    wst <= W_WEND;
                end

                W_WEND: begin
                    last_motor   <= acc;
                    acc          <= '0;
                    window_count <= '0;
                    if (threat_phase == TPW'(THREAT_PERIOD - 1)) begin
                        threat_phase <= '0;
                        if (threat_present) begin
                            threat_x <= 6'($signed({1'b0, threat_x}) - $signed(sgn7(tdx)));
                            threat_y <= 6'($signed({1'b0, threat_y}) - $signed(sgn7(tdy)));
                        end
                    end else begin
                        threat_phase <= threat_phase + 1'b1;
                    end
                    wst <= W_CATCH;
                end

                W_CATCH: begin
                    if (threat_present && tdist <= 6'd1) begin
                        caught   <= caught + 1'b1;
                        threat_x <= fly_x + 6'd32;
                        threat_y <= fly_y + 6'd32;
                    end
                    wst <= W_PEND;
                end

                W_PEND: begin
                    if (pend_food) begin
                        food_x <= clamp_add(fly_x, hdx(heading), 4'(FOOD_AHEAD));
                        food_y <= clamp_add(fly_y, hdy(heading), 4'(FOOD_AHEAD));
                    end
                    if (pend_threat) begin
                        threat_x <= clamp_add(fly_x, hdx(side_h), 4'(THREAT_SIDE));
                        threat_y <= clamp_add(fly_y, hdy(side_h), 4'(THREAT_SIDE));
                    end
                    wst <= W_LFSR;
                end

                W_LFSR: begin
                    lfsr <= {lfsr_fb, lfsr[15:1]};
                    done <= 1'b1;
                    wst  <= W_IDLE;
                end

                default: wst <= W_IDLE;
            endcase
        end
    end

endmodule
