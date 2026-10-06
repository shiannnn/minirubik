# Assignment 1 Phase 1: minirubik on RV32I

###### tags: `computer-architecture` `RISC-V` `Ripes` `minirubik`

> **Due**: 2026-10-08 11:59 (GMT+8)
> **Fork source**: sysprog21/minirubik (commit: `TODO`)
> **Ripes version**: v2.2.6-106 (processor model: `RV32_ISS`)

## Table of Contents

[TOC]

## 0. Preparation

- [ ] Complete Lab1: RV32I Simulator
- [ ] Install Ripes (`RV32_ISS`) and record the version
- [ ] Fork sysprog21/minirubik and record the source commit
- [ ] Push all work as commits with meaningful messages

## Stage 1: Characterize the Baseline

### 1.1 Program Analysis

#### What the program computes

`solver.c` solves a 2×2×2 cube **optimally**: given a scrambled position, it prints a shortest move sequence (at most 11 moves in the half-turn metric) that returns the cube to solved. It works in two phases:

1. **Build a table** (`build_table`). A breadth-first search from the solved state visits all 3,674,160 reachable states. For each state it stores one byte, `toward_solved[state]`: the move that takes that state one step closer to solved.
2. **Query** (`main`). Parse the 14-digit input, rank it, then repeatedly look up the stored move, apply it, and re-rank until the rank is 0.

The answer is optimal because BFS pops states in non-decreasing distance order, so the first visit to a state is along a shortest path. The stored move is the *inverse* of the move used to reach the state (`inverse_move`), so following the table walks back home.

#### How it represents a cube

One corner is fixed, which removes the 24 whole-cube rotations. Only 7 corners move, and only the faces R, B and D can turn without disturbing the fixed corner. Each face has 3 non-trivial turns, giving 9 moves: `R R2 R'  B B2 B'  D D2 D'`.

```c
typedef struct { uint8_t p[7], o[7]; } state_t;
```

- `p[i]`: which cubie (0–6) sits in position `i`.
- `o[i]`: that cubie's twist, in {0, 1, 2}.

`rank_state` maps a state to a dense integer in $[0, 3{,}674{,}160)$:

$$
\text{rank} = \text{permRank} \times 729 + \text{orientRank}
$$

- `permRank` $\in [0, 5040)$: Lehmer code of `p`, evaluated by Horner's rule.
- `orientRank` $\in [0, 729)$: the first 6 orientations read as a base-3 number. The seventh is determined by the others and is not stored.

A quarter turn changes the permutation using only the old permutation, and changes the orientation using only the old orientation (`source[][]`, `twist[][]`). The program therefore precomputes two small tables:

- `permutation[3][5040]`: next permutation rank, per face.
- `orientation[3][729]`: next orientation rank, per face.

Half turns and inverse turns apply the quarter turn two or three times, so the BFS hot loop never touches a `state_t`.

#### Invariants it relies on

| # | Invariant | Where it is used |
|---|---|---|
| 1 | `p` is a bijection on {0,…,6} | `valid` duplicate scan; Lehmer rank is a bijection only under this condition |
| 2 | Every `o[i]` is in {0, 1, 2} | `valid`; base-3 orientation rank |
| 3 | $\sum o_i \equiv 0 \pmod 3$ | `valid`; makes the 7th orientation redundant, so there are $3^6$ orientation values |
| 4 | Four quarter turns of a face give the identity | `inverse_move` pairing; checked by `self_test` |
| 5 | $7! \times 3^6 = 3{,}674{,}160$ states, all reachable | BFS ends with `tail == STATES` (completeness check) |
| 6 | All 9 moves cost one unit | FIFO order gives non-decreasing distance, so the first visit is a shortest path |

#### Where the cost lies

**Time.** Nearly all of it is the BFS loop in `build_table`; the query phase runs at most 11 iterations.

| Quantity | Count |
|---|---|
| States dequeued | 3,674,160 |
| Edges (9 per state) | 33,067,440 |
| Transition updates (2 lookups per edge: `permutation`, `orientation`) | 66,134,880 |
| Rank rebuilds `next_p * 729 + next_o` | 33,067,440 |
| `/ 729` and `% 729` | 3,674,160 each |

Each edge also loads `toward_solved[there]`, a random access over 3.5 MiB. On RV32I there is no M extension, so `*729`, `/729`, `% 729` (and the `% 3` in `quarter_turn`) become long shift-add or software routines inside the hottest loop. A direct translation lands around $10^9$ instructions.

**Memory.** Three allocations are live at the peak:

| Allocation | Size | Share |
|---|---:|---:|
| `queue` (`uint32_t` × 3,674,160) | 14,696,640 B | 79.8% |
| `toward_solved` (1 B × 3,674,160) | 3,674,160 B | 20.0% |
| Transition tables, $3 \times (5040 + 729) \times 2$ B | 34,614 B | 0.2% |
| **Total** | **18,405,414 B (17.553 MiB)** | |

The queue exists only to name the BFS frontier. Because Ripes stores guest memory as one hash entry per byte, these 18.4 MB become roughly 18.4 million host entries. The cost is therefore concentrated in (a) a table covering *every* state and (b) per-edge multiply/divide that RV32I cannot do cheaply. Stage 2 removes (a); Stage 3 removes (b).

### 1.2 Measurements

**Setup.** Ripes CLI build `D:\Ripes\Ripes.exe` (build dated 2026-10-03; record the pinned version:  v2.2.6-106), Windows 11, CPU: Intel Core i7-10700. Both measurements were produced by a script (`measure/measure.ps1`) that runs `Ripes --mode cli --src <file> -t asm --proc <model> --iret --cycles`, so no value was read or timed by hand. Test programs are `measure/memfill.s` and `measure/spin.s`; the raw data are in `ratio_results.csv` and `rate_results.csv`.

#### 1.2.1 Host-bytes-per-guest-byte ratio

**Method.** `memfill.s` executes one `sb` per byte over a region starting at `0x20000000`, so every written guest byte is a distinct address (3 instructions per byte). It was run on `RV32_ISS` for $N = 0, 1, 2, 4, 8$ MiB, 3 runs each. The script polls the Ripes process every 20 ms and records its peak working set. The $N = 0$ run is the baseline (Ripes start-up).

