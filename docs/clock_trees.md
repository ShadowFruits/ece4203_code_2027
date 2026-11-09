# Clock tree synthesis variants (sky130hd)

Three designs, from small to large, each with a `CTS` switch on the `make`
command line. Every choice runs in its own directory, and `make clock_report`
adds the tree's numbers to the run's reports and to `make metrics`.

```bash
cd openroad_flow
make CTS=buf2                       # registered_adder (the default design)
make CTS=buf2 clock_report          # clock_report.txt + numbers for make metrics
make CTS=buf2 gui_cts               # open the tree in the GUI after CTS
make cts_variants                   # every choice, clock reports, then metrics

make DESIGN=aes CTS=small           # aes: sink clustering choices
make DESIGN=aes cts_variants        # ~20 min per run

make metrics                        # metrics/metrics.md, "Clock tree" table at the end
```

| Design | Flops | Switch | Choices | Where it's defined |
|---|---|---|---|---|
| `registered_adder` | 194 | `CTS` | `base` · `buf1` · `buf2` · `dist` · `nodummy` | `designs/sky130hd/registered_adder/config.mk` |
| `aes` | 562 | `CTS` | `base` · `small` · `large` · `noclust` | `designs/sky130hd/aes/config.mk` |
| `adder64_pipelined` | 6,370 | (none) | one run, `make DESIGN=adder64_pipelined` | `designs/sky130hd/adder64_pipelined/config.mk` |

Placement is the same for every choice of a design. Only CTS and the steps after
it change.

## What each run shows

`make clock_report` (`scripts/clock_report.tcl`) reads the finished design and writes:

- `reports/.../clock_report.txt`:
  - a summary: tree cells, flops, dummy loads, levels, latency, skew, clock wirelength and clock power
  - the output of `report_clock_latency`, `report_clock_skew` and `report_power`
- `logs/.../clock_report.json`: the same numbers, for `make metrics`.

ORFS also saves two pictures of the tree in `reports/.../` for every run:

| File | Shows |
|---|---|
| `cts_default_core_clock.webp.png` | The tree against time. Each buffer is drawn at its arrival time, so a balanced tree has all the flops in one row at the bottom |
| `cts_default_core_clock_layout.webp.png` | The same tree on the chip, each leaf cluster in its own color |

In the GUI (`make gui_cts` or `make gui_final`), **Windows → Clock Tree Viewer**
shows the same tree interactively. Click a buffer to find it in the layout. In
the GUI's Tcl console, `report_clock_latency`, `report_clock_skew -setup` and
`report_clock_skew -hold` give the numbers.

## 1. registered_adder: what a clock tree is

**Base** uses ORFS's defaults: `clock_tree_synthesis -sink_clustering_enable -repair_clock_nets`, and only `clkbuf_16`.
- The H-tree splits the 194 flops in half four times, down to 16 regions of at most 15 flops each.
- Each region gets a leaf buffer, plus one root buffer: 17 buffers, 2 between the clock pin and any flop.
- CTS adds 13 **dummy loads**: buffers or inverters whose outputs are not connected. They even out the loads on the leaf buffers.
- Latency is 0.44 ns and skew is 0.014 ns. The tree is designed to arrive late everywhere at the same time, not early.
- The clock takes **30% of the total power**.

194 flops is too few for sink clustering to run, so the cluster size settings
do nothing here; they're on aes instead. The choices that do change this tree:

| Choice | What it does |
|---|---|
| `buf1` | Only the weakest clock buffer, `clkbuf_1` |
| `buf2` | Only `clkbuf_2` |
| `dist` | A buffer at least every 40 µm along the tree's wires (`CTS_BUF_DISTANCE = 40`) |
| `nodummy` | No dummy loads (`-dont_use_dummy_load`) |

### Results

From `make cts_variants` on the `v2027.1.0` image.

| Variant | Clock buffers | Levels | Dummy loads | Latency (ns) | Skew (ns) | Clock wire (µm) | Clock power (mW) | Clock share of power | Hold buffers added | Final hold slack (ns) |
|---|---|---|---|---|---|---|---|---|---|---|
| base | 17 | 2 | 13 | 0.44 | 0.014 | 2,278 | 3.60 | 30% | 0 | 0.39 |
| CTS=buf1 | 17 | 2 | 14 | **1.39** | **0.142** | 2,357 | 2.13 | 20% | **246** | 0.19 |
| CTS=buf2 | 17 | 2 | 14 | 0.81 | 0.039 | 2,199 | 2.13 | 21% | **90** | 0.07 |
| CTS=dist | **31** | **5** | 6 | 0.66 | 0.018 | 2,400 | **4.74** | **36%** | 0 | 0.17 |
| CTS=nodummy | 17 | 2 | 0 | 0.43 | 0.016 | 2,229 | 2.78 | 25% | 0 | 0.40 |

What the numbers show:

