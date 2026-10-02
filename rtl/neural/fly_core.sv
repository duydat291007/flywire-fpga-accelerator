// fly_core.sv
// Neural engine of the virtual pet, independent of the board.
//
// After reset, a boot loader copies the network weights from ROM into the
// matrix-vector unit through its ordinary weight-write port. Then each
// accepted step request runs one timestep (docs/specification.md 4.1):
//
//   S_XLOAD   bulk-load x = s[t] (current spike bank) into the MVU
//   S_CMD     issue y = W x with dim = N_NEURONS
//   S_RES     for each result y[i], in order: LIF(V[t][i], y[i], U[i]) goes
//             through a 2-stage pipeline (lif_pipe) and is written to the
//             NEXT bank only
//   S_FLUSH   wait for the last neuron to leave the pipeline
//   S_COMMIT  every neuron written -> toggle bank select, step += 1
//   S_WORLD   world update with the committed spikes s[t+1] (fly_world runs
//             a short micro-sequence and pulses `done`)
//
// Reads come only from the current bank and writes go only to the next bank,
// so every neuron of step t+1 sees the same spike vector s[t].
//
// Potentials live in one 2*N x 16 memory (address {bank, neuron}) with an
// asynchronous read, so Vivado maps it to distributed RAM instead of 8k
// flip-flops and wide multiplexers. Memory cannot be reset in one cycle, so
// it is cleared during the weight boot, which follows every reset anyway.

