# Specification

Project: **SystemVerilog Systolic Neural Accelerator with UVM Verification and Live USB Visualization**

Status: v2.0. v1 (written before the RTL) used a hand-designed 64-neuron network.
v2 replaces it with a 256-neuron subcircuit of the FlyWire adult fly brain connectome
(FAFB v783) and a heading-based world; see `docs/flywire.md` for how the circuit was
chosen and what is and is not taken from FlyWire. Where implementation forced a
decision, the change is recorded in `docs/bug_journal.md` or `docs/architecture.md`.

The network is a reduced, simplified subcircuit (integer LIF neurons, synapse counts as
weights). It is not a faithful simulation of a fly brain. It has no learning.

---

## 1. Conventions

| Item | Convention |
|---|---|
| Matrix index | `W[destination][source]`; rows = destinations, columns = sources |
| Operation | `y[i] = sum_{j=0}^{dim-1} W[i][j] * x[j]` for `i = 0 .. dim-1` |
| Clock | One 100 MHz clock (`clk`). Everything else uses clock enables. |
| Reset | Synchronous, active-high `rst` inside the design. |
| Multi-byte fields on UART | Little-endian (least significant byte first) |
| Signedness | Every signed signal is declared `signed`; casts are explicit |

---

## 2. Matrix-vector unit (MVU)

Two interchangeable implementations share one port list:

* `mvu_serial` – one multiply-accumulate per clock (baseline).
* `mvu_systolic` – weight-stationary `ROWS x COLS` systolic array (default 4 x 4).

### 2.1 Parameters

| Parameter | Default | Legal | Meaning |
|---|---|---|---|
| `N_MAX` | 64 (fly_core uses 256) | power of 2, 4..256 | Largest supported dimension |
| `ROWS` | 4 | power of 2, divides `N_MAX` | PE rows = sources per tile (systolic only) |
| `COLS` | 4 | power of 2, divides `N_MAX` | PE columns = destinations per tile (systolic only) |
| `BANKED` | 1 | 0/1 | 0: one weight memory, 1 weight/cycle. 1: `COLS` banks, `COLS` weights/cycle |
| `WBUF` | 2 | 1..4 | Weight buffers per PE. 1 = load then compute; 2+ = load next tile while computing |

### 2.2 Numeric format and range proof

| Signal | Type | Range |
|---|---|---|
| weight `w` | signed 8 | -128..127 |
| input `x` | signed 8 | -128..127 |
| product `w*x` | signed 16 (`$signed(w) * $signed(x)`) | -16256..+16384 |
| product widened | signed 32, sign-extended | same |
| partial sum / accumulator / result | signed 32 | see below |

For `dim <= 256` the sum of `dim` products lies in
`[256 * -16256, 256 * 16384] = [-4,161,536, +4,194,304]`.
A signed 24-bit value covers `[-8,388,608, +8,388,607]`, so 24 bits suffice; 32 bits give
8 bits of headroom. **No legal input can overflow.** The adders are ordinary 32-bit two's
complement adders (wrap-around is the formal semantics, but it is unreachable). No
saturation, rounding, or truncation occurs anywhere in the MVU datapath.

The generic ports keep full signed-INT8 inputs so the engine can be exercised and
benchmarked independently of the spiking application.

### 2.3 Ports

```
clk, rst

// Weight write port (valid/ready)
w_valid, w_ready, w_dst[AW-1:0], w_src[AW-1:0], w_data[7:0] (signed)

// Input-vector write port (valid/ready), one element per transfer
x_valid, x_ready, x_idx[AW-1:0], x_data[7:0] (signed)

// Binary bulk load: x[j] = bits[j] ? 1 : 0 for all j < N_MAX, in one transfer
xb_valid, xb_ready, xb_bits[N_MAX-1:0]

// Command
cmd_valid, cmd_ready, cmd_dim[DW-1:0]

// Result stream
res_valid, res_ready, res_data[31:0] (signed), res_idx[AW-1:0], res_last

// Status
busy, done, err_dim
```
`AW = log2(N_MAX)`, `DW = log2(N_MAX) + 1`.