| Guest bytes written | Peak host working set | (peak − baseline) / N |
|---:|---:|---:|
| 0 (baseline) | ≈ 24 MB (see note) | — |
| 1 MiB | 108.7 MB | 87.4 |
| 2 MiB | 192.8 MB | 83.8 |
| 4 MiB | 361.3 MB | 82.0 |
| 8 MiB | 698.0 MB | 81.2 |

The slope between adjacent sizes is independent of the baseline: 2→4 MiB and 4→8 MiB both give **≈ 80.3 host bytes per guest byte**. This is the figure used below.

> Note: one of the three $N = 0$ runs sampled only 3 MB because polling ended before Ripes finished loading, which pulls the mean baseline down to 17.1 MB. This is why the per-size ratios in the table (87.4 → 81.2) are slightly high and converge toward the slope.

#### 1.2.2 Retired instructions per second

**Method.** `spin.s` is a fixed countdown loop (`addi` + `bnez`), about $2 \times$ ITER instructions. For each model it was run at two lengths, 3 runs each, taking retired instructions from `--iret` and wall time from a stopwatch around the process. The rate is the slope $(I_2 - I_1)/(t_2 - t_1)$, which removes the fixed start-up cost.

| Processor model | Lengths (instr) | Mean time | Rate (instr/s) | Start-up |
|---|---|---|---:|---:|
| `RV32_ISS` | 4.0 M / 20.0 M | 0.32 s / 1.37 s | **≈ 15.3 M** | ≈ 0.06 s |
| `RV32_5S` (5-stage, forwarding + hazard detection) | 0.4 M / 2.0 M | 3.25 s / 15.86 s | **≈ 0.127 M** | ≈ 0.10 s |

`RV32_ISS` is about 120× faster than the pipelined model. On `RV32_ISS`, cycles equal retired instructions; on the pipelined model they do not, so the rate is reported in retired instructions, not cycles.

**Caveat on the ISS figure.** `spin.s` never touches memory. The memory-bound loop `memfill.s` ran 25.2 M instructions (8 MiB, 3 per byte) in about 4.15 s, i.e. **≈ 6.1 M instr/s** on `RV32_ISS`. A realistic program that loads and stores heavily sits between the two figures, so both are used in 1.3.

### 1.3 Why the Full Baseline Table Is Fatal on the Target

The baseline allocates 18,405,414 B (17.553 MiB): `queue` 14,696,640 B, `toward_solved` 3,674,160 B, transition tables 34,614 B. A direct RV32I translation performs about $10^9$ instructions (see 1.1).

**Memory.** Using the measured ratio of ≈ 80.3:

$$
18{,}405{,}414\ \text{B} \times 80.3 \approx 1.48 \times 10^{9}\ \text{B} \approx 1.4\ \text{GiB of host memory}
$$

Every allocated byte is eventually written (a `memset` of 3.67 MB up front, then the queue fills to exactly `STATES` entries), so the whole amount becomes resident. This is host memory spent to simulate a guest that has only a 128 KiB data budget; the baseline exceeds that budget by a factor of 18,405,414 / 131,072 ≈ 140.

**Time.** For $10^9$ retired instructions:

| Model | Rate used | Estimated run time |
|---|---:|---:|
| `RV32_ISS`, memory-free loop (best case) | 15.3 M instr/s | ≈ 65 s |
| `RV32_ISS`, memory-bound loop (closer to baseline) | 6.1 M instr/s | ≈ 165 s |
| `RV32_5S` | 0.127 M instr/s | ≈ 7,900 s ≈ 2.2 h |

**Conclusion.** The full table is not merely slow; it is unusable on the target. On `RV32_ISS` the time is tolerable (one to three minutes), but the memory is not: 1.4 GiB of host memory for 17.5 MiB of guest data, and 140× the 128 KiB budget. On a pipelined model, which the instruction-level walkthrough requires, the same run takes over two hours. The Stage 4 budget of $5 \times 10^7$ retired instructions is about 3 s on `RV32_ISS` at 15.3 M instr/s, but about 6.6 minutes on `RV32_5S`. The design must therefore avoid enumerating the state space and keep only small tables, which motivates Stage 2.

## Stage 2: Choose Representation and Algorithm

### 2.1 State Representation

The search does not carry a `state_t` or a dense rank. It carries two small integers that are the coordinates of a **pattern database (PDB)** entry:

- `o` in [0, 729): the base-3 orientation rank of the 6 free slots, exactly as in `solver.c`. Orientation updates depend only on the slot (`twist[][]`, `source[][]`), never on which cubie sits there, so `o` evolves by itself.
- `l` in [0, 210): the locations of cubies 0, 1 and 2, ranked as `(l0*6 + r1)*5 + r2` with `r1 = l1 - (l1 > l0)` and `r2 = l2 - (l2 > l0) - (l2 > l1)`. This is 7 × 6 × 5 = 210.

The PDB index is `o * 210 + l`, so the table has 729 × 210 = **153,090** entries. The full 7-byte `state_t` is only rebuilt from the move path when the PDB says 0, to confirm the cube is really solved (the other four cubies are not tracked).

Justification against the Stage 1 numbers:

| Stage 1 fact | Consequence for the representation |
|---|---|
| ≈ 80.3 host bytes per guest byte | 83,457 B of tables cost about 6.7 MB of host memory, against 1.48 GB for the baseline |
| 128 KiB static budget (131,072 B) | One entry per byte is 153,090 B and does not fit; 4 bits per entry is 76,545 B and does |
| No M extension | The dense rank `perm*729 + orient` needs `*729`, `/729` and `% 729`; the two-coordinate form needs only a shift-add `*210` |
| ≈ 15.3 M instr/s on `RV32_ISS`; 5×10⁷ budget ≈ 3.3 s | The per-node cost must stay near a hundred instructions, so no per-node ranking |

The abstraction is a true quotient of the Cayley graph. Distances in the abstract graph are therefore never larger than real distances, which is what makes the table an admissible heuristic.

### 2.2 Algorithm

Candidates considered:

