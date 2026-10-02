# Vivado implementation results

Post-route numbers from scripts/vivado/build.tcl. `mvu` rows: the matrix-vector unit alone, out of context (only reg-to-reg paths are meaningful). `top` rows: the full board design. Cycles: simulation, 64x64 operation (mvu) or one neural update (top), no output stalls. Time = cycles / 100 MHz, shown only when post-route timing is met. Power reports in the per-build folders are Vivado ESTIMATES.

| target | config | vivado | part | LUT | FF | DSP | BRAM_tiles | LUTRAM | WNS_ns | WHS_ns | timing | cycles | time_us |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mvu | serial | 2025.2 | xc7a35tcpg236-1 | 344 | 550 | 5 | 1 | 44 | 0.229 | 0.088 | met @100MHz | 4163 | 41.63 |
| mvu | sys2x2_banked | 2025.2 | xc7a35tcpg236-1 | 705 | 715 | 4 | 1 | 72 | 2.719 | 0.016 | met @100MHz | 4163 | 41.63 |
| mvu | sys2x2_simple | 2025.2 | xc7a35tcpg236-1 | 671 | 710 | 4 | 1 | 48 | 3.326 | 0.040 | met @100MHz | 10305 | 103.05 |
| mvu | sys4x4_banked | 2025.2 | xc7a35tcpg236-1 | 838 | 879 | 16 | 2 | 92 | 3.193 | 0.135 | met @100MHz | 3649 | 36.49 |
| mvu | sys4x4_banked_wbuf2 | 2025.2 | xc7a35tcpg236-1 | 923 | 891 | 16 | 2 | 188 | 1.719 | 0.082 | met @100MHz | 1861 | 18.61 |
| mvu | sys4x4_banked_wbuf3 | 2025.2 | xc7a35tcpg236-1 | 923 | 903 | 16 | 2 | 188 | 1.514 | 0.029 | met @100MHz | 1269 | 12.69 |
| mvu | sys4x4_simple | 2025.2 | xc7a35tcpg236-1 | 833 | 882 | 16 | 1 | 92 | 1.719 | 0.092 | met @100MHz | 6721 | 67.21 |
| mvu | sys8x8_banked_wbuf2 | 2025.2 | xc7a35tcpg236-1 | 1628 | 1427 | 64 | 4 | 580 | 1.037 | 0.078 | met @100MHz | 905 | 9.05 |
| top | serial | 2025.2 | xc7a35tcpg236-1 | 2500 | 3996 | 5 | 2 | 44 | 0.574 | 0.044 | met @100MHz | 65799 | 657.99 |
| top | sys4x4_banked_wbuf2 | 2025.2 | xc7a35tcpg236-1 | 3430 | 3681 | 16 | 32 | 453 | 0.157 | 0.040 | met @100MHz | 28937 | 289.37 |