A transfer on any valid/ready port happens on a rising edge where `valid && ready`.

### 2.4 Behavior

| Topic | Rule |
|---|---|
| Idle | `busy = 0`. `cmd_ready = w_ready = x_ready = xb_ready = 1`. |
| Command acceptance | `cmd_valid && cmd_ready`. `cmd_dim` is latched; later changes on the port have no effect. |
| Legal dimension | `1 <= cmd_dim <= N_MAX` |
| Invalid dimension | Command is accepted, no computation starts, `busy` stays 0, no result is produced, and in the next cycle `done = 1` and `err_dim = 1` for one cycle. |
| Busy | `busy = 1` from the cycle after a legal command is accepted until the cycle in which the last result is accepted, inclusive. |
| Writes while busy | `w_ready`, `x_ready`, `xb_ready` are 0 while busy. Writes are stalled (backpressured), never dropped or applied mid-operation. |
| Output order | `res_idx = 0, 1, ..., dim-1`. `res_last = 1` only on `res_idx = dim-1`. Exactly `dim` results per legal command. |
| Backpressure | While `res_valid && !res_ready`, `res_data`, `res_idx`, `res_last` hold and `res_valid` stays 1. All arithmetic is finished before the first result is offered, so output stalls cannot corrupt computation. |
| Retirement / done | The operation retires on the edge where the `res_last` transfer happens. In the following cycle `busy = 0` and `done = 1` for exactly one cycle (`err_dim = 0`). A new command may be accepted in that cycle. |
| Outstanding operations | One. |
| Reset | Synchronous. Aborts any operation: next cycle `busy = 0`, `res_valid = 0`, `done = 0`, internal valid bits cleared. Weight and input memories are **not** cleared (block/distributed RAM); their contents after power-up are undefined until written. |
| Stale state | No accumulator, PE weight, or pipeline value from a previous or aborted command may affect a later command. |
| Values outside `dim` | Weights `W[i][j]` or inputs `x[j]` with `i >= dim` or `j >= dim` never affect results, whatever the memory holds. |

---

## 3. Neuron model

Per neuron, per timestep `t -> t+1`, bit-accurate in RTL and in `model/`:

```
leaked    = (15 * V[t]) >> 4                    # = floor(15*V/16), V >= 0
candidate = leaked + I[t] + U[t]
if candidate >= THRESHOLD:  s[t+1] = 1; V[t+1] = 0
else:                       s[t+1] = 0; V[t+1] = max(0, candidate)
```

| Quantity | Width | Range / rule |
|---|---|---|
| `V` stored potential | unsigned 16 | invariant `0 <= V < THRESHOLD` |
| `THRESHOLD` | unsigned 16 | `1..65535` (build-time constant from the network file) |
| `15*V` | unsigned 20 | `<= 983,025 < 2^20` |
| `leaked` | unsigned 16 | `<= V` |
| `I[t] = y[i]` | signed 32 | MVU output with `x = s[t]` |
| `U[t]` | unsigned 8 | external (sensory) input |
| `candidate` | signed 34 | `leaked + I + U`, all zero/sign-extended to 34 bits; cannot overflow for any 32-bit `I` |
| stored `V[t+1]` | unsigned 16 | `candidate[15:0]` when `0 <= candidate < THRESHOLD`; else 0 |

Equality with the threshold fires. No refractory period. No learning.

**Timestep consistency.** Every neuron's update for `t+1` uses the spike vector `s[t]`.
State lives in two banks (current / next). Updates read only the current bank and
write only the next bank. The bank-select bit toggles once, after all neurons are
written. Telemetry reads the current bank only when no update is in progress.

---

## 4. Neural step, world, and virtual pet

### 4.1 One timestep (in this order)

1. Compute `U[t]` from the world state at step `t` (sensors).
2. Load `x = s[t]` into the MVU (binary bulk load), run `y = W s[t]` with `dim = 256`.
3. For `i = 0..255` in result order: LIF update, write next bank.
4. Commit: toggle bank select; `step = step + 1`.
5. World update from `s[t+1]` (section 4.3).

