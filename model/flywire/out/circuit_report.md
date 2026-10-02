# FlyWire subcircuit selection

Source: FlyWire Codex FAFB v783 export, 139255 neurons, 3732460 connections with >= 5 synapses.

Selected 256 neurons, 2296 internal connections (2265 with a fast transmitter sign; 1397 excitatory, 868 inhibitory).

| role | count |
|---|---|
| intermediate (food path left) | 79 |
| intermediate (food path right) | 74 |
| intermediate (threat path left) | 27 |
| intermediate (threat path right) | 20 |
| sensor: food (sugar GRN) | 16 |
| sensor: threat (looming) | 16 |
| output: escape-related | 8 |
| output: backward walking | 4 |
| output: steering | 4 |
| output: feeding (proboscis motor) | 4 |
| output: escape (giant fiber) | 2 |
| output: forward walking / approach | 2 |

## Input retained inside the subcircuit

Fraction of each neuron's input synapses that come from other selected neurons.

| group | median | min | max |
|---|---|---|---|
| intermediate | 0.10 | 0.00 | 1.00 |
| output | 0.11 | 0.02 | 0.38 |

## Outputs

| idx | type | side | inputs kept | reachable from food | from threat |
|---|---|---|---|---|---|
| 232 | DNp01 | left | 0.08 | yes | yes |
| 233 | DNp01 | right | 0.06 | yes | yes |
| 234 | DNp02 | left | 0.09 | yes | yes |
| 235 | DNp04 | left | 0.11 | yes | yes |
| 236 | DNp06 | left | 0.05 | yes | yes |
| 237 | DNp11 | left | 0.08 | yes | yes |
| 238 | DNp02 | right | 0.06 | yes | yes |
| 239 | DNp04 | right | 0.12 | yes | yes |
| 240 | DNp06 | right | 0.02 | yes | yes |
| 241 | DNp11 | right | 0.13 | yes | yes |
| 242 | MDN | left | 0.11 | yes | yes |
| 243 | MDN | left | 0.12 | yes | yes |
| 244 | MDN | right | 0.11 | yes | yes |
| 245 | MDN | right | 0.14 | yes | yes |
| 246 | DNp09 | left | 0.03 | yes | yes |
| 247 | DNp09 | right | 0.03 | yes | yes |
| 248 | DNa01 | left | 0.28 | yes | yes |
| 249 | DNa02 | left | 0.15 | yes | yes |
| 250 | DNa01 | right | 0.27 | yes | yes |
| 251 | DNa02 | right | 0.08 | yes | yes |
| 252 | CB0762 | left | 0.35 | yes | yes |
| 253 | CB0911 | left | 0.36 | yes | yes |
| 254 | CB0762 | right | 0.38 | yes | yes |
| 255 | CB0911 | right | 0.34 | yes | yes |

## Intermediate cell types (top 30 by count)

- LAL028 (intermediate (threat path left)): 3
- CB2820 (intermediate (food path right)): 3
- CB0219 (intermediate (food path right)): 2
- CB0226 (intermediate (food path left)): 2
- DNpe030 (intermediate (food path right)): 2
- DNge123 (intermediate (food path left)): 2
- PVLP024 (intermediate (threat path right)): 2
- PVLP151 (intermediate (threat path right)): 2
- PVLP024 (intermediate (threat path left)): 2
- DNge075 (intermediate (food path left)): 2
- CB0438 (intermediate (food path left)): 2
- CB0865 (intermediate (food path right)): 2
- CB3114 (intermediate (threat path left)): 2
- DNg67 (intermediate (food path right)): 2
- CB0362 (intermediate (food path left)): 2
- CB0441 (intermediate (food path left)): 2
- CB0283 (intermediate (food path left)): 2
- CB0118 (intermediate (food path left)): 2
- CB0597 (intermediate (food path left)): 2
- AN_multi_112 (intermediate (food path right)): 1
- AN_GNG_WED_1 (intermediate (food path left)): 1
- AN_GNG_81 (intermediate (food path right)): 1
- CB0008 (intermediate (food path left)): 1
- AN_multi_117 (intermediate (food path left)): 1
- AVLP429 (intermediate (threat path left)): 1
- AN_multi_41 (intermediate (threat path right)): 1
- CB0062 (intermediate (food path left)): 1
- CB0062 (intermediate (food path right)): 1
- CB0095 (intermediate (threat path left)): 1
- CB0070 (intermediate (food path right)): 1