- **Buffer strength** (`buf1`, `buf2`):
  - The tree has the same shape, but weak buffers give slow edges.
  - Latency triples (`buf1`) and skew grows 10×.
  - Clock power drops by 40%, because small buffers have less input capacitance and internal power.
- **Skew causes hold violations:**
  - With 0.014 ns of skew, the short paths (such as `a_r[0]` → XOR → `sum[0]`) pass hold.
  - With `buf1`, 129 endpoints fail hold before repair.
  - Timing repair then adds 246 delay buffers to fix them.
  - So the power saved in the clock tree is partly spent again on hold buffers.
- **Repeaters on long wires** (`dist`):
  - 14 more buffers, and 5 levels instead of 2.
  - Latency goes up 50% and clock power 30%. Skew stays low.
  - On a die this small the long wires didn't need repeaters.
- **Dummy loads** (`nodummy`):
  - Removing them saves 23% of clock power.
  - Skew changes sign and grows slightly (−0.016 ns against 0.014 ns), because the leaf buffers no longer see equal loads.
- **Setup slack** is about −1.6 ns in every run. That comes from the 64-bit ripple carry chain, not the clock tree.

## 2. aes: sink clustering

aes (`aes_cipher_top`, ORFS's design) has 562 flops. That's enough for **sink
clustering** to run: nearby flops are grouped first, each group gets a buffer,
and the H-tree is built over the groups. The cluster settings limit how many
flops a group can have, and how far apart they can be.

| Choice | Cluster limit |
|---|---|
| `base` | ORFS's aes settings: up to 20 flops within 50 µm |
| `small` | Up to 5 flops within 20 µm |
| `large` | Up to 40 flops within 150 µm |
| `noclust` | No sink clustering (`CTS_ARGS = -repair_clock_nets`); the H-tree alone picks the leaf regions |

`designs/sky130hd/aes/config.mk` uses ORFS's aes config from the image and only adds this switch.

### Results

| Variant | Clock buffers | Levels | Dummy loads | Latency (ns) | Skew (ns) | Clock wire (µm) | Clock power (mW) | Worst setup slack (ns) |
|---|---|---|---|---|---|---|---|---|
| CTS=small | **275** | 4 | 196 | 0.94 | 0.073 | 13,660 | **21.3** | −0.08 |
| base | 105 | 3 | 94 | 0.86 | 0.075 | 10,930 | 10.8 | −0.05 |
| CTS=noclust | 81 | 3 | 47 | 0.81 | 0.050 | 11,090 | 8.2 | **−0.62** |
| CTS=large | **30** | 3 | 28 | 0.83 | 0.067 | 9,750 | **5.2** | −0.39 |

(The clock is 3.6 ns.)

- **Cluster size sets the number of buffers:**
  - from 275 (`small`) to 30 (`large`), and clock power from 21.3 to 5.2 mW
  - clock wirelength from 13,660 to 9,750 µm
- **Setup slack depends on the tree too:**
  - `base` and `small` are close to meeting the 3.6 ns clock.
  - `large` and `noclust` miss by 0.39 and 0.62 ns.
  - Skew is about the same in all four, but which flops end up early or late differs. On aes's critical paths, that difference is worth up to 0.6 ns.
- **Clock power is under 4% of aes's total.** The flow's power analysis assumes a default switching activity for every net, and aes's logic switches a lot under that assumption. Compare this with registered_adder (30%) and adder64_pipelined (46%), which are mostly flops.

## 3. adder64_pipelined: a large tree

`adder64_pipelined.v` has `STAGES = 64, CHUNK = 1`: its input delay lines make
it 6,370 flops and about 176,000 µm² of cells, in a 650 × 650 µm die (~50%
utilization). A run takes about 5 minutes.

```bash
make DESIGN=adder64_pipelined
make DESIGN=adder64_pipelined clock_report
```

| Clock buffers | Levels | Dummy loads | Latency (ns) | Skew (ns) | Clock wire (µm) | Clock power (mW) | Clock share of power | Hold buffers added |
|---|---|---|---|---|---|---|---|---|
| 620 | 4 | 487 | 0.98 | 0.041 | 65,560 | 113 | **46%** | 0 |

- Nearly half the power is in the clock tree.
- There are 66 mm of clock wire: twice the total wire of the whole registered_adder.
- The delay lines are flop-to-flop with no logic between them, which is the classic hold risk. They still pass hold with 0.40 ns of slack, because a sky130 flop's clock-to-Q delay is far larger than 0.04 ns of skew.

## Not shown here

OpenROAD doesn't do the following, so they're for discussion rather than demos:
- useful skew: deliberately skewing the clock to borrow time for critical paths
- clock meshes, spines or multi-source trees
- clock gating insertion. Clock gates that are already in the RTL are kept: ibex on sky130hd maps `prim_clock_gating` to `sky130_fd_sc_hd__dlclkp_1`, and CTS buffers through it.