| Candidate | Memory | Verdict |
|---|---|---|
| Full BFS distance or move table (baseline) | 3.5 MiB table + 14 MiB queue | Fails the 128 KiB budget |
| 4-bit distance table over all 3,674,160 states | 1.75 MiB | Still 14× over budget |
| Distance mod 3 table over all states (2 bit) | 0.88 MiB | Still 7× over budget |
| Plain iterative deepening, no heuristic | tiny | About 6¹¹ ≈ 3.6×10⁸ nodes at depth 11; too many |
| Meet in the middle | needs a hash set of a depth-5 or depth-6 frontier | Needs hashing and probing on top of a table; not pursued |
| **IDA\* with a PDB heuristic** | 83,457 B | **Chosen** |

IDA\* works as follows. Start with `bound = h(root)`. Run a depth-first search that prunes every node with `g + h > bound`. If a pass finds no solution, increase `bound` by 1 and repeat. Memory is one path of at most 12 frames, so no heap and no queue. Two further choices:

- **Same-face pruning.** Never turn the same face twice in a row, so after the first move only 6 of the 9 moves are tried. This loses nothing (see 2.4).
- **Heuristic.** The PDB described in 2.1, built offline by BFS over the 153,090 abstract states. Its maximum value is 9, so it fits in a nibble.

A permutation-only table (5,040 entries, maximum 7) was also built and used as a second heuristic in the Stage 2 host oracle (`stage2.c`, worst case 114,384 nodes). Stage 3 drops it, because maintaining a permutation rank per node costs more than the extra pruning saves (see 3.3).

### 2.3 Memory Budget

| Item | Size (bytes) |
|---|---|
| Factored transition tables (baseline, `permutation` + `orientation`) | 34,614 (not used by the final design) |
| Heuristic table: PDB, 153,090 entries × 4 bit | 76,545 |
| Orientation transition `onext[3][1024]`, `uint16_t` (rows padded to 1024 for shift addressing) | 6,144 |
| Location transition `lnext[3][256]`, `uint8_t` | 768 |
| Other (search stack ≈ 130 B, 14 B root state, path buffer; all on the stack) | ≈ 150 |
| **Total static data (≤ 128 KiB)** | **83,457 B = 81.5 KiB**; 47,615 B of headroom |

The largest table covers 153,090 abstract states, 4.2% of the 3,674,160 real states.

### 2.4 Termination and Optimality

**Termination.** One IDA\* pass is a depth-limited search with branching factor at most 6 after the first move, so it ends. The bound increases by 1 per pass, and the BFS layer counts (1, 9, 54, 321, 1847, 9992, 50136, 227536, 870072, 1887748, 623800, 2644; sum 3,674,160) show that every state is within 11 moves, so some pass with `bound ≤ 11` finds a solution.

**Optimality.**

1. `h` never exceeds the true distance (admissible), because the abstract graph is a quotient of the real one: every real path maps to an abstract path of the same length.
2. A node pruned at `bound = b` has `g + h > b`, hence every solution through it is longer than `b`. When a pass at bound `b` fails, no solution of length ≤ `b` exists, so the first solution found at the next bound is shortest.
3. Same-face pruning is safe: two consecutive turns of one face combine into a single move (`R R2 = R'`, `R R' = identity`), so any path containing them can be replaced by a strictly shorter one.

**Host-side evidence** (`stage2.c`, `stage3.c`; the C oracle uses a full BFS table as ground truth):

| Gate | Check | Result |
|---|---|---|
| H1 | `h(s) ≤ d(s)` for all 3,674,160 states (`stage3.c` reads the packed nibble accessor) | 0 violations |
| H3 | returned length equals BFS distance and the path reaches solved, for every state (`./stage3 --full`) | 3,674,160 states, 0 wrong, 111.2 s wall clock (gcc -O2, Windows 11) |

H3 is exhaustive: all 3,674,160 states return a path of exactly the BFS length that reaches solved, and since the largest BFS distance is 11 this also shows that no state is deeper. A state can have several shortest solutions, and IDA\* need not pick the one the baseline BFS records. For `43752611332133` the baseline prints `R' D2 R2 D' R D2 B D' R2` and IDA\* prints `R D2 R2 D R D2 B D' R2`. Both are 9 moves and both reach solved.

### 2.5 Precomputation

- The PDB, `onext` and `lnext` are generated on the host and linked as read-only data (`.rodata`). In `stage3.c` they are built at start-up for convenience; for the target the same arrays are emitted as constants.
- No complete distance table over all 3,674,160 states exists in the target. The only BFS over the full space lives in `--verify`, which runs on the host as the oracle.

## Stage 3: Improve Efficiency in C First

### 3.1 Eliminating Multiply and Divide

- **Index computation.** The only non-power-of-two multiplier left in the search is 210 in the PDB index. It is written as shifts and adds: `o*210 + l = (o<<7) + (o<<6) + (o<<4) + (o<<1) + l` (210 = 128 + 64 + 16 + 2).
- **Table row addressing.** `onext` and `lnext` rows are padded to 1024 and 256 entries, so a row start is `face << 10` or `face << 8` and not `face * 729`. This costs 6,144 − 4,374 = 1,770 B of padding in `onext`.
- **Modulo 3.** Orientation arithmetic is gone from the search: the new orientation index is read from `onext`. `% 3` only runs when the tables are generated.
- **Dense rank and `/ 729`.** The search never forms `perm * 729 + orient`, so the division and modulo by 729 disappear.
- **Face of a move.** `m / 3` is replaced by two counters (`face`, `turn`), and the move number is `(face << 1) + face + turn`.

### 3.2 Reducing Branches and Memory Traffic

- **No recursion.** A fixed stack of 13 frames (`no`, `nl`, `co`, `cl`, `face`, `turn`, `last`) replaces the recursive `ida_dfs`. Nothing is pushed on a call stack, and the depth is bounded by the compile-time constant `MAXD`.
- **No `state_t` copying.** Stage 2 copied 14 bytes per step and applied 1 to 3 `quarter_turn`s per move (7 iterations each). Stage 3 advances `o` and `l` with one lookup each. The full state is rebuilt from the path only when the PDB entry is 0.
- **Cumulative turns.** The three moves of one face are generated by applying the quarter-turn table once, twice, then three times, so a half turn and an inverse turn cost one extra lookup instead of a fresh computation.
- **Branch-free nibble read.** `(pdb[i >> 1] >> ((i & 1) << 2)) & 15` replaces the `if (i & 1)` choice.
- **No permutation ranking per node.** Stage 2 ran `rank_perm` (21 comparisons, 7 multiplications) on every node to look up the second heuristic.

