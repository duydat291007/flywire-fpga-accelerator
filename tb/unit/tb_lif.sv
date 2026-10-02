// tb_lif.sv - lif_update (single cycle, reference) and lif_pipe (2-stage,
// used in fly_core) against model-generated vectors (tests/vectors/lif_cases.txt).
// One instance pair per tested threshold. Vectors stream into lif_pipe one per
// cycle; its outputs are checked two cycles later against the same expectation.
`timescale 1ns/1ps

module tb_lif #(parameter VECTORS = "tests/vectors/lif_cases.txt");
    localparam int MAXN = 20000;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic [15:0] v;
    logic [31:0] i_in;
    logic [7:0]  u_in;
    logic [15:0] vn [3];
    logic        sp [3];
    logic        pv [3];
    logic [15:0] pvn [3];
    logic        psp [3];
    logic [14:0] ptag [3];
    logic        in_valid = 0;
    logic [14:0] in_tag = 0;

    lif_update #(.THRESHOLD(100))   u0 (.v, .i_in, .u_in, .v_next(vn[0]), .spike(sp[0]));
    lif_update #(.THRESHOLD(1))     u1 (.v, .i_in, .u_in, .v_next(vn[1]), .spike(sp[1]));
    lif_update #(.THRESHOLD(65535)) u2 (.v, .i_in, .u_in, .v_next(vn[2]), .spike(sp[2]));
    lif_pipe #(.THRESHOLD(100),   .TAG_W(15)) p0 (.clk, .rst, .in_valid, .in_v(v), .in_i(i_in), .in_u(u_in),
        .in_tag, .out_valid(pv[0]), .out_v_next(pvn[0]), .out_spike(psp[0]), .out_tag(ptag[0]));
    lif_pipe #(.THRESHOLD(1),     .TAG_W(15)) p1 (.clk, .rst, .in_valid, .in_v(v), .in_i(i_in), .in_u(u_in),
        .in_tag, .out_valid(pv[1]), .out_v_next(pvn[1]), .out_spike(psp[1]), .out_tag(ptag[1]));
    lif_pipe #(.THRESHOLD(65535), .TAG_W(15)) p2 (.clk, .rst, .in_valid, .in_v(v), .in_i(i_in), .in_u(u_in),
        .in_tag, .out_valid(pv[2]), .out_v_next(pvn[2]), .out_spike(psp[2]), .out_tag(ptag[2]));

    int ev [MAXN];          // expected v_next per vector
    int es [MAXN];          // expected spike
    int ek [MAXN];          // which threshold instance
    int checked_pipe = 0;

    // Pipeline checker: every valid output must match its tagged vector
    always @(posedge clk) begin
        #1;
        for (int k = 0; k < 3; k++)
            if (pv[k] && ek[ptag[k]] == k) begin
                if (pvn[k] !== 16'(ev[ptag[k]]) || psp[k] !== es[ptag[k]][0]) begin
                    $display("FAIL lif_pipe vector %0d: got (%0d,%0d) expected (%0d,%0d)",
                             ptag[k], pvn[k], psp[k], ev[ptag[k]], es[ptag[k]]);
                    $fatal(1, "lif_pipe mismatch");
                end
                checked_pipe++;
            end
    end

    initial begin
        int fd, n, r, th, vv, ii, uu, evn, esp, k, eq_fire;
        fd = $fopen(VECTORS, "r");
        if (fd == 0) $fatal(1, "cannot open vectors");
        r = $fscanf(fd, "%d", n);
        if (n > MAXN) $fatal(1, "too many vectors");
        eq_fire = 0;
        @(negedge clk); rst = 0;
        for (int c = 0; c < n; c++) begin
            r = $fscanf(fd, "%d %d %d %d %d %d", th, vv, ii, uu, evn, esp);
            k = (th == 100) ? 0 : (th == 1) ? 1 : 2;
            ev[c] = evn; es[c] = esp; ek[c] = k;
            v = 16'(vv); i_in = 32'(ii); u_in = 8'(uu);
            in_valid = 1; in_tag = 15'(c);
            #1;
            if (vn[k] !== 16'(evn) || sp[k] !== esp[0]) begin
                $display("FAIL th=%0d v=%0d i=%0d u=%0d: got (%0d,%0d) expected (%0d,%0d)",
                         th, vv, ii, uu, vn[k], sp[k], evn, esp);
                $fatal(1, "LIF mismatch");
            end
            if (esp && ((15 * vv) / 16 + ii + uu == th)) eq_fire++;
            @(negedge clk);
        end
        in_valid = 0;
        repeat (4) @(negedge clk);
        if (checked_pipe != n) $fatal(1, "lif_pipe checked %0d of %0d vectors", checked_pipe, n);
        $display("PASS tb_lif: %0d vectors on lif_update and lif_pipe (%0d exact-threshold firings)",
                 n, eq_fire);
        $finish;
    end
endmodule
