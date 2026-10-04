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
- Cube (2x2x2) state representation and invariants
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