Before and after, per generated node (see 3.3 for the counts).

### 3.3 Operation Count Analysis

Counts are tallied by hand from the C source, per generated node. They are not retired instructions: those come from Ripes `--iret` in Stage 4.

| Version | Mul/Div | Branches | Loads/Stores | Total ops |
|---|---|---|---|---|
| Original C (Stage 2 loop: `apply_move`, `heur` with `rank_perm`, `pdb_index`) | ≈ 33 (16 mul + 14 `% 3` + 3 for `m / 3` and `m % 3`) | ≈ 75 | ≈ 115 loads / ≈ 40 stores | ≈ 470 |
| Optimized C (`stage3.c` search loop) | 0 | ≈ 5 | ≈ 8 loads / ≈ 4 stores | ≈ 45 |

Node counts on the host (distance-11 states only below; both columns come from the exhaustive H3 run for Stage 3 and from `stage2 --bench` for Stage 2):

| | Stage 2 | Stage 3 |
|---|---|---|
| Worst-case nodes, distance-11 | 114,384 | 424,243 |
| Mean nodes, distance-11 (2,644 states) | 14,616 | 47,317 |

Stage 3 visits about 3.7× more nodes because it dropped the permutation table, but each node is about 10× cheaper in operations and uses no multiplication:

- Budget: 5×10⁷ ÷ 424,243 ≈ 118 instructions per node. The Stage 3 estimate of about 45 fits with margin.
- Stage 2 at its worst case: 114,384 × 470 ≈ 5.4×10⁷ operations before counting that each of its ≈ 33 multiplications and divisions expands to a shift-add loop or a `__mulsi3` call on RV32I. It would exceed the budget by a wide margin.

The measured Stage 4 instruction count may differ from these estimates. If it exceeds about 118 per node, the permutation table can be added back as nibbles (about 2.5 KB) to bring the node count back near 114k.

### 3.4 C Code

Full source: `stage3.c` in the fork (link to be added once pushed). Key fragments:

```c
/* o*210 + l without a multiplier: 210 = 128 + 64 + 16 + 2. */
static inline uint32_t pdb_idx(uint32_t o, uint32_t l)
{
    return (o << 7) + (o << 6) + (o << 4) + (o << 1) + l;
}
/* branch-free nibble read */
static inline uint32_t pdb_get(uint32_t i)
{
    return (pdb[i >> 1] >> ((i & 1) << 2)) & 15;
}
```

```c
for (;;) {
    if (turn[d] == 3) {            /* finished one face: next face */
        turn[d] = 0; ++face[d];
        co[d] = no[d]; cl[d] = nl[d];
    }
    if (face[d] == 3) {            /* frame exhausted: backtrack   */
        if (d == 0) break;
        --d; continue;
    }
    if (face[d] == last[d]) { ++face[d]; continue; }   /* same face */
    uint32_t f = face[d];
    co[d] = onext[f][co[d]];       /* one more quarter turn        */
    cl[d] = lnext[f][cl[d]];
    path[d] = (uint8_t) ((f << 1) + f + turn[d]);
    ++turn[d];
    int h = (int) pdb_get(pdb_idx(co[d], cl[d]));
    if (d + 1 + h > bound) continue;                    /* IDA* prune */
    if (h == 0 && is_solved_after(root, path, d + 1))
        return d + 1;
    if (d + 1 == bound) continue;
    /* push child frame */
    no[d+1] = co[d]; nl[d+1] = cl[d];
    co[d+1] = co[d]; cl[d+1] = cl[d];
    face[d+1] = turn[d+1] = 0; last[d+1] = (uint8_t) f;
    ++d;
}
```

### 3.5 Performance Comparison of the Two Retained Algorithms

Both IDA\* variants are kept in the repository so they can be compared. They share the cube model, the PDB and the same-face pruning, and differ only in the heuristic and in how the search state is maintained.

| | Variant A: `stage2.c` | Variant B: `stage3.c` |
|---|---|---|
| Heuristic | `max(PDB, permutation distance)` | PDB only |
| Search state | `state_t` (7 B perm + 7 B orient), re-ranked every node | `(o, l)` pair, advanced by `onext` / `lnext` lookups |
| Recursion | recursive `ida_dfs` | explicit 13-frame stack |
| Multiply / divide in the loop | yes (`rank_perm`, `rank_orient`, `pdb_index`, `% 3`) | none |
| Static tables | 76,545 B PDB + 5,040 B permutation table | 76,545 B PDB + 6,144 B `onext` + 768 B `lnext` |

**Method.** `./stage2 --bench` and `./stage3 --bench` build the full BFS table as ground truth, then solve the same sample with the same seed: all 2,644 distance-11 states and about 3,000 random states from each of the distance 7, 8, 9 and 10 layers (the sampling rate is chosen from the layer size). Each solve is timed on its own with the host's high-resolution counter, and the returned length is compared with the BFS distance. Host: this Windows 11 machine, `gcc -O2`, hardware multiplier available. Both runs report `wrong lengths: 0`.

**Results.**

| d | states | A mean nodes | A max nodes | B mean nodes | B max nodes | A ns/node | B ns/node |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 7 | 3,008 | 58 | 1,098 | 121 | 7,286 | 50.4 | 10.6 |
| 8 | 2,913 | 190 | 2,689 | 489 | 5,654 | 52.1 | 10.1 |
| 9 | 2,990 | 835 | 7,075 | 2,427 | 39,391 | 52.7 | 10.9 |
| 10 | 2,933 | 3,042 | 25,466 | 9,266 | 90,846 | 52.2 | 11.0 |
| 11 | 2,644 | 14,616 | 114,384 | 47,317 | 424,243 | 51.5 | 10.9 |

Totals for the distance-11 layer (2,644 states):

| | A | B | B relative to A |
|---|---:|---:|---:|
| Total nodes | 38,645,096 | 125,106,746 | 3.24× more |
| Time | 1,988 ms | 1,364 ms | 1.46× faster |
| Time per node | 51.5 ns | 10.9 ns | 4.7× cheaper |

