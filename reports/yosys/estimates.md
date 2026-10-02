# Yosys resource ESTIMATES (not Vivado results)

Tool: Yosys 0.33 (git sha1 2584903a060), `synth_xilinx -family xc7 -flatten`, RTL converted with sv2v. No placement, routing, or timing. MVU rows are the unit alone; basys3_top rows are the whole design. Device capacity (XC7A35T): 20,800 LUT, 41,600 FF, 90 DSP, 50 RAMB36 (100 RAMB18).

| config | LUT | FF | DSP48E1 | RAMB18 | RAMB36 | LUTRAM_cells | SRL | CARRY4 |
|---|---|---|---|---|---|---|---|---|
| mvu serial | 413 | 595 | 1 | 0 | 1 | 11 | 0 | 8 |
| mvu 2x2 simple wbuf1 | 637 | 740 | 5 | 0 | 1 | 12 | 7 | 47 |
| mvu 2x2 banked wbuf2 | 672 | 775 | 5 | 2 | 0 | 12 | 7 | 47 |
| mvu 4x4 simple wbuf1 | 784 | 1002 | 17 | 0 | 1 | 24 | 6 | 62 |
| mvu 4x4 banked wbuf1 | 803 | 999 | 17 | 4 | 0 | 24 | 6 | 63 |
| mvu 4x4 banked wbuf2 | 935 | 1137 | 17 | 4 | 0 | 24 | 6 | 63 |
| mvu 4x4 banked wbuf3 | 812 | 893 | 17 | 4 | 0 | 56 | 6 | 63 |
| mvu 8x8 banked wbuf2 | 1781 | 2417 | 64 | 8 | 0 | 48 | 37 | 101 |
| basys3_top serial | 3099 | 3858 | 2 | 0 | 2 | 11 | 0 | 270 |
| basys3_top 4x4 banked wbuf2 | 3564 | 4295 | 17 | 4 | 1 | 24 | 6 | 314 |