### 4.2 Neuron roles (256 neurons, FlyWire subcircuit)

| Index | Role |
|---|---|
| 0-7, 8-15 | Food sensors left, right: sugar/water gustatory receptor neurons |
| 16-23, 24-31 | Threat sensors left, right: LPLC2 / LC4 looming detectors |
| 32-231 | Intermediate neurons on the strongest sensor-to-output paths |
| 232-233 | Giant fiber DNp01 left, right (escape) |
| 234-241 | DNp02, DNp04, DNp06, DNp11 left then right (escape-related) |
| 242-245 | MDN (backward walking) |
| 246-247 | DNp09 left, right (forward walking) |
| 248-249, 250-251 | DNa01, DNa02 left; DNa01, DNa02 right (steering) |
| 252-255 | Proboscis motor neurons (feeding) |

`W[post][pre] = sign(pre) * min(127, 2 * synapse_count)`; sign +1 for acetylcholine, -1 for
GABA and glutamate, modulatory transmitters dropped. Generated by
`model/flywire/select_circuit.py` and `model/fly_model/network.py`.

### 4.3 World v2 (integer)

| Item | Rule |
|---|---|
| Arena | `x, y` in `0..63`; `y` grows downward; heading `h` in `0..7` (0 = +x, 45 degree steps clockwise) |
| Reset state | fly (32,32) heading 0, food (8,12), threat (56,52), counters 0, LFSR `0xACE1` |
| Food / threat present | board switches (level) |
| Side of a target | `sign(DX[h] * dy - DY[h] * dx)`: -1 left, +1 right, 0 straight ahead/behind (both sides) |
| Food sensors | if food present and Chebyshev distance `<= 3`: 60 to each sugar sensor on that side |
| Threat sensors | if threat present and distance `d <= 12`: `40 + 5 * (12 - d)` to each looming sensor on that side |
| Motor window | every 8 steps, count spikes of: giant fiber, MDN, DNp09, steer L, steer R, proboscis |
| Action (priority order) | 1. giant fiber `>= 1`: jump 6 cells away from the threat (if a wall blocks, try headings +1, -1, +2, -2). 2. proboscis `>= 2` and food within 3: eat, `eaten += 1`, food moves to `(lfsr[5:0], lfsr[11:6])`. 3. turn one step if steer R - L `>= 2` (right) or `<= -2` (left), else a random turn when `lfsr[2:0] == 0` (direction `lfsr[3]`); then walk 1 cell backward if MDN - DNp09 `>= 2`, else forward; a wall instead turns the fly around |
| Threat pursuit | every 3rd motor window the threat steps one cell toward the fly |
| Caught | threat present and distance `<= 1`: `caught += 1`, threat moves to the point diagonally opposite the fly (`+32` mod 64 on each axis) |
| Food button | food placed 5 cells ahead of the fly (clamped) |
| Threat button | threat placed 8 cells to the fly's left (`lfsr[0] = 0`) or right (`lfsr[0] = 1`), clamped |
| LFSR | 16-bit Fibonacci, taps 16,14,13,11; advances once per step (after everything else) |

Button presses are latched and applied at the next step's world update. The fly moves
only from output-neuron spike counts; nothing maps a button or a target position
directly to a movement choice. Default forward walking, random turns, and the threat
pursuer are world assumptions, not FlyWire circuitry (`docs/flywire.md`).

---

## 5. Board I/O (Basys 3, XC7A35T-1CPG236C)

Pin names follow Digilent's `Basys-3-Master.xdc`.