**Reading the numbers.**

- The permutation table cuts the node count by a factor that grows with depth: B visits 2.1× A's mean nodes at d = 7, 2.6× at d = 8, 2.9× at d = 9, 3.0× at d = 10 and 3.2× at d = 11.
- Variant B's per-node cost is flat at about 10 to 11 ns and Variant A's at about 51 to 53 ns, so the cost per node does not depend on depth. The wall time is therefore decided by `nodes × cost per node`, and B wins on this host even though it visits more nodes.
- The host has a hardware multiplier. Variant A spends about 33 multiply, divide and modulo operations per node, and RV32I has none. The host ratio of 4.7× per node is therefore a lower bound on what B gains on the target.

**Projection to RV32I (model, not measured).** Let `c` be the number of RV32I instructions one multiply, divide or modulo costs. Using the per-node tallies from 3.3 (A ≈ 437 + 33c, B ≈ 45) and the worst-case distance-11 node counts:

| `c` | A per node | A worst case (114,384 nodes) | B per node | B worst case (424,243 nodes) |
|---:|---:|---:|---:|---:|
| 1 | 470 | 5.4×10⁷ | 45 | 1.9×10⁷ |
| 20 | 1,097 | 1.3×10⁸ | 45 | 1.9×10⁷ |
| 50 | 2,087 | 2.4×10⁸ | 45 | 1.9×10⁷ |

The limit is 5×10⁷. Variant A exceeds it as soon as `c` is above 1, while Variant B stays under it for every `c`, with about 2.6× of margin. These are model numbers. The retired-instruction counts of both variants must be measured with Ripes `--iret` in Stage 4, and `c` for a software multiply should be taken from the actual code.

**Conclusion.** Variant A visits fewer nodes and Variant B does far less work per node. On the host B is already 1.46× faster, and on RV32I, where multiplication is expensive, the gap grows. Variant B is the one carried into Stage 4. Variant A stays in the repository as the reference with the stronger heuristic. If Stage 4 shows B above the budget, the permutation table can be added to B as a nibble table with a permutation-rank transition that does not need multiplication.

Reproduce:

```bash
gcc -O2 -Wall -o stage2 stage2.c && gcc -O2 -Wall -o stage3 stage3.c
./stage2 --bench
./stage3 --bench
```

## Stage 4: Translate to RV32I Assembly

Source: `stage3.s` (one file: code, test data and the generated tables). The state is read from registers given on the Ripes command line, see How to Run. Reference build and measurement scripts: `ref/`, `measure/`, `tools/`.

**Measurement conventions.** Retired instructions come from `Ripes --mode cli --proc RV32_ISS --iret` on Ripes v2.2.6-106-g5b8a616, one state per run (`measure/measure_stage4.ps1` cuts the `cases` table to one entry), so every count is a whole program: start-up, parse, search, replay check, printing, exit. Code size is the `.text` size of the assembled object (`riscv64-unknown-elf-size -A`); the measured build is stage5_cli.s, whose renderer is compiled out. Static data is the `.data` size of the same object.

### How to Run

Ripes has no stdin and no `argv`, so the cube state is given in registers with `--reginit`. A state is 14 digits `PPPPPPPOOOOOOO`: seven cubie digits 1 to 7 (no repeats), then seven orientation digits 1 to 3 whose sum minus 7 is a multiple of 3. The program expects the first seven digits as a decimal number in `a0` (`gpr:10`) and the last seven as a decimal number in `a1` (`gpr:11`), and turns them back into the 14-character string by subtracting powers of ten (no divide).

Use the Ripes build that has `RV32_ISS` (v2.2.6-106-g5b8a616 here). v2.2.6 has no such model, and its `--reginit` takes the format `<idx>=<value>`.

**Solve one state** (the assignment vector `21345671111111`):

```bash
Ripes --mode cli --src stage3.s -t asm --proc RV32_ISS --iret --reginit "gpr:10=2134567,11=1111111"
```

Output (Ripes prints a NUL after every string, so a terminal may show extra gaps):

```
[PASS] 21345671111111 : 11 moves: R B' D2 R' B R' B' R D2 R B
Program exited with code: 0
===== instructions retired
7463271
```

- The first line is printed by the program. `[PASS]` means the path found by the search, replayed move by move on a full 7-cubie model inside the program, ends in the solved cube. The number is the move count and the moves follow in the notation of `solver.c`.
- The exit code is `0` when the state was solved and `1` otherwise.
- An invalid state is rejected with `[FAIL] invalid state ...` and exit code `1`. Rejected: a digit outside its range, a repeated cubie, an orientation sum that is not a multiple of 3, or a number of more than seven digits.
- `--iret` adds the retired instruction count of the whole program, including input decode, printing and exit.

**Run the built-in test cases.** Start without `--reginit` (or load `stage3.s` in the GUI, where `a0` starts at 0). The three inlined cases, the solved cube, the 3-move scramble and the distance-11 vector, are solved and checked against their expected lengths:

```bash
Ripes --mode cli --src stage3.s -t asm --proc RV32_ISS --iret
```

It prints three `[PASS]` lines and `all cases passed`, and exits with the number of failed cases. The cases are the `case0` to `case2` strings and the `cases` table at the end of `stage3.s`.

**Pipelined models** work with the same arguments, for example `--proc RV32_5S`, but run about 100 times slower, so a distance-11 state needs minutes. Add `--timeout <ms>` if the default is too short.

**Measure many states.** `measure\measure_stage4.ps1` runs a list of states through exactly this interface and writes `measure\stage4_results.csv`. The switch `-Worst` adds the 20 distance-11 states with the most IDA\* nodes:

```
powershell -File measure\measure_stage4.ps1 -Ripes C:\path\to\Ripes.exe -Worst
```

### 4.1 Design and Constraint Checklist
- [x] RV32I only: assembled with `-march=rv32i`, which rejects any M instruction; no call to `__mulsi3` or `__divsi3`
- [x] No heap, recursion, or floating point (explicit 16-frame array, `call` only to leaf helpers)
- [x] Input: 14-character states inlined with `.string` (`case0` to `case2`), validated by `parse` (digit ranges, repeated cubies, orientation sum)
- [x] `.data` + `.bss` + `.rodata` ≤ 128 KiB: 84,120 B in total (all in `.data`, see 4.2)