`timescale 1ns/1ps

module fly_core
    import fly_cfg_pkg::*;
#(
    parameter int    ENGINE_SYSTOLIC = 1,
    parameter int    ROWS     = 4,
    parameter int    COLS     = 4,
    parameter int    BANKED   = 1,
    parameter int    WBUF     = 2,
    parameter        ROM_FILE = "network_weights.mem"
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        step_req,          // run one timestep when step_ready
    output logic        step_ready,
    input  logic        food_present,      // sampled at step start
    input  logic        threat_present,
    input  logic        respawn_food_evt,
    input  logic        respawn_threat_evt,
    input  logic [4:0]  probe_group,       // potentials of neurons 8*g .. 8*g+7

    output logic        booted,
    output logic        step_busy,
    output logic        commit,            // pulse: new state committed
    output logic        step_done,         // pulse: world updated, step complete
    output logic [31:0] step_count,
    output logic [31:0] cycles_last,       // step accept .. commit, inclusive
    output logic [N_NEURONS-1:0] spikes,   // committed spike vector s[t]
    output logic [7:0][15:0] probe_v,      // committed potentials of probe group (updated per step)
    output logic        food_q,
    output logic        threat_q,
    output logic [5:0]  fly_x, fly_y, food_x, food_y, threat_x, threat_y,
    output logic [2:0]  heading,
    output logic [15:0] eaten,
    output logic [15:0] caught,
    output logic [15:0] jumps,
    output logic [15:0] lfsr,
    output logic [2:0]  last_action,
    output logic [5:0][7:0] last_motor
);

    localparam int N  = N_NEURONS;
    localparam int AW = $clog2(N);
    initial if (N != 256) $fatal(1, "fly_core index ranges assume the 256-neuron FlyWire layout");

    // ------------------------------------------------------------------
    // Matrix-vector unit
    // ------------------------------------------------------------------
    logic        w_valid, w_ready;
    logic [AW-1:0] w_dst, w_src;
    logic [7:0]  w_data;
    logic        xb_valid, xb_ready;
    logic        cmd_valid, cmd_ready;
    logic        res_valid, res_ready, res_last;
    logic [31:0] res_data;
    logic [AW-1:0] res_idx;
    logic        mvu_busy, mvu_done, mvu_err;

    generate
        if (ENGINE_SYSTOLIC != 0) begin : g_mvu
            mvu_systolic #(.N_MAX(N), .ROWS(ROWS), .COLS(COLS), .BANKED(BANKED), .WBUF(WBUF)) u_mvu (
                .clk, .rst,
                .w_valid, .w_ready, .w_dst, .w_src, .w_data,
                .x_valid(1'b0), .x_ready(), .x_idx('0), .x_data(8'd0),
                .xb_valid, .xb_ready, .xb_bits(spikes),
                .cmd_valid, .cmd_ready, .cmd_dim((AW+1)'(N)),
                .res_valid, .res_ready, .res_data, .res_idx, .res_last,
                .busy(mvu_busy), .done(mvu_done), .err_dim(mvu_err));
        end else begin : g_mvu
            mvu_serial #(.N_MAX(N)) u_mvu (
                .clk, .rst,
                .w_valid, .w_ready, .w_dst, .w_src, .w_data,
                .x_valid(1'b0), .x_ready(), .x_idx('0), .x_data(8'd0),
                .xb_valid, .xb_ready, .xb_bits(spikes),
                .cmd_valid, .cmd_ready, .cmd_dim((AW+1)'(N)),
                .res_valid, .res_ready, .res_data, .res_idx, .res_last,
                .busy(mvu_busy), .done(mvu_done), .err_dim(mvu_err));
        end
    endgenerate

    // ------------------------------------------------------------------
    // Weight boot loader: ROM -> MVU weight port, once after every reset.
    // The ROM has a registered read (block RAM friendly); the MVU is idle
    // during boot, so w_ready is always 1 (checked by assertion).
    // ------------------------------------------------------------------
    logic [7:0]  rom [N * N];
    initial $readmemh(ROM_FILE, rom);

    localparam int BW = 2 * AW;      // ROM address width
    logic [BW:0]   boot_addr;        // 0..N*N
    logic [7:0]    rom_q;
    logic          boot_issue;

    assign boot_issue = !booted && (boot_addr != (BW+1)'(N * N));

    always_ff @(posedge clk) rom_q <= rom[boot_addr[BW-1:0]];

    always_ff @(posedge clk) begin
        if (rst) begin
            boot_addr <= '0;
            booted    <= 1'b0;
            w_valid   <= 1'b0;
        end else begin
            w_valid <= boot_issue;
            w_dst   <= boot_addr[BW-1:AW];
            w_src   <= boot_addr[AW-1:0];
            if (boot_issue)
                boot_addr <= boot_addr + 1'b1;
            if (!boot_issue && !w_valid && !booted)
                booted <= 1'b1;
        end
    end
    assign w_data = rom_q;

    // ------------------------------------------------------------------
    // Neuron state: two banks; `cur` selects the committed bank
    // ------------------------------------------------------------------
    logic          cur;
    logic [15:0]   vmem [2 * N];     // potentials, address {bank, neuron}; no reset
    logic [N-1:0]  sbank0, sbank1;
    logic [N-1:0]  written;          // next-bank entries written this step (checked by SVA)

    assign spikes = cur ? sbank1 : sbank0;

    // Current-bank potential of neuron res_idx (read side of the LIF pipeline)
    wire [15:0] v_cur_i = vmem[{cur, res_idx}];

    // External input for neuron res_idx: neurons 0..31 are the four sensor
    // groups of 8 (food L, food R, threat L, threat R). The drives depend only
    // on the world state, which cannot change during a timestep, so they are
    // registered once per step (S_CMD) to keep them off the LIF path.
    logic [3:0][7:0] u_sens, u_sens_q;
    logic [7:0][15:0] probe_next;    // probe group's next-bank potentials (see below)
    logic            world_done;     // fly_world finished this step's update
    wire  [7:0]      u_i = (res_idx < AW'(32)) ? u_sens_q[res_idx[4:3]] : 8'd0;

    // LIF pipeline: result handshake -> 2 register stages -> write to bank !cur.
    // (Single-cycle lif_update failed 100 MHz by 3.4 ns; see BUG-004.)
    logic [15:0] v_new;
    logic        s_new;
    logic        lw_valid, lw_last;
    logic [AW-1:0] lw_idx;
    wire         res_fire;

    lif_pipe #(.THRESHOLD(THRESHOLD), .TAG_W(AW+1)) u_lif (
        .clk, .rst,
        .in_valid(res_fire), .in_v(v_cur_i), .in_i(res_data), .in_u(u_i),
        .in_tag({res_last, res_idx}),
        .out_valid(lw_valid), .out_v_next(v_new), .out_spike(s_new),
        .out_tag({lw_last, lw_idx}));

    // ------------------------------------------------------------------
    // Step controller
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {S_IDLE, S_XLOAD, S_CMD, S_RES, S_FLUSH, S_COMMIT, S_WORLD} st_t;
    st_t st;

    assign step_ready = booted && (st == S_IDLE);
    assign step_busy  = (st != S_IDLE);
    assign xb_valid   = (st == S_XLOAD);
    assign cmd_valid  = (st == S_CMD);
    assign res_ready  = (st == S_RES);

    assign res_fire = res_valid && res_ready;
    logic [31:0] cyc;

    always_ff @(posedge clk) begin
        if (rst) begin
            st          <= S_IDLE;
            cur         <= 1'b0;
            sbank0      <= '0;
            sbank1      <= '0;
            step_count  <= '0;
            cycles_last <= '0;
            commit      <= 1'b0;
            step_done   <= 1'b0;
            food_q      <= 1'b0;
            threat_q    <= 1'b0;
            written     <= '0;
            probe_v     <= '0;
        end else begin
            commit    <= 1'b0;
            step_done <= 1'b0;
            cyc       <= cyc + 1'b1;

            case (st)
                S_IDLE: if (step_req && step_ready) begin
                    food_q   <= food_present;
                    threat_q <= threat_present;
                    cyc      <= 32'd1;
                    written  <= '0;
                    st       <= S_XLOAD;
                end
                S_XLOAD: if (xb_ready) st <= S_CMD;
                S_CMD: begin
                    // fly_world registers u_sens; food_q/threat_q were latched
                    // two edges ago, so the drives here are for this step
                    u_sens_q <= u_sens;
                    if (cmd_ready) st <= S_RES;
                end
                S_RES:   if (res_fire && res_last) st <= S_FLUSH;
                S_FLUSH: if (lw_valid && lw_last)  st <= S_COMMIT;   // last write lands now
                S_COMMIT: begin
                    cur         <= ~cur;
                    step_count  <= step_count + 1'b1;
                    cycles_last <= cyc;
                    commit      <= 1'b1;
                    probe_v     <= probe_next;   // next bank becomes the committed bank
                    st          <= S_WORLD;
                end
                S_WORLD: if (world_done) begin
                    step_done <= 1'b1;
                    st        <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase

            // Write side of the LIF pipeline: only the NEXT bank is written
            if (lw_valid) begin
                written[lw_idx] <= 1'b1;
                if (cur) sbank0[lw_idx] <= s_new;
                else     sbank1[lw_idx] <= s_new;
            end
        end
    end

    // Potential memory write port: cleared during boot, then LIF writes to the
    // next bank only. (Separate always_ff without reset -> distributed RAM.)
    wire          clr_we   = !booted && (boot_addr < (BW+1)'(2 * N));
    wire          vm_we    = clr_we || lw_valid;
    wire [AW:0]   vm_waddr = clr_we ? boot_addr[AW:0] : {~cur, lw_idx};
    wire [15:0]   vm_wdata = clr_we ? 16'd0 : v_new;
    always_ff @(posedge clk)
        if (vm_we) vmem[vm_waddr] <= vm_wdata;

    // Probe: copy the selected group's new potentials as they are written;
    // they become probe_v at commit (every neuron is written every step).
    always_ff @(posedge clk)
        if (lw_valid && lw_idx[AW-1:3] == probe_group)
            probe_next[lw_idx[2:0]] <= v_new;

    // ------------------------------------------------------------------
    // World: one update per committed step, using the committed spikes
    // ------------------------------------------------------------------
    fly_world u_world (
        .clk, .rst,
        .food_present(food_q), .threat_present(threat_q),
        .respawn_food_evt, .respawn_threat_evt,
        .update(commit), .done(world_done), .spikes(spikes),
        .u_sens,
        .fly_x, .fly_y, .food_x, .food_y, .threat_x, .threat_y, .heading,
        .eaten, .caught, .jumps, .lfsr, .last_action, .last_motor);

endmodule
