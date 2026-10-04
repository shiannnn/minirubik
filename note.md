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
| H3 | returned length equals BFS distance and the path reaches solved | 22,872 states (all 2,644 distance-11 states plus about 1 in 180 of the others), 0 wrong |

H3 is a sample for the non-distance-11 states, not exhaustive. A state can have several shortest solutions, and IDA\* need not pick the one the baseline BFS records. For `43752611332133` the baseline prints `R' D2 R2 D' R D2 B D' R2` and IDA\* prints `R D2 R2 D R D2 B D' R2`. Both are 9 moves and both reach solved.

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

Node counts on the host (same 22,872 states as H3; distance-11 states only below):

| | Stage 2 | Stage 3 |
|---|---|---|
| Worst-case nodes, distance-11 | 114,384 | 424,243 |
| Mean nodes, distance-11 (2,644 states) | 14,616 | 47,317 |

Stage 3 visits about 3.7× more nodes because it dropped the permutation table, but each node is about 10× cheaper in operations and uses no multiplication:

- Budget: 5×10⁷ ÷ 424,243 ≈ 118 instructions per node. The Stage 3 estimate of about 45 fits with margin.
- Stage 2 at its worst case: 114,384 × 470 ≈ 5.4×10⁷ operations before counting that each of its ≈ 33 multiplications and divisions expands to a shift-add loop or a `__mulsi3` call on RV32I. It would exceed the budget by a wide margin.

The measured Stage 4 instruction count may differ from these estimates. If it exceeds about 118 per node, the permutation table can be added back as nibbles (about 2.5 KB) to bring the node count back near 114k.

### 3.4 C Code

Full source: `stage3.c` (link to the GitHub repository goes here). Key fragments:

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
## Stage 2: Choose Representation and Algorithm

### 2.1 State Representation
- Choice and justification against Stage 1 measurements and the 128 KiB budget

### 2.2 Algorithm
- Candidates: admissible heuristics / pattern databases / iterative deepening
- Final choice and rationale

### 2.3 Memory Budget
| Item | Size (bytes) |
|---|---|
| Factored transition tables | 34,614 |
| Heuristic tables | TODO |
| Other | TODO |
| **Total (≤ 128 KiB)** | TODO |

### 2.4 Termination and Optimality
- Termination argument
- Optimality argument (shortest solution)

### 2.5 Precomputation
- Tables generated on the host and linked as read-only data
- Confirm no complete distance table over all 3,674,160 states

## Stage 3: Improve Efficiency in C First

### 3.1 Eliminating Multiply and Divide
- Index computation (shifts for powers of two; ×3/5/7/9 as shift plus add/subtract)
- Modulo 3 (orientation sum ≤ 4, single conditional subtract)
- Branchless modulo (arithmetic-shift mask)

### 3.2 Reducing Branches and Memory Traffic
- Before/after comparison

### 3.3 Operation Count Analysis
| Version | Mul/Div | Branches | Loads/Stores | Total ops |
|---|---|---|---|---|
| Original C | | | | |
| Optimized C | | | | |

### 3.4 C Code
```c
// TODO
```

## Stage 4: Translate to RV32I Assembly

### 4.1 Design and Constraint Checklist
- [ ] RV32I only (no M extension, no compiler-generated routines)
- [ ] No heap, recursion, or floating point
- [ ] Input: 14-character cube state string (inlined at assembly time)
- [ ] `.data` + `.bss` + `.rodata` ≤ 128 KiB

### 4.2 Program Structure
- Data layout (tables / state / stack)
- Functions and register conventions
- Main flow (input → search → validate → output)

### 4.3 Iterative Refinement Log
| Version | Change | `.text` bytes | Retired instr (`--iret`) |
|---|---|---|---|
| v0 | Initial version | | |
| v1 | | | |
| v2 | | | |

> Conventions: `.text` is the linked size with the renderer compiled out; instruction counts use `--iret` on the pinned Ripes build.

### 4.4 Comparison with the GCC Reference
- Build command: `riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32`

| | Retired instr | Code size |
|---|---|---|
| GCC reference | | |
| This implementation | | |

### 4.5 Correctness Tests
| ID | Description | Result |
|---|---|---|
| H1 | Heuristic admissibility: h(s) ≤ d(s) over all 3,674,160 states | |
| H2 | All tables fully populated; maximum value and solved entry checked | |
| H3 | Search returns the optimal length for every state | |
| H4 | Packed accessor agrees with unpacked reference | |
| T5 | Applying the returned path reaches the solved state on Ripes | |
| T6 | `21345671111111` returns an 11-move optimal solution | |
| T7 | Three test cases reproduce on RV32_ISS and at least one visual pipeline model | |

#### Test Cases
1. Solved cube: `TODO`
2. Short scramble: `TODO`
3. Distance-11 state: `21345671111111`

### 4.6 Pass Conditions
- [ ] Static data ≤ 128 KiB: `TODO`
- [ ] Every distance-11 state ≤ 5×10⁷ retired instructions on RV32_ISS: `TODO`
- [ ] Instruction count for `21345671111111` (reported separately): `TODO`

### 4.7 LED Matrix Visualization
- Peripheral: 35 × 25, one 32-bit word per LED (24-bit RGB), index `y * WIDTH + x`
- Symbols: `LED_MATRIX_0_BASE` / `_WIDTH` / `_HEIGHT`
- Unfolded net on a 4×3 face grid (6 slots used); facelets 4×3 px with separators (35 wide × 20 tall)
- Redraw after every solver move (not a pre-recorded animation); distinguishable face colors
- Assembler switch: `.equ RENDER, 0` with `.if RENDER`
- State that the GUI build (animated) and CLI build (measured) differ only in the renderer

### 4.8 Ripes Instruction-Level Walkthrough
- Signals: register write enable, multiplexer selection
- Pipeline stages: IF / ID / EX / MEM / WB
- Memory updates and correctness argument
- Screenshots / video link: `TODO`

## Appendix

### A. Repository Layout
```
TODO
```

### B. Reproduction Steps
1. 
2. 

### C. References
- [Assignment 1 spec](https://hackmd.io/@sysprog/2026-arch-homework1)
- [sysprog21/minirubik](https://github.com/sysprog21/minirubik)
- [Ripes](https://github.com/mortbopet/Ripes)