### 4.2 Program Structure

**Data layout.** Everything is in `.data`, because Ripes 2.2.6 accepts neither `.section`, `.rodata`, `.bss` nor `.space`.

| Item | Bytes |
|---|---:|
| `pdb` (153,090 × 4 bit) | 76,545 |
| `onext` 3 × 1024 × u16 | 6,144 |
| `lnext` 3 × 256 × u8 | 768 |
| `source_tbl`, `dest_tbl`, `twist_tbl` (8 B rows) | 72 |
| move names, messages, test strings, `cases`, `pow10` | ≈ 308 |
| scratch: `root_st`, `cur_st`, `new_st`, `path`, `frames` (16 × 16 B), `loc_buf`, `num_buf`, `in_buf` | 332 |
| **Total** | **84,120** |

The three big tables are produced by `tools/gen_stage3_tables.py`, a port of `build_tables()`. The script rewrites the block between the `BEGIN/END GENERATED TABLES` markers. No table covers all 3,674,160 states.

**Frame.** 16 B per depth, addressed with literal offsets because Ripes 2.2.6 mis-assembles `.equ` symbols used as offsets: `0` node orientation index, `2` cursor orientation index, `4` node location index, `5` cursor location index, `6` face, `7` quarter turns done, `8` face of the parent move.

**Functions and registers.**
- `search(a0 = root)` returns the move count in `a0`, or -1. Registers: `s0` frame pointer, `s1` depth, `s2` bound, `s3`/`s4`/`s5` = `onext`/`lnext`/`pdb`, `s6`/`s8` = root orientation/location index, `s7` = `&path[d]`, `s9` = root, `s10` = constant 3.
- `quick_solved(a1 = n)`: used when the PDB says h = 0. Then cubies 0 to 2 are home and every orientation is 0, so the cube is solved iff cubies 3 to 6 are home. It follows their slots through `dest_tbl` (the inverse of `source`). Leaf routine.
- `is_solved(a0 = root, a1 = n)`: full 7-cubie replay (the `quarter_turn` model of `stage3.c`). Used for the independent check in `solve_case`.
- `parse`, `solve_case`, `put_str`, `put_uint`: input checking and output. Ecalls: 4 = print string, 93 = exit with code.
- Start-up `_start`: if `a0` is 0 it runs the built-in cases; otherwise it decodes `a0` and `a1` into `in_buf` (see How to Run) and calls `solve_case` with no expected distance.

**Main flow.** For each case (a built-in one, or the one decoded from the registers): `parse`, `search`, compare with the expected distance, replay the path with `is_solved`, then print `[PASS]` or `[FAIL]`, the state, the move count and the moves. The exit code is the number of failed cases. If no solution is found by bound 11, `search` returns -1, so an unreachable input cannot loop forever.

**Ripes notes.** `ecall` is preceded by three `nop`s so that the `a7` value reaches the register file in the pipelined models (a bare `li a7, 4` followed by `ecall` raised "Unknown system call in register a7: 0"). Comments avoid parentheses and square brackets because the Ripes assembler rejects them.

### 4.3 Iterative Refinement Log

Retired instructions on `RV32_ISS`. "d11 vector" is `21345671111111`. "worst" is `12347651111111`, the distance-11 state with the most IDA\* nodes (424,243).

| Version | Change | `.text` bytes | d11 vector | worst |
|---|---|---:|---:|---:|
| v0 | straight translation; at h = 0 replay the whole path with `is_solved` | 2,048 | 14,810,055 | 48,023,955 |
| v1 | h = 0 test follows only cubies 3 to 6 through `dest_tbl` (`quick_solved`) | 2,040 | 7,806,090 | 25,640,356 |
| v2 | constant 3 kept in `s10` for the two tests in the dfs loop | 2,044 | 7,463,027 | 24,509,105 |
| v3 | state read from `a0`/`a1` through `--reginit` instead of an inlined string; same search | 2,176 | 7,463,271 | 24,509,349 |

- v0 to v1: 46.6 % fewer on the worst state. The h = 0 test ran 8,537 times on this state and replayed 82,583 moves in total (host count). Removing the replay saved 22.4 M instructions, about 270 per replayed move, so most of v0 was this check.
- v1 to v2: 4.4 % fewer on the worst state and 4.4 % fewer on the vector.
- v2 to v3: 244 instructions more on every state, the decimal-to-string decode of the input. v0 to v2 were measured with the state edited into the source; from v3 on, every number is measured through `--reginit`.
- The node count is the same in all versions (424,243 on the worst state), so every change is a change in cost per node. v3 spends 24,509,349 / 424,243, about 57.8 instructions per node, including the h = 0 checks.

### 4.4 Comparison with the GCC Reference

Build command: `riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32 -mno-relax -nostdlib -static` (GCC 10.2.0, libgcc `rv32i/ilp32`; `measure/build_ref.sh`). The source is `ref/stage3_ref.c`: the search of `stage3.c` with the same tables (`tools/gen_stage3_tables.py --c`), a compile-time state, no printing, and a byte-loop `memcpy` because there is no rv32i libc (GCC lowers the `state_t` copy in `is_solved_after` to a call). The binary links `__divsi3`, `__modsi3`, `__udivsi3` and `__umodsi3`, which `% 3`, `m / 3` and `m % 3` need without an M extension. Counts come from `measure/measure_ref.ps1` on the same Ripes build.

| Program | d11 vector | worst | `.text` bytes |
|---|---:|---:|---:|
| GCC `-O2`, algorithm of `stage3.c` | 23,580,300 | 76,231,639 | 1,652 |
| GCC `-O2` with the `quick_solved` test (`-DQUICK`) | 8,622,122 | 28,325,779 | 1,820 |
| `stage3.s` (v3) | 7,463,271 | 24,509,349 | 2,176 |