| Port | Pin | Function |
|---|---|---|
| `clk` | W5 | 100 MHz |
| `btnC` | U18 | reset |
| `btnU` | T18 | single step (when paused) |
| `btnL` | W19 | place food ahead of the fly |
| `btnR` | T17 | place threat beside the fly |
| `sw[0]` | V17 | 1 = run, 0 = pause |
| `sw[1]` | V16 | food present |
| `sw[2]` | W16 | threat present |
| `sw[3]` | W17 | slow mode (10 steps/s instead of 100) |
| `sw[9:5]` | T3, V2, W13, W14, V15 | potential-probe group (neurons `8*sw[9:5] .. +7`) |
| `RsTx` | A18 | UART **output from FPGA** to the USB-UART bridge |
| `led[*]` | see XDC | status |

Buttons: 2-flop synchronizer, 10 ms debounce, rising-edge pulse. Switches: 2-flop
synchronizer and debounce. The reset button is synchronized and debounced; a power-on
reset also runs at configuration.

---

## 6. UART telemetry

115200 baud, 8 data bits, no parity, 1 stop bit (8N1), LSB first. Divisor
`round(100e6 / 115200) = 868` (actual 115,207 baud, +0.006 %).

### 6.1 Packet v2 (119 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | sync `0xA5` |
| 1 | 1 | sync `0x5A` |
| 2 | 1 | version `0x02` |
| 3 | 1 | payload length = 113 (bytes 4..116) |
| 4 | 2 | sequence number (wraps at 65536) |
| 6 | 4 | step |
| 10 | 1 | flags: b0 running, b1 food present, b2 threat present, b3 a snapshot was dropped since the previous packet, b4 engine is systolic |
| 11 | 2 | total dropped snapshots (saturating) |
| 13 | 4 | cycles for the last neural update (step start to commit) |
| 17 | 6 | fly x, fly y, food x, food y, threat x, threat y (1 byte each) |
| 23 | 1 | heading (bits 2..0) and last action (bits 6..4: 0 walk, 1 back, 2 jump, 3 eat, 4 wall turn) |
| 24 | 2 | eaten (wraps) |
| 26 | 2 | caught (wraps) |
| 28 | 2 | jumps (wraps) |
| 30 | 6 | spike counts of the last motor window: giant fiber, MDN, DNp09, steer L, steer R, proboscis |
| 36 | 64 | activity: neuron `4k+m` in bits `2m+1..2m` of byte `36+k`; count = spikes since previous snapshot, saturating at 3 |
| 100 | 1 | probe base neuron (`8 * group`) |
| 101 | 16 | potentials of neurons `probe_base .. probe_base+7`, u16 each (refreshed once per step) |
| 117 | 2 | CRC-16/CCITT-FALSE over bytes 2..116, low byte first |

CRC-16/CCITT-FALSE: poly `0x1021`, init `0xFFFF`, no reflection, no final XOR
(check value for ASCII `"123456789"` is `0x29B1`).

### 6.2 Link budget

119 bytes x 10 bit-times = 1190 bits = 10.3 ms per packet, so at most 96 packets/s.
Default telemetry period 20 ms (50 packets/s) uses 52 % of the link. At 100 steps/s a
packet covers 2 steps, so a 2-bit count (max 3) never saturates at default rates.

### 6.3 Snapshot and overflow rules

* A telemetry timer fires every `TELEM_PERIOD` cycles (default 2,000,000).
* A snapshot is captured in a single cycle, only while the neural engine is idle
  (between timesteps), so all fields describe the same committed step.
* If the transmitter is still sending the previous packet when the timer fires, that
  snapshot is **dropped**: the drop counter increments and flag b3 is set in the next
  packet. Activity counters keep accumulating, so no spikes are lost from the counts
  (they may saturate at 3).
* Activity counters are copied and cleared in the capture cycle. Because capture only
  happens when no commit occurs in that cycle, no spike event can be lost at the
  boundary.

### 6.4 Receiver

The laptop parser scans for `A5 5A`, checks version and length, waits for the whole
packet, checks the CRC. On any mismatch it discards one byte and rescans. It counts
good packets, CRC errors, discarded bytes, and sequence gaps.

---

## 7. Open items

* Bidirectional UART control: optional, not in v1.
* Per-neuron thresholds, refractory periods, fixed-point parameters: out of scope.
