# Closed-loop behaviour of the FlyWire network (reference model)

40 trials per scenario, horizon 320 timesteps (40 motor windows). Weight scale 2, threshold 100. Fast simulator verified step-for-step against fly_model.world.FlySim.

| scenario | success | FlyWire circuit | all synapses removed | median latency (circuit) |
|---|---|---|---|---|
| food | ate the food | 35/40 | 0/40 | 21 steps to eating |
| threat | escaped (not caught) | 39/40 | 29/40 | 6 steps to first jump |

Lesioned fly: sensors still receive input, but nothing propagates, so it never feeds or jumps; its escapes come only from the default walk.