- Against plain GCC the assembly retires 68.4 % fewer instructions on the vector and 67.8 % fewer on the worst state. Plain GCC is above the 5×10⁷ budget on the worst state; the assembly is below it.
- Most of that gap is the algorithm, not the code generation. GCC pays for the full replay through libgcc `%` and `/` calls, while `stage3.s` uses `quick_solved`. To isolate code generation, the `-DQUICK` row gives the compiler the same test. Against it the assembly retires 13.4 % fewer on the vector and 13.5 % fewer on the worst state.
- The assembly is 356 to 524 bytes larger in `.text`. The programs are not identical: `stage3.s` also contains `parse` validation, the CLI decode, the full-model replay and the printing code, none of which is in the reference.
- The assembly's solved-cube run costs 837 instructions against 365 for the `-DQUICK` reference. The difference, 472 instructions, is the input decode, the parsing checks and the printing, and it is included in every assembly number above.

### 4.5 Correctness Tests
| ID | Description | Result |
|---|---|---|
| H1 | Heuristic admissibility: h(s) ≤ d(s) over all 3,674,160 states | PASS: 0 violations; h = d on 415,268 states (`./stage3 --hcheck`) |
| H2 | All tables fully populated; maximum value and solved entry checked | PASS: PDB 153,090 entries, none unset, max 9, only index 0 (solved) is 0; `onext`/`lnext` rows are permutations with zero padding; both agree with the full 7-cubie model on 3,674,160 × 3 transitions |
| H3 | Search returns the optimal length for every state | PASS: 3,674,160 states, 0 wrong, 111.2 s (host, `./stage3 --full`) |
| H4 | Packed accessor agrees with unpacked reference | PASS: 76,545 even + 76,545 odd indices, 0 mismatches |
| T5 | Applying the returned path reaches the solved state | PASS on Ripes `RV32_ISS`: all 2,644 distance-11 states (`measure/all_d11_iret.csv`) plus the 8 states of other depths (0, 3, 8, 8, 8, 9, 9, 10) in `measure/stage4_results.csv`, each run alone through `--reginit`, each checked against its expected length and replayed on the full model by the program itself. Also PASS under qemu-riscv32 (`tools/qemu_test.sh`) on all 2,644 distance-11 states plus 2,508 random others (5,152 states), every length equal to the BFS distance |
| T6 | `21345671111111` returns an 11-move optimal solution | PASS: `R B' D2 R' B R' B' R D2 R B`, 11 moves; the program compares the length with the expected 11 and replays the path |
| T7 | Three test cases reproduce on RV32_ISS and at least one visual pipeline model | `RV32_ISS`: all three PASS in one run without `--reginit`, and each one also PASSes alone through `--reginit`. `RV32_5S` (Ripes CLI, `stage5_cli.s`, no `--reginit`, `--timeout 1800000`): all three PASS in one run and the program prints `all cases passed`, exit code 0. 7,466,180 instructions retired in 9,704,819 cycles, 43.7 s wall-clock. The earlier 60 s timeout was too short for case 3. The datapath itself is shown in section 4.8, with screenshots still to add |

#### Test Cases
1. Solved cube: `12345671111111`, expected 0 moves, 837 instructions
2. Short scramble, 3 moves: `23475162132323`, expected 3 moves (`D' B R'`), 2,884 instructions
3. Distance-11 state: `21345671111111`, expected 11 moves, 7,463,271 instructions

More states measured, with the expected length taken from `tests/solutions.txt`: `62345713133111` (8), `24316572122213` (8), `25713642221111` (8), `24513763133333` (9), `43752611332133` (9), `25416373331111` (10), and the second-worst state `61352472313211` (11).

### 4.6 Pass Conditions
- [x] Static data ≤ 128 KiB: 84,120 B (all `.data`; 83,457 B of it are the tables)
- [x] Every distance-11 state ≤ 5×10⁷ retired instructions on RV32_ISS: all 2,644 distance-11 states were run on `RV32_ISS` through `--reginit` (`measure/measure_all_d11.ps1`, data in `measure/all_d11_iret.csv`). Every one printed `[PASS]` with 11 moves. Retired instructions: minimum 809,149, mean 2,808,078, **maximum 24,509,349** (`12347651111111`), then 23,789,564 (`61352472313211`) and 20,229,570 (`51342763312223`). No state is above 5×10⁷; the maximum uses 49 % of the budget. The measured build is `stage5_cli.s`, in which the renderer is compiled out (see 4.7). The distance-11 list comes from a host BFS (`measure/all_d11_states.txt`).
- [x] Instruction count for `21345671111111` (reported separately): 7,463,271

### 4.7 LED Matrix Visualization

