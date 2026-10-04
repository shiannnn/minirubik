# Assignment 1 Phase 1: minirubik on RV32I

###### tags: `computer-architecture` `RISC-V` `Ripes` `minirubik`

> **Due**: 2026-10-08 11:59 (GMT+8)
> **Fork source**: sysprog21/minirubik (commit: `TODO`)
> **Ripes version**: `TODO` (processor model: `RV32_ISS`)

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
#### 1.2.1 Host-bytes-per-guest-byte ratio
- Methodology (tight memory loop over a large region)
- Results

#### 1.2.2 Retired instructions per second
| Processor model | Rate (instr/s) | Notes |
|---|---|---|
| RV32_ISS | TODO | |
| Pipelined model (TODO) | TODO | |

### 1.3 Why the Full Baseline Table Is Fatal on the Target
- Memory analysis (~17.553 MiB)
- Time analysis (~10⁹ instructions ÷ measured rate)
- Conclusion

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
# Assignment 1: Optimizations and RISC-V Assembly

###### tags: `computer-architecture` `RISC-V` `Ripes` `minirubik`

> **Due**: 2026-10-08 11:59 (GMT+8)
> **Fork source**: sysprog21/minirubik (commit: `TODO`)
> **Ripes version**: `TODO` (processor model: `RV32_ISS`)

## Table of Contents

[TOC]

## 0. Preparation

- [ ] Complete Lab1: RV32I Simulator
- [ ] Install Ripes (`RV32_ISS`) and record the version
- [ ] Fork sysprog21/minirubik and record the source commit
- [ ] Push all work as commits with meaningful messages

## Stage 1: Characterize the Baseline

### 1.1 Program Analysis
- What the program computes
    The program solves a 2×2×2 cube optimally. Given a scrambled position, it prints a shortest move sequence (at most 11 moves in the half-turn metric) that returns the cube to solved.
- Cube (2x2x2) state representation and invariants
    ```
    Permutation validity
    ```
- Where the cost concentrates (3,674,160 states / 33,067,440 edges / ~66M transition updates)

### 1.2 Measurements
#### 1.2.1 Host-bytes-per-guest-byte ratio
- Methodology (tight memory loop over a large region)
- Results

#### 1.2.2 Retired instructions per second
| Processor model | Rate (instr/s) | Notes |
|---|---|---|
| RV32_ISS | TODO | |
| Pipelined model (TODO) | TODO | |

### 1.3 Why the Full Baseline Table Is Fatal on the Target
- Memory analysis (~17.553 MiB)
- Time analysis (~10⁹ instructions ÷ measured rate)
- Conclusion

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
