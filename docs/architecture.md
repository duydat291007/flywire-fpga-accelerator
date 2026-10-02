# Architecture and dataflow

![block diagram](architecture.svg)

## 1. System

```
 switches/buttons ──► input_conditioner (sync, debounce, edge) ──► step pacing
                                                                     │ step_req
 ┌──────────────────────────── fly_core ────────────────────────────▼──────────┐
 │ boot loader: ROM ──► MVU weight port (4096 writes after every reset)        │
 │                                                                             │
 │ state banks: V[2][64] (u16), s[2] (64 bits), select bit `cur`               │
 │      s[cur] ──bulk load──► MVU ──y[i] in order──► lif_update ──► bank !cur  │
 │                                                    ▲ U[i]                    │
 │ fly_world: positions, sensors ─────────────────────┘                        │
 │            motor window ◄── committed spikes; move/eat/caught/LFSR         │
 └───────────┬─────────────────────────────────────────────────────────────────┘
             │ commit, spikes, state
             ▼
   telemetry: activity counters ─► snapshot (1 cycle) ─► packet + CRC ─► uart_tx ─► RsTx
```

The accelerator (`mvu_serial` / `mvu_systolic`) knows nothing about neurons,
UART, or the board. `fly_core` uses only its public ports.

## 2. Matrix-vector unit (MVU)

Both implementations share the ports and behavior in `docs/specification.md` §2:
valid/ready writes, one command at a time, results buffered and streamed in
order, `busy`/`done`/`err_dim`, synchronous reset that aborts.

### 2.1 Serial baseline (`mvu_serial`)

One weight read per cycle (dst-major), one signed 8×8 multiply and a 32-bit
accumulate per cycle, result buffer written at the end of each row.

| Phase | Cycles (dim n) |
|---|---|
| issue + MAC | n² |
| pipeline flush | 2 |
| drain (no stalls) | n |
| done | 1 |
| **total, n = 64** | **4163** (measured) |

### 2.2 Systolic engine (`mvu_systolic`)

Weight-stationary `ROWS × COLS` array. PE[r][c] holds
`W[og·COLS + c][ig·ROWS + r]` for tile (og, ig). x enters row r with r cycles of
skew and moves right; partial sums move down; each column's result leaves the
bottom row. Every hop is a register (`systolic_pe`).

```
            x[ig·R+0] ─►[PE00]─►[PE01]─►[PE02]─►[PE03]
                          │      │      │      │
   (1 cycle later)  x[+1]─►[PE10]─►[PE11]─►[PE12]─►[PE13]
                          │      │      │      │        partial sums move down,
   (2 later)        x[+2]─►[PE20]─►[PE21]─►[PE22]─►[PE23]  x moves right,
                          │      │      │      │        one register per hop
   (3 later)        x[+3]─►[PE30]─►[PE31]─►[PE32]─►[PE33]
                          ▼      ▼      ▼      ▼
                       y-piece for outputs og·C+0 .. og·C+3  (column c at L+R+c)
```

Three agents run concurrently:

* **Loader** reads one tile's weights into weight buffer `k mod WBUF` of every PE:
  `LSTEPS = ROWS·COLS` cycles from a single memory (`BANKED=0`), or
  `LSTEPS = ROWS` cycles from `COLS` banks (`BANKED=1`, bank = dst mod COLS, one
  PE row per cycle). Out-of-range weights of partial tiles are written as 0.
  It may start a tile only when that buffer is free.
* **Launcher** sends one skewed wavefront per loaded tile. The wavefront
  carries its buffer index (`xsel`) and tag `{og, first_ig, last_ig}`, so each
  PE switches buffers exactly when the wavefront reaches it: there is no global
  swap signal.
* **Collector** accumulates each column across the `NIG` tiles of an output
  group (32-bit), writes finished results into one result bank per column
  (`dst mod COLS`, never two writes to one bank in a cycle), and frees the
  tile's weight buffer when column `COLS-1` finishes.

### 2.3 Cycle-level schedule (4×4, banked)