**Setup in Ripes.** Open the I/O tab, add an LED Matrix and set Width to 35 and Height to 25 (the panel lists Height above Width; 35 × 25 is also the peripheral's default). Load `stage5_led.s`, choose `RV32_ISS`, run. With no register input the three built-in cases are solved in turn, and each is drawn as it is solved.

**Addressing.** One 32-bit word per LED, 0x00RRGGBB, row-major: the LED at (x, y) is the word at `LED_MATRIX_0_BASE + 4 * (y * WIDTH + x)`. This is the layout `examples/C/leds.c` uses; the column-major formula in the peripheral's own description is wrong. The code uses the symbols `LED_MATRIX_0_BASE` and `LED_MATRIX_0_WIDTH` and no literal address. Because RV32I has no multiply, `y * WIDTH` is a loop that adds `4 * WIDTH` once per row.

**Layout.** The cube is an unfolded net in a 4 × 3 grid of face slots, six of them used:

```
        U
      L F R B
        D
```

That is 8 × 6 facelets. A facelet is 4 LEDs wide and 3 tall. Facelets inside one face touch; faces are one dark LED apart. Width is 8 × 4 + 3 = 35, height is 6 × 3 + 2 = 20, so rows 20 to 24 stay dark. LED x of facelet column `fx` is `4 * fx + fx / 2`, LED y of facelet row `fy` is `3 * fy + fy / 2`. Colours: U white, D yellow, F green, B blue, R red, L orange (`0xFFFFFF`, `0xFFFF00`, `0x00B000`, `0x0000FF`, `0xFF0000`, `0xFF7000`).

**From solver state to pixels.** The solver state is `p[7]`, `o[7]` for the seven movable corners; the corner at position 0 never moves. The orientation digit `o` is the index of the corner's U/D sticker among the three faces of its position, counted clockwise as seen from outside the corner, starting from the U/D face. For the cubie `C` at position `q` with orientation `o`, face index `k` shows the colour of sticker `(k - o) mod 3` of `C`. Three small tables (`xy_tbl`, `colour_tbl`, `colors`) hold this; `tools/led_ref.c tables` generates them. The same program first checks, on 3000 random scrambles, that rotating 24 stickers in 3-D reproduces the `source` and `twist` tables of `solver.c`, which is how the sign of `o` was fixed rather than guessed.

**Driven by the solver.** After `search` returns `n` moves in `path`, `animate` loops `k = 0 .. n`: it calls the existing `is_solved` to replay the first `k` moves into `cur_st`, then `render` draws `cur_st`, then a pause (`li t0, 3000000`, about 6 million instructions) lets the frame be seen. Frame 0 is the scramble, frame `n` is the solved cube, and each frame in between differs from the last by one move, so the corners can be followed to their home positions. Nothing is recorded in advance.

**One source, two builds.** Ripes 2.2.6-106 rejects `.if`, `.else` and `.endif` (`Unknown directive '.if'`), so the assemble-time switch is a pre-assembly filter instead of `.equ RENDER, 0`. `stage5.s` is the master; `tools/variants.ps1` resolves the `#ifdef LED` blocks and writes `stage5_cli.s` and `stage5_led.s`, both plain files that Ripes assembles. **The two builds differ only in the renderer**: the `animate` and `render` code, the LED tables, and one `call animate` in `solve_case`. `stage5_cli.s` is `stage3.s` with a longer header comment, line for line (`diff` shows nothing else), and `measure_stage4.ps1 -Src stage5_cli.s` gives the same retired-instruction counts as `measure\stage4_results.csv` for all 11 base states (7,463,271 for `21345671111111`). The LED build cannot be measured with `--iret`, since `LED_MATRIX_0_BASE` is undefined under `--mode cli`.

**What was and was not tested.**
- Renderer logic, with Ripes CLI: a third variant, DUMP, uses the same `render` but points it at a 35 × 25 word array in memory instead of the LED base address, and prints the array after every frame. `tools\verify_led.ps1 -Ripes <Ripes.exe>` runs 9 states (solved, 3, 8, 9, 10 and 11 moves, including the worst IDA\* cases) and compares every frame, 80 in all, with frames computed by turning 3-D stickers. The check starts from the solved cube, undoes the solution backwards to get the scramble, and confirms that the scramble matches the 14 input digits; all 9 cases pass. Flipping one pixel in the captured output makes the check fail.
- Not tested: the LED build in the Ripes GUI. The only difference from the DUMP build is the base address and `LED_MATRIX_0_WIDTH` coming from the peripheral instead of from `.equ`; the LED build was assembled and run to completion in the CLI with those three symbols supplied as `.equ`. The pause length was chosen from the CLI speed of about 12 million instructions per second and has not been tuned in the GUI.

### 4.8 Ripes Instruction-Level Walkthrough

**Program.** `tools/walkthrough.s`, 25 instructions, built from the patterns `stage5_led.s` depends on. It was run on `RV32_ISS` and on `RV32_5S` and exits with code 55 on both, so the pipelined model computes the same result. `RV32_ISS` retires 25 instructions in 25 cycles; `RV32_5S` retires the same 25 instructions in 36 cycles, the difference being pipeline fill, the load-use stall and branch flushes.

**How to reproduce.** Processor tab: `RV32_5S`. Load `tools/walkthrough.s`, assemble, press Step once per clock cycle and read the signals on the datapath.

| # | Instruction | What to show | Expected signals |
| :-- | :-- | :-- | :-- |
| 1 | `slli t1, t0, 1` then `add t1, t1, t0` | shift-and-add multiply, forwarding | `RegWrite` = 1; ALU operand B selects the immediate for `slli` and the register for `add`; the `add` takes `t1` from the forwarding unit, no stall |
| 2 | `lbu t3, 0(t2)` then `add t4, t3, t1` | load-use hazard | `MemRead` = 1; write-back mux selects memory data; the `add` waits one cycle in ID, a bubble enters EX |
| 3 | `sw t4, 0(s1)`, `sb t3, 4(s1)` | memory update | `RegWrite` = 0, `MemWrite` = 1; the Memory tab at `fb` shows 55, then 40 at `fb + 4` |
| 4 | `bnez t5, loop` | taken branch | the PC mux selects the branch target; instructions fetched behind the branch are flushed; not taken on the third pass, PC + 4 |
| 5 | `lw a0, 0(s1)` | read back | `a0` = 55, which is the exit code |

**Per-stage view of one instruction**, `lbu t3, 0(t2)`: IF fetches it at PC; ID reads `t2` and sign-extends the offset 0; EX computes `t2 + 0`; MEM reads one byte and zero-extends it; WB writes 40 into `t3`.

**Correctness argument.** Register and memory contents after the last instruction (`t4` = 55, byte at `fb + 4` = 40, `a0` = 55) are identical on the ISS and on the 5-stage model, and the cycle difference comes only from stalls and flushes, never from different results.

**Screenshots:** `TODO`, one per row of the table, taken from the Ripes window.

## Appendix

### A. Repository Layout
```
TODO
```

### B. Reproduction Steps
1. Run one state or the built-in cases on Ripes: see How to Run in Stage 4.
2. Regenerate the tables in `stage3.s`: `python tools/gen_stage3_tables.py stage3.s`.
3. Measure: `powershell -File measure\measure_stage4.ps1 -Ripes <Ripes.exe> -Worst`, then `measure\measure_ref.ps1` for the GCC reference (needs `riscv64-unknown-elf-gcc` in WSL).
. LED renderer: `powershell -File toolsvariants.ps1` writes `stage5_cli.s` and `stage5_led.s` from `stage5.s`; `powershell -File toolsverify_led.ps1 -Ripes <Ripes.exe>` checks every frame, needs gcc.

### C. References
- [Assignment 1 spec](https://hackmd.io/@sysprog/2026-arch-homework1)
- [sysprog21/minirubik](https://github.com/sysprog21/minirubik)
- [Ripes](https://github.com/mortbopet/Ripes)
