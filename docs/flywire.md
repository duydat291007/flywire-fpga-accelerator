# FlyWire subcircuit (network v2)

Status:

- **Model:** the Python reference model runs the FlyWire network in a closed loop.
- **RTL:** ported to 256 neurons (fly_core, world v2, telemetry packet v2, board top, dashboard).
- **Simulated in the cloud:** Verilator and Icarus. The full 700-step closed-loop trace matches the model bit-for-bit for the serial, 2×2, 4×4 and 8×8 engines.
- **Not done yet:** Vivado/XSim on Dat's machine and testing on the board.

## Data

- Source: FlyWire Codex, dataset **FAFB v783**, downloaded 2026-10-01 from <https://codex.flywire.ai/api/download>. You need to sign in, and the download requires agreeing to the FlyWire citation guidelines.
- Files, kept in `data/flywire/` and not committed (git-ignored):
  - `connections_princeton.csv.gz` (Connections, Filtered)
  - `classification.csv.gz`
  - `consolidated_cell_types.csv.gz`
  - `neurons.csv.gz` (neurotransmitter predictions)
  - `names.csv.gz`
- Install its extra Python packages with `.venv/bin/pip install -r requirements-flywire.txt`. Codex files track the live database, so a later download may differ slightly from this one and from the October 2024 publication snapshot.
- Citation: follow the FlyWire citation guidelines. The core references are Dorkenwald et al., *Nature* 2024 (connectome) and Schlegel et al., *Nature* 2024 (annotations).

## Pipeline

```
data/flywire/*.csv.gz
   -> model/flywire/select_circuit.py   -> model/flywire/out/circuit_neurons.csv, circuit_edges.csv, circuit_report.md
   -> model/fly_model/network.py         (weights: sign * min(127, 2 * synapses))
   -> model/flywire/behavior_check.py    -> model/flywire/out/behavior_report.md
```

The files in `model/flywire/out/` are small derived data and are committed, so the rest of the flow works without the raw download.

## Selection method (`select_circuit.py`)

1. Sum connections across neuropils for each (pre, post) pair, and keep pairs with 5 or more synapses (the FlyWire convention).
2. Sign each connection by the presynaptic neuron's predicted transmitter: ACh is +1; GABA and glutamate are -1; dopamine, serotonin and octopamine (modulatory) are dropped.
3. Fixed endpoints:
   - Sensors: 8 sugar/water gustatory neurons per side and 8 LPLC2/LC4 looming detectors per side. On each side, the sensors with the strongest multi-hop reach to the outputs are kept.
   - Outputs: giant fiber DNp01, DNp02/04/06/11, MDN, DNp09, and DNa01/DNa02 (both sides), plus the 2 proboscis motor neurons per side most strongly reached from the chosen sugar neurons.
4. Intermediates come from the strongest paths. Edge cost is -log of the fraction of the postsynaptic neuron's input that the connection supplies. Four pathways (food/threat × left/right) take turns adding their next-best path to their next target. Edges already used are penalised, so later paths explore alternatives.

## What is and is not FlyWire

| From FlyWire, unmodified | Our modelling choices |
|---|---|
| Which neurons are connected | Neuron model: integer LIF, threshold 100, leak 15/16 |
| Synapse counts, which give weight magnitudes | One global gain (×2) and the 8-bit clip at ±127 |
| Excitatory/inhibitory sign, from transmitter predictions | Which 256 neurons are kept (selection method above) |
| Cell identities (types, sides, root IDs) | The world: sensor drive levels, motor decoding, a default forward walk, random turns, the pursuing threat |

**Known limits:**

- Cutting 256 neurons out of 139,255 removes most inputs. The median intermediate neuron keeps about 10% of its input synapses, and the outputs keep 3–27% (see `circuit_report.md`).
- Synapse count is only a proxy for synaptic strength.
- Modulatory transmitters are ignored.
- Sugar neurons are contact chemoreceptors. Here they respond within 3 cells of the food.
- The fly walks forward by default, because walking rhythm generators are in the ventral nerve cord, which FAFB does not include.

## Index layout (also in `model/fly_model/network.py`)

| Indices | Neurons |
|---|---|
| 0–7 | Food sensors, left |
| 8–15 | Food sensors, right |
| 16–23 | Threat sensors, left |
| 24–31 | Threat sensors, right |
| 32–231 | Intermediates |
| 232–233 | Giant fiber (DNp01) |
| 234–241 | Other escape descending neurons |
| 242–245 | MDN |
| 246–247 | DNp09 |
| 248–251 | Steering (DNa01/DNa02), left then right |
| 252–255 | Proboscis motor neurons |

## World v2 (`model/fly_model/world.py`)

The fly has a position and one of 8 headings. Sensing is egocentric: each target is to the left or right of the heading.

Every 8 timesteps, one action is chosen from the motor spike counts, in this order of priority:

1. **Escape jump:** 1 or more giant-fiber spikes make the fly jump 6 cells away from the threat. If walls block that direction, it tries headings up to ±135° away, so a cornered fly can escape along a wall.
2. **Eat:** 2 or more proboscis motor spikes while the food is within taste range.
3. **Turn:** if the steering difference (right − left) is at least 2; otherwise a random turn about 1 in 8 of the time.
4. **Walk:** backward if MDN − DNp09 ≥ 2, otherwise forward.

The buttons place objects relative to the fly:

- **Food button:** food appears 5 cells ahead.
- **Threat button:** the threat appears 8 cells to one side, then pursues the fly at 1 cell every 3 windows.

## Behaviour (`behavior_report.md`)

40 trials per scenario; "lesioned" means every synapse is removed:

| Scenario | FlyWire circuit | Lesioned |
|---|---|---|
| Food: ate the food | 35/40, median 21 steps | 0/40 |
| Threat: escaped | 38/40, first jump after a median of 6 steps | 29/40 |

These results hold across weight gains of ×1, ×2 and ×4, so they don't depend on fine-tuning.
