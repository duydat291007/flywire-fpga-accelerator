# MVU cycle counts (simulation)

Identical workload for every configuration; every result checked against the model. Cycles from command acceptance to `done`, including result drain, excluding the external weight/x load (same for all). Clock rate is not part of this table: see `reports/impl/results.md` for post-route timing.

## Cycles per operation, no output stalls

| Config | PEs | dim 1 | dim 2 | dim 4 | dim 5 | dim 8 | dim 16 | dim 17 | dim 32 | dim 33 | dim 48 | dim 63 | dim 64 | speedup vs serial (dim 64) | useful MAC/cycle (dim 64) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| serial | 1 | 5 | 9 | 23 | 33 | 75 | 275 | 309 | 1059 | 1125 | 2355 | 4035 | 4163 | 1.00x | 0.98 |
| 2x2 simple wbuf1 | 4 | 12 | 13 | 45 | 96 | 169 | 657 | 828 | 2593 | 2924 | 5809 | 10304 | 10305 | 0.40x | 0.40 |
| 2x2 banked wbuf1 | 4 | 10 | 11 | 37 | 78 | 137 | 529 | 666 | 2081 | 2346 | 4657 | 8256 | 8257 | 0.50x | 0.50 |
| 2x2 banked wbuf2 | 4 | 10 | 11 | 23 | 46 | 75 | 275 | 346 | 1059 | 1194 | 2355 | 4162 | 4163 | 1.00x | 0.98 |
| 4x4 simple wbuf1 | 16 | 28 | 29 | 31 | 110 | 113 | 433 | 668 | 1697 | 2140 | 3793 | 6720 | 6721 | 0.62x | 0.61 |
| 4x4 simple wbuf2 | 16 | 28 | 29 | 31 | 80 | 83 | 283 | 428 | 1067 | 1340 | 2363 | 4170 | 4171 | 1.00x | 0.98 |
| 4x4 banked wbuf1 | 16 | 16 | 17 | 19 | 62 | 65 | 241 | 368 | 929 | 1168 | 2065 | 3648 | 3649 | 1.14x | 1.12 |
| 4x4 banked wbuf2 | 16 | 16 | 17 | 19 | 38 | 41 | 133 | 200 | 485 | 608 | 1061 | 1860 | 1861 | 2.24x | 2.20 |
| 4x4 banked wbuf3 | 16 | 16 | 17 | 19 | 34 | 37 | 101 | 144 | 341 | 420 | 729 | 1268 | 1269 | 3.28x | 3.23 |
| 4x4 banked wbuf4 | 16 | 16 | 17 | 19 | 32 | 35 | 91 | 128 | 299 | 368 | 635 | 1098 | 1099 | 3.79x | 3.73 |
| 8x8 banked wbuf2 | 64 | 28 | 29 | 31 | 32 | 35 | 77 | 148 | 249 | 372 | 525 | 904 | 905 | 4.60x | 4.53 |
| 8x8 banked wbuf4 | 64 | 28 | 29 | 31 | 32 | 35 | 67 | 108 | 179 | 252 | 355 | 594 | 595 | 7.00x | 6.88 |

Useful MAC/cycle = 4096 multiply-accumulates / total cycles (drain included). An array of P PEs could at best reach P; weight bandwidth (1 or COLS weights per cycle) is the real bound for matrix-vector products (docs/architecture.md 2.4).

## Output-stall overhead, dim 64

| Config | 0 % | 25 % | 50 % | 75 % | 90 % | extra cycles at 50 % |
|---|---|---|---|---|---|---|
| serial | 4163 | 4179 | 4225 | 4360 | 4774 | 62 |
| 2x2 simple wbuf1 | 10305 | 10336 | 10357 | 10522 | 10744 | 52 |
| 2x2 banked wbuf1 | 8257 | 8278 | 8337 | 8487 | 8748 | 80 |
| 2x2 banked wbuf2 | 4163 | 4191 | 4222 | 4360 | 4728 | 59 |
| 4x4 simple wbuf1 | 6721 | 6740 | 6798 | 6879 | 7251 | 77 |
| 4x4 simple wbuf2 | 4171 | 4189 | 4258 | 4308 | 4691 | 87 |
| 4x4 banked wbuf1 | 3649 | 3668 | 3716 | 3796 | 4292 | 67 |
| 4x4 banked wbuf2 | 1861 | 1882 | 1943 | 2037 | 2545 | 82 |
| 4x4 banked wbuf3 | 1269 | 1301 | 1325 | 1455 | 1782 | 56 |
| 4x4 banked wbuf4 | 1099 | 1120 | 1164 | 1310 | 1747 | 65 |
| 8x8 banked wbuf2 | 905 | 927 | 969 | 1046 | 1439 | 64 |
| 8x8 banked wbuf4 | 595 | 612 | 644 | 776 | 1146 | 49 |

Stalls only lengthen the drain: all arithmetic finishes before the first result is offered, so overhead is independent of the engine and roughly dim × p/(1−p) cycles for stall probability p (random, deterministic seed).