`S` = cycle a tile's load starts (relative numbers, measured in simulation):

| Cycle | Event |
|---|---|
| S .. S+3 | 4 bank reads issued (one PE row per cycle) |
| S+1 .. S+4 | rows 0–3 written into weight buffer |
| S+5 | `ld_done` visible; launcher registers x values |
| S+6 | PE[0][0] computes (row r, column c compute at S+6+r+c) |
| S+10 .. S+13 | column c result valid at S+10+c |
| S+14 | buffer free again |

A buffer is therefore occupied for `T_occ = LSTEPS + ROWS + COLS + 2` cycles.
With WBUF buffers and a loader that needs `LSTEPS` cycles per tile:

```
cycles per tile ≈ max(LSTEPS, T_occ / WBUF)
```

| Configuration | LSTEPS | T_occ | Predicted /tile | Measured dim-64 total | Measured /tile |
|---|---|---|---|---|---|
| 4×4 simple, WBUF=1 | 16 | 26 | 26 | 6721 | (6721−65)/256 = 26.0 |
| 4×4 banked, WBUF=1 | 4 | 14 | 14 | 3649 | 14.0 |
| 4×4 banked, WBUF=2 | 4 | 14 | 7 | 1861 | 7.0 |

(65 = 64 drain cycles + done. See `docs/optimization.md` for all configurations.)

### 2.4 Why more PEs do not help this workload linearly

A matrix-**vector** product uses every weight exactly once. The array can never
perform more useful MACs per cycle than the memory delivers weights per cycle:
1 (simple) or COLS (banked). A 4×4 banked array has 16 multipliers but at most
4 weights/cycle, so even a perfect schedule keeps ≤ 25 % of PEs busy. Weight
reuse needs several independent input vectors (batching), which the recurrent
network cannot provide: step t+1 needs the spikes of step t. This is recorded
as a measured limitation, not hidden.

## 3. Neural timestep (`fly_core`)

| State | Cycles | Action |
|---|---|---|
| IDLE | — | accept `step_req` (after boot), latch food/threat presence |
| XLOAD | 1 | bulk-load `x = s[cur]` (64 bits in one transfer) |
| CMD | 1 | `dim = 64` |
| RES | MVU latency | each result `y[i]` → LIF(V[cur][i], y[i], U[i]) → bank `!cur` |
| COMMIT | 1 | `cur ^= 1`, `step += 1`, record cycles |
| WORLD | 1 | motor window, move, eat/caught, respawns, LFSR |

Measured cycles per neural update (accept → commit): **1863** (4×4 banked,
WBUF=2), **4165** (serial), **6723** (4×4 simple). At 100 MHz: 18.6 µs,
41.7 µs, 67.2 µs. The board runs 100 steps/s, so the engine is busy < 0.7 % of
the time even with the serial baseline: the application does not need the
accelerator's speed. The accelerator is benchmarked on its own (§2).

Consistency rule: LIF reads only bank `cur`, writes only bank `!cur`, every
neuron exactly once per step (assertions `a_single_write`, `a_commit_complete`,
`a_bank_only_at_commit`). A mutant that reads the wrong bank is caught by the
800-step full-state comparison.

## 4. Telemetry path

Activity counters (64 × 4-bit, saturating) increment on each commit. Every
`PERIOD` cycles a snapshot is requested; it is captured in one cycle while the
engine is idle, copied into snapshot registers, and the counters restart.
The serializer sends the 80 snapshot bytes as one little-endian vector,
updating CRC-16/CCITT-FALSE as each byte is accepted, then the two CRC bytes.
If a tick arrives while a packet is pending or being sent, that snapshot is
dropped and counted; nothing else is lost. Details: `docs/specification.md` §6.

## 5. Clocking and reset

Single 100 MHz clock. Slower behaviors (pacing, debounce, baud) use counters
and enables. Reset is synchronous active-high, from power-on (FPGA register
initial values) or the debounced center button. Memories (weights ROM/RAM,
result banks) are not reset; the boot loader rewrites all weights after every
reset, and the protocol never reads a result bank before writing it.
