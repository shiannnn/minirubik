# GENERATED from stage5.s by tools\variants.ps1, CLI build, no renderer. Do not edit.
# Stage 5: the Stage 4 solver below plus an LED matrix renderer. This is the
# master source. Ripes has no conditional assembly, so tools/variants.ps1
# filters the #ifdef lines and writes two plain files from it:
#   stage5_cli.s   no renderer, identical to stage3.s apart from this header.
#                  Assembles under Ripes --mode cli, which has no peripherals,
#                  so this is the build that --iret measures.
#   stage5_led.s   adds the renderer. Needs an LED Matrix in the Ripes I/O tab,
#                  Width 35 and Height 25. The panel lists Height above Width.
# The two builds differ only in the renderer: animate, render and its tables,
# and one call to animate in solve_case. The search code is the same source lines.
# GUI run: load stage5_led.s, processor RV32_ISS, run. With a0 = 0 the three
# built-in cases are solved one after the other, and after each solve the cube
# is drawn as a net, once as given and once after every move of the solution.
# The pause between frames is the li t0 in animate, raise it for slower playback.
#
# Stage 4: stage3.c IDA* + 4-bit pattern database in pure RV32I.
#
#   - only RV32I instructions: no mul/div/rem, no libgcc helpers
#   - no recursion, explicit 16-frame array, no heap, no floating point
#   - ./.rodata tables are generated on the host by tools/gen_stage3_tables.py
#     they are the same onext / lnext / pdb arrays that stage3.c builds
#   - input: 14-character cube states inlined as .string in `cases`
#   - the program checks itself: the returned length must equal the expected
#     distance and the path is replayed on a full 7-cubie model
#
# Ripes: load this file, run on RV32_ISS. Exit code a7=93 = number of failed
# cases; the console prints one line per case.
# Two ways to run:
#   no input     a0 = 0 at start: the three built-in cases are solved and checked
#   CLI input    Ripes --reginit "gpr:10=PPPPPPP,11=OOOOOOO" solves one state,
#                see note.md for the exact command
# The built-in cases are the case0 to case2 strings near the end of the file.
#
# Only directives that every Ripes build accepts are used: .text .data .byte
# .half .word .string .zero .align, so there is no .section, .rodata or .bss:
# all static data sits in .data, tables first, scratch last.

# frame layout, 16 bytes per search depth, used as literal offsets
#   0 half  orientation index of the node       2 half  cursor orientation index
#   4 byte  location index of the node          5 byte  cursor location index
#   6 byte  face being tried 0..2 = R B D      7 byte  quarter turns applied so far
#   8 byte  face used by the parent move

        .text
        .globl  _start
        .globl  solve_case
_start:
        beqz    a0, run_cases           # no input given: run the built-in cases
        # CLI input, Ripes --reginit "gpr:10=PPPPPPP,11=OOOOOOO"
        #   a0 = the 7 permutation digits as a decimal number
        #   a1 = the 7 orientation digits as a decimal number
        # They are turned back into the 14 character string, one digit at a
        # time by subtracting powers of ten, so no divide is needed.
        la      t0, in_buf
        li      t4, 2                   # two numbers
cli_num:
        la      t1, pow10
        li      t2, 7                   # digits per number
cli_digit:
        lw      t3, 0(t1)
        li      t5, 48                  # ascii 0
cli_sub:
        blt     a0, t3, cli_emit
        sub     a0, a0, t3
        addi    t5, t5, 1
        j       cli_sub
cli_emit:
        sb      t5, 0(t0)
        addi    t0, t0, 1
        addi    t1, t1, 4
        addi    t2, t2, -1
        bnez    t2, cli_digit
        mv      a0, a1                  # second number
        addi    t4, t4, -1
        bnez    t4, cli_num
        sb      zero, 0(t0)
        la      a0, in_buf
        li      a1, -1                  # no expected distance
        call    solve_case
        xori    a0, a0, 1               # exit code 0 = solved, 1 = failed
        li      a7, 93
        nop                             # let a7 reach the register file before ecall
        nop
        nop
        ecall
run_cases:
        li      s2, 0                   # case index
        li      s3, 0                   # failures
case_loop:
        li      t0, 3                   # number of cases
        bge     s2, t0, case_done
        slli    t0, s2, 3
        la      t1, cases
        add     t0, t0, t1
        lw      a0, 0(t0)
        lw      a1, 4(t0)
        call    solve_case
        xori    a0, a0, 1
        add     s3, s3, a0
        addi    s2, s2, 1
        j       case_loop
case_done:
        la      a0, msg_pass
        beqz    s3, case_print
        la      a0, msg_fail
case_print:
        call    put_str
        mv      a0, s3
        li      a7, 93
        nop                             # let a7 reach the register file before ecall
        nop
        nop
        ecall

# ---------------------------------------------------------------------------
# solve_case: a0 = state string, a1 = expected distance or -1 -> a0 = 1 if ok
# ---------------------------------------------------------------------------
solve_case:
        addi    sp, sp, -32
        sw      ra, 28(sp)
        sw      s0, 24(sp)
        sw      s1, 20(sp)
        sw      s2, 16(sp)
        mv      s0, a0                  # state string
        mv      s1, a1                  # expected
        la      a1, root_st
        call    parse
        beqz    a0, sc_invalid
        la      a0, root_st
        call    search
        mv      s2, a0                  # length or -1
        li      t0, 1
        bltz    s2, sc_report           # no solution found: fail t0 -> 0
        bltz    s1, sc_replay           # no expectation given
        beq     s2, s1, sc_replay
        li      t0, 0
        j       sc_report
sc_replay:
        la      a0, root_st
        mv      a1, s2
        call    is_solved               # independent replay on the full model
        mv      t0, a0
sc_report:
        mv      s1, t0                  # s1 = pass flag
        la      a0, msg_ok
        bnez    s1, sc_head
        la      a0, msg_bad
sc_head:
        call    put_str
        mv      a0, s0
        call    put_str
        la      a0, msg_sep
        call    put_str
        bltz    s2, sc_nosol
        mv      a0, s2
        call    put_uint
        la      a0, msg_moves
        call    put_str
        li      s0, 0                   # print the path
sc_path:
        bge     s0, s2, sc_end
        la      t0, path
        add     t0, t0, s0
        lbu     t0, 0(t0)
        slli    t0, t0, 2
        la      a0, move_names
        add     a0, a0, t0
        call    put_str
        la      a0, msg_space
        call    put_str
        addi    s0, s0, 1
        j       sc_path
sc_nosol:
        la      a0, msg_nosol
        call    put_str
sc_end:
        la      a0, msg_nl
        call    put_str
        mv      a0, s1
        j       sc_ret
sc_invalid:
        la      a0, msg_inv
        call    put_str
        mv      a0, s0
        call    put_str
        la      a0, msg_nl
        call    put_str
        li      a0, 0
sc_ret:
        lw      ra, 28(sp)
        lw      s0, 24(sp)
        lw      s1, 20(sp)
        lw      s2, 16(sp)
        addi    sp, sp, 32
        ret

# ---------------------------------------------------------------------------
# parse: a0 = string, a1 = dest 16 bytes, perm at offset 0, orient at offset 8 -> a0 = ok
# Accepts exactly 14 digits; perm digits 1..7 without repeats; orientation
# digits 1..3 whose sum is a multiple of 3 the reachable states of the cube.
# ---------------------------------------------------------------------------
parse:
        li      t0, 0                   # i
        li      t1, 0                   # seen bitmask
        li      t2, 0                   # orientation sum
pa_loop:
        add     t3, a0, t0
        lbu     t4, 0(t3)
        addi    t4, t4, -49             # '1'
        li      t5, 6
        bltu    t5, t4, pa_bad          # perm digit out of 1..7
        add     t6, a1, t0
        sb      t4, 0(t6)
        li      t6, 1
        sll     t6, t6, t4
        and     t5, t1, t6
        bnez    t5, pa_bad              # repeated cubie
        or      t1, t1, t6
        lbu     t4, 7(t3)
        addi    t4, t4, -49
        li      t5, 2
        bltu    t5, t4, pa_bad          # orientation digit out of 1..3
        add     t6, a1, t0
        sb      t4, 8(t6)
        add     t2, t2, t4
        addi    t0, t0, 1
        li      t5, 7
        bne     t0, t5, pa_loop
        lbu     t4, 14(a0)
        bnez    t4, pa_bad              # string longer than 14
pa_mod:
        li      t5, 3
        blt     t2, t5, pa_modend
        addi    t2, t2, -3
        j       pa_mod
pa_modend:
        bnez    t2, pa_bad
        li      a0, 1
        ret
pa_bad:
        li      a0, 0
        ret

# ---------------------------------------------------------------------------
# search: a0 = root state -> a0 = number of moves, path filled, or -1
# Same algorithm as search in stage3.c.
#   s0 frame pointer   s1 depth d      s2 bound       s3 onext
#   s4 lnext           s5 pdb          s6 root o      s7 &pathd
#   s8 root l          s9 root state
# ---------------------------------------------------------------------------
search:
        addi    sp, sp, -64
        sw      s10, 48(sp)
        sw      ra, 44(sp)
        sw      s0, 40(sp)
        sw      s1, 36(sp)
        sw      s2, 32(sp)
        sw      s3, 28(sp)
        sw      s4, 24(sp)
        sw      s5, 20(sp)
        sw      s6, 16(sp)
        sw      s7, 12(sp)
        sw      s8, 8(sp)
        sw      s9, 4(sp)
        mv      s9, a0
        li      s10, 3                  # constant 3 for the face and turn tests
        la      s3, onext
        la      s4, lnext
        la      s5, pdb

        # o0 = rank_orient: base-3 number of the first six orientations
        li      s6, 0
        li      t0, 0
rk_o:
        add     t1, s9, t0
        lbu     t1, 8(t1)
        slli    t2, s6, 1
        add     s6, t2, s6
        add     s6, s6, t1
        addi    t0, t0, 1
        li      t2, 6
        bne     t0, t2, rk_o

        # l0 = loc_index of cubies 0,1,2
        la      t3, loc_buf
        li      t0, 0
rk_l:
        add     t1, s9, t0
        lbu     t1, 0(t1)               # cubie at slot j
        add     t2, t3, t1
        sb      t0, 0(t2)               # loccubie = slot all 7 cubies
        addi    t0, t0, 1
        li      t2, 7
        bne     t0, t2, rk_l
        lbu     a2, 0(t3)
        lbu     a3, 1(t3)
        lbu     a4, 2(t3)
        sltu    t0, a2, a3              # l1 > l0
        sub     a3, a3, t0              # r1
        sltu    t0, a2, a4              # l2 > l0
        sub     a4, a4, t0
        lbu     t1, 1(t3)               # original l1 for l2 > l1
        lbu     t2, 2(t3)
        sltu    t0, t1, t2              # l2 > l1
        sub     a4, a4, t0              # r2
        slli    t0, a2, 2
        slli    t1, a2, 1
        add     t0, t0, t1              # l0 * 6
        add     t0, t0, a3
        slli    t1, t0, 2
        add     t0, t1, t0              # l0*6 + r1 * 5
        add     s8, t0, a4

        # h0 = pdbo0 * 210 + l0
        slli    t4, s6, 7
        slli    t0, s6, 6
        add     t4, t4, t0
        slli    t0, s6, 4
        add     t4, t4, t0
        slli    t0, s6, 1
        add     t4, t4, t0
        add     t4, t4, s8
        srli    a0, t4, 1
        add     a0, a0, s5
        lbu     a0, 0(a0)
        andi    a1, t4, 1
        slli    a1, a1, 2
        srl     a0, a0, a1
        andi    s2, a0, 15              # bound = h0
        bnez    s2, bound_init
        li      a1, 0
        call    quick_solved
        beqz    a0, bound_init
        li      a0, 0
        j       search_ret

bound_init:
        la      s0, frames
        li      s1, 0
        la      s7, path
        sh      s6, 0(s0)
        sh      s6, 2(s0)
        sb      s8, 4(s0)
        sb      s8, 5(s0)
        sb      zero, 6(s0)
        sb      zero, 7(s0)
        li      t0, 4
        sb      t0, 8(s0)

dfs_loop:
        lbu     t0, 7(s0)
        bne     t0, s10, face_chk
        sb      zero, 7(s0)        # finished one face: go to the next
        lbu     t2, 6(s0)
        addi    t2, t2, 1
        sb      t2, 6(s0)
        lhu     t3, 0(s0)
        sh      t3, 2(s0)
        lbu     t3, 4(s0)
        sb      t3, 5(s0)
        li      t0, 0
face_chk:
        lbu     t2, 6(s0)
        beq     t2, s10, backtrack       # frame exhausted
        lbu     t3, 8(s0)
        bne     t2, t3, expand
        addi    t2, t2, 1               # never repeat the parent's face
        sb      t2, 6(s0)
        j       dfs_loop

expand:                                 # t2 = face f, t0 = turn
        slli    t4, t2, 11              # onext row = f * 1024 halfwords
        add     t4, t4, s3
        lhu     t5, 2(s0)
        slli    t6, t5, 1
        add     t4, t4, t6
        lhu     t5, 0(t4)               # t5 = new orientation index
        sh      t5, 2(s0)
        slli    t4, t2, 8               # lnext row = f * 256 bytes
        add     t4, t4, s4
        lbu     t6, 5(s0)
        add     t4, t4, t6
        lbu     t6, 0(t4)               # t6 = new location index
        sb      t6, 5(s0)
        slli    t4, t2, 1               # move = 3f + turn
        add     t4, t4, t2
        add     t4, t4, t0
        sb      t4, 0(s7)               # pathd
        addi    t0, t0, 1
        sb      t0, 7(s0)
        slli    t4, t5, 7               # idx = o*210 + l, 210 = 128+64+16+2
        slli    a0, t5, 6
        add     t4, t4, a0
        slli    a0, t5, 4
        add     t4, t4, a0
        slli    a0, t5, 1
        add     t4, t4, a0
        add     t4, t4, t6
        srli    a0, t4, 1               # nibble read
        add     a0, a0, s5
        lbu     a0, 0(a0)
        andi    a1, t4, 1
        slli    a1, a1, 2
        srl     a0, a0, a1
        andi    a0, a0, 15              # a0 = h
        addi    a1, s1, 1               # a1 = d + 1
        add     a2, a1, a0
        blt     s2, a2, dfs_loop        # d + 1 + h > bound: prune
        bnez    a0, no_goal
        call    quick_solved            # h == 0: check the other four cubies
        bnez    a0, found
        lbu     t2, 6(s0)
        lhu     t5, 2(s0)
        lbu     t6, 5(s0)
        addi    a1, s1, 1
no_goal:
        beq     a1, s2, dfs_loop        # no budget left for children
        addi    s0, s0, 16              # push the child frame
        addi    s1, s1, 1
        addi    s7, s7, 1
        sh      t5, 0(s0)
        sh      t5, 2(s0)
        sb      t6, 4(s0)
        sb      t6, 5(s0)
        sb      zero, 6(s0)
        sb      zero, 7(s0)
        sb      t2, 8(s0)
        j       dfs_loop

backtrack:
        beqz    s1, next_bound
        addi    s0, s0, -16
        addi    s1, s1, -1
        addi    s7, s7, -1
        j       dfs_loop

next_bound:
        addi    s2, s2, 1
        li      t0, 12                  # every state is within 11 moves
        bne     s2, t0, bound_init
        li      a0, -1
        j       search_ret
found:
        addi    a0, s1, 1
search_ret:
        lw      ra, 44(sp)
        lw      s0, 40(sp)
        lw      s1, 36(sp)
        lw      s2, 32(sp)
        lw      s3, 28(sp)
        lw      s4, 24(sp)
        lw      s5, 20(sp)
        lw      s6, 16(sp)
        lw      s7, 12(sp)
        lw      s8, 8(sp)
        lw      s9, 4(sp)
        lw      s10, 48(sp)
        addi    sp, sp, 64
        ret

# ---------------------------------------------------------------------------
# is_solved: a0 = root state, a1 = n -> a0 = 1 if the first n moves of path solve the root
# Replays the moves on the full 7-cubie model, as quarter_turn does in stage3.c.
# Leaf routine: uses only a0-a7 and t0-t6.
# ---------------------------------------------------------------------------
is_solved:
        la      t0, cur_st
        la      t1, new_st
        lw      t2, 0(a0)
        sw      t2, 0(t0)
        lw      t2, 4(a0)
        sw      t2, 4(t0)
        lw      t2, 8(a0)
        sw      t2, 8(t0)
        lw      t2, 12(a0)
        sw      t2, 12(t0)
        la      t2, path
        mv      t3, a1
is_mv:
        beqz    t3, is_check
        lbu     a2, 0(t2)               # move m = 3f + turns - 1
        addi    t2, t2, 1
        addi    t3, t3, -1
        li      a3, 0                   # f
        li      a4, 3
        blt     a2, a4, is_fok
        li      a3, 1
        addi    a2, a2, -3
        blt     a2, a4, is_fok
        li      a3, 2
        addi    a2, a2, -3
is_fok:
        addi    a2, a2, 1               # number of quarter turns
is_qt:
        slli    a4, a3, 3               # rows of source/twist are 8 bytes
        la      a5, source_tbl
        add     a5, a5, a4
        la      a6, twist_tbl
        add     a6, a6, a4
        li      t4, 0
is_i:
        add     t5, a5, t4
        lbu     t5, 0(t5)               # s = sourcefi
        add     a0, t0, t5
        lbu     a0, 0(a0)
        add     a1, t1, t4
        sb      a0, 0(a1)               # new.pi = cur.ps
        add     a0, t0, t5
        lbu     a0, 8(a0)               # cur.os
        add     a1, a6, t4
        lbu     a1, 0(a1)               # twistfi
        add     a0, a0, a1
        li      a1, 3
        blt     a0, a1, is_nowrap
        addi    a0, a0, -3              # sum <= 4, so one subtract is enough
is_nowrap:
        add     a1, t1, t4
        sb      a0, 8(a1)
        addi    t4, t4, 1
        li      a0, 7
        bne     t4, a0, is_i
        lw      a0, 0(t1)
        sw      a0, 0(t0)
        lw      a0, 4(t1)
        sw      a0, 4(t0)
        lw      a0, 8(t1)
        sw      a0, 8(t0)
        lw      a0, 12(t1)
        sw      a0, 12(t0)
        addi    a2, a2, -1
        bnez    a2, is_qt
        j       is_mv
is_check:
        li      t4, 0
is_chk:
        add     t5, t0, t4
        lbu     a0, 0(t5)
        bne     a0, t4, is_no           # pi != i
        lbu     a0, 8(t5)
        bnez    a0, is_no               # oi != 0
        addi    t4, t4, 1
        li      a0, 7
        bne     t4, a0, is_chk
        li      a0, 1
        ret
is_no:
        li      a0, 0
        ret

# ---------------------------------------------------------------------------
# quick_solved: a1 = n -> a0 = 1 if the first n moves of path bring cubies 3..6 home.
# Only called when the pattern database says h == 0, i.e. cubies 0,1,2 are
# home and every orientation is 0, so the cube is solved iff cubies 3..6 are
# home. Follows the slot of each of those cubies with destfslot, the
# inverse of sourcef. loc_buf holds the root slot of every cubie.
# Leaf routine: uses only a0-a6 and t0-t3.
# ---------------------------------------------------------------------------
quick_solved:
        la      t0, loc_buf
        lbu     a2, 3(t0)
        lbu     a3, 4(t0)
        lbu     a4, 5(t0)
        lbu     a5, 6(t0)
        la      t0, path
        la      a6, dest_tbl
qs_mv:
        beqz    a1, qs_check
        lbu     t1, 0(t0)               # move m = 3f + turns - 1
        addi    t0, t0, 1
        addi    a1, a1, -1
        li      t2, 3
        li      t3, 0                   # row offset f * 8
        blt     t1, t2, qs_fok
        li      t3, 8
        addi    t1, t1, -3
        blt     t1, t2, qs_fok
        li      t3, 16
        addi    t1, t1, -3
qs_fok:
        add     t3, t3, a6              # dest row of face f
qs_qt:
        add     t2, t3, a2
        lbu     a2, 0(t2)
        add     t2, t3, a3
        lbu     a3, 0(t2)
        add     t2, t3, a4
        lbu     a4, 0(t2)
        add     t2, t3, a5
        lbu     a5, 0(t2)
        addi    t1, t1, -1
        bgez    t1, qs_qt               # turns - 1 further quarter turns
        j       qs_mv
qs_check:
        li      a0, 0
        li      t1, 3
        bne     a2, t1, qs_ret
        li      t1, 4
        bne     a3, t1, qs_ret
        li      t1, 5
        bne     a4, t1, qs_ret
        li      t1, 6
        bne     a5, t1, qs_ret
        li      a0, 1
qs_ret:
        ret

# ---------------------------------------------------------------------------
# console helpers
# ---------------------------------------------------------------------------
put_str:                                # a0 = NUL-terminated string
        li      a7, 4
        nop                             # let a7 reach the register file before ecall
        nop
        nop
        ecall
        ret

put_uint:                               # a0 = value 0..99, printed in decimal
        addi    sp, sp, -16
        sw      ra, 12(sp)
        li      t0, 0                   # tens
pu_div:
        li      t1, 10
        blt     a0, t1, pu_out
        addi    a0, a0, -10
        addi    t0, t0, 1
        j       pu_div
pu_out:
        la      t2, num_buf
        addi    t0, t0, 48
        addi    a0, a0, 48
        sb      t0, 0(t2)
        sb      a0, 1(t2)
        sb      zero, 2(t2)
        li      t1, 48
        bne     t0, t1, pu_print        # two digits
        addi    t2, t2, 1               # drop the leading zero
pu_print:
        mv      a0, t2
        call    put_str
        lw      ra, 12(sp)
        addi    sp, sp, 16
        ret

# ---------------------------------------------------------------------------
# read-only data
# ---------------------------------------------------------------------------
        .data
        .align  2
case0:  .string "12345671111111"        # solved cube
case1:  .string "23475162132323"        # short scramble R B-prime D
case2:  .string "21345671111111"        # distance-11 state
        .align  2
cases:                                  # { state string, expected distance }
        .word   case0, 0
        .word   case1, 3
        .word   case2, 11

pow10:                                  # powers of ten for the CLI input
        .word   1000000, 100000, 10000, 1000, 100, 10, 1
msg_ok:    .string "[PASS] "
msg_bad:   .string "[FAIL] "
msg_sep:   .string " : "
msg_moves: .string " moves: "
msg_space: .string " "
msg_nl:    .string "\n"
msg_nosol: .string "no solution"
msg_inv:   .string "[FAIL] invalid state "
msg_pass:  .string "all cases passed\n"
msg_fail:  .string "some cases FAILED\n"

        .align  2
move_names:                             # 9 moves, 4 bytes each, NUL padded
        .byte   82, 0, 0, 0             # R
        .byte   82, 50, 0, 0            # R2
        .byte   82, 39, 0, 0            # R'
        .byte   66, 0, 0, 0             # B
        .byte   66, 50, 0, 0            # B2
        .byte   66, 39, 0, 0            # B'
        .byte   68, 0, 0, 0             # D
        .byte   68, 50, 0, 0            # D2
        .byte   68, 39, 0, 0            # D'

source_tbl:                             # sourcefi, rows padded to 8
        .byte   1, 4, 2, 0, 3, 5, 6, 0
        .byte   0, 1, 2, 4, 5, 6, 3, 0
        .byte   0, 2, 5, 3, 1, 4, 6, 0
dest_tbl:                               # destfs: slot cubie s moves to
        .byte   3, 0, 2, 4, 1, 5, 6, 0
        .byte   0, 1, 2, 6, 3, 4, 5, 0
        .byte   0, 4, 1, 3, 5, 2, 6, 0
twist_tbl:                              # twistfi, rows padded to 8
        .byte   1, 2, 0, 2, 1, 0, 0, 0
        .byte   0, 0, 0, 1, 2, 1, 2, 0
        .byte   0, 0, 0, 0, 0, 0, 0, 0

# BEGIN GENERATED TABLES tools/gen_stage3_tables.py
        .align  2
onext:                                  # u16 3 x 1024, row = face << 10
        .half   426, 427, 428, 264, 265, 266, 345, 346, 347, 429, 430, 431, 267, 268, 269, 348
        .half   349, 350, 423, 424, 425, 261, 262, 263, 342, 343, 344, 453, 454, 455, 291, 292
        .half   293, 372, 373, 374, 456, 457, 458, 294, 295, 296, 375, 376, 377, 450, 451, 452
        .half   288, 289, 290, 369, 370, 371, 480, 481, 482, 318, 319, 320, 399, 400, 401, 483
        .half   484, 485, 321, 322, 323, 402, 403, 404, 477, 478, 479, 315, 316, 317, 396, 397
        .half   398, 669, 670, 671, 507, 508, 509, 588, 589, 590, 672, 673, 674, 510, 511, 512
        .half   591, 592, 593, 666, 667, 668, 504, 505, 506, 585, 586, 587, 696, 697, 698, 534
        .half   535, 536, 615, 616, 617, 699, 700, 701, 537, 538, 539, 618, 619, 620, 693, 694
        .half   695, 531, 532, 533, 612, 613, 614, 723, 724, 725, 561, 562, 563, 642, 643, 644
        .half   726, 727, 728, 564, 565, 566, 645, 646, 647, 720, 721, 722, 558, 559, 560, 639
        .half   640, 641, 183, 184, 185, 21, 22, 23, 102, 103, 104, 186, 187, 188, 24, 25
        .half   26, 105, 106, 107, 180, 181, 182, 18, 19, 20, 99, 100, 101, 210, 211, 212
        .half   48, 49, 50, 129, 130, 131, 213, 214, 215, 51, 52, 53, 132, 133, 134, 207
        .half   208, 209, 45, 46, 47, 126, 127, 128, 237, 238, 239, 75, 76, 77, 156, 157
        .half   158, 240, 241, 242, 78, 79, 80, 159, 160, 161, 234, 235, 236, 72, 73, 74
        .half   153, 154, 155, 408, 409, 410, 246, 247, 248, 327, 328, 329, 411, 412, 413, 249
        .half   250, 251, 330, 331, 332, 405, 406, 407, 243, 244, 245, 324, 325, 326, 435, 436
        .half   437, 273, 274, 275, 354, 355, 356, 438, 439, 440, 276, 277, 278, 357, 358, 359
        .half   432, 433, 434, 270, 271, 272, 351, 352, 353, 462, 463, 464, 300, 301, 302, 381
        .half   382, 383, 465, 466, 467, 303, 304, 305, 384, 385, 386, 459, 460, 461, 297, 298
        .half   299, 378, 379, 380, 651, 652, 653, 489, 490, 491, 570, 571, 572, 654, 655, 656
        .half   492, 493, 494, 573, 574, 575, 648, 649, 650, 486, 487, 488, 567, 568, 569, 678
        .half   679, 680, 516, 517, 518, 597, 598, 599, 681, 682, 683, 519, 520, 521, 600, 601
        .half   602, 675, 676, 677, 513, 514, 515, 594, 595, 596, 705, 706, 707, 543, 544, 545
        .half   624, 625, 626, 708, 709, 710, 546, 547, 548, 627, 628, 629, 702, 703, 704, 540
        .half   541, 542, 621, 622, 623, 165, 166, 167, 3, 4, 5, 84, 85, 86, 168, 169
        .half   170, 6, 7, 8, 87, 88, 89, 162, 163, 164, 0, 1, 2, 81, 82, 83
        .half   192, 193, 194, 30, 31, 32, 111, 112, 113, 195, 196, 197, 33, 34, 35, 114
        .half   115, 116, 189, 190, 191, 27, 28, 29, 108, 109, 110, 219, 220, 221, 57, 58
        .half   59, 138, 139, 140, 222, 223, 224, 60, 61, 62, 141, 142, 143, 216, 217, 218
        .half   54, 55, 56, 135, 136, 137, 417, 418, 419, 255, 256, 257, 336, 337, 338, 420
        .half   421, 422, 258, 259, 260, 339, 340, 341, 414, 415, 416, 252, 253, 254, 333, 334
        .half   335, 444, 445, 446, 282, 283, 284, 363, 364, 365, 447, 448, 449, 285, 286, 287
        .half   366, 367, 368, 441, 442, 443, 279, 280, 281, 360, 361, 362, 471, 472, 473, 309
        .half   310, 311, 390, 391, 392, 474, 475, 476, 312, 313, 314, 393, 394, 395, 468, 469
        .half   470, 306, 307, 308, 387, 388, 389, 660, 661, 662, 498, 499, 500, 579, 580, 581
        .half   663, 664, 665, 501, 502, 503, 582, 583, 584, 657, 658, 659, 495, 496, 497, 576
        .half   577, 578, 687, 688, 689, 525, 526, 527, 606, 607, 608, 690, 691, 692, 528, 529
        .half   530, 609, 610, 611, 684, 685, 686, 522, 523, 524, 603, 604, 605, 714, 715, 716
        .half   552, 553, 554, 633, 634, 635, 717, 718, 719, 555, 556, 557, 636, 637, 638, 711
        .half   712, 713, 549, 550, 551, 630, 631, 632, 174, 175, 176, 12, 13, 14, 93, 94
        .half   95, 177, 178, 179, 15, 16, 17, 96, 97, 98, 171, 172, 173, 9, 10, 11
        .half   90, 91, 92, 201, 202, 203, 39, 40, 41, 120, 121, 122, 204, 205, 206, 42
        .half   43, 44, 123, 124, 125, 198, 199, 200, 36, 37, 38, 117, 118, 119, 228, 229
        .half   230, 66, 67, 68, 147, 148, 149, 231, 232, 233, 69, 70, 71, 150, 151, 152
        .half   225, 226, 227, 63, 64, 65, 144, 145, 146, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   16, 9, 14, 24, 20, 22, 8, 1, 3, 15, 11, 13, 26, 19, 21, 7
        .half   0, 5, 17, 10, 12, 25, 18, 23, 6, 2, 4, 42, 38, 40, 53, 46
        .half   48, 34, 27, 32, 44, 37, 39, 52, 45, 50, 33, 29, 31, 43, 36, 41
        .half   51, 47, 49, 35, 28, 30, 71, 64, 66, 79, 72, 77, 60, 56, 58, 70
        .half   63, 68, 78, 74, 76, 62, 55, 57, 69, 65, 67, 80, 73, 75, 61, 54
        .half   59, 96, 92, 94, 107, 100, 102, 88, 81, 86, 98, 91, 93, 106, 99, 104
        .half   87, 83, 85, 97, 90, 95, 105, 101, 103, 89, 82, 84, 125, 118, 120, 133
        .half   126, 131, 114, 110, 112, 124, 117, 122, 132, 128, 130, 116, 109, 111, 123, 119
        .half   121, 134, 127, 129, 115, 108, 113, 151, 144, 149, 159, 155, 157, 143, 136, 138
        .half   150, 146, 148, 161, 154, 156, 142, 135, 140, 152, 145, 147, 160, 153, 158, 141
        .half   137, 139, 179, 172, 174, 187, 180, 185, 168, 164, 166, 178, 171, 176, 186, 182
        .half   184, 170, 163, 165, 177, 173, 175, 188, 181, 183, 169, 162, 167, 205, 198, 203
        .half   213, 209, 211, 197, 190, 192, 204, 200, 202, 215, 208, 210, 196, 189, 194, 206
        .half   199, 201, 214, 207, 212, 195, 191, 193, 231, 227, 229, 242, 235, 237, 223, 216
        .half   221, 233, 226, 228, 241, 234, 239, 222, 218, 220, 232, 225, 230, 240, 236, 238
        .half   224, 217, 219, 258, 254, 256, 269, 262, 264, 250, 243, 248, 260, 253, 255, 268
        .half   261, 266, 249, 245, 247, 259, 252, 257, 267, 263, 265, 251, 244, 246, 287, 280
        .half   282, 295, 288, 293, 276, 272, 274, 286, 279, 284, 294, 290, 292, 278, 271, 273
        .half   285, 281, 283, 296, 289, 291, 277, 270, 275, 313, 306, 311, 321, 317, 319, 305
        .half   298, 300, 312, 308, 310, 323, 316, 318, 304, 297, 302, 314, 307, 309, 322, 315
        .half   320, 303, 299, 301, 341, 334, 336, 349, 342, 347, 330, 326, 328, 340, 333, 338
        .half   348, 344, 346, 332, 325, 327, 339, 335, 337, 350, 343, 345, 331, 324, 329, 367
        .half   360, 365, 375, 371, 373, 359, 352, 354, 366, 362, 364, 377, 370, 372, 358, 351
        .half   356, 368, 361, 363, 376, 369, 374, 357, 353, 355, 393, 389, 391, 404, 397, 399
        .half   385, 378, 383, 395, 388, 390, 403, 396, 401, 384, 380, 382, 394, 387, 392, 402
        .half   398, 400, 386, 379, 381, 421, 414, 419, 429, 425, 427, 413, 406, 408, 420, 416
        .half   418, 431, 424, 426, 412, 405, 410, 422, 415, 417, 430, 423, 428, 411, 407, 409
        .half   447, 443, 445, 458, 451, 453, 439, 432, 437, 449, 442, 444, 457, 450, 455, 438
        .half   434, 436, 448, 441, 446, 456, 452, 454, 440, 433, 435, 476, 469, 471, 484, 477
        .half   482, 465, 461, 463, 475, 468, 473, 483, 479, 481, 467, 460, 462, 474, 470, 472
        .half   485, 478, 480, 466, 459, 464, 503, 496, 498, 511, 504, 509, 492, 488, 490, 502
        .half   495, 500, 510, 506, 508, 494, 487, 489, 501, 497, 499, 512, 505, 507, 493, 486
        .half   491, 529, 522, 527, 537, 533, 535, 521, 514, 516, 528, 524, 526, 539, 532, 534
        .half   520, 513, 518, 530, 523, 525, 538, 531, 536, 519, 515, 517, 555, 551, 553, 566
        .half   559, 561, 547, 540, 545, 557, 550, 552, 565, 558, 563, 546, 542, 544, 556, 549
        .half   554, 564, 560, 562, 548, 541, 543, 583, 576, 581, 591, 587, 589, 575, 568, 570
        .half   582, 578, 580, 593, 586, 588, 574, 567, 572, 584, 577, 579, 592, 585, 590, 573
        .half   569, 571, 609, 605, 607, 620, 613, 615, 601, 594, 599, 611, 604, 606, 619, 612
        .half   617, 600, 596, 598, 610, 603, 608, 618, 614, 616, 602, 595, 597, 638, 631, 633
        .half   646, 639, 644, 627, 623, 625, 637, 630, 635, 645, 641, 643, 629, 622, 624, 636
        .half   632, 634, 647, 640, 642, 628, 621, 626, 663, 659, 661, 674, 667, 669, 655, 648
        .half   653, 665, 658, 660, 673, 666, 671, 654, 650, 652, 664, 657, 662, 672, 668, 670
        .half   656, 649, 651, 692, 685, 687, 700, 693, 698, 681, 677, 679, 691, 684, 689, 699
        .half   695, 697, 683, 676, 678, 690, 686, 688, 701, 694, 696, 682, 675, 680, 718, 711
        .half   716, 726, 722, 724, 710, 703, 705, 717, 713, 715, 728, 721, 723, 709, 702, 707
        .half   719, 712, 714, 727, 720, 725, 708, 704, 706, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 27, 54, 1, 28, 55, 2, 29, 56, 9, 36, 63, 10, 37, 64, 11
        .half   38, 65, 18, 45, 72, 19, 46, 73, 20, 47, 74, 81, 108, 135, 82, 109
        .half   136, 83, 110, 137, 90, 117, 144, 91, 118, 145, 92, 119, 146, 99, 126, 153
        .half   100, 127, 154, 101, 128, 155, 162, 189, 216, 163, 190, 217, 164, 191, 218, 171
        .half   198, 225, 172, 199, 226, 173, 200, 227, 180, 207, 234, 181, 208, 235, 182, 209
        .half   236, 3, 30, 57, 4, 31, 58, 5, 32, 59, 12, 39, 66, 13, 40, 67
        .half   14, 41, 68, 21, 48, 75, 22, 49, 76, 23, 50, 77, 84, 111, 138, 85
        .half   112, 139, 86, 113, 140, 93, 120, 147, 94, 121, 148, 95, 122, 149, 102, 129
        .half   156, 103, 130, 157, 104, 131, 158, 165, 192, 219, 166, 193, 220, 167, 194, 221
        .half   174, 201, 228, 175, 202, 229, 176, 203, 230, 183, 210, 237, 184, 211, 238, 185
        .half   212, 239, 6, 33, 60, 7, 34, 61, 8, 35, 62, 15, 42, 69, 16, 43
        .half   70, 17, 44, 71, 24, 51, 78, 25, 52, 79, 26, 53, 80, 87, 114, 141
        .half   88, 115, 142, 89, 116, 143, 96, 123, 150, 97, 124, 151, 98, 125, 152, 105
        .half   132, 159, 106, 133, 160, 107, 134, 161, 168, 195, 222, 169, 196, 223, 170, 197
        .half   224, 177, 204, 231, 178, 205, 232, 179, 206, 233, 186, 213, 240, 187, 214, 241
        .half   188, 215, 242, 243, 270, 297, 244, 271, 298, 245, 272, 299, 252, 279, 306, 253
        .half   280, 307, 254, 281, 308, 261, 288, 315, 262, 289, 316, 263, 290, 317, 324, 351
        .half   378, 325, 352, 379, 326, 353, 380, 333, 360, 387, 334, 361, 388, 335, 362, 389
        .half   342, 369, 396, 343, 370, 397, 344, 371, 398, 405, 432, 459, 406, 433, 460, 407
        .half   434, 461, 414, 441, 468, 415, 442, 469, 416, 443, 470, 423, 450, 477, 424, 451
        .half   478, 425, 452, 479, 246, 273, 300, 247, 274, 301, 248, 275, 302, 255, 282, 309
        .half   256, 283, 310, 257, 284, 311, 264, 291, 318, 265, 292, 319, 266, 293, 320, 327
        .half   354, 381, 328, 355, 382, 329, 356, 383, 336, 363, 390, 337, 364, 391, 338, 365
        .half   392, 345, 372, 399, 346, 373, 400, 347, 374, 401, 408, 435, 462, 409, 436, 463
        .half   410, 437, 464, 417, 444, 471, 418, 445, 472, 419, 446, 473, 426, 453, 480, 427
        .half   454, 481, 428, 455, 482, 249, 276, 303, 250, 277, 304, 251, 278, 305, 258, 285
        .half   312, 259, 286, 313, 260, 287, 314, 267, 294, 321, 268, 295, 322, 269, 296, 323
        .half   330, 357, 384, 331, 358, 385, 332, 359, 386, 339, 366, 393, 340, 367, 394, 341
        .half   368, 395, 348, 375, 402, 349, 376, 403, 350, 377, 404, 411, 438, 465, 412, 439
        .half   466, 413, 440, 467, 420, 447, 474, 421, 448, 475, 422, 449, 476, 429, 456, 483
        .half   430, 457, 484, 431, 458, 485, 486, 513, 540, 487, 514, 541, 488, 515, 542, 495
        .half   522, 549, 496, 523, 550, 497, 524, 551, 504, 531, 558, 505, 532, 559, 506, 533
        .half   560, 567, 594, 621, 568, 595, 622, 569, 596, 623, 576, 603, 630, 577, 604, 631
        .half   578, 605, 632, 585, 612, 639, 586, 613, 640, 587, 614, 641, 648, 675, 702, 649
        .half   676, 703, 650, 677, 704, 657, 684, 711, 658, 685, 712, 659, 686, 713, 666, 693
        .half   720, 667, 694, 721, 668, 695, 722, 489, 516, 543, 490, 517, 544, 491, 518, 545
        .half   498, 525, 552, 499, 526, 553, 500, 527, 554, 507, 534, 561, 508, 535, 562, 509
        .half   536, 563, 570, 597, 624, 571, 598, 625, 572, 599, 626, 579, 606, 633, 580, 607
        .half   634, 581, 608, 635, 588, 615, 642, 589, 616, 643, 590, 617, 644, 651, 678, 705
        .half   652, 679, 706, 653, 680, 707, 660, 687, 714, 661, 688, 715, 662, 689, 716, 669
        .half   696, 723, 670, 697, 724, 671, 698, 725, 492, 519, 546, 493, 520, 547, 494, 521
        .half   548, 501, 528, 555, 502, 529, 556, 503, 530, 557, 510, 537, 564, 511, 538, 565
        .half   512, 539, 566, 573, 600, 627, 574, 601, 628, 575, 602, 629, 582, 609, 636, 583
        .half   610, 637, 584, 611, 638, 591, 618, 645, 592, 619, 646, 593, 620, 647, 654, 681
        .half   708, 655, 682, 709, 656, 683, 710, 663, 690, 717, 664, 691, 718, 665, 692, 719
        .half   672, 699, 726, 673, 700, 727, 674, 701, 728, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .half   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
lnext:                                  # u8 3 x 256, row = face << 8
        .byte   91, 92, 90, 93, 94, 100, 102, 101, 103, 104, 105, 107, 106, 108, 109, 95, 96, 97, 98, 99, 110, 112, 113, 111, 114, 115, 117, 118, 116, 119, 11, 12
        .byte   10, 13, 14, 6, 7, 5, 8, 9, 17, 16, 15, 18, 19, 1, 0, 2, 3, 4, 22, 21, 23, 20, 24, 27, 26, 28, 25, 29, 70, 72, 71, 73
        .byte   74, 61, 62, 60, 63, 64, 77, 75, 76, 78, 79, 66, 65, 67, 68, 69, 82, 80, 83, 81, 84, 87, 85, 88, 86, 89, 135, 137, 136, 138, 139, 122
        .byte   121, 120, 123, 124, 132, 130, 131, 133, 134, 127, 125, 126, 128, 129, 143, 140, 142, 141, 144, 148, 145, 147, 146, 149, 40, 41, 42, 43, 44, 31, 30, 32
        .byte   33, 34, 36, 35, 37, 38, 39, 47, 45, 46, 48, 49, 52, 50, 51, 53, 54, 57, 55, 56, 58, 59, 165, 167, 168, 166, 169, 152, 151, 153, 150, 154
        .byte   162, 160, 163, 161, 164, 173, 170, 172, 171, 174, 157, 155, 156, 158, 159, 178, 175, 177, 179, 176, 195, 197, 198, 196, 199, 182, 181, 183, 180, 184, 192, 190
        .byte   193, 191, 194, 203, 200, 202, 201, 204, 187, 185, 186, 188, 189, 208, 205, 207, 209, 206, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 4, 1, 2, 3, 5, 9, 6, 7, 8, 25, 26, 27, 28, 29, 10, 11, 14, 12, 13, 15, 16, 19, 17, 18, 20, 21, 24, 22, 23, 30, 34
        .byte   31, 32, 33, 35, 39, 36, 37, 38, 55, 56, 57, 58, 59, 40, 41, 44, 42, 43, 45, 46, 49, 47, 48, 50, 51, 54, 52, 53, 60, 64, 61, 62
        .byte   63, 65, 69, 66, 67, 68, 85, 86, 87, 88, 89, 70, 71, 74, 72, 73, 75, 76, 79, 77, 78, 80, 81, 84, 82, 83, 180, 181, 182, 183, 184, 185
        .byte   186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 90, 91, 94, 92, 93, 95, 96, 99
        .byte   97, 98, 100, 101, 104, 102, 103, 115, 116, 117, 118, 119, 105, 106, 107, 109, 108, 110, 111, 112, 114, 113, 120, 121, 124, 122, 123, 125, 126, 129, 127, 128
        .byte   130, 131, 134, 132, 133, 145, 146, 147, 148, 149, 135, 136, 137, 139, 138, 140, 141, 142, 144, 143, 150, 151, 154, 152, 153, 155, 156, 159, 157, 158, 160, 161
        .byte   164, 162, 163, 175, 176, 177, 178, 179, 165, 166, 167, 169, 168, 170, 171, 172, 174, 173, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   15, 17, 18, 16, 19, 2, 1, 3, 0, 4, 12, 10, 13, 11, 14, 23, 20, 22, 21, 24, 7, 5, 6, 8, 9, 28, 25, 27, 29, 26, 120, 122
        .byte   123, 121, 124, 125, 127, 128, 126, 129, 135, 136, 138, 137, 139, 140, 141, 143, 142, 144, 130, 131, 132, 133, 134, 145, 146, 148, 149, 147, 32, 31, 33, 30
        .byte   34, 45, 47, 48, 46, 49, 40, 42, 43, 41, 44, 50, 53, 52, 51, 54, 35, 37, 36, 38, 39, 55, 58, 57, 59, 56, 92, 90, 93, 91, 94, 105
        .byte   106, 108, 107, 109, 95, 97, 98, 96, 99, 110, 113, 111, 112, 114, 100, 102, 101, 103, 104, 115, 118, 116, 119, 117, 153, 150, 152, 151, 154, 170, 171, 173
        .byte   172, 174, 155, 158, 157, 156, 159, 165, 168, 166, 167, 169, 160, 163, 161, 162, 164, 175, 179, 176, 178, 177, 62, 60, 61, 63, 64, 75, 76, 77, 78, 79
        .byte   65, 67, 66, 68, 69, 70, 72, 71, 73, 74, 80, 83, 81, 82, 84, 85, 88, 86, 87, 89, 183, 180, 182, 184, 181, 200, 201, 203, 204, 202, 185, 188
        .byte   187, 189, 186, 195, 198, 196, 199, 197, 205, 209, 206, 208, 207, 190, 193, 191, 192, 194, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
pdb:                                    # 153090 x 4 bit, low nibble = even index
        .byte   48, 70, 85, 82, 81, 85, 69, 18, 52, 70, 101, 19, 37, 115, 51, 53, 70, 86, 86, 69, 86, 37, 52, 101, 101, 70, 51, 70, 70, 85, 53, 69
        .byte   54, 102, 101, 86, 82, 101, 67, 100, 102, 86, 83, 68, 85, 85, 68, 86, 100, 83, 100, 84, 85, 68, 101, 52, 85, 102, 101, 101, 84, 98, 101, 101
        .byte   53, 54, 36, 102, 20, 85, 66, 102, 70, 70, 67, 101, 83, 101, 51, 100, 99, 70, 85, 66, 85, 70, 102, 84, 85, 100, 68, 71, 99, 70, 99, 54
        .byte   99, 53, 101, 102, 101, 69, 99, 37, 100, 118, 103, 119, 87, 103, 102, 119, 104, 136, 102, 117, 135, 119, 103, 102, 103, 119, 135, 134, 135, 135, 117, 135
        .byte   136, 102, 134, 135, 136, 118, 118, 120, 103, 118, 119, 119, 119, 120, 118, 135, 118, 103, 103, 119, 102, 119, 135, 120, 103, 120, 119, 120, 120, 120, 119, 119
        .byte   120, 104, 119, 119, 120, 135, 118, 134, 118, 135, 134, 119, 135, 119, 119, 119, 103, 120, 117, 103, 103, 134, 119, 135, 88, 104, 119, 135, 120, 102, 104, 119
        .byte   103, 119, 118, 135, 120, 136, 135, 103, 119, 134, 136, 119, 119, 120, 136, 135, 120, 151, 103, 102, 119, 134, 102, 119, 118, 104, 119, 103, 119, 134, 87, 135
        .byte   119, 119, 136, 120, 119, 135, 135, 104, 135, 119, 136, 119, 120, 119, 136, 135, 135, 135, 120, 136, 120, 120, 135, 135, 136, 120, 135, 119, 136, 136, 136, 118
        .byte   136, 119, 119, 119, 120, 104, 136, 120, 120, 119, 119, 119, 119, 120, 134, 103, 119, 103, 118, 120, 119, 103, 135, 119, 87, 119, 120, 120, 102, 136, 87, 118
        .byte   119, 101, 119, 118, 104, 118, 118, 102, 119, 103, 118, 119, 119, 118, 102, 119, 88, 102, 87, 136, 118, 101, 102, 103, 103, 103, 118, 119, 117, 118, 103, 101
        .byte   103, 102, 120, 116, 119, 117, 120, 103, 103, 119, 118, 134, 117, 103, 117, 119, 118, 102, 103, 119, 133, 119, 103, 100, 119, 103, 119, 135, 104, 104, 86, 120
        .byte   103, 103, 119, 135, 118, 136, 118, 104, 104, 119, 119, 136, 119, 119, 135, 119, 118, 119, 135, 102, 119, 103, 135, 120, 87, 118, 133, 119, 135, 119, 116, 133
        .byte   120, 103, 117, 86, 119, 101, 135, 102, 118, 119, 118, 118, 119, 134, 104, 86, 103, 101, 102, 118, 103, 118, 119, 120, 135, 135, 104, 104, 119, 136, 104, 135
        .byte   119, 118, 119, 119, 103, 117, 135, 101, 87, 119, 87, 103, 100, 119, 102, 88, 87, 118, 119, 71, 118, 135, 118, 86, 86, 102, 102, 86, 134, 118, 103, 87
        .byte   103, 135, 119, 118, 135, 119, 119, 103, 119, 103, 118, 119, 134, 120, 103, 136, 103, 134, 136, 119, 118, 136, 119, 119, 136, 119, 104, 135, 120, 119, 119, 118
        .byte   103, 135, 118, 117, 103, 118, 101, 103, 136, 102, 103, 119, 103, 86, 134, 88, 134, 118, 135, 103, 103, 101, 104, 118, 118, 118, 103, 104, 88, 118, 120, 118
        .byte   118, 119, 101, 86, 103, 103, 86, 102, 133, 69, 119, 118, 103, 121, 86, 102, 119, 120, 103, 102, 136, 117, 102, 103, 118, 118, 119, 118, 103, 120, 120, 120
        .byte   120, 136, 103, 135, 120, 119, 104, 119, 119, 119, 119, 119, 118, 135, 121, 103, 118, 136, 103, 120, 133, 119, 134, 136, 120, 134, 119, 136, 136, 120, 135, 119
        .byte   120, 135, 103, 135, 120, 151, 120, 136, 135, 104, 135, 120, 119, 135, 104, 135, 119, 135, 103, 135, 119, 135, 119, 120, 136, 119, 104, 134, 135, 120, 119, 120
        .byte   119, 119, 136, 135, 135, 119, 136, 136, 118, 104, 135, 120, 104, 119, 136, 88, 103, 135, 118, 118, 135, 135, 119, 135, 101, 101, 118, 117, 119, 120, 119, 118
        .byte   103, 119, 118, 132, 119, 133, 117, 118, 117, 102, 117, 119, 103, 116, 118, 119, 102, 102, 119, 102, 119, 103, 135, 119, 119, 135, 119, 119, 118, 136, 102, 120
        .byte   103, 135, 119, 119, 103, 134, 135, 119, 119, 135, 103, 119, 104, 120, 86, 119, 103, 102, 117, 135, 102, 118, 119, 88, 119, 118, 118, 119, 136, 103, 104, 104
        .byte   118, 103, 135, 136, 119, 136, 119, 119, 119, 104, 103, 119, 135, 119, 119, 135, 136, 101, 103, 101, 135, 119, 71, 134, 85, 118, 133, 103, 117, 117, 119, 103
        .byte   104, 119, 118, 118, 119, 119, 103, 134, 120, 135, 119, 103, 118, 135, 120, 103, 120, 120, 120, 104, 119, 119, 120, 134, 136, 118, 119, 120, 135, 119, 119, 119
        .byte   120, 120, 120, 135, 120, 120, 135, 119, 135, 135, 119, 104, 135, 136, 136, 135, 103, 119, 134, 136, 119, 135, 120, 136, 135, 119, 151, 119, 119, 120, 135, 135
        .byte   120, 119, 120, 119, 119, 120, 120, 136, 119, 119, 120, 119, 120, 135, 135, 119, 119, 119, 118, 119, 120, 119, 136, 119, 120, 120, 104, 136, 103, 136, 120, 136
        .byte   120, 120, 119, 135, 120, 119, 119, 135, 103, 71, 119, 117, 71, 103, 101, 103, 118, 101, 55, 118, 71, 103, 120, 70, 103, 119, 118, 69, 54, 102, 102, 86
        .byte   102, 118, 86, 70, 119, 104, 104, 118, 135, 135, 118, 87, 120, 103, 118, 135, 133, 120, 119, 136, 118, 118, 119, 119, 135, 118, 103, 103, 135, 135, 103, 135
        .byte   119, 101, 119, 103, 103, 120, 118, 119, 104, 135, 102, 103, 104, 135, 103, 120, 135, 87, 118, 119, 117, 101, 117, 120, 119, 100, 86, 103, 85, 86, 120, 119
        .byte   86, 117, 120, 118, 134, 136, 103, 102, 119, 104, 103, 87, 135, 87, 135, 103, 101, 119, 119, 135, 102, 118, 119, 119, 104, 119, 120, 118, 119, 103, 135, 119
        .byte   120, 120, 135, 120, 120, 120, 103, 120, 120, 120, 120, 103, 119, 103, 136, 135, 119, 119, 135, 120, 119, 135, 136, 119, 119, 119, 136, 135, 119, 104, 135, 120
        .byte   135, 134, 119, 135, 119, 119, 119, 121, 103, 120, 134, 118, 119, 104, 120, 118, 135, 134, 120, 119, 135, 119, 118, 135, 103, 119, 119, 119, 135, 136, 135, 134
        .byte   134, 135, 135, 134, 119, 135, 120, 135, 119, 119, 119, 136, 136, 120, 120, 136, 136, 120, 135, 136, 136, 120, 120, 136, 120, 136, 87, 119, 116, 119, 117, 118
        .byte   134, 102, 119, 103, 133, 119, 103, 101, 118, 86, 120, 134, 119, 119, 102, 118, 120, 119, 103, 118, 120, 103, 119, 135, 104, 133, 136, 118, 87, 104, 104, 119
        .byte   118, 136, 119, 120, 103, 119, 119, 101, 119, 87, 118, 120, 103, 118, 134, 134, 135, 119, 135, 102, 136, 120, 54, 103, 119, 118, 133, 85, 132, 118, 102, 72
        .byte   117, 102, 70, 102, 119, 119, 133, 118, 135, 118, 101, 119, 119, 87, 72, 119, 103, 119, 86, 118, 120, 119, 85, 99, 120, 117, 116, 103, 135, 100, 70, 135
        .byte   118, 101, 102, 119, 71, 118, 86, 119, 102, 119, 88, 119, 103, 86, 119, 118, 103, 120, 133, 120, 118, 118, 119, 120, 118, 104, 119, 120, 135, 136, 119, 118
        .byte   134, 103, 120, 134, 119, 102, 119, 119, 119, 119, 136, 119, 120, 119, 134, 119, 71, 119, 136, 103, 119, 102, 104, 101, 118, 119, 117, 135, 119, 119, 87, 119
        .byte   120, 117, 103, 118, 117, 134, 119, 118, 103, 103, 117, 119, 103, 72, 119, 103, 103, 116, 119, 134, 102, 117, 101, 135, 103, 86, 119, 119, 101, 118, 119, 104
        .byte   102, 120, 103, 119, 119, 119, 135, 120, 118, 118, 119, 120, 119, 103, 117, 102, 86, 86, 136, 102, 118, 120, 119, 102, 102, 101, 103, 135, 71, 134, 102, 117
        .byte   119, 120, 101, 120, 119, 86, 117, 87, 118, 104, 104, 119, 135, 119, 119, 118, 119, 104, 119, 103, 104, 119, 120, 119, 119, 103, 103, 120, 103, 120, 102, 87
        .byte   118, 103, 119, 103, 103, 102, 120, 119, 135, 102, 119, 103, 104, 102, 120, 134, 119, 86, 102, 102, 102, 88, 87, 134, 119, 120, 134, 119, 103, 135, 134, 120
        .byte   134, 120, 119, 119, 119, 119, 118, 87, 119, 117, 117, 118, 101, 116, 117, 119, 102, 116, 85, 119, 117, 119, 99, 118, 116, 118, 116, 103, 119, 116, 101, 119
        .byte   120, 85, 102, 118, 134, 103, 119, 118, 118, 118, 136, 119, 119, 119, 87, 119, 118, 119, 119, 136, 104, 134, 87, 117, 104, 136, 103, 104, 136, 87, 103, 119
        .byte   135, 103, 118, 71, 119, 119, 88, 100, 136, 119, 69, 118, 104, 54, 103, 103, 86, 119, 102, 87, 116, 135, 134, 87, 134, 102, 103, 119, 88, 117, 117, 119
        .byte   102, 134, 104, 133, 118, 86, 118, 118, 118, 133, 118, 120, 135, 119, 135, 70, 119, 119, 103, 120, 102, 88, 101, 103, 119, 101, 135, 102, 118, 88, 118, 118
        .byte   119, 103, 103, 118, 120, 120, 135, 119, 102, 103, 120, 119, 135, 134, 119, 134, 118, 119, 135, 136, 118, 134, 118, 118, 135, 136, 135, 133, 134, 120, 136, 136
        .byte   119, 135, 120, 120, 136, 104, 119, 120, 135, 119, 136, 135, 119, 136, 103, 119, 104, 119, 135, 102, 120, 119, 103, 119, 119, 119, 136, 118, 118, 102, 134, 134
        .byte   136, 118, 119, 104, 119, 103, 120, 117, 135, 120, 119, 118, 134, 134, 103, 134, 119, 118, 103, 135, 134, 135, 119, 118, 134, 136, 119, 119, 136, 135, 119, 135
        .byte   104, 119, 103, 134, 119, 120, 119, 118, 135, 118, 87, 102, 118, 103, 120, 102, 118, 117, 134, 119, 103, 135, 135, 119, 134, 118, 119, 119, 103, 135, 119, 118
        .byte   118, 119, 134, 120, 117, 119, 103, 119, 135, 134, 120, 136, 119, 135, 119, 120, 119, 104, 118, 120, 119, 87, 120, 102, 119, 104, 119, 103, 120, 119, 135, 119
        .byte   118, 135, 134, 118, 136, 119, 87, 135, 118, 87, 136, 104, 134, 103, 120, 134, 134, 134, 136, 119, 119, 135, 120, 120, 119, 135, 134, 120, 120, 120, 120, 120
        .byte   135, 120, 119, 119, 135, 119, 119, 118, 135, 135, 120, 104, 119, 134, 119, 120, 97, 100, 100, 38, 38, 66, 71, 100, 38, 70, 66, 68, 103, 102, 36, 118
        .byte   116, 100, 101, 101, 100, 101, 118, 69, 54, 100, 102, 117, 101, 67, 102, 100, 68, 103, 103, 70, 101, 117, 102, 99, 70, 86, 117, 54, 102, 85, 87, 115
        .byte   86, 100, 71, 115, 53, 117, 119, 117, 85, 116, 37, 101, 102, 86, 100, 84, 70, 116, 85, 118, 117, 117, 86, 117, 85, 83, 102, 85, 53, 119, 70, 87
        .byte   71, 86, 83, 87, 84, 87, 98, 53, 117, 119, 102, 69, 102, 116, 84, 116, 101, 101, 85, 117, 53, 101, 118, 117, 117, 120, 119, 102, 136, 120, 120, 120
        .byte   135, 119, 119, 104, 119, 119, 118, 119, 118, 119, 103, 118, 135, 119, 103, 135, 119, 120, 152, 135, 118, 133, 135, 119, 119, 136, 135, 119, 120, 120, 120, 135
        .byte   136, 135, 136, 118, 135, 135, 120, 119, 119, 119, 136, 120, 119, 119, 103, 104, 119, 118, 119, 119, 119, 120, 135, 135, 135, 135, 120, 118, 103, 119, 120, 135
        .byte   119, 135, 118, 136, 87, 104, 104, 118, 119, 119, 118, 135, 118, 119, 135, 119, 103, 119, 118, 151, 119, 120, 134, 104, 119, 103, 119, 119, 120, 119, 118, 119
        .byte   104, 118, 105, 135, 119, 135, 136, 120, 119, 136, 120, 119, 120, 135, 119, 118, 119, 119, 120, 120, 121, 135, 104, 119, 136, 103, 118, 137, 119, 119, 104, 119
        .byte   135, 135, 135, 102, 120, 103, 104, 152, 119, 103, 118, 120, 120, 87, 136, 135, 136, 119, 117, 119, 119, 103, 118, 102, 119, 118, 102, 135, 119, 118, 135, 120
        .byte   103, 134, 136, 121, 104, 134, 134, 118, 119, 85, 104, 120, 102, 120, 136, 152, 135, 120, 104, 118, 136, 119, 135, 119, 136, 120, 119, 134, 103, 120, 119, 118
        .byte   120, 120, 119, 118, 119, 119, 120, 119, 136, 135, 118, 71, 118, 103, 119, 87, 87, 118, 104, 120, 118, 118, 119, 87, 135, 119, 118, 134, 120, 120, 119, 119
        .byte   136, 120, 118, 119, 120, 135, 119, 136, 135, 119, 101, 136, 102, 120, 118, 136, 135, 102, 103, 118, 119, 136, 119, 103, 120, 103, 102, 116, 103, 118, 101, 119
        .byte   118, 101, 86, 135, 118, 86, 102, 118, 120, 103, 118, 119, 103, 119, 119, 136, 120, 120, 120, 135, 103, 118, 71, 135, 119, 119, 102, 102, 86, 87, 119, 135
        .byte   119, 86, 103, 119, 119, 135, 87, 120, 119, 104, 117, 136, 135, 86, 119, 103, 70, 120, 119, 103, 87, 103, 117, 118, 102, 85, 118, 102, 102, 136, 118, 103
        .byte   104, 103, 118, 119, 119, 133, 103, 102, 102, 119, 118, 104, 136, 118, 135, 103, 117, 118, 103, 134, 136, 118, 102, 103, 119, 119, 119, 136, 119, 119, 119, 119
        .byte   103, 103, 87, 119, 116, 102, 117, 118, 117, 117, 119, 86, 117, 102, 119, 117, 87, 120, 133, 103, 133, 86, 134, 84, 135, 119, 118, 117, 119, 117, 101, 119
        .byte   118, 102, 102, 118, 102, 119, 104, 87, 88, 120, 103, 119, 86, 118, 118, 120, 103, 118, 136, 119, 103, 120, 120, 104, 120, 120, 135, 119, 119, 119, 119, 119
        .byte   117, 118, 118, 103, 104, 118, 119, 104, 135, 102, 134, 118, 135, 119, 120, 120, 118, 118, 135, 120, 136, 119, 120, 118, 136, 119, 120, 135, 119, 120, 103, 119
        .byte   118, 120, 119, 136, 135, 135, 120, 120, 119, 135, 135, 119, 134, 86, 103, 119, 87, 103, 103, 120, 103, 120, 119, 118, 103, 120, 87, 119, 103, 119, 103, 119
        .byte   102, 120, 135, 103, 119, 118, 119, 104, 117, 104, 136, 118, 103, 120, 134, 104, 119, 119, 118, 135, 136, 120, 104, 118, 119, 136, 86, 120, 119, 103, 135, 118
        .byte   104, 118, 120, 103, 135, 136, 104, 118, 103, 135, 136, 103, 119, 135, 119, 119, 120, 119, 136, 119, 119, 119, 134, 102, 136, 119, 135, 119, 119, 118, 120, 104
        .byte   119, 135, 119, 103, 120, 104, 136, 118, 135, 135, 117, 103, 135, 104, 136, 118, 119, 134, 135, 104, 120, 119, 103, 120, 119, 120, 103, 104, 103, 104, 118, 120
        .byte   135, 119, 135, 136, 120, 118, 136, 136, 119, 119, 120, 135, 119, 135, 119, 119, 120, 120, 120, 119, 119, 136, 120, 135, 119, 119, 103, 119, 136, 119, 103, 104
        .byte   104, 119, 136, 119, 120, 119, 119, 119, 120, 119, 104, 134, 103, 136, 120, 133, 119, 135, 103, 103, 118, 119, 119, 103, 118, 118, 119, 119, 104, 103, 119, 119
        .byte   135, 102, 118, 119, 102, 119, 118, 87, 119, 118, 102, 118, 117, 136, 135, 103, 135, 136, 120, 134, 119, 104, 133, 120, 120, 134, 88, 104, 101, 104, 133, 103
        .byte   116, 70, 117, 71, 135, 119, 103, 87, 116, 55, 118, 118, 118, 135, 103, 87, 87, 103, 120, 71, 118, 117, 119, 118, 117, 101, 101, 86, 119, 72, 103, 71
        .byte   119, 117, 118, 84, 118, 115, 70, 119, 119, 118, 119, 134, 119, 101, 87, 118, 87, 119, 118, 87, 103, 117, 71, 118, 87, 120, 119, 86, 102, 71, 103, 86
        .byte   119, 135, 119, 118, 118, 101, 119, 118, 72, 134, 86, 118, 117, 119, 86, 119, 118, 69, 119, 117, 86, 103, 136, 118, 133, 134, 119, 133, 120, 118, 104, 120
        .byte   103, 120, 87, 134, 104, 120, 100, 102, 100, 134, 134, 55, 118, 70, 102, 116, 103, 100, 132, 120, 120, 117, 119, 119, 103, 102, 119, 119, 103, 86, 117, 102
        .byte   119, 119, 71, 117, 119, 120, 118, 120, 103, 101, 103, 119, 102, 119, 118, 135, 119, 87, 88, 119, 135, 135, 135, 118, 135, 102, 135, 119, 135, 118, 119, 119
        .byte   118, 102, 119, 118, 87, 104, 102, 104, 135, 135, 103, 117, 135, 120, 102, 135, 134, 118, 120, 119, 135, 135, 120, 119, 136, 104, 135, 119, 104, 119, 135, 134
        .byte   120, 135, 119, 120, 136, 136, 135, 136, 135, 135, 134, 119, 135, 135, 104, 102, 119, 135, 103, 86, 102, 135, 103, 102, 103, 86, 104, 103, 135, 134, 135, 120
        .byte   135, 135, 135, 135, 119, 120, 119, 120, 118, 119, 118, 136, 119, 136, 135, 135, 103, 119, 135, 119, 119, 119, 135, 135, 135, 118, 120, 119, 119, 134, 102, 104
        .byte   119, 103, 119, 119, 120, 103, 119, 119, 119, 120, 103, 70, 135, 101, 118, 117, 119, 119, 119, 87, 86, 87, 87, 118, 104, 135, 101, 136, 102, 119, 134, 135
        .byte   120, 118, 103, 118, 104, 119, 136, 104, 120, 119, 134, 102, 135, 119, 119, 119, 118, 119, 119, 134, 120, 119, 119, 135, 117, 102, 134, 86, 85, 120, 104, 101
        .byte   117, 118, 84, 119, 119, 87, 119, 134, 103, 117, 134, 102, 120, 119, 118, 103, 119, 103, 119, 119, 118, 102, 118, 104, 101, 103, 102, 87, 86, 86, 134, 118
        .byte   103, 134, 118, 134, 87, 103, 120, 103, 120, 102, 88, 101, 104, 135, 102, 119, 102, 119, 104, 135, 71, 119, 87, 119, 117, 119, 87, 118, 103, 88, 119, 117
        .byte   87, 87, 119, 104, 101, 103, 101, 103, 135, 102, 118, 120, 119, 103, 118, 102, 102, 118, 120, 134, 103, 118, 119, 104, 119, 119, 87, 135, 104, 102, 102, 135
        .byte   104, 135, 119, 119, 119, 135, 87, 118, 119, 102, 118, 136, 102, 103, 119, 119, 117, 118, 87, 135, 133, 119, 119, 120, 100, 120, 117, 117, 117, 87, 119, 119
        .byte   102, 104, 120, 103, 134, 120, 119, 102, 103, 135, 103, 120, 87, 119, 136, 134, 119, 120, 103, 118, 120, 119, 119, 120, 135, 118, 119, 119, 70, 119, 100, 104
        .byte   100, 70, 120, 102, 102, 116, 115, 117, 118, 104, 100, 103, 119, 118, 135, 118, 118, 117, 119, 120, 118, 117, 119, 103, 133, 103, 118, 119, 133, 101, 118, 101
        .byte   119, 120, 119, 104, 119, 103, 120, 84, 120, 135, 119, 102, 103, 120, 135, 119, 119, 135, 119, 103, 103, 118, 103, 87, 119, 85, 135, 101, 86, 118, 86, 119
        .byte   100, 87, 103, 70, 87, 135, 119, 135, 118, 118, 103, 103, 118, 119, 119, 103, 88, 102, 136, 119, 134, 101, 120, 118, 103, 119, 102, 119, 118, 119, 102, 87
        .byte   119, 135, 102, 102, 117, 119, 119, 118, 135, 103, 120, 119, 103, 119, 119, 135, 119, 120, 135, 103, 103, 120, 103, 120, 120, 120, 119, 119, 135, 136, 119, 136
        .byte   136, 103, 120, 134, 120, 137, 119, 135, 136, 119, 120, 119, 135, 119, 135, 136, 119, 119, 136, 135, 120, 119, 119, 136, 134, 135, 119, 120, 120, 135, 137, 134
        .byte   120, 119, 118, 119, 135, 135, 136, 119, 135, 119, 102, 119, 119, 120, 119, 104, 120, 119, 119, 103, 118, 135, 103, 103, 102, 103, 119, 119, 119, 118, 119, 135
        .byte   119, 135, 120, 120, 135, 119, 136, 136, 120, 136, 121, 136, 137, 136, 88, 69, 118, 103, 86, 101, 102, 104, 103, 87, 84, 134, 86, 119, 86, 87, 103, 103
        .byte   119, 119, 102, 134, 118, 118, 136, 117, 104, 119, 135, 104, 119, 134, 151, 118, 118, 103, 103, 119, 118, 103, 119, 119, 119, 103, 134, 135, 120, 119, 118, 104
        .byte   119, 103, 120, 135, 135, 135, 104, 134, 119, 119, 120, 103, 119, 119, 104, 118, 103, 118, 103, 134, 89, 87, 103, 104, 102, 135, 134, 104, 135, 135, 136, 119
        .byte   120, 120, 101, 119, 103, 102, 135, 120, 119, 117, 119, 119, 101, 101, 102, 136, 116, 70, 133, 103, 101, 86, 119, 119, 119, 135, 119, 119, 119, 103, 119, 119
        .byte   104, 135, 103, 103, 119, 118, 119, 102, 118, 103, 119, 119, 120, 135, 119, 119, 135, 120, 103, 119, 135, 118, 104, 120, 119, 103, 120, 118, 87, 118, 119, 118
        .byte   102, 120, 120, 134, 133, 118, 104, 119, 118, 103, 104, 104, 135, 104, 135, 103, 135, 117, 136, 119, 134, 104, 135, 118, 87, 103, 118, 104, 103, 120, 103, 119
        .byte   117, 120, 135, 135, 135, 119, 135, 120, 119, 119, 104, 104, 119, 119, 120, 119, 136, 119, 120, 135, 119, 120, 134, 120, 135, 120, 120, 120, 120, 104, 120, 136
        .byte   119, 116, 85, 119, 87, 87, 87, 135, 88, 85, 117, 119, 118, 101, 116, 103, 119, 103, 119, 136, 119, 117, 117, 103, 118, 134, 118, 135, 102, 134, 104, 103
        .byte   136, 120, 119, 118, 133, 118, 103, 104, 119, 86, 103, 119, 135, 136, 119, 102, 88, 120, 104, 151, 103, 119, 135, 120, 119, 102, 118, 119, 120, 102, 103, 119
        .byte   104, 118, 119, 118, 102, 119, 104, 118, 86, 119, 103, 120, 119, 118, 119, 119, 118, 103, 102, 119, 103, 119, 104, 103, 134, 87, 136, 118, 119, 119, 135, 119
        .byte   136, 135, 118, 104, 118, 119, 136, 119, 86, 88, 120, 119, 118, 104, 103, 118, 135, 103, 118, 102, 119, 103, 135, 118, 87, 133, 103, 118, 120, 120, 102, 102
        .byte   103, 118, 103, 119, 103, 135, 134, 103, 135, 119, 118, 118, 119, 117, 119, 135, 134, 103, 134, 135, 104, 134, 119, 119, 119, 120, 118, 119, 104, 120, 120, 103
        .byte   103, 103, 119, 103, 120, 119, 118, 120, 102, 134, 119, 119, 119, 102, 118, 119, 102, 119, 118, 118, 120, 103, 103, 118, 120, 135, 118, 102, 118, 134, 119, 103
        .byte   118, 135, 117, 119, 104, 118, 135, 103, 134, 134, 135, 103, 118, 103, 104, 120, 119, 101, 136, 119, 117, 134, 118, 119, 118, 102, 119, 104, 118, 134, 135, 102
        .byte   118, 71, 119, 86, 135, 103, 119, 117, 117, 117, 120, 117, 119, 120, 103, 87, 119, 119, 135, 118, 103, 119, 134, 135, 118, 120, 120, 134, 119, 88, 119, 134
        .byte   120, 135, 119, 119, 119, 135, 119, 120, 118, 119, 136, 118, 103, 135, 120, 102, 119, 135, 103, 134, 103, 118, 118, 119, 119, 120, 86, 119, 135, 120, 102, 120
        .byte   120, 118, 134, 119, 119, 134, 88, 135, 88, 117, 102, 118, 135, 119, 120, 104, 118, 119, 119, 120, 119, 103, 118, 103, 103, 119, 119, 71, 87, 87, 118, 119
        .byte   102, 85, 103, 117, 103, 119, 102, 85, 119, 119, 135, 119, 119, 120, 136, 120, 119, 120, 103, 118, 119, 103, 119, 104, 135, 120, 103, 119, 135, 119, 119, 134
        .byte   104, 119, 134, 135, 117, 135, 104, 103, 120, 119, 103, 120, 119, 120, 135, 135, 119, 104, 119, 134, 120, 119, 103, 135, 118, 120, 119, 118, 119, 119, 120, 103
        .byte   120, 103, 120, 120, 135, 119, 119, 102, 119, 119, 119, 117, 119, 103, 119, 119, 103, 102, 118, 103, 135, 119, 102, 104, 103, 119, 119, 119, 87, 135, 87, 102
        .byte   87, 102, 135, 102, 102, 120, 135, 102, 103, 136, 118, 102, 103, 86, 103, 119, 102, 119, 117, 119, 103, 119, 135, 103, 120, 135, 119, 120, 103, 119, 120, 119
        .byte   118, 103, 103, 136, 103, 103, 119, 103, 120, 117, 152, 119, 119, 135, 103, 118, 118, 135, 102, 120, 119, 119, 119, 135, 103, 134, 119, 136, 103, 104, 135, 136
        .byte   118, 134, 118, 103, 135, 117, 120, 119, 103, 135, 120, 102, 119, 136, 104, 116, 119, 102, 87, 118, 102, 135, 135, 119, 87, 88, 118, 88, 135, 104, 102, 136
        .byte   102, 87, 119, 87, 87, 119, 104, 87, 70, 103, 104, 103, 87, 87, 102, 134, 103, 103, 102, 101, 103, 134, 84, 101, 118, 101, 87, 117, 135, 136, 119, 103
        .byte   119, 120, 135, 119, 118, 134, 119, 135, 119, 118, 119, 118, 119, 120, 86, 86, 118, 103, 120, 150, 118, 118, 135, 119, 103, 135, 86, 119, 87, 119, 120, 120
        .byte   70, 135, 135, 103, 87, 102, 120, 102, 120, 102, 136, 103, 118, 136, 104, 119, 117, 118, 119, 119, 120, 118, 118, 120, 102, 135, 103, 134, 119, 120, 117, 118
        .byte   102, 119, 86, 119, 120, 135, 103, 101, 103, 104, 134, 103, 119, 87, 118, 135, 119, 103, 119, 104, 118, 120, 119, 55, 83, 53, 133, 85, 131, 37, 119, 85
        .byte   119, 99, 101, 115, 87, 118, 87, 117, 87, 102, 119, 101, 70, 135, 119, 71, 119, 119, 71, 119, 102, 70, 136, 87, 70, 102, 88, 134, 87, 103, 55, 103
        .byte   70, 119, 134, 102, 118, 132, 86, 100, 102, 102, 117, 87, 86, 132, 104, 135, 99, 102, 135, 87, 117, 102, 119, 117, 119, 86, 119, 118, 103, 87, 116, 86
        .byte   71, 103, 102, 85, 102, 118, 102, 104, 134, 103, 134, 87, 101, 101, 118, 71, 119, 118, 85, 102, 119, 120, 102, 103, 118, 102, 87, 118, 101, 118, 71, 119
        .byte   68, 103, 100, 89, 115, 70, 136, 87, 70, 69, 103, 103, 70, 103, 103, 86, 104, 118, 134, 101, 120, 119, 117, 103, 135, 102, 101, 103, 119, 119, 133, 119
        .byte   118, 117, 120, 119, 118, 116, 118, 117, 119, 120, 135, 118, 118, 102, 135, 118, 103, 102, 120, 119, 134, 101, 103, 86, 103, 119, 134, 104, 103, 103, 119, 119
        .byte   119, 87, 120, 102, 102, 103, 87, 136, 119, 135, 118, 103, 103, 119, 103, 119, 103, 103, 118, 118, 102, 87, 120, 134, 119, 118, 134, 117, 102, 85, 118, 118
        .byte   134, 102, 87, 117, 120, 120, 100, 103, 119, 103, 102, 119, 134, 119, 119, 119, 104, 120, 118, 103, 136, 119, 103, 135, 135, 118, 136, 134, 120, 136, 120, 136
        .byte   120, 119, 120, 135, 120, 119, 134, 135, 119, 135, 119, 120, 119, 120, 119, 120, 119, 104, 135, 104, 119, 119, 102, 117, 104, 135, 119, 103, 104, 119, 119, 118
        .byte   119, 135, 102, 102, 120, 135, 135, 120, 119, 119, 118, 118, 119, 119, 104, 135, 120, 102, 104, 136, 135, 135, 135, 102, 120, 119, 120, 135, 119, 135, 136, 119
        .byte   119, 119, 135, 119, 136, 120, 120, 136, 119, 136, 135, 136, 119, 136, 120, 135, 136, 118, 84, 103, 117, 136, 118, 102, 134, 134, 117, 119, 103, 85, 102, 120
        .byte   119, 103, 119, 136, 118, 136, 135, 135, 119, 120, 119, 135, 119, 120, 135, 119, 120, 103, 119, 118, 120, 119, 120, 119, 120, 119, 104, 135, 103, 102, 118, 116
        .byte   135, 118, 119, 134, 119, 119, 118, 133, 118, 104, 85, 135, 119, 120, 134, 103, 119, 103, 120, 119, 118, 135, 120, 119, 103, 119, 118, 136, 118, 119, 103, 102
        .byte   133, 102, 103, 118, 103, 119, 119, 103, 102, 119, 119, 86, 119, 103, 86, 100, 103, 71, 119, 101, 103, 102, 118, 85, 135, 117, 104, 117, 103, 102, 118, 118
        .byte   87, 135, 102, 118, 103, 102, 101, 134, 103, 134, 86, 104, 103, 118, 118, 119, 120, 102, 117, 103, 103, 102, 118, 120, 119, 119, 119, 119, 119, 119, 103, 119
        .byte   120, 118, 103, 135, 119, 119, 119, 119, 119, 102, 135, 104, 118, 119, 118, 103, 102, 102, 103, 136, 119, 101, 134, 120, 118, 135, 86, 102, 135, 119, 119, 119
        .byte   119, 102, 119, 103, 86, 119, 120, 136, 135, 119, 120, 119, 119, 119, 119, 120, 135, 103, 119, 119, 120, 119, 119, 135, 135, 135, 103, 135, 118, 118, 118, 119
        .byte   119, 119, 119, 102, 118, 103, 134, 119, 118, 119, 134, 103, 103, 119, 119, 118, 119, 119, 134, 118, 120, 119, 135, 136, 118, 119, 119, 103, 120, 120, 119, 120
        .byte   135, 134, 135, 120, 119, 136, 136, 119, 135, 136, 119, 136, 136, 120, 135, 120, 119, 103, 120, 120, 120, 119, 104, 119, 119, 136, 119, 136, 119, 136, 120, 119
        .byte   120, 135, 104, 118, 136, 120, 136, 135, 120, 103, 136, 120, 118, 120, 136, 103, 119, 120, 119, 136, 135, 119, 119, 120, 120, 103, 118, 135, 135, 119, 104, 119
        .byte   104, 119, 119, 103, 117, 102, 120, 119, 102, 103, 134, 118, 135, 119, 119, 134, 103, 102, 103, 118, 119, 119, 135, 102, 135, 119, 102, 119, 119, 119, 104, 134
        .byte   135, 118, 120, 119, 135, 120, 119, 134, 119, 135, 119, 135, 118, 103, 136, 134, 120, 136, 119, 135, 118, 119, 119, 119, 103, 119, 119, 135, 136, 119, 134, 136
        .byte   135, 103, 120, 136, 120, 121, 120, 136, 117, 88, 87, 118, 103, 102, 136, 134, 100, 136, 118, 87, 119, 135, 102, 119, 87, 88, 102, 103, 71, 102, 103, 117
        .byte   103, 135, 101, 119, 103, 103, 134, 119, 135, 118, 136, 119, 120, 120, 135, 120, 119, 119, 120, 135, 136, 119, 117, 118, 86, 135, 118, 104, 103, 86, 119, 120
        .byte   118, 118, 118, 118, 134, 87, 104, 120, 135, 134, 120, 136, 104, 135, 120, 103, 134, 134, 136, 117, 120, 120, 119, 118, 134, 136, 136, 120, 118, 120, 134, 119
        .byte   135, 120, 119, 104, 118, 119, 102, 134, 118, 118, 101, 119, 119, 85, 119, 118, 103, 135, 104, 119, 119, 135, 135, 135, 119, 152, 120, 120, 119, 119, 136, 120
        .byte   135, 120, 136, 119, 119, 120, 136, 119, 135, 136, 119, 135, 136, 135, 119, 120, 119, 102, 120, 136, 135, 118, 119, 134, 119, 103, 118, 136, 119, 85, 135, 134
        .byte   136, 119, 134, 119, 104, 134, 88, 119, 119, 118, 103, 119, 135, 118, 119, 135, 133, 119, 119, 103, 134, 119, 134, 119, 135, 102, 136, 135, 135, 135, 120, 135
        .byte   119, 118, 120, 118, 103, 120, 135, 135, 120, 119, 119, 119, 137, 102, 103, 119, 87, 103, 119, 119, 103, 87, 120, 119, 104, 103, 119, 120, 119, 135, 120, 104
        .byte   135, 119, 120, 135, 119, 120, 135, 120, 119, 135, 119, 136, 135, 135, 118, 136, 135, 136, 120, 119, 135, 136, 120, 119, 133, 134, 104, 119, 118, 119, 120, 103
        .byte   136, 104, 136, 103, 135, 117, 120, 119, 70, 102, 88, 136, 101, 135, 103, 120, 103, 104, 136, 117, 87, 119, 135, 135, 135, 135, 104, 135, 136, 120, 136, 136
        .byte   136, 136, 120, 119, 136, 119, 136, 120, 136, 103, 120, 118, 135, 135, 120, 119, 135, 120, 135, 119, 86, 120, 87, 87, 117, 119, 70, 119, 102, 103, 103, 135
        .byte   85, 135, 102, 103, 88, 135, 119, 134, 135, 134, 104, 135, 104, 119, 135, 86, 135, 102, 120, 119, 104, 119, 120, 119, 134, 135, 118, 136, 119, 120, 120, 136
        .byte   103, 119, 120, 119, 118, 102, 103, 103, 119, 118, 120, 103, 119, 120, 135, 119, 88, 87, 103, 136, 118, 119, 102, 102, 135, 119, 102, 133, 118, 118, 118, 102
        .byte   120, 118, 119, 119, 118, 119, 119, 119, 119, 120, 135, 135, 104, 103, 119, 119, 119, 118, 119, 135, 103, 134, 103, 119, 119, 120, 103, 103, 120, 119, 103, 119
        .byte   119, 103, 118, 118, 119, 118, 119, 118, 118, 118, 87, 118, 103, 120, 119, 135, 118, 135, 103, 104, 135, 103, 118, 87, 120, 118, 103, 136, 103, 118, 120, 119
        .byte   119, 136, 120, 120, 119, 119, 102, 118, 119, 119, 119, 120, 119, 104, 104, 120, 136, 119, 135, 120, 119, 136, 119, 119, 135, 103, 120, 100, 120, 133, 120, 133
        .byte   87, 134, 135, 134, 118, 135, 86, 136, 103, 103, 119, 134, 136, 118, 119, 120, 119, 119, 136, 119, 120, 135, 136, 119, 118, 120, 118, 104, 119, 119, 119, 119
        .byte   117, 103, 119, 103, 136, 134, 103, 120, 119, 118, 101, 103, 119, 119, 119, 104, 118, 103, 120, 134, 119, 86, 135, 104, 119, 85, 120, 119, 84, 135, 118, 103
        .byte   102, 119, 118, 133, 119, 119, 133, 119, 119, 119, 120, 104, 119, 102, 118, 119, 120, 119, 134, 119, 119, 102, 118, 119, 136, 102, 120, 135, 86, 103, 119, 121
        .byte   134, 119, 54, 118, 87, 119, 72, 87, 116, 119, 102, 116, 84, 119, 87, 103, 101, 118, 119, 118, 87, 120, 135, 120, 119, 118, 134, 118, 119, 120, 135, 120
        .byte   119, 103, 120, 87, 120, 135, 120, 103, 102, 135, 103, 119, 118, 135, 120, 103, 103, 87, 103, 135, 135, 86, 103, 136, 87, 88, 118, 104, 119, 104, 103, 120
        .byte   119, 101, 103, 87, 118, 103, 135, 118, 103, 119, 119, 119, 120, 69, 119, 103, 87, 71, 104, 115, 118, 117, 116, 100, 103, 102, 86, 86, 119, 101, 119, 103
        .byte   103, 118, 119, 119, 102, 118, 102, 87, 102, 119, 103, 119, 117, 101, 103, 119, 102, 135, 120, 134, 86, 103, 118, 120, 104, 102, 118, 104, 119, 135, 119, 135
        .byte   119, 135, 119, 119, 136, 103, 118, 118, 120, 120, 120, 135, 120, 120, 119, 119, 118, 136, 135, 119, 120, 118, 135, 118, 119, 119, 119, 118, 134, 119, 135, 103
        .byte   135, 103, 119, 102, 119, 135, 103, 119, 102, 119, 120, 120, 119, 120, 119, 103, 103, 120, 119, 119, 120, 135, 120, 120, 120, 119, 103, 120, 136, 136, 120, 135
        .byte   119, 135, 120, 135, 136, 103, 119, 119, 118, 103, 118, 118, 118, 118, 119, 118, 119, 118, 103, 118, 71, 116, 102, 134, 70, 120, 70, 102, 100, 119, 102, 104
        .byte   52, 104, 117, 103, 118, 119, 119, 104, 87, 120, 119, 120, 117, 135, 119, 86, 119, 136, 87, 119, 135, 87, 103, 71, 134, 87, 134, 120, 119, 118, 135, 135
        .byte   103, 120, 118, 102, 135, 119, 119, 118, 119, 119, 88, 135, 135, 119, 102, 118, 134, 118, 104, 119, 119, 119, 119, 119, 119, 87, 118, 120, 119, 118, 118, 119
        .byte   88, 134, 86, 102, 119, 103, 86, 135, 120, 72, 103, 135, 103, 87, 119, 102, 136, 118, 119, 118, 120, 103, 135, 101, 119, 86, 103, 135, 135, 103, 101, 117
        .byte   118, 118, 102, 104, 86, 118, 119, 118, 102, 87, 118, 134, 104, 118, 118, 103, 118, 119, 135, 103, 119, 119, 119, 120, 103, 119, 120, 119, 120, 136, 104, 120
        .byte   120, 119, 135, 135, 119, 120, 134, 119, 135, 135, 136, 102, 119, 135, 118, 118, 119, 135, 117, 87, 118, 103, 118, 102, 135, 135, 136, 103, 119, 136, 136, 136
        .byte   135, 119, 119, 119, 136, 136, 119, 118, 120, 103, 118, 103, 135, 118, 134, 103, 120, 118, 119, 134, 135, 117, 87, 135, 120, 120, 135, 120, 136, 120, 120, 136
        .byte   136, 136, 119, 134, 135, 119, 119, 118, 101, 119, 119, 118, 102, 104, 102, 118, 120, 118, 118, 119, 101, 119, 102, 119, 136, 118, 119, 135, 119, 135, 119, 119
        .byte   119, 120, 136, 120, 119, 72, 117, 102, 119, 102, 103, 119, 103, 84, 101, 86, 86, 119, 117, 119, 119, 135, 118, 120, 135, 103, 103, 120, 102, 119, 135, 120
        .byte   119, 119, 118, 119, 103, 119, 118, 119, 119, 104, 119, 103, 104, 119, 103, 120, 104, 103, 104, 135, 119, 103, 118, 87, 103, 135, 103, 119, 102, 119, 103, 119
        .byte   88, 118, 120, 103, 71, 86, 117, 120, 118, 70, 103, 117, 88, 120, 87, 104, 118, 102, 135, 87, 119, 103, 135, 118, 119, 102, 135, 103, 102, 119, 119, 119
        .byte   136, 135, 136, 118, 120, 135, 151, 120, 102, 136, 120, 136, 120, 120, 119, 136, 119, 135, 119, 103, 103, 119, 135, 120, 136, 119, 118, 136, 136, 135, 119, 119
        .byte   135, 120, 152, 119, 104, 135, 120, 119, 136, 136, 135, 120, 119, 120, 136, 119, 120, 119, 118, 119, 103, 137, 119, 120, 119, 119, 134, 118, 119, 120, 102, 118
        .byte   119, 120, 119, 87, 119, 103, 120, 102, 119, 135, 119, 120, 120, 119, 134, 120, 136, 118, 103, 118, 119, 120, 119, 136, 71, 102, 69, 119, 118, 101, 87, 102
        .byte   117, 119, 85, 118, 118, 103, 117, 103, 120, 103, 135, 120, 118, 134, 119, 119, 136, 119, 120, 135, 119, 103, 103, 118, 117, 101, 86, 102, 87, 101, 118, 103
        .byte   117, 102, 103, 69, 134, 135, 119, 103, 119, 120, 120, 119, 134, 118, 120, 136, 120, 119, 104, 120, 103, 117, 119, 102, 86, 119, 101, 102, 116, 87, 103, 86
        .byte   86, 102, 119, 135, 136, 135, 119, 104, 119, 119, 120, 119, 120, 136, 135, 119, 134, 103, 103, 135, 118, 103, 103, 87, 134, 119, 103, 119, 136, 135, 103, 135
        .byte   118, 119, 117, 103, 119, 120, 120, 103, 135, 88, 103, 134, 118, 103, 118, 103, 118, 119, 135, 117, 119, 103, 103, 119, 119, 120, 134, 120, 135, 103, 120, 87
        .byte   118, 136, 103, 119, 102, 101, 102, 119, 103, 119, 103, 103, 87, 102, 119, 119, 119, 119, 118, 119, 119, 118, 119, 120, 103, 120, 119, 119, 118, 104, 119, 119
        .byte   88, 118, 103, 104, 104, 103, 103, 103, 88, 119, 103, 119, 104, 134, 119, 135, 102, 119, 101, 119, 102, 119, 119, 119, 119, 104, 103, 102, 119, 120, 103, 103
        .byte   135, 119, 135, 118, 135, 119, 88, 120, 119, 103, 118, 135, 120, 88, 120, 119, 120, 119, 119, 102, 119, 119, 104, 135, 119, 134, 103, 119, 119, 120, 119, 120
        .byte   120, 119, 103, 120, 87, 104, 119, 120, 120, 119, 119, 120, 103, 103, 135, 120, 103, 134, 135, 101, 135, 136, 103, 137, 119, 136, 136, 119, 120, 135, 135, 119
        .byte   120, 136, 118, 135, 103, 135, 103, 135, 104, 104, 136, 119, 103, 103, 135, 104, 88, 120, 136, 120, 103, 119, 135, 120, 119, 135, 120, 119, 119, 134, 119, 118
        .byte   136, 135, 118, 119, 118, 103, 104, 102, 104, 119, 104, 119, 134, 119, 119, 88, 120, 119, 135, 135, 120, 135, 103, 119, 120, 118, 119, 119, 119, 135, 119, 103
        .byte   119, 119, 118, 135, 119, 134, 119, 135, 117, 103, 136, 119, 119, 119, 135, 104, 134, 118, 102, 120, 119, 118, 118, 119, 103, 103, 135, 120, 88, 118, 87, 119
        .byte   136, 136, 152, 119, 120, 135, 119, 135, 120, 102, 119, 136, 136, 119, 119, 135, 120, 133, 120, 135, 135, 103, 119, 135, 119, 134, 119, 119, 103, 120, 104, 119
        .byte   136, 119, 87, 119, 103, 104, 135, 104, 103, 87, 119, 103, 119, 119, 120, 134, 118, 119, 136, 119, 118, 120, 119, 135, 136, 136, 135, 119, 88, 85, 84, 119
        .byte   119, 86, 101, 104, 118, 101, 101, 134, 100, 85, 117, 88, 102, 102, 119, 135, 118, 134, 117, 103, 135, 118, 104, 119, 118, 105, 104, 118, 134, 119, 118, 118
        .byte   102, 103, 118, 86, 117, 118, 103, 102, 118, 119, 119, 120, 119, 120, 120, 103, 135, 134, 120, 135, 103, 119, 134, 104, 103, 135, 103, 119, 119, 103, 103, 101
        .byte   118, 119, 120, 119, 104, 120, 102, 119, 118, 119, 134, 136, 120, 133, 119, 104, 87, 118, 119, 136, 134, 103, 120, 119, 104, 135, 119, 119, 102, 152, 134, 104
        .byte   135, 102, 103, 135, 120, 103, 84, 86, 134, 87, 118, 101, 88, 103, 86, 86, 119, 71, 101, 119, 118, 135, 119, 119, 120, 103, 134, 102, 135, 119, 135, 119
        .byte   104, 119, 120, 87, 118, 134, 102, 101, 71, 116, 119, 102, 86, 117, 102, 87, 119, 117, 102, 136, 134, 103, 103, 87, 119, 135, 120, 119, 135, 151, 103, 135
        .byte   103, 135, 119, 104, 119, 119, 119, 119, 119, 104, 136, 104, 119, 120, 120, 120, 120, 103, 119, 103, 119, 119, 103, 103, 119, 104, 87, 103, 136, 119, 102, 120
        .byte   118, 136, 104, 119, 102, 119, 135, 118, 87, 135, 119, 120, 103, 135, 119, 135, 135, 134, 118, 103, 104, 120, 120, 119, 135, 119, 117, 134, 119, 119, 103, 119
        .byte   120, 119, 119, 136, 136, 119, 120, 119, 119, 120, 119, 104, 119, 119, 119, 119, 103, 120, 119, 102, 118, 135, 104, 103, 119, 120, 118, 102, 119, 88, 103, 88
        .byte   118, 104, 136, 135, 119, 103, 104, 136, 103, 120, 120, 135, 119, 119, 120, 120, 119, 119, 120, 135, 104, 119, 135, 119, 136, 102, 119, 104, 135, 118, 120, 134
        .byte   118, 120, 102, 101, 103, 120, 133, 120, 118, 119, 120, 119, 136, 135, 120, 135, 119, 103, 119, 120, 103, 135, 136, 104, 86, 102, 87, 120, 102, 119, 104, 133
        .byte   118, 136, 102, 134, 102, 136, 119, 120, 135, 120, 135, 119, 120, 136, 135, 119, 118, 135, 120, 136, 135, 119, 103, 119, 135, 102, 104, 118, 104, 117, 135, 119
        .byte   117, 119, 104, 104, 133, 103, 120, 103, 103, 102, 136, 136, 102, 118, 119, 87, 119, 104, 103, 118, 120, 119, 120, 119, 118, 135, 135, 119, 135, 103, 104, 103
        .byte   119, 103, 136, 136, 102, 119, 119, 104, 120, 135, 135, 119, 120, 119, 120, 87, 136, 136, 120, 119, 119, 135, 120, 104, 135, 119, 136, 119, 103, 120, 119, 104
        .byte   104, 86, 86, 103, 117, 103, 118, 104, 118, 118, 102, 136, 134, 119, 102, 136, 118, 120, 136, 104, 136, 120, 120, 135, 119, 120, 120, 119, 135, 118, 136, 120
        .byte   135, 119, 104, 135, 134, 135, 135, 119, 103, 120, 135, 119, 118, 120, 136, 119, 104, 135, 104, 88, 135, 104, 135, 104, 119, 119, 119, 103, 118, 103, 117, 87
        .byte   118, 117, 136, 120, 120, 87, 88, 133, 118, 118, 71, 135, 135, 102, 136, 119, 118, 134, 119, 118, 104, 104, 118, 120, 119, 87, 135, 119, 120, 118, 136, 103
        .byte   136, 119, 103, 119, 120, 135, 136, 119, 120, 136, 135, 120, 136, 119, 119, 136, 135, 119, 120, 120, 136, 103, 135, 136, 135, 119, 121, 135, 120, 136, 135, 136
        .byte   119, 120, 120, 135, 135, 136, 135, 118, 119, 119, 134, 134, 120, 118, 118, 101, 134, 134, 119, 118, 88, 118, 119, 135, 135, 103, 135, 104, 120, 119, 120, 119
        .byte   120, 119, 119, 103, 120, 117, 135, 119, 118, 118, 135, 120, 102, 119, 119, 136, 103, 103, 134, 103, 134, 134, 118, 88, 119, 103, 119, 120, 136, 118, 120, 118
        .byte   120, 119, 103, 136, 119, 135, 103, 119, 120, 118, 118, 103, 135, 118, 135, 119, 117, 119, 102, 102, 84, 102, 135, 101, 119, 86, 117, 118, 103, 134, 86, 119
        .byte   101, 118, 118, 119, 136, 134, 135, 120, 118, 103, 119, 120, 104, 86, 119, 119, 119, 87, 133, 86, 102, 118, 103, 86, 103, 102, 86, 135, 116, 101, 101, 119
        .byte   119, 102, 118, 118, 118, 118, 118, 118, 87, 118, 119, 119, 101, 103, 120, 103, 136, 135, 102, 119, 135, 119, 119, 119, 103, 103, 119, 120, 135, 102, 88, 136
        .byte   119, 86, 86, 103, 118, 103, 136, 102, 103, 119, 120, 118, 119, 135, 103, 135, 120, 119, 119, 118, 103, 103, 119, 119, 120, 104, 119, 119, 118, 102, 104, 104
        .byte   88, 104, 120, 135, 134, 88, 134, 119, 104, 136, 136, 119, 119, 120, 120, 119, 119, 119, 120, 135, 104, 120, 104, 136, 120, 120, 119, 136, 103, 103, 119, 119
        .byte   103, 135, 119, 103, 136, 120, 119, 135, 119, 135, 136, 118, 119, 135, 134, 135, 151, 120, 152, 135, 120, 120, 135, 136, 135, 119, 120, 135, 104, 136, 119, 119
        .byte   119, 119, 120, 136, 104, 103, 119, 136, 135, 118, 119, 136, 120, 135, 136, 135, 134, 136, 135, 135, 120, 136, 120, 119, 119, 119, 104, 104, 120, 135, 120, 119
        .byte   102, 135, 119, 120, 119, 135, 135, 104, 119, 120, 120, 120, 135, 135, 119, 120, 103, 135, 120, 102, 135, 120, 120, 119, 103, 119, 135, 135, 102, 135, 135, 119
        .byte   135, 120, 102, 119, 135, 104, 87, 72, 135, 103, 136, 119, 135, 117, 134, 119, 87, 118, 120, 119, 119, 119, 119, 119, 135, 119, 103, 103, 119, 120, 120, 118
        .byte   119, 120, 135, 135, 104, 104, 120, 136, 120, 104, 103, 120, 135, 120, 135, 119, 104, 135, 103, 87, 120, 87, 103, 103, 120, 72, 118, 135, 87, 118, 119, 120
        .byte   119, 119, 119, 119, 120, 135, 135, 134, 120, 104, 103, 118, 135, 119, 103, 119, 119, 104, 119, 120, 119, 119, 119, 118, 119, 103, 104, 103, 119, 119, 135, 120
        .byte   136, 120, 136, 118, 136, 119, 120, 135, 103, 120, 119, 135, 102, 119, 118, 135, 119, 103, 134, 120, 103, 102, 119, 120, 103, 88, 135, 104, 137, 135, 135, 119
        .byte   120, 119, 135, 119, 119, 120, 103, 136, 136, 118, 120, 103, 103, 134, 119, 136, 135, 119, 119, 119, 120, 119, 134, 103, 136, 135, 120, 135, 135, 119, 136, 136
        .byte   120, 120, 120, 135, 120, 119, 136, 102, 121, 102, 119, 103, 119, 118, 135, 117, 103, 119, 102, 103, 119, 103, 104, 86, 87, 116, 120, 101, 117, 120, 104, 87
        .byte   88, 119, 118, 117, 120, 119, 119, 119, 119, 135, 135, 136, 119, 118, 120, 135, 135, 103, 135, 135, 135, 118, 135, 103, 119, 103, 118, 120, 102, 103, 119, 119
        .byte   119, 119, 135, 134, 118, 119, 119, 104, 133, 120, 120, 135, 102, 103, 118, 119, 103, 136, 119, 120, 120, 134, 135, 119, 118, 120, 135, 120, 134, 118, 152, 119
        .byte   119, 136, 104, 104, 120, 120, 120, 118, 135, 118, 120, 135, 87, 136, 119, 120, 134, 103, 120, 87, 103, 118, 136, 135, 102, 134, 102, 88, 120, 119, 104, 118
        .byte   87, 102, 120, 134, 101, 119, 119, 104, 103, 119, 102, 102, 119, 118, 119, 135, 134, 104, 134, 119, 135, 103, 119, 119, 135, 120, 119, 119, 120, 136, 101, 118
        .byte   135, 118, 103, 101, 101, 103, 86, 134, 102, 104, 102, 119, 119, 119, 119, 120, 119, 120, 120, 119, 134, 119, 135, 104, 119, 103, 119, 118, 135, 120, 120, 103
        .byte   103, 118, 119, 119, 103, 104, 119, 103, 135, 118, 104, 119, 118, 119, 85, 103, 120, 102, 103, 103, 118, 103, 102, 118, 86, 119, 119, 135, 119, 119, 135, 103
        .byte   119, 120, 103, 119, 135, 104, 119, 120, 119, 119, 119, 118, 150, 118, 117, 119, 102, 104, 119, 118, 120, 119, 118, 119, 103, 136, 119, 120, 119, 119, 135, 102
        .byte   119, 135, 120, 136, 118, 120, 103, 119, 103, 119, 135, 103, 135, 102, 119, 103, 136, 119, 119, 117, 119, 86, 136, 87, 119, 87, 103, 117, 119, 116, 120, 119
        .byte   87, 103, 134, 88, 118, 136, 118, 119, 119, 135, 119, 87, 119, 120, 120, 104, 104, 134, 103, 117, 119, 86, 119, 85, 102, 119, 103, 119, 103, 104, 118, 136
        .byte   119, 102, 136, 104, 136, 120, 120, 120, 120, 120, 119, 136, 119, 135, 136, 120, 135, 119, 120, 135, 119, 119, 135, 135, 103, 135, 136, 104, 119, 136, 103, 135
        .byte   135, 120, 135, 120, 120, 120, 119, 120, 136, 120, 103, 134, 152, 102, 135, 119, 102, 135, 87, 104, 120, 86, 134, 88, 119, 71, 120, 87, 120, 136, 119, 134
        .byte   118, 88, 118, 136, 103, 133, 87, 135, 133, 135, 136, 116, 119, 136, 134, 120, 119, 135, 120, 119, 119, 119, 135, 120, 136, 118, 135, 104, 134, 119, 136, 135
        .byte   118, 134, 135, 119, 117, 120, 135, 120, 134, 120, 102, 119, 119, 136, 120, 134, 88, 135, 103, 119, 119, 136, 119, 134, 104, 103, 87, 103, 87, 118, 133, 120
        .byte   117, 119, 116, 103, 135, 120, 117, 117, 133, 103, 119, 119, 119, 119, 119, 120, 135, 103, 135, 135, 104, 135, 135, 119, 119, 119, 120, 103, 102, 102, 119, 104
        .byte   118, 120, 119, 118, 119, 119, 119, 120, 104, 103, 104, 120, 87, 103, 104, 118, 103, 119, 85, 119, 103, 119, 119, 103, 135, 102, 118, 135, 119, 119, 120, 120
        .byte   103, 120, 119, 120, 120, 135, 119, 120, 120, 118, 103, 135, 135, 104, 103, 103, 103, 104, 135, 119, 134, 135, 119, 117, 103, 135, 119, 118, 135, 120, 135, 120
        .byte   104, 119, 120, 119, 135, 120, 119, 103, 119, 102, 104, 119, 134, 104, 119, 118, 119, 119, 135, 134, 120, 119, 135, 135, 134, 135, 119, 119, 135, 120, 118, 120
        .byte   120, 118, 119, 119, 119, 118, 135, 117, 134, 118, 118, 119, 134, 103, 120, 120, 119, 119, 134, 87, 134, 103, 119, 102, 103, 134, 102, 87, 136, 134, 103, 135
        .byte   135, 135, 119, 119, 136, 135, 119, 120, 119, 135, 119, 120, 120, 120, 119, 119, 135, 134, 120, 135, 119, 102, 120, 136, 103, 120, 120, 135, 87, 120, 87, 135
        .byte   103, 119, 119, 102, 103, 119, 119, 103, 118, 119, 134, 118, 119, 136, 119, 103, 120, 119, 134, 120, 120, 120, 103, 136, 136, 119, 120, 119, 136, 135, 136, 135
        .byte   120, 119, 120, 120, 136, 119, 136, 136, 119, 135, 103, 120, 119, 119, 134, 134, 119, 119, 104, 102, 120, 104, 135, 117, 119, 119, 119, 136, 120, 118, 103, 135
        .byte   120, 119, 118, 136, 135, 119, 119, 120, 136, 119, 136, 119, 118, 135, 118, 135, 117, 136, 136, 118, 103, 120, 135, 136, 119, 119, 118, 120, 103, 120, 120, 135
        .byte   119, 119, 119, 136, 119, 135, 133, 135, 119, 102, 120, 119, 103, 120, 104, 103, 102, 119, 104, 136, 103, 119, 134, 120, 119, 136, 119, 103, 103, 136, 102, 118
        .byte   136, 119, 119, 120, 135, 119, 103, 120, 120, 119, 135, 136, 136, 118, 136, 135, 119, 104, 119, 119, 135, 118, 119, 119, 135, 135, 119, 104, 118, 119, 120, 118
        .byte   118, 135, 136, 88, 119, 103, 119, 119, 102, 103, 119, 103, 120, 118, 119, 119, 135, 120, 135, 119, 135, 117, 119, 134, 136, 134, 104, 119, 134, 119, 135, 104
        .byte   136, 119, 136, 135, 135, 135, 120, 136, 136, 135, 136, 135, 120, 136, 136, 135, 135, 136, 135, 136, 135, 103, 135, 120, 103, 135, 136, 120, 135, 136, 86, 54
        .byte   70, 102, 103, 69, 101, 120, 119, 85, 116, 84, 86, 102, 103, 119, 102, 103, 103, 152, 103, 118, 135, 87, 118, 118, 135, 119, 136, 119, 118, 100, 135, 102
        .byte   86, 100, 103, 118, 117, 115, 87, 100, 103, 103, 101, 120, 134, 119, 87, 118, 103, 104, 118, 133, 102, 118, 118, 135, 119, 119, 87, 118, 120, 87, 118, 71
        .byte   103, 88, 118, 119, 119, 119, 118, 103, 135, 118, 103, 87, 120, 119, 104, 118, 119, 120, 103, 135, 117, 136, 103, 120, 119, 134, 118, 102, 102, 135, 118, 134
        .byte   102, 87, 118, 119, 120, 117, 103, 71, 119, 87, 119, 119, 136, 87, 85, 119, 119, 86, 120, 135, 120, 117, 135, 119, 119, 119, 104, 135, 135, 120, 120, 136
        .byte   119, 135, 118, 119, 103, 103, 135, 133, 119, 135, 118, 103, 119, 103, 119, 118, 102, 101, 87, 102, 104, 118, 103, 104, 87, 103, 134, 119, 118, 87, 119, 102
        .byte   104, 103, 103, 119, 103, 119, 119, 135, 135, 119, 118, 119, 103, 135, 87, 102, 119, 136, 119, 136, 118, 103, 119, 120, 104, 104, 136, 104, 135, 119, 119, 117
        .byte   119, 119, 136, 135, 120, 119, 119, 118, 118, 119, 136, 119, 120, 119, 118, 119, 118, 119, 119, 120, 103, 133, 135, 136, 119, 135, 135, 103, 119, 104, 119, 118
        .byte   135, 120, 120, 135, 135, 119, 136, 120, 134, 135, 136, 119, 120, 135, 118, 119, 103, 118, 118, 120, 118, 118, 118, 119, 119, 119, 119, 104, 103, 120, 104, 135
        .byte   135, 104, 136, 135, 103, 135, 135, 120, 135, 119, 135, 135, 136, 136, 135, 135, 135, 120, 118, 119, 135, 136, 136, 103, 119, 120, 119, 135, 132, 135, 119, 118
        .byte   119, 118, 117, 86, 135, 118, 119, 87, 119, 120, 119, 103, 118, 70, 119, 118, 135, 101, 86, 134, 103, 103, 119, 117, 103, 104, 88, 102, 136, 102, 103, 118
        .byte   136, 133, 118, 101, 104, 119, 102, 134, 104, 134, 135, 120, 102, 88, 119, 135, 103, 118, 134, 103, 101, 103, 135, 119, 120, 118, 119, 119, 103, 119, 103, 120
        .byte   136, 119, 104, 119, 118, 87, 135, 120, 119, 134, 119, 135, 136, 119, 135, 135, 118, 135, 119, 135, 119, 119, 135, 118, 118, 118, 118, 120, 119, 118, 103, 119
        .byte   103, 119, 103, 119, 120, 134, 103, 120, 136, 104, 136, 118, 87, 120, 136, 104, 136, 104, 103, 120, 135, 136, 120, 135, 119, 136, 135, 135, 119, 136, 120, 136
        .byte   119, 135, 102, 119, 68, 69, 87, 102, 86, 120, 99, 101, 102, 87, 101, 101, 116, 104, 119, 103, 118, 102, 103, 117, 135, 86, 119, 135, 103, 118, 119, 102
        .byte   103, 135, 136, 135, 134, 119, 104, 85, 135, 136, 135, 119, 119, 119, 134, 119, 134, 102, 103, 120, 119, 104, 134, 117, 87, 119, 119, 135, 102, 118, 103, 118
        .byte   119, 103, 104, 118, 103, 119, 117, 87, 119, 104, 104, 103, 135, 118, 119, 118, 101, 87, 104, 102, 103, 103, 135, 103, 119, 118, 101, 119, 120, 100, 71, 104
        .byte   118, 71, 87, 136, 55, 116, 119, 118, 85, 102, 133, 103, 136, 103, 102, 136, 119, 103, 135, 103, 103, 87, 119, 119, 119, 86, 120, 119, 134, 102, 103, 103
        .byte   103, 119, 101, 119, 119, 104, 120, 119, 104, 120, 120, 135, 135, 119, 119, 103, 119, 119, 119, 135, 118, 119, 104, 120, 120, 118, 103, 135, 136, 104, 118, 119
        .byte   87, 119, 135, 135, 119, 119, 135, 120, 102, 119, 103, 135, 118, 103, 119, 118, 117, 119, 102, 119, 119, 120, 118, 102, 104, 103, 119, 87, 119, 118, 86, 102
        .byte   103, 118, 119, 102, 102, 86, 136, 102, 102, 135, 135, 102, 135, 119, 103, 103, 119, 104, 120, 119, 87, 72, 87, 119, 135, 120, 101, 87, 134, 119, 119, 117
        .byte   101, 117, 120, 119, 119, 119, 119, 118, 135, 119, 118, 103, 119, 119, 118, 119, 103, 104, 86, 104, 120, 117, 134, 119, 87, 118, 118, 120, 120, 102, 102, 119
        .byte   120, 120, 120, 119, 135, 119, 136, 120, 104, 136, 120, 135, 119, 120, 118, 135, 120, 103, 118, 119, 118, 119, 120, 103, 119, 119, 119, 102, 119, 136, 86, 119
        .byte   135, 103, 135, 119, 120, 135, 120, 103, 135, 119, 136, 103, 119, 104, 120, 118, 104, 87, 103, 103, 120, 119, 118, 102, 120, 103, 119, 103, 119, 103, 136, 134
        .byte   119, 119, 119, 117, 104, 120, 103, 120, 119, 104, 135, 119, 120, 104, 120, 120, 135, 119, 119, 135, 103, 103, 104, 88, 103, 118, 136, 102, 119, 117, 119, 118
        .byte   119, 103, 103, 135, 120, 103, 103, 86, 119, 103, 103, 119, 120, 134, 120, 135, 119, 119, 135, 120, 136, 119, 135, 104, 135, 135, 135, 135, 103, 120, 119, 118
        .byte   104, 135, 87, 120, 102, 119, 104, 103, 119, 118, 103, 119, 134, 120, 104, 119, 103, 119, 101, 120, 135, 119, 135, 120, 120, 135, 119, 135, 135, 119, 135, 120
        .byte   118, 135, 120, 118, 134, 135, 119, 119, 135, 118, 135, 119, 135, 120, 120, 119, 118, 120, 136, 135, 136, 135, 120, 119, 119, 119, 119, 120, 135, 118, 135, 136
        .byte   118, 119, 120, 118, 135, 103, 136, 103, 119, 119, 119, 135, 118, 135, 120, 135, 118, 119, 119, 135, 135, 135, 136, 103, 135, 119, 136, 119, 118, 120, 135, 119
        .byte   120, 119, 136, 119, 119, 134, 103, 119, 119, 103, 103, 119, 119, 118, 118, 103, 118, 120, 103, 103, 119, 135, 120, 120, 133, 86, 135, 104, 71, 136, 135, 88
        .byte   118, 135, 135, 71, 119, 135, 119, 133, 87, 134, 118, 119, 136, 133, 120, 104, 102, 103, 102, 120, 101, 119, 119, 119, 103, 104, 135, 119, 102, 119, 120, 103
        .byte   135, 102, 136, 118, 118, 102, 135, 119, 88, 135, 135, 120, 103, 119, 119, 136, 119, 135, 119, 135, 119, 102, 119, 103, 120, 120, 136, 120, 104, 119, 120, 120
        .byte   151, 119, 135, 119, 120, 119, 119, 118, 136, 136, 120, 135, 135, 137, 136, 135, 118, 120, 121, 119, 119, 137, 119, 136, 120, 120, 135, 119, 103, 119, 150, 136
        .byte   121, 103, 119, 119, 135, 120, 120, 118, 136, 119, 119, 119, 119, 119, 118, 119, 135, 119, 103, 119, 118, 119, 118, 119, 88, 133, 86, 135, 87, 119, 86, 136
        .byte   117, 119, 103, 120, 69, 118, 103, 104, 118, 120, 134, 103, 102, 119, 136, 133, 118, 119, 102, 86, 103, 102, 103, 119, 135, 103, 120, 87, 120, 102, 102, 136
        .byte   135, 119, 119, 119, 120, 136, 135, 119, 135, 136, 102, 152, 136, 119, 104, 121, 135, 120, 119, 119, 136, 135, 119, 119, 120, 119, 135, 120, 136, 103, 118, 119
        .byte   119, 118, 135, 136, 103, 119, 103, 120, 119, 120, 103, 102, 119, 87, 119, 120, 119, 120, 120, 118, 120, 136, 136, 119, 135, 136, 120, 118, 104, 102, 120, 120
        .byte   120, 119, 134, 119, 120, 119, 119, 120, 136, 120, 136, 134, 136, 118, 119, 120, 135, 135, 134, 118, 135, 135, 119, 119, 119, 119, 119, 103, 119, 135, 118, 119
        .byte   120, 119, 120, 103, 103, 135, 119, 119, 135, 120, 103, 135, 103, 135, 119, 136, 136, 88, 119, 120, 136, 134, 104, 135, 118, 136, 120, 134, 119, 136, 103, 136
        .byte   87, 120, 119, 136, 102, 119, 120, 104, 120, 135, 120, 120, 119, 104, 120, 103, 136, 119, 120, 103, 119, 118, 103, 135, 118, 119, 133, 120, 104, 103, 136, 136
        .byte   136, 134, 119, 135, 104, 119, 118, 136, 135, 88, 119, 103, 119, 119, 103, 121, 104, 103, 119, 120, 119, 118, 101, 119, 102, 104, 135, 135, 135, 120, 120, 134
        .byte   101, 119, 119, 119, 120, 119, 119, 102, 134, 116, 103, 119, 104, 120, 119, 85, 88, 118, 103, 103, 88, 136, 118, 119, 103, 120, 136, 103, 120, 120, 135, 119
        .byte   119, 134, 103, 103, 135, 120, 103, 135, 136, 135, 119, 135, 120, 135, 134, 135, 120, 119, 118, 119, 119, 120, 118, 103, 134, 120, 120, 135, 119, 119, 119, 120
        .byte   119, 119, 119, 120, 118, 120, 120, 118, 86, 103, 135, 117, 87, 104, 134, 86, 88, 135, 70, 88, 102, 85, 86, 102, 71, 100, 120, 117, 101, 87, 133, 117
        .byte   85, 118, 120, 103, 103, 135, 135, 119, 119, 134, 102, 136, 119, 88, 136, 119, 104, 119, 118, 135, 119, 118, 134, 119, 119, 119, 104, 118, 102, 120, 120, 119
        .byte   119, 119, 104, 102, 120, 119, 103, 135, 118, 119, 118, 118, 119, 119, 120, 103, 103, 87, 101, 135, 118, 118, 102, 118, 103, 104, 134, 118, 102, 135, 118, 119
        .byte   103, 133, 119, 119, 102, 120, 103, 119, 118, 120, 136, 119, 135, 103, 103, 103, 118, 120, 102, 87, 151, 103, 118, 119, 117, 102, 135, 119, 118, 86, 86, 117
        .byte   85, 72, 118, 118, 102, 118, 102, 133, 103, 118, 118, 104, 119, 119, 87, 103, 103, 120, 102, 103, 103, 103, 119, 103, 103, 104, 119, 120, 135, 119, 136, 118
        .byte   135, 135, 135, 120, 136, 119, 103, 136, 103, 102, 118, 118, 134, 103, 117, 119, 119, 134, 120, 119, 134, 118, 102, 102, 102, 104, 104, 117, 102, 88, 102, 118
        .byte   103, 118, 87, 118, 103, 119, 134, 120, 103, 85, 119, 118, 87, 118, 118, 119, 118, 118, 134, 117, 70, 117, 120, 134, 103, 119, 103, 119, 104, 118, 118, 86
        .byte   119, 119, 119, 102, 119, 119, 85, 70, 87, 86, 87, 118, 102, 118, 87, 103, 117, 119, 100, 118, 120, 119, 103, 102, 117, 119, 118, 119, 103, 104, 119, 104
        .byte   134, 118, 104, 136, 119, 118, 135, 119, 135, 120, 135, 119, 102, 119, 103, 104, 135, 120, 119, 117, 104, 86, 133, 104, 103, 118, 84, 103, 133, 135, 119, 118
        .byte   118, 120, 87, 87, 120, 119, 87, 104, 102, 118, 134, 119, 116, 133, 120, 118, 119, 104, 102, 119, 119, 103, 102, 136, 119, 103, 104, 117, 134, 118, 87, 87
        .byte   119, 101, 135, 119, 118, 102, 119, 135, 104, 103, 118, 103, 118, 87, 118, 135, 102, 118, 87, 104, 102, 103, 117, 119, 119, 102, 135, 119, 102, 120, 104, 135
        .byte   118, 119, 103, 119, 118, 118, 135, 103, 119, 134, 118, 101, 135, 104, 118, 120, 119, 136, 119, 119, 135, 119, 119, 104, 119, 119, 134, 119, 133, 101, 119, 120
        .byte   103, 134, 103, 104, 103, 118, 103, 120, 102, 102, 119, 118, 103, 120, 103, 87, 119, 102, 102, 119, 120, 118, 119, 103, 103, 86, 120, 103, 134, 119, 134, 102
        .byte   118, 118, 119, 118, 119, 119, 134, 102, 103, 135, 120, 134, 136, 119, 119, 119, 103, 135, 134, 119, 119, 135, 135, 119, 135, 119, 103, 118, 136, 103, 135, 120
        .byte   102, 103, 136, 119, 119, 136, 119, 135, 104, 119, 120, 119, 118, 119, 119, 135, 119, 120, 118, 103, 119, 135, 136, 119, 120, 136, 120, 135, 136, 135, 135, 135
        .byte   120, 120, 136, 136, 103, 119, 119, 119, 104, 135, 119, 119, 136, 135, 119, 135, 120, 119, 136, 104, 135, 118, 136, 135, 120, 120, 120, 120, 136, 135, 136, 135
        .byte   119, 135, 135, 102, 120, 134, 118, 120, 118, 117, 104, 119, 120, 118, 103, 118, 136, 136, 104, 120, 119, 119, 119, 119, 135, 103, 119, 120, 119, 134, 118, 135
        .byte   120, 102, 86, 104, 118, 103, 118, 88, 101, 118, 102, 134, 118, 118, 120, 119, 119, 117, 87, 133, 119, 103, 101, 88, 118, 117, 119, 135, 116, 119, 135, 118
        .byte   134, 104, 118, 135, 136, 102, 120, 135, 103, 102, 119, 133, 120, 135, 119, 135, 119, 134, 119, 134, 119, 118, 119, 103, 133, 119, 118, 120, 120, 120, 119, 136
        .byte   119, 120, 120, 136, 120, 120, 136, 119, 134, 103, 119, 120, 136, 136, 136, 119, 119, 120, 136, 136, 136, 136, 135, 134, 120, 120, 119, 120, 120, 150, 118, 120
        .byte   136, 118, 135, 119, 103, 120, 118, 120, 103, 135, 117, 88, 104, 133, 119, 119, 117, 119, 87, 119, 117, 119, 116, 120, 104, 120, 120, 119, 119, 103, 119, 135
        .byte   118, 103, 103, 119, 118, 135, 120, 119, 119, 136, 118, 135, 120, 119, 119, 135, 120, 135, 104, 103, 136, 135, 85, 120, 103, 101, 119, 135, 102, 119, 119, 103
        .byte   102, 136, 104, 136, 135, 120, 104, 103, 119, 119, 103, 118, 119, 135, 119, 103, 117, 118, 120, 119, 119, 103, 118, 120, 103, 119, 119, 118, 135, 120, 103, 119
        .byte   118, 119, 119, 119, 120, 102, 135, 102, 87, 118, 119, 103, 119, 118, 102, 119, 101, 135, 118, 119, 119, 118, 119, 135, 104, 135, 120, 118, 117, 119, 136, 135
        .byte   119, 119, 120, 119, 135, 119, 119, 119, 135, 103, 135, 103, 103, 136, 119, 103, 87, 103, 120, 120, 119, 134, 119, 118, 119, 120, 118, 119, 135, 119, 104, 120
        .byte   120, 134, 134, 119, 134, 119, 136, 119, 119, 136, 120, 135, 117, 136, 119, 136, 119, 133, 119, 120, 119, 118, 120, 118, 104, 135, 136, 135, 102, 119, 135, 120
        .byte   119, 118, 119, 104, 118, 88, 104, 118, 88, 135, 104, 103, 135, 104, 119, 120, 119, 119, 135, 119, 103, 136, 135, 118, 103, 119, 120, 119, 103, 103, 135, 102
        .byte   87, 118, 120, 103, 102, 103, 117, 118, 119, 102, 120, 133, 119, 118, 103, 118, 119, 103, 118, 118, 87, 118, 118, 118, 118, 136, 102, 119, 120, 136, 135, 120
        .byte   136, 120, 119, 102, 119, 136, 104, 119, 103, 120, 85, 120, 117, 71, 103, 119, 87, 103, 118, 86, 119, 86, 118, 69, 119, 87, 118, 134, 119, 87, 85, 119
        .byte   119, 120, 87, 119, 133, 120, 104, 120, 119, 119, 136, 119, 120, 119, 136, 120, 135, 120, 103, 103, 135, 104, 134, 102, 119, 120, 119, 117, 118, 120, 102, 134
        .byte   120, 103, 117, 118, 135, 119, 119, 102, 119, 118, 119, 135, 102, 119, 119, 119, 120, 103, 119, 136, 119, 136, 104, 135, 119, 120, 117, 103, 135, 119, 119, 119
        .byte   118, 119, 119, 88, 118, 119, 135, 134, 120, 120, 103, 135, 118, 103, 135, 119, 118, 119, 119, 119, 119, 103, 118, 135, 118, 103, 119, 119, 102, 103, 118, 87
        .byte   118, 119, 101, 119, 119, 104, 135, 103, 135, 135, 135, 118, 119, 104, 119, 119, 120, 136, 119, 135, 135, 134, 119, 136, 103, 104, 119, 120, 120, 119, 120, 120
        .byte   120, 118, 136, 120, 119, 136, 135, 136, 136, 119, 135, 119, 119, 119, 118, 119, 135, 118, 134, 134, 120, 120, 102, 119, 119, 118, 119, 119, 135, 135, 120, 135
        .byte   119, 119, 134, 119, 135, 134, 120, 120, 119, 120, 119, 135, 120, 120, 120, 120, 120, 136, 136, 119, 119, 120, 119, 135, 136, 135, 136, 103, 103, 119, 135, 103
        .byte   103, 119, 86, 136, 135, 119, 134, 119, 134, 103, 118, 119, 103, 119, 135, 119, 119, 135, 136, 119, 136, 103, 102, 136, 87, 118, 136, 119, 103, 104, 120, 119
        .byte   134, 120, 119, 119, 104, 136, 119, 134, 103, 119, 117, 103, 103, 101, 102, 118, 135, 118, 117, 119, 103, 102, 120, 119, 119, 134, 120, 135, 119, 119, 136, 136
        .byte   120, 136, 136, 136, 120, 119, 135, 120, 135, 119, 120, 135, 119, 120, 104, 135, 103, 135, 135, 118, 119, 119, 119, 119, 103, 120, 118, 119, 119, 117, 119, 103
        .byte   134, 102, 119, 135, 120, 118, 135, 117, 104, 119, 119, 118, 133, 118, 103, 118, 103, 134, 120, 135, 103, 120, 120, 136, 103, 120, 119, 88, 120, 104, 135, 103
        .byte   120, 119, 120, 120, 119, 88, 120, 103, 104, 118, 120, 104, 103, 119, 103, 135, 120, 118, 134, 119, 86, 120, 119, 120, 134, 119, 119, 135, 103, 120, 120, 134
        .byte   120, 120, 119, 88, 118, 135, 120, 119, 135, 119, 103, 135, 103, 119, 118, 104, 120, 104, 103, 134, 135, 119, 119, 135, 120, 119, 133, 103, 104, 118, 119, 104
        .byte   120, 120, 119, 136, 136, 136, 136, 136, 135, 135, 119, 135, 119, 88, 119, 134, 87, 119, 116, 87, 117, 120, 119, 101, 119, 88, 119, 136, 136, 118, 135, 118
        .byte   119, 134, 119, 119, 119, 120, 134, 136, 120, 119, 103, 118, 120, 136, 117, 120, 119, 119, 118, 136, 118, 135, 104, 151, 135, 104, 88, 136, 103, 136, 119, 135
        .byte   103, 135, 134, 103, 119, 120, 135, 119, 119, 120, 135, 118, 135, 119, 119, 119, 119, 119, 134, 119, 118, 120, 119, 119, 136, 119, 119, 135, 104, 135, 119, 104
        .byte   119, 119, 119, 119, 103, 120, 135, 136, 119, 120, 136, 104, 118, 135, 135, 135, 136, 119, 151, 103, 135, 103, 104, 120, 120, 119, 120, 118, 119, 119, 119, 119
        .byte   119, 136, 120, 120, 135, 135, 134, 102, 136, 119, 87, 135, 103, 119, 102, 134, 120, 104, 120, 119, 117, 104, 103, 119, 118, 119, 120, 135, 102, 119, 134, 134
        .byte   102, 119, 88, 104, 103, 135, 104, 135, 134, 118, 136, 118, 118, 135, 119, 118, 135, 119, 118, 136, 136, 118, 119, 136, 119, 135, 136, 135, 119, 119, 103, 135
        .byte   119, 120, 136, 119, 103, 136, 87, 104, 120, 119, 104, 119, 135, 102, 119, 120, 135, 136, 135, 103, 120, 102, 136, 119, 119, 119, 119, 119, 118, 120, 104, 119
        .byte   86, 136, 120, 121, 133, 135, 118, 88, 103, 133, 136, 135, 72, 102, 119, 120, 136, 116, 135, 133, 135, 117, 104, 120, 133, 86, 135, 136, 135, 120, 135, 104
        .byte   134, 135, 151, 136, 119, 136, 135, 135, 135, 119, 102, 119, 119, 135, 118, 134, 104, 120, 104, 119, 134, 135, 119, 117, 103, 135, 87, 117, 87, 100, 101, 101
        .byte   87, 120, 117, 102, 72, 119, 101, 102, 103, 135, 103, 120, 102, 102, 118, 119, 119, 119, 118, 87, 103, 120, 119, 119, 136, 119, 135, 120, 119, 120, 119, 120
        .byte   104, 120, 102, 135, 136, 136, 136, 136, 117, 87, 120, 103, 86, 103, 135, 71, 117, 119, 103, 102, 119, 134, 104, 87, 87, 103, 119, 119, 134, 117, 101, 135
        .byte   104, 71, 118, 118, 103, 103, 104, 119, 119, 119, 102, 135, 119, 119, 135, 103, 103, 135, 119, 120, 119, 134, 119, 102, 134, 103, 118, 135, 101, 119, 118, 135
        .byte   119, 119, 119, 135, 117, 101, 135, 135, 102, 135, 136, 135, 102, 102, 136, 136, 103, 134, 136, 136, 120, 104, 104, 120, 119, 135, 120, 119, 120, 119, 119, 119
        .byte   119, 119, 118, 134, 104, 104, 119, 120, 136, 120, 103, 119, 136, 136, 119, 118, 120, 118, 119, 102, 120, 118, 120, 135, 103, 119, 120, 103, 119, 120, 104, 120
        .byte   136, 120, 120, 135, 120, 120, 136, 135, 136, 135, 120, 135, 120, 136, 103, 119, 102, 119, 103, 119, 120, 119, 119, 103, 134, 119, 135, 119, 118, 136, 136, 120
        .byte   135, 136, 135, 136, 120, 135, 119, 136, 135, 119, 135, 136, 133, 119, 135, 70, 119, 117, 119, 103, 87, 88, 86, 119, 136, 119, 87, 120, 118, 118, 119, 135
        .byte   118, 119, 119, 103, 118, 118, 120, 119, 104, 133, 120, 119, 119, 135, 103, 118, 119, 118, 103, 120, 135, 103, 119, 103, 118, 119, 119, 119, 151, 120, 120, 119
        .byte   119, 135, 119, 135, 119, 103, 103, 104, 119, 102, 102, 135, 103, 102, 120, 118, 118, 118, 136, 118, 87, 118, 119, 103, 117, 120, 118, 104, 119, 117, 104, 118
        .byte   101, 104, 87, 102, 136, 103, 118, 117, 120, 118, 104, 117, 101, 120, 101, 118, 135, 102, 102, 103, 103, 119, 119, 120, 119, 102, 87, 119, 120, 103, 135, 136
        .byte   118, 118, 120, 103, 119, 119, 103, 135, 133, 119, 118, 135, 118, 120, 102, 118, 136, 103, 119, 120, 120, 136, 103, 119, 118, 119, 133, 104, 135, 136, 119, 119
        .byte   134, 135, 119, 118, 136, 119, 119, 135, 119, 120, 119, 119, 135, 103, 135, 119, 118, 120, 86, 101, 118, 119, 134, 136, 119, 134, 119, 119, 103, 102, 118, 135
        .byte   134, 118, 120, 117, 118, 103, 135, 134, 119, 119, 119, 119, 103, 136, 104, 135, 119, 120, 120, 120, 118, 136, 135, 103, 119, 119, 103, 120, 136, 119, 103, 118
        .byte   135, 103, 120, 119, 120, 119, 136, 102, 134, 119, 117, 118, 87, 134, 119, 118, 119, 103, 118, 88, 119, 119, 87, 135, 88, 119, 70, 120, 118, 120, 119, 119
        .byte   118, 118, 119, 117, 103, 117, 135, 116, 118, 118, 133, 136, 117, 103, 135, 119, 134, 119, 135, 104, 102, 136, 117, 136, 133, 120, 119, 99, 70, 102, 105, 100
        .byte   102, 120, 120, 68, 71, 136, 118, 72, 103, 87, 133, 102, 118, 120, 134, 103, 102, 118, 118, 103, 135, 86, 119, 118, 120, 118, 118, 103, 119, 118, 136, 135
        .byte   119, 118, 119, 104, 86, 119, 119, 118, 136, 135, 119, 87, 102, 119, 119, 104, 119, 118, 119, 120, 135, 102, 136, 119, 135, 119, 136, 119, 119, 134, 120, 103
        .byte   119, 135, 120, 120, 119, 104, 135, 135, 103, 119, 136, 134, 135, 134, 101, 118, 120, 119, 135, 103, 103, 104, 120, 119, 120, 119, 104, 118, 135, 119, 118, 104
        .byte   134, 135, 87, 134, 103, 103, 102, 136, 117, 103, 119, 102, 119, 104, 119, 118, 104, 119, 103, 119, 118, 135, 136, 136, 119, 135, 136, 119, 118, 119, 103, 136
        .byte   119, 136, 103, 103, 135, 135, 119, 120, 135, 119, 120, 118, 135, 119, 119, 103, 136, 136, 135, 136, 136, 136, 120, 136, 135, 136, 136, 136, 119, 120, 135, 136
        .byte   119, 120, 120, 136, 136, 120, 135, 120, 136, 136, 120, 119, 136, 119, 120, 135, 120, 135, 120, 136, 134, 135, 134, 103, 136, 119, 120, 135, 119, 136, 120, 137
        .byte   135, 104, 120, 119, 135, 136, 120, 120, 135, 119, 135, 120, 136, 119, 136, 136, 135, 136, 120, 135, 120, 136, 136, 120, 136, 120, 136, 135, 152, 136, 151, 119
        .byte   136, 119, 136, 151, 136, 135, 135, 136, 120, 136, 136, 136, 135, 120, 119, 120, 136, 135, 119, 118, 135, 135, 135, 136, 135, 119, 118, 120, 135, 119, 135, 118
        .byte   119, 135, 103, 118, 120, 119, 119, 118, 136, 134, 120, 135, 120, 119, 120, 120, 136, 119, 119, 119, 135, 119, 104, 104, 87, 103, 135, 135, 103, 118, 102, 135
        .byte   135, 117, 134, 118, 120, 102, 136, 119, 135, 135, 120, 119, 119, 119, 120, 103, 120, 120, 119, 120, 120, 135, 135, 120, 135, 136, 136, 135, 135, 134, 134, 119
        .byte   119, 119, 119, 119, 119, 118, 119, 119, 103, 118, 120, 134, 118, 117, 103, 118, 104, 135, 134, 118, 134, 103, 119, 119, 120, 104, 120, 104, 120, 101, 136, 119
        .byte   119, 120, 136, 136, 120, 135, 120, 120, 120, 136, 134, 120, 120, 119, 120, 135, 120, 104, 118, 103, 119, 103, 119, 87, 118, 102, 103, 102, 102, 119, 103, 86
        .byte   120, 103, 119, 119, 118, 135, 136, 135, 119, 136, 135, 119, 136, 135, 136, 119, 136, 119, 103, 104, 135, 118, 135, 135, 118, 119, 119, 120, 136, 119, 135, 135
        .byte   135, 87, 135, 119, 103, 120, 120, 118, 119, 120, 134, 118, 137, 119, 104, 119, 134, 118, 120, 120, 118, 119, 120, 135, 120, 119, 134, 119, 120, 119, 118, 119
        .byte   104, 120, 133, 135, 135, 103, 119, 134, 104, 119, 103, 119, 119, 119, 119, 118, 119, 118, 118, 135, 120, 119, 135, 103, 104, 136, 119, 136, 136, 135, 135, 104
        .byte   133, 120, 120, 104, 120, 118, 135, 120, 103, 119, 136, 119, 135, 120, 119, 104, 120, 103, 120, 135, 120, 134, 120, 117, 120, 135, 119, 119, 104, 119, 136, 135
        .byte   119, 135, 120, 119, 103, 135, 104, 136, 103, 120, 135, 135, 135, 120, 119, 118, 135, 135, 119, 118, 104, 135, 119, 70, 87, 119, 135, 117, 103, 135, 87, 104
        .byte   118, 87, 117, 117, 119, 103, 102, 104, 135, 134, 133, 119, 103, 120, 103, 119, 119, 118, 103, 135, 120, 135, 120, 135, 136, 135, 119, 136, 136, 103, 135, 135
        .byte   120, 119, 120, 119, 136, 136, 135, 136, 136, 135, 118, 120, 135, 120, 119, 119, 136, 135, 136, 135, 119, 120, 136, 135, 120, 136, 104, 119, 119, 135, 119, 136
        .byte   135, 119, 136, 136, 120, 119, 135, 120, 134, 104, 135, 119, 135, 135, 135, 119, 136, 136, 135, 119, 135, 119, 120, 135, 136, 136, 136, 136, 136, 120, 135, 136
        .byte   119, 118, 120, 119, 120, 136, 119, 120, 136, 120, 135, 120, 135, 136, 120, 120, 120, 120, 120, 136, 120, 136, 119, 135, 135, 136, 120, 120, 135, 135, 120, 102
        .byte   86, 104, 119, 87, 119, 87, 119, 70, 119, 118, 103, 87, 120, 118, 103, 134, 135, 87, 119, 120, 103, 101, 103, 104, 135, 119, 136, 119, 135, 136, 134, 104
        .byte   120, 119, 119, 134, 120, 118, 87, 136, 136, 103, 133, 103, 119, 116, 118, 103, 101, 88, 136, 119, 135, 119, 118, 118, 135, 134, 135, 135, 119, 118, 118, 135
        .byte   135, 120, 119, 104, 117, 119, 118, 104, 119, 120, 135, 120, 102, 136, 135, 119, 136, 103, 119, 120, 119, 119, 119, 119, 86, 118, 134, 104, 118, 120, 119, 120
        .byte   119, 102, 134, 119, 135, 119, 119, 135, 119, 103, 134, 103, 134, 118, 103, 103, 119, 103, 119, 117, 119, 120, 118, 119, 104, 135, 120, 119, 120, 118, 103, 119
        .byte   103, 118, 103, 119, 120, 120, 135, 119, 120, 135, 119, 135, 135, 102, 119, 135, 119, 119, 103, 103, 102, 117, 118, 120, 134, 119, 119, 120, 118, 118, 135, 119
        .byte   118, 118, 134, 135, 103, 117, 120, 118, 104, 135, 119, 120, 118, 119, 135, 104, 119, 135, 136, 120, 120, 103, 119, 120, 121, 135, 119, 136, 120, 120, 103, 120
        .byte   119, 119, 136, 120, 119, 135, 120, 121, 120, 119, 136, 103, 136, 135, 119, 118, 118, 136, 119, 102, 120, 102, 103, 103, 119, 103, 134, 101, 119, 118, 136, 135
        .byte   120, 136, 136, 120, 135, 118, 103, 151, 135, 136, 119, 120, 135, 136, 119, 118, 136, 136, 136, 135, 119, 136, 103, 120, 118, 119, 119, 135, 118, 119, 136, 119
        .byte   104, 136, 135, 120, 136, 120, 119, 136, 120, 119, 135, 134, 119, 120, 135, 118, 119, 104, 119, 104, 135, 104, 118, 101, 136, 118, 119, 119, 135, 135, 135, 135
        .byte   104, 120, 136, 136, 120, 119, 119, 120, 105, 119, 120, 135, 118, 119, 118, 119, 136, 103, 135, 136, 119, 119, 134, 119, 103, 104, 135, 135, 119, 119, 119, 119
        .byte   120, 134, 119, 103, 102, 136, 135, 119, 119, 120, 119, 119, 119, 104, 135, 104, 134, 104, 135, 117, 135, 118, 135, 135, 136, 104, 135, 119, 118, 135, 120, 87
        .byte   120, 134, 120, 134, 103, 118, 119, 84, 135, 119, 117, 135, 118, 133, 118, 119, 117, 119, 119, 85, 104, 104, 118, 134, 119, 134, 119, 134, 118, 134, 118, 120
        .byte   119, 119, 133, 136, 120, 119, 119, 119, 135, 119, 136, 136, 119, 102, 120, 136, 135, 135, 136, 134, 119, 136, 120, 135, 136, 135, 120, 119, 136, 118, 136, 134
        .byte   119, 103, 103, 134, 118, 118, 102, 85, 102, 102, 119, 119, 101, 102, 102, 119, 135, 135, 119, 104, 119, 136, 103, 119, 120, 118, 135, 119, 119, 103, 120, 135
        .byte   135, 119, 120, 120, 120, 134, 119, 103, 119, 104, 120, 119, 119, 103, 119, 135, 120, 120, 119, 135, 135, 119, 120, 119, 103, 136, 119, 102, 119, 136, 135, 119
        .byte   135, 118, 135, 135, 120, 104, 103, 119, 118, 135, 134, 119, 119, 136, 102, 120, 119, 118, 119, 119, 133, 119, 103, 133, 119, 120, 102, 119, 120, 102, 118, 135
        .byte   134, 119, 134, 86, 102, 87, 120, 119, 120, 86, 119, 119, 118, 119, 103, 119, 119, 102, 134, 118, 134, 119, 118, 119, 102, 120, 120, 120, 135, 120, 103, 135
        .byte   119, 136, 120, 136, 119, 119, 104, 120, 120, 119, 135, 136, 136, 119, 120, 136, 136, 118, 120, 119, 136, 135, 119, 119, 135, 119, 104, 135, 103, 135, 136, 119
        .byte   102, 119, 119, 135, 120, 119, 104, 135, 136, 135, 120, 135, 135, 135, 135, 119, 135, 119, 136, 135, 136, 118, 103, 120, 135, 103, 102, 134, 119, 104, 134, 120
        .byte   120, 118, 87, 135, 135, 119, 120, 120, 120, 136, 120, 120, 136, 136, 104, 136, 120, 136, 136, 119, 134, 119, 136, 136, 135, 134, 136, 135, 118, 119, 119, 135
        .byte   120, 136, 120, 120, 119, 136, 135, 136, 136, 136, 120, 136, 136, 119, 136, 136, 120, 120, 136, 136, 136, 135, 119, 136, 119, 136, 119, 135, 120, 135, 119, 135
        .byte   136, 120, 136, 136, 121, 136, 121, 135, 120, 136, 120, 120, 120, 121, 120, 119, 135, 136, 120, 135, 119, 119, 136, 136, 119, 136, 119, 118, 120, 136, 136, 135
        .byte   135, 135, 135, 136, 135, 136, 120, 136, 135, 136, 120, 136, 136, 135, 135, 136, 120, 135, 136, 119, 136, 136, 120, 136, 135, 135, 136, 136, 134, 119, 119, 118
        .byte   87, 135, 134, 118, 117, 103, 118, 103, 119, 104, 102, 120, 104, 119, 136, 103, 120, 118, 118, 119, 135, 119, 135, 119, 134, 119, 135, 135, 136, 136, 119, 119
        .byte   104, 119, 103, 120, 135, 119, 136, 103, 135, 119, 136, 119, 120, 119, 119, 120, 135, 103, 135, 102, 119, 119, 136, 119, 103, 120, 136, 120, 103, 119, 120, 118
        .byte   134, 135, 134, 102, 118, 136, 87, 119, 102, 118, 119, 135, 119, 120, 120, 119, 136, 103, 136, 135, 136, 119, 134, 119, 120, 133, 119, 119, 118, 104, 135, 120
        .byte   135, 135, 135, 135, 120, 102, 134, 119, 133, 118, 119, 104, 118, 118, 119, 135, 103, 103, 135, 102, 121, 120, 119, 136, 120, 134, 119, 119, 119, 136, 136, 134
        .byte   119, 134, 120, 120, 119, 120, 120, 103, 135, 119, 135, 120, 119, 119, 119, 118, 118, 120, 120, 119, 86, 135, 119, 119, 119, 136, 119, 120, 102, 135, 120, 135
        .byte   103, 118, 119, 102, 135, 118, 120, 135, 118, 119, 103, 119, 120, 86, 135, 102, 117, 120, 117, 135, 117, 116, 119, 118, 87, 119, 118, 117, 135, 118, 117, 119
        .byte   119, 103, 134, 119, 119, 120, 120, 135, 119, 119, 120, 103, 119, 119, 135, 120, 120, 135, 135, 120, 119, 135, 136, 151, 119, 150, 135, 136, 135, 136, 120, 119
        .byte   120, 136, 119, 136, 134, 120, 120, 120, 119, 136, 135, 103, 135, 135, 120, 120, 120, 120, 120, 135, 135, 119, 134, 119, 136, 119, 104, 135, 135, 135, 103, 135
        .byte   135, 134, 119, 135, 119, 136, 134, 135, 119, 119, 119, 136, 136, 103, 136, 135, 135, 102, 104, 119, 120, 118, 120, 136, 120, 119, 136, 135, 136, 118, 135, 119
        .byte   119, 135, 135, 119, 136, 135, 103, 135, 136, 103, 120, 118, 120, 120, 103, 119, 120, 135, 119, 136, 135, 136, 135, 134, 103, 135, 119, 119, 135, 103, 136, 120
        .byte   87, 119, 103, 120, 103, 135, 120, 119, 120, 119, 136, 136, 120, 136, 120, 119, 103, 120, 103, 136, 120, 120, 120, 134, 120, 152, 135, 120, 135, 120, 120, 119
        .byte   135, 120, 119, 135, 134, 135, 118, 103, 104, 118, 104, 136, 87, 118, 120, 119, 134, 119, 118, 119, 119, 135, 120, 136, 136, 135, 104, 136, 135, 135, 135, 136
        .byte   135, 119, 134, 119, 136, 120, 87, 119, 119, 103, 120, 135, 119, 134, 134, 119, 118, 103, 120, 136, 120, 120, 136, 120, 119, 105, 120, 119, 136, 136, 136, 119
        .byte   119, 118, 117, 104, 87, 86, 119, 119, 87, 85, 101, 119, 119, 103, 100, 104, 119, 119, 119, 135, 135, 117, 119, 119, 118, 118, 103, 134, 119, 135, 120, 103
        .byte   119, 120, 119, 118, 119, 134, 103, 119, 103, 86, 136, 119, 104, 120, 120, 119, 119, 134, 119, 136, 119, 103, 119, 103, 120, 134, 119, 103, 103, 119, 104, 120
        .byte   118, 135, 134, 103, 101, 119, 119, 118, 102, 134, 134, 120, 103, 120, 119, 119, 134, 103, 120, 118, 103, 119, 103, 135, 103, 119, 118, 119, 119, 120, 120, 135
        .byte   136, 103, 120, 103, 103, 136, 119, 102, 118, 119, 119, 135, 104, 134, 103, 136, 103, 119, 119, 135, 135, 133, 104, 134, 135, 135, 118, 119, 135, 118, 136, 135
        .byte   119, 135, 135, 134, 135, 119, 134, 104, 102, 103, 119, 119, 117, 119, 135, 103, 87, 102, 103, 118, 103, 119, 119, 118, 103, 118, 136, 135, 118, 118, 119, 118
        .byte   88, 119, 134, 119, 104, 119, 103, 120, 136, 119, 103, 136, 134, 119, 120, 136, 118, 87, 119, 151, 119, 103, 120, 135, 120, 119, 120, 120, 135, 120, 120, 103
        .byte   119, 120, 119, 118, 119, 119, 135, 120, 136, 135, 103, 118, 120, 136, 119, 120, 135, 119, 119, 120, 119, 119, 135, 119, 118, 120, 119, 119, 136, 118, 119, 136
        .byte   120, 136, 136, 120, 135, 136, 135, 136, 136, 136, 135, 120, 120, 135, 135, 121, 120, 135, 135, 120, 136, 135, 119, 136, 120, 136, 136, 136, 136, 136, 135, 120
        .byte   136, 136, 136, 136, 152, 136, 135, 120, 121, 136, 137, 152, 136, 136, 135, 135, 136, 119, 135, 119, 136, 135, 135, 135, 136, 134, 119, 119, 135, 135, 136, 136
        .byte   136, 135, 120, 136, 120, 135, 136, 135, 120, 136, 136, 136, 135, 135, 136, 104, 136, 120, 135, 136, 119, 118, 135, 120, 135, 119, 135, 118, 119, 136, 135, 119
        .byte   120, 103, 119, 118, 119, 119, 119, 104, 104, 136, 119, 119, 120, 136, 119, 120, 120, 104, 135, 119, 136, 120, 103, 120, 119, 104, 118, 117, 104, 119, 103, 119
        .byte   72, 120, 119, 120, 86, 120, 119, 88, 135, 119, 103, 135, 135, 119, 120, 120, 103, 104, 120, 119, 120, 119, 135, 119, 120, 119, 135, 135, 119, 103, 135, 119
        .byte   104, 119, 135, 119, 134, 118, 119, 103, 101, 103, 120, 119, 117, 72, 135, 135, 104, 136, 136, 88, 120, 120, 120, 119, 119, 119, 104, 119, 103, 120, 118, 135
        .byte   104, 120, 119, 120, 135, 119, 119, 135, 118, 119, 118, 120, 102, 119, 135, 119, 119, 120, 135, 119, 135, 135, 119, 135, 120, 119, 118, 135, 133, 119, 102, 119
        .byte   136, 118, 135, 120, 120, 119, 136, 136, 87, 120, 119, 104, 119, 104, 120, 104, 120, 104, 103, 120, 135, 135, 118, 119, 103, 136, 119, 119, 136, 118, 119, 135
        .byte   136, 118, 136, 119, 119, 119, 118, 103, 135, 119, 119, 135, 135, 119, 103, 136, 136, 118, 136, 136, 135, 136, 136, 103, 135, 104, 136, 136, 120, 119, 135, 119
        .byte   84, 135, 119, 117, 119, 103, 133, 135, 135, 117, 120, 119, 85, 118, 119, 135, 119, 133, 136, 119, 102, 120, 120, 135, 102, 119, 118, 136, 120, 120, 120, 119
        .byte   135, 119, 103, 119, 119, 135, 119, 118, 118, 119, 119, 136, 104, 119, 119, 119, 120, 118, 119, 119, 136, 135, 120, 119, 119, 120, 134, 134, 120, 135, 103, 133
        .byte   118, 136, 118, 118, 136, 118, 119, 103, 120, 119, 120, 118, 134, 136, 135, 135, 87, 119, 120, 119, 104, 136, 136, 103, 119, 119, 86, 120, 136, 119, 135, 103
        .byte   103, 135, 104, 120, 135, 120, 103, 119, 104, 120, 119, 136, 136, 104, 119, 135, 119, 118, 120, 134, 119, 103, 135, 119, 118, 103, 120, 102, 119, 120, 120, 118
        .byte   120, 133, 118, 118, 104, 135, 120, 135, 135, 135, 136, 136, 119, 136, 120, 120, 135, 120, 120, 136, 120, 118, 118, 136, 119, 136, 103, 118, 103, 135, 119, 136
        .byte   87, 120, 135, 119, 118, 119, 103, 119, 119, 104, 119, 103, 120, 101, 136, 135, 135, 119, 119, 119, 120, 118, 120, 120, 135, 119, 136, 104, 135, 118, 135, 135
        .byte   120, 135, 120, 120, 136, 136, 120, 136, 135, 136, 136, 120, 120, 119, 119, 120, 102, 119, 103, 119, 135, 135, 133, 119, 134, 119, 104, 119, 134, 119, 104, 120
        .byte   120, 119, 119, 119, 119, 120, 119, 119, 119, 135, 118, 120, 135, 118, 119, 119, 136, 118, 135, 119, 120, 135, 103, 135, 134, 119, 120, 119, 120, 103, 103, 119
        .byte   135, 135, 119, 119, 119, 102, 119, 103, 119, 119, 118, 103, 120, 120, 120, 120, 135, 135, 119, 136, 120, 135, 104, 104, 135, 136, 119, 103, 119, 118, 119, 134
        .byte   118, 135, 120, 119, 118, 119, 136, 135, 119, 135, 119, 135, 120, 119, 136, 120, 135, 135, 118, 119, 136, 120, 135, 104, 136, 119, 104, 120, 104, 136, 119, 136
        .byte   120, 119, 136, 136, 135, 119, 120, 119, 134, 102, 132, 70, 119, 100, 119, 103, 104, 69, 72, 132, 102, 102, 55, 117, 119, 119, 118, 116, 133, 103, 119, 118
        .byte   119, 119, 133, 118, 119, 118, 103, 119, 86, 119, 119, 103, 119, 117, 135, 118, 118, 119, 119, 103, 103, 103, 119, 134, 120, 118, 119, 118, 85, 120, 118, 118
        .byte   119, 103, 103, 103, 103, 117, 103, 103, 119, 133, 101, 103, 118, 100, 136, 117, 118, 118, 103, 88, 133, 120, 103, 87, 88, 103, 119, 119, 117, 119, 119, 69
        .byte   103, 119, 104, 134, 104, 119, 119, 120, 101, 134, 86, 119, 118, 119, 119, 119, 119, 103, 117, 119, 119, 87, 87, 86, 119, 70, 119, 117, 120, 118, 119, 101
        .byte   118, 135, 135, 133, 119, 134, 103, 120, 119, 120, 118, 119, 136, 118, 136, 102, 104, 104, 135, 120, 119, 103, 119, 119, 119, 119, 103, 118, 133, 119, 119, 120
        .byte   119, 120, 136, 104, 135, 103, 120, 135, 136, 136, 118, 120, 135, 119, 120, 120, 136, 119, 135, 103, 135, 135, 136, 119, 118, 119, 137, 134, 103, 118, 104, 136
        .byte   119, 119, 102, 120, 133, 119, 103, 103, 102, 119, 119, 119, 119, 118, 119, 119, 118, 119, 103, 103, 119, 119, 119, 103, 119, 101, 119, 119, 118, 118, 103, 102
        .byte   120, 119, 87, 119, 104, 120, 118, 118, 118, 118, 135, 119, 117, 104, 119, 103, 118, 103, 103, 104, 119, 119, 104, 102, 102, 136, 118, 119, 119, 119, 119, 86
        .byte   119, 120, 119, 120, 103, 119, 102, 136, 104, 120, 120, 119, 103, 135, 120, 119, 120, 120, 134, 135, 136, 118, 119, 103, 119, 120, 119, 136, 103, 119, 103, 120
        .byte   119, 120, 118, 119, 133, 120, 116, 87, 119, 135, 120, 88, 119, 87, 87, 117, 120, 135, 101, 135, 119, 118, 86, 134, 135, 102, 119, 135, 102, 119, 135, 118
        .byte   119, 103, 133, 120, 118, 136, 103, 119, 119, 120, 119, 118, 135, 119, 119, 119, 120, 120, 117, 136, 103, 118, 103, 135, 118, 103, 119, 135, 118, 136, 136, 119
        .byte   104, 103, 135, 119, 119, 104, 120, 103, 103, 119, 120, 120, 120, 120, 119, 135, 120, 135, 136, 120, 120, 135, 119, 136, 136, 135, 136, 134, 118, 135, 136, 119
        .byte   119, 104, 120, 120, 135, 135, 135, 135, 119, 120, 135, 119, 102, 118, 135, 134, 119, 119, 120, 135, 135, 135, 104, 134, 120, 136, 120, 119, 119, 120, 103, 136
        .byte   120, 119, 120, 120, 120, 135, 136, 118, 135, 104, 120, 120, 104, 136, 120, 120, 136, 136, 119, 136, 120, 119, 135, 136, 135, 134, 120, 120, 120, 136, 135, 120
        .byte   120, 135, 136, 135, 135, 120, 135, 104, 136, 136, 120, 136, 135, 119, 136, 120, 136, 104, 135, 119, 136, 136, 136, 136, 119, 119, 135, 136, 136, 120, 134, 151
        .byte   120, 136, 135, 120, 135, 120, 120, 136, 120, 135, 135, 120, 135, 120, 135, 136, 136, 119, 134, 136, 135, 136, 135, 135, 120, 103, 134, 135, 136, 120, 119, 135
        .byte   135, 135, 119, 120, 119, 134, 136, 135, 135, 135, 136, 120, 135, 135, 135, 135, 135, 120, 136, 120, 136, 120, 117, 102, 119, 101, 87, 118, 120, 103, 86, 85
        .byte   118, 119, 118, 70, 119, 120, 136, 119, 134, 119, 119, 134, 119, 118, 135, 102, 119, 103, 119, 135, 103, 120, 136, 118, 119, 135, 120, 119, 120, 135, 119, 103
        .byte   136, 135, 136, 87, 103, 136, 119, 120, 136, 134, 118, 118, 120, 102, 103, 134, 136, 119, 117, 86, 118, 120, 103, 118, 118, 88, 116, 88, 119, 102, 88, 120
        .byte   136, 119, 119, 135, 135, 119, 136, 119, 104, 118, 135, 120, 103, 136, 120, 120, 103, 103, 120, 135, 136, 119, 135, 134, 119, 135, 119, 117, 118, 119, 70, 103
        .byte   118, 104, 116, 103, 134, 67, 134, 135, 118, 100, 134, 116, 132, 117, 120, 119, 119, 71, 135, 103, 88, 119, 120, 103, 118, 135, 103, 133, 87, 102, 71, 119
        .byte   119, 119, 117, 118, 85, 118, 119, 135, 101, 102, 119, 104, 118, 104, 120, 118, 120, 101, 135, 86, 119, 102, 135, 135, 119, 119, 102, 117, 119, 120, 87, 103
        .byte   85, 119, 87, 104, 116, 119, 103, 119, 102, 119, 87, 119, 103, 118, 133, 103, 119, 118, 119, 119, 119, 132, 88, 118, 87, 88, 119, 87, 119, 87, 119, 71
        .byte   119, 119, 119, 119, 117, 119, 117, 103, 118, 119, 103, 119, 118, 103, 103, 118, 104, 118, 87, 120, 102, 120, 135, 119, 136, 102, 135, 119, 117, 119, 104, 103
        .byte   119, 119, 119, 118, 119, 103, 133, 103, 119, 135, 103, 119, 103, 119, 103, 134, 120, 103, 134, 120, 120, 119, 102, 119, 136, 119, 120, 134, 118, 135, 135, 134
        .byte   120, 103, 133, 119, 120, 119, 120, 120, 120, 136, 120, 119, 135, 135, 119, 119, 120, 135, 104, 119, 119, 135, 119, 120, 118, 119, 119, 118, 119, 119, 120, 135
        .byte   119, 120, 87, 104, 119, 119, 103, 119, 118, 118, 135, 136, 102, 103, 135, 135, 85, 53, 119, 115, 87, 117, 53, 117, 115, 55, 87, 39, 53, 117, 119, 100
        .byte   102, 135, 55, 102, 86, 118, 118, 118, 69, 120, 117, 70, 135, 103, 118, 102, 85, 103, 102, 103, 102, 87, 102, 103, 102, 86, 101, 118, 70, 118, 102, 100
        .byte   102, 87, 132, 103, 118, 71, 101, 88, 118, 118, 103, 99, 71, 119, 100, 102, 100, 72, 119, 102, 102, 100, 131, 134, 134, 103, 116, 87, 119, 85, 119, 102
        .byte   103, 101, 84, 103, 118, 103, 102, 118, 69, 102, 87, 102, 118, 103, 102, 118, 102, 84, 103, 102, 101, 102, 103, 86, 87, 104, 103, 119, 118, 103, 118, 118
        .byte   101, 134, 117, 103, 119, 120, 119, 133, 119, 135, 135, 120, 119, 136, 135, 120, 135, 118, 119, 136, 135, 119, 119, 118, 119, 118, 103, 85, 119, 103, 102, 118
        .byte   118, 102, 119, 119, 118, 134, 135, 86, 119, 120, 135, 135, 120, 134, 119, 120, 119, 102, 103, 135, 136, 120, 103, 104, 119, 103, 120, 136, 119, 135, 119, 120
        .byte   119, 104, 135, 136, 136, 135, 119, 135, 119, 120, 119, 135, 120, 119, 135, 120, 135, 152, 120, 102, 120, 102, 119, 87, 118, 102, 120, 119, 102, 119, 103, 101
        .byte   103, 103, 103, 118, 118, 135, 103, 102, 118, 119, 119, 119, 119, 118, 104, 119, 88, 119, 120, 119, 119, 119, 134, 119, 136, 120, 135, 120, 119, 120, 119, 120
        .byte   118, 86, 119, 71, 117, 101, 102, 86, 102, 118, 87, 118, 119, 118, 102, 119, 119, 104, 120, 119, 135, 120, 136, 120, 120, 103, 136, 136, 135, 119, 136, 120
        .byte   119, 118, 135, 120, 119, 119, 119, 118, 119, 120, 136, 120, 103, 87, 103, 87, 119, 102, 103, 117, 118, 118, 116, 101, 118, 118, 103, 118, 119, 103, 119, 120
        .byte   119, 135, 120, 135, 120, 120, 103, 119, 119, 135, 120, 135, 120, 117, 118, 103, 118, 103, 103, 119, 134, 119, 102, 119, 134, 103, 118, 136, 119, 118, 119, 135
        .byte   136, 135, 119, 119, 119, 136, 119, 136, 120, 135, 102, 119, 120, 118, 120, 136, 135, 135, 120, 103, 119, 103, 136, 104, 134, 103, 136, 135, 119, 134, 120, 120
        .byte   135, 119, 119, 135, 118, 119, 136, 120, 120, 135, 137, 136, 120, 120, 118, 136, 120, 134, 119, 120, 119, 119, 120, 120, 135, 135, 120, 119, 120, 134, 103, 135
        .byte   135, 135, 120, 120, 135, 103, 136, 86, 119, 103, 135, 103, 134, 118, 118, 87, 118, 134, 119, 118, 103, 103, 119, 103, 102, 119, 104, 119, 119, 104, 102, 88
        .byte   119, 102, 119, 119, 119, 135, 136, 135, 119, 135, 136, 135, 135, 120, 136, 119, 119, 136, 118, 118, 104, 85, 120, 102, 103, 119, 118, 102, 119, 118, 102, 117
        .byte   119, 136, 119, 103, 119, 135, 103, 118, 119, 135, 119, 135, 118, 119, 135, 135, 103, 135, 104, 103, 135, 119, 103, 102, 118, 119, 135, 119, 119, 135, 117, 134
        .byte   118, 103, 120, 120, 119, 120, 136, 119, 118, 103, 120, 135, 120, 104, 119, 135, 119, 136, 119, 135, 136, 120, 136, 136, 119, 119, 120, 135, 104, 103, 134, 134
        .byte   102, 134, 104, 134, 101, 120, 133, 102, 118, 102, 118, 118, 103, 136, 120, 120, 103, 119, 103, 120, 118, 120, 120, 136, 102, 136, 135, 135, 134, 86, 120, 119
        .byte   102, 135, 119, 118, 118, 103, 134, 136, 104, 103, 135, 119, 135, 120, 134, 134, 135, 104, 119, 120, 136, 135, 119, 120, 135, 120, 135, 119, 135, 136, 120, 135
        .byte   119, 135, 119, 119, 136, 136, 134, 135, 102, 118, 118, 104, 118, 135, 104, 118, 134, 118, 117, 119, 102, 103, 103, 119, 136, 104, 136, 136, 119, 120, 118, 120
        .byte   135, 119, 119, 119, 135, 120, 102, 132, 134, 134, 70, 71, 70, 119, 54, 117, 100, 135, 103, 104, 100, 117, 135, 119, 116, 135, 120, 86, 135, 120, 103, 133
        .byte   118, 119, 118, 119, 119, 102, 87, 102, 119, 118, 103, 118, 87, 118, 102, 87, 135, 102, 119, 87, 88, 119, 87, 118, 87, 120, 70, 119, 135, 119, 135, 101
        .byte   119, 117, 104, 104, 103, 119, 119, 119, 87, 118, 103, 119, 104, 117, 103, 119, 119, 103, 103, 119, 104, 119, 119, 87, 102, 119, 119, 119, 102, 88, 120, 119
        .byte   119, 118, 117, 119, 103, 133, 118, 134, 88, 118, 103, 119, 103, 119, 116, 120, 119, 136, 118, 119, 135, 120, 119, 103, 120, 119, 135, 104, 119, 103, 120, 119
        .byte   118, 119, 120, 119, 119, 119, 120, 119, 104, 119, 118, 120, 102, 120, 101, 102, 119, 119, 87, 120, 117, 102, 103, 102, 102, 104, 103, 103, 118, 87, 103, 103
        .byte   120, 103, 136, 103, 136, 135, 135, 118, 118, 119, 118, 103, 120, 103, 119, 119, 136, 103, 134, 119, 102, 119, 119, 119, 117, 118, 103, 118, 119, 120, 87, 103
        .byte   119, 136, 120, 118, 119, 104, 103, 119, 135, 120, 120, 120, 119, 120, 135, 119, 119, 120, 136, 104, 119, 135, 136, 119, 135, 118, 135, 120, 118, 103, 135, 119
        .byte   136, 119, 136, 118, 119, 119, 119, 135, 135, 136, 135, 135, 134, 120, 137, 135, 135, 120, 135, 135, 119, 135, 135, 135, 136, 136, 135, 136, 104, 135, 119, 119
        .byte   134, 119, 135, 119, 136, 135, 136, 136, 135, 119, 136, 135, 134, 119, 136, 135, 120, 120, 120, 120, 119, 103, 135, 104, 135, 133, 136, 136, 120, 119, 135, 119
        .byte   134, 103, 120, 103, 118, 119, 119, 102, 103, 135, 136, 135, 118, 136, 103, 86, 135, 119, 119, 135, 86, 134, 104, 119, 134, 119, 119, 118, 104, 135, 119, 119
        .byte   103, 136, 87, 119, 136, 103, 118, 118, 120, 133, 119, 120, 119, 134, 104, 135, 136, 119, 136, 119, 135, 135, 120, 104, 136, 120, 119, 136, 135, 119, 120, 135
        .byte   120, 136, 119, 104, 135, 135, 120, 120, 120, 120, 136, 104, 120, 119, 118, 134, 103, 117, 119, 120, 135, 102, 103, 133, 119, 120, 102, 119, 119, 135, 119, 135
        .byte   120, 120, 135, 135, 136, 120, 136, 136, 136, 120, 136, 136, 103, 120, 119, 120, 135, 134, 136, 119, 120, 120, 135, 119, 104, 120, 135, 119, 120, 118, 120, 119
        .byte   119, 120, 103, 119, 135, 119, 119, 135, 135, 102, 104, 117, 101, 87, 119, 102, 87, 88, 71, 118, 87, 118, 118, 119, 102, 135, 135, 136, 119, 119, 120, 136
        .byte   120, 120, 118, 135, 119, 135, 135, 120, 101, 118, 118, 116, 87, 102, 86, 120, 103, 87, 101, 118, 103, 117, 103, 103, 120, 103, 118, 103, 103, 101, 104, 119
        .byte   118, 118, 120, 101, 119, 119, 135, 120, 118, 137, 134, 119, 135, 120, 135, 135, 120, 119, 136, 119, 119, 135, 136, 119, 119, 134, 120, 120, 120, 119, 136, 103
        .byte   119, 135, 136, 136, 120, 134, 119, 135, 136, 119, 119, 135, 135, 103, 135, 103, 119, 120, 118, 103, 119, 119, 119, 102, 86, 135, 119, 103, 102, 135, 103, 103
        .byte   136, 118, 134, 120, 120, 119, 119, 135, 120, 120, 136, 119, 104, 120, 103, 120, 120, 119, 104, 117, 118, 119, 117, 120, 135, 103, 136, 104, 135, 136, 135, 102
        .byte   103, 119, 103, 119, 103, 119, 103, 119, 103, 119, 103, 102, 117, 118, 118, 119, 119, 119, 118, 119, 119, 120, 135, 135, 119, 118, 136, 119, 104, 135, 135, 119
        .byte   136, 120, 136, 136, 119, 119, 119, 136, 135, 136, 120, 135, 119, 120, 135, 136, 136, 136, 135, 119, 136, 136, 135, 120, 134, 119, 120, 135, 119, 103, 117, 87
        .byte   119, 117, 118, 119, 103, 87, 87, 117, 118, 118, 72, 134, 120, 135, 119, 133, 118, 104, 119, 119, 119, 119, 118, 135, 134, 135, 119, 88, 104, 120, 135, 119
        .byte   134, 102, 118, 120, 119, 118, 118, 118, 120, 120, 120, 118, 119, 136, 136, 119, 102, 118, 136, 103, 120, 119, 119, 119, 119, 118, 119, 120, 120, 134, 103, 103
        .byte   120, 117, 103, 102, 134, 119, 103, 119, 135, 120, 120, 120, 103, 119, 119, 119, 134, 135, 119, 103, 120, 119, 119, 118, 119, 135, 135, 118, 118, 104, 103, 120
        .byte   135, 136, 135, 120, 119, 119, 136, 134, 135, 119, 119, 119, 103, 119, 135, 103, 119, 135, 120, 134, 119, 120, 134, 135, 118, 103, 118, 120, 136, 119, 117, 135
        .byte   136, 102, 120, 135, 120, 134, 134, 135, 133, 104, 120, 120, 120, 136, 103, 135, 118, 136, 104, 104, 135, 104, 120, 104, 119, 88, 120, 119, 120, 120, 118, 135
        .byte   118, 135, 119, 104, 118, 136, 136, 119, 120, 120, 120, 119, 135, 118, 119, 135, 136, 136, 135, 119, 119, 136, 120, 135, 135, 120, 136, 134, 136, 135, 119, 120
        .byte   135, 135, 135, 103, 118, 136, 120, 119, 119, 120, 119, 136, 136, 119, 120, 119, 135, 118, 103, 118, 119, 119, 135, 119, 119, 135, 103, 135, 135, 136, 120, 135
        .byte   136, 120, 119, 136, 119, 135, 136, 135, 119, 104, 136, 136, 136, 135, 136, 136, 136, 135, 152, 136, 135, 136, 135, 136, 120, 136, 120, 136, 120, 120, 119, 136
        .byte   118, 135, 136, 135, 135, 119, 120, 135, 135, 136, 135, 136, 120, 136, 135, 119, 136, 136, 135, 136, 120, 120, 120, 136, 120, 119, 119, 136, 120, 119, 103, 136
        .byte   119, 136, 104, 103, 120, 135, 120, 120, 135, 119, 120, 104, 136, 119, 136, 135, 136, 135, 135, 120, 135, 119, 120, 120, 102, 119, 119, 102, 118, 120, 117, 134
        .byte   117, 119, 117, 102, 118, 135, 135, 119, 134, 135, 103, 118, 119, 135, 118, 119, 136, 118, 118, 103, 86, 119, 119, 118, 118, 103, 118, 120, 119, 135, 119, 118
        .byte   118, 120, 136, 119, 103, 118, 118, 103, 136, 120, 103, 134, 119, 118, 118, 135, 101, 118, 103, 136, 119, 101, 119, 103, 119, 134, 103, 119, 136, 104, 119, 119
        .byte   103, 102, 135, 103, 103, 135, 120, 119, 119, 119, 104, 136, 135, 134, 133, 118, 135, 136, 120, 119, 119, 120, 120, 135, 120, 119, 120, 120, 119, 119, 136, 119
        .byte   118, 103, 135, 118, 119, 119, 103, 119, 118, 103, 119, 87, 103, 103, 119, 135, 120, 136, 103, 135, 119, 135, 120, 136, 120, 120, 135, 120, 135, 135, 119, 134
        .byte   103, 102, 121, 103, 120, 136, 119, 119, 119, 119, 103, 119, 120, 119, 119, 103, 120, 119, 135, 119, 119, 119, 119, 119, 119, 103, 103, 118, 120, 120, 120, 119
        .byte   120, 120, 135, 135, 136, 119, 135, 118, 119, 136, 119, 136, 136, 135, 120, 136, 135, 136, 135, 120, 135, 135, 119, 120, 120, 136, 119, 121, 118, 120, 135, 119
        .byte   119, 119, 119, 135, 104, 135, 136, 119, 118, 136, 103, 135, 119, 119, 135, 135, 119, 119, 119, 102, 120, 120, 119, 119, 134, 120, 104, 119, 119, 120, 136, 119
        .byte   135, 135, 135, 120, 119, 135, 135, 120, 134, 119, 103, 135, 104, 104, 120, 119, 119, 118, 120, 135, 118, 119, 136, 103, 119, 136, 136, 136, 119, 119, 135, 136
        .byte   135, 119, 120, 136, 136, 135, 104, 136, 119, 119, 134, 119, 103, 119, 120, 120, 135, 134, 88, 134, 118, 103, 104, 120, 135, 134, 119, 103, 86, 118, 120, 103
        .byte   135, 119, 119, 119, 120, 136, 135, 120, 135, 136, 120, 136, 136, 136, 119, 135, 136, 120, 103, 103, 119, 135, 102, 104, 118, 119, 119, 103, 85, 118, 104, 119
        .byte   86, 101, 120, 102, 119, 102, 87, 119, 136, 120, 119, 87, 103, 102, 119, 104, 134, 104, 118, 118, 133, 118, 136, 135, 119, 120, 119, 102, 119, 117, 119, 119
        .byte   103, 119, 135, 119, 136, 136, 135, 134, 135, 119, 135, 119, 135, 119, 120, 120, 136, 135, 136, 136, 136, 136, 135, 119, 120, 136, 120, 120, 136, 136, 120, 135
        .byte   119, 136, 120, 118, 120, 119, 120, 135, 135, 120, 119, 135, 134, 134, 103, 103, 102, 118, 135, 118, 87, 103, 119, 117, 119, 117, 119, 120, 118, 118, 102, 120
        .byte   118, 119, 135, 119, 118, 135, 118, 102, 133, 103, 102, 103, 103, 102, 117, 86, 102, 118, 118, 118, 119, 118, 118, 101, 118, 102, 119, 119, 118, 119, 103, 119
        .byte   103, 118, 119, 119, 119, 119, 119, 120, 118, 120, 135, 103, 120, 134, 134, 119, 87, 119, 135, 119, 120, 120, 119, 135, 118, 119, 102, 119, 119, 119, 118, 117
        .byte   118, 135, 120, 119, 135, 134, 102, 135, 118, 135, 134, 118, 102, 119, 102, 119, 119, 101, 119, 119, 119, 117, 103, 119, 118, 119, 136, 104, 135, 119, 119, 118
        .byte   103, 120, 120, 118, 103, 116, 103, 86, 56, 117, 71, 152, 100, 70, 70, 103, 70, 71, 87, 102, 104, 103, 102, 103, 86, 103, 118, 118, 134, 87, 102, 101
        .byte   104, 118, 102, 135, 119, 101, 119, 87, 104, 101, 134, 136, 118, 119, 135, 120, 103, 134, 119, 120, 117, 103, 102, 120, 118, 119, 103, 136, 103, 103, 87, 118
        .byte   119, 117, 87, 102, 120, 119, 103, 119, 118, 70, 119, 103, 119, 101, 135, 117, 119, 119, 117, 70, 119, 102, 87, 103, 118, 102, 119, 118, 102, 133, 134, 134
        .byte   135, 119, 87, 133, 119, 136, 103, 133, 118, 118, 119, 102, 135, 119, 120, 119, 119, 134, 102, 120, 119, 103, 119, 120, 119, 119, 135, 119, 118, 119, 104, 119
        .byte   119, 103, 119, 119, 119, 136, 104, 119, 135, 103, 119, 118, 135, 135, 118, 119, 120, 119, 119, 102, 120, 119, 135, 120, 135, 120, 135, 135, 136, 136, 134, 120
        .byte   103, 119, 120, 136, 119, 119, 135, 136, 120, 134, 119, 120, 103, 118, 135, 103, 136, 118, 119, 119, 118, 135, 103, 120, 135, 134, 119, 119, 134, 135, 120, 136
        .byte   118, 136, 135, 119, 135, 135, 119, 135, 120, 135, 119, 135, 136, 135, 136, 134, 136, 134, 119, 136, 135, 120, 119, 120, 118, 120, 103, 118, 119, 118, 103, 103
        .byte   120, 102, 103, 120, 118, 103, 118, 119, 104, 119, 119, 104, 119, 119, 119, 118, 120, 103, 119, 120, 71, 104, 119, 119, 117, 88, 135, 85, 119, 119, 133, 118
        .byte   134, 119, 133, 103, 136, 119, 104, 136, 120, 135, 119, 120, 120, 135, 135, 120, 136, 103, 134, 119, 103, 88, 103, 104, 135, 118, 103, 104, 118, 103, 135, 104
        .byte   87, 120, 120, 135, 118, 119, 135, 135, 118, 118, 135, 119, 120, 135, 118, 117, 119, 135, 103, 119, 135, 119, 118, 119, 119, 118, 118, 135, 135, 134, 135, 118
        .byte   101, 85, 69, 119, 116, 119, 135, 103, 116, 103, 117, 116, 99, 103, 135, 118, 119, 134, 104, 118, 120, 135, 117, 119, 119, 102, 120, 121, 104, 103, 119, 119
        .byte   135, 120, 103, 88, 103, 134, 136, 135, 119, 86, 120, 120, 88, 103, 118, 120, 119, 119, 118, 103, 120, 103, 103, 118, 102, 119, 117, 134, 118, 119, 102, 119
        .byte   118, 101, 104, 103, 86, 119, 119, 134, 102, 117, 119, 116, 101, 86, 101, 119, 71, 101, 53, 103, 100, 120, 102, 100, 119, 118, 118, 119, 119, 119, 119, 103
        .byte   119, 119, 101, 135, 103, 102, 87, 119, 119, 102, 134, 86, 102, 102, 85, 119, 118, 100, 102, 117, 117, 85, 134, 136, 120, 119, 136, 120, 135, 119, 135, 119
        .byte   136, 136, 119, 135, 119, 104, 88, 102, 118, 118, 119, 118, 70, 102, 102, 86, 118, 101, 85, 103, 117, 119, 120, 118, 119, 120, 151, 119, 120, 135, 103, 135
        .byte   119, 118, 119, 119, 120, 134, 102, 118, 135, 135, 104, 103, 134, 103, 119, 87, 118, 120, 101, 119, 119, 120, 135, 119, 135, 119, 119, 104, 118, 118, 119, 134
        .byte   119, 103, 135, 103, 103, 103, 120, 136, 119, 120, 119, 102, 119, 103, 117, 118, 119, 135, 70, 103, 99, 134, 100, 116, 102, 119, 71, 72, 101, 102, 100, 104
        .byte   102, 134, 119, 102, 103, 118, 103, 119, 117, 119, 119, 119, 119, 102, 119, 134, 134, 136, 87, 118, 136, 120, 135, 101, 104, 118, 136, 103, 104, 135, 134, 134
        .byte   136, 136, 88, 133, 119, 136, 103, 133, 119, 118, 119, 103, 135, 134, 119, 119, 117, 119, 103, 134, 103, 103, 119, 118, 119, 118, 120, 104, 119, 87, 87, 135
        .byte   151, 119, 120, 118, 101, 135, 120, 71, 119, 135, 103, 117, 135, 119, 69, 119, 135, 103, 102, 102, 133, 117, 119, 119, 134, 118, 119, 120, 135, 118, 119, 119
        .byte   103, 119, 119, 104, 119, 102, 119, 119, 119, 120, 119, 119, 135, 119, 118, 135, 135, 118, 103, 135, 119, 118, 119, 119, 103, 117, 118, 119, 103, 120, 103, 136
        .byte   102, 135, 118, 119, 103, 104, 118, 120, 119, 120, 135, 120, 118, 103, 118, 119, 119, 119, 119, 135, 119, 120, 120, 119, 103, 119, 135, 119, 136, 104, 135, 120
        .byte   136, 119, 119, 104, 120, 118, 118, 86, 103, 118, 104, 134, 135, 103, 87, 103, 118, 104, 119, 103, 120, 135, 136, 102, 119, 119, 135, 135, 118, 118, 119, 135
        .byte   119, 119, 120, 119, 101, 119, 135, 85, 119, 101, 119, 84, 119, 117, 119, 119, 88, 119, 117, 103, 102, 116, 118, 135, 85, 119, 117, 87, 101, 86, 119, 101
        .byte   120, 119, 119, 134, 103, 135, 136, 119, 103, 119, 118, 119, 102, 120, 133, 119, 119, 101, 104, 120, 119, 103, 103, 102, 135, 103, 119, 117, 102, 102, 120, 118
        .byte   119, 118, 134, 119, 135, 119, 119, 119, 119, 104, 118, 102, 120, 103, 134, 104, 119, 136, 103, 134, 119, 135, 119, 120, 135, 118, 119, 87, 104, 135, 120, 119
        .byte   135, 103, 103, 120, 119, 120, 134, 103, 135, 118, 118, 101, 104, 102, 103, 118, 104, 119, 117, 103, 103, 86, 86, 103, 103, 134, 102, 118, 119, 102, 87, 88
        .byte   103, 135, 135, 119, 102, 86, 134, 103, 102, 101, 119, 102, 119, 103, 118, 103, 119, 135, 119, 102, 119, 103, 103, 119, 119, 118, 119, 119, 119, 87, 118, 120
        .byte   103, 119, 135, 119, 120, 134, 102, 118, 119, 104, 119, 119, 136, 119, 119, 119, 103, 120, 135, 120, 104, 103, 135, 118, 135, 119, 119, 119, 119, 119, 103, 120
        .byte   119, 136, 134, 119, 119, 135, 134, 135, 119, 103, 119, 118, 135, 135, 86, 119, 119, 119, 120, 119, 119, 104, 118, 103, 103, 118, 119, 118, 102, 117, 103, 120
        .byte   134, 134, 117, 133, 117, 119, 120, 103, 118, 120, 118, 119, 119, 119, 119, 120, 102, 118, 119, 135, 136, 119, 119, 119, 135, 136, 119, 136, 135, 119, 119, 120
        .byte   136, 136, 119, 119, 105, 118, 136, 120, 118, 119, 119, 136, 135, 118, 119, 135, 136, 119, 119, 119, 120, 135, 120, 119, 120, 136, 120, 118, 134, 103, 120, 135
        .byte   119, 103, 136, 120, 118, 135, 134, 119, 119, 103, 119, 117, 120, 120, 103, 86, 104, 119, 102, 119, 102, 118, 118, 87, 102, 119, 119, 103, 118, 119, 55, 119
        .byte   85, 118, 82, 56, 85, 85, 83, 133, 115, 103, 83, 119, 115, 117, 118, 117, 102, 85, 104, 118, 103, 118, 102, 117, 102, 103, 116, 103, 133, 120, 133, 117
        .byte   70, 101, 119, 87, 119, 103, 119, 102, 135, 116, 101, 104, 102, 68, 134, 120, 103, 117, 102, 118, 86, 71, 117, 134, 102, 55, 100, 102, 119, 117, 99, 135
        .byte   101, 102, 133, 102, 87, 117, 68, 104, 119, 117, 119, 133, 119, 116, 116, 119, 119, 86, 103, 103, 117, 118, 103, 116, 117, 118, 103, 116, 103, 87, 104, 101
        .byte   102, 103, 136, 102, 87, 103, 102, 103, 103, 118, 101, 101, 87, 119, 102, 134, 103, 87, 102, 104, 118, 118, 119, 118, 118, 102, 103, 120, 120, 103, 117, 120
        .byte   120, 103, 104, 133, 120, 119, 120, 135, 103, 103, 119, 119, 120, 119, 120, 118, 136, 120, 119, 135, 103, 119, 119, 120, 120, 118, 120, 135, 103, 119, 136, 118
        .byte   119, 136, 134, 134, 120, 135, 86, 119, 103, 119, 135, 120, 104, 119, 136, 103, 103, 119, 103, 119, 136, 135, 119, 118, 135, 136, 120, 120, 135, 120, 135, 104
        .byte   119, 118, 136, 135, 118, 88, 103, 135, 119, 119, 119, 134, 118, 135, 119, 104, 87, 135, 85, 87, 120, 85, 86, 119, 119, 85, 71, 116, 119, 103, 87, 118
        .byte   118, 103, 119, 118, 119, 119, 102, 119, 133, 102, 102, 136, 119, 102, 135, 119, 135, 119, 102, 135, 119, 119, 104, 120, 118, 119, 105, 135, 120, 102, 134, 102
        .byte   103, 120, 104, 119, 102, 86, 134, 133, 119, 103, 120, 103, 134, 135, 120, 87, 134, 134, 119, 135, 104, 119, 120, 119, 135, 135, 120, 101, 119, 119, 118, 118
        .byte   103, 118, 103, 118, 119, 103, 118, 102, 104, 119, 102, 119, 104, 101, 135, 103, 101, 134, 118, 119, 118, 134, 119, 119, 119, 119, 135, 135, 118, 120, 136, 119
        .byte   102, 136, 103, 103, 119, 120, 120, 86, 119, 119, 135, 120, 119, 119, 136, 103, 120, 135, 120, 134, 120, 119, 119, 104, 87, 120, 118, 119, 134, 102, 136, 135
        .byte   104, 103, 103, 103, 135, 103, 120, 134, 119, 119, 119, 118, 135, 136, 134, 117, 120, 118, 119, 134, 135, 119, 104, 120, 136, 119, 119, 103, 135, 119, 119, 119
        .byte   119, 119, 120, 134, 119, 120, 120, 120, 120, 136, 136, 135, 120, 136, 135, 121, 119, 120, 135, 134, 119, 104, 120, 102, 119, 104, 103, 120, 103, 120, 87, 119
        .byte   103, 119, 104, 119, 119, 104, 118, 87, 103, 102, 119, 120, 120, 134, 102, 104, 118, 134, 101, 87, 103, 86, 71, 103, 103, 86, 103, 86, 136, 118, 103, 118
        .byte   119, 119, 135, 119, 119, 103, 135, 119, 119, 120, 103, 104, 136, 119, 135, 118, 118, 120, 135, 134, 135, 120, 118, 118, 135, 133, 120, 119, 120, 119, 117, 119
        .byte   136, 119, 133, 117, 102, 103, 103, 103, 103, 116, 120, 119, 104, 135, 119, 135, 118, 134, 119, 119, 103, 119, 135, 103, 119, 118, 120, 119, 103, 102, 120, 135
        .byte   120, 119, 119, 118, 119, 119, 119, 118, 119, 103, 120, 119, 135, 103, 104, 119, 104, 120, 103, 102, 120, 119, 103, 119, 119, 103, 134, 119, 119, 120, 119, 136
        .byte   119, 135, 102, 103, 119, 119, 120, 118, 136, 135, 119, 119, 103, 119, 136, 120, 135, 119, 119, 104, 104, 120, 120, 136, 136, 135, 135, 119, 136, 120, 119, 120
        .byte   135, 120, 135, 136, 135, 119, 120, 136, 104, 119, 120, 120, 103, 135, 117, 120, 119, 136, 134, 103, 118, 135, 118, 104, 119, 118, 86, 119, 119, 119, 102, 103
        .byte   103, 119, 103, 103, 118, 135, 104, 136, 136, 120, 120, 120, 135, 135, 119, 119, 135, 120, 135, 136, 118, 118, 136, 118, 134, 118, 86, 118, 119, 118, 134, 117
        .byte   102, 118, 103, 104, 102, 118, 135, 118, 119, 102, 102, 103, 135, 117, 119, 119, 118, 117, 119, 101, 101, 102, 102, 102, 103, 102, 119, 85, 103, 118, 120, 102
        .byte   103, 117, 119, 103, 103, 101, 119, 87, 88, 119, 86, 119, 71, 103, 87, 119, 103, 103, 119, 103, 102, 119, 104, 104, 119, 119, 88, 103, 134, 102, 118, 135
        .byte   120, 118, 120, 119, 135, 119, 103, 136, 119, 120, 119, 103, 119, 103, 120, 136, 118, 120, 120, 136, 152, 120, 135, 120, 136, 119, 119, 136, 120, 135, 102, 102
        .byte   119, 103, 87, 88, 120, 103, 134, 86, 118, 119, 103, 134, 118, 102, 119, 119, 119, 118, 104, 135, 119, 119, 103, 119, 119, 103, 120, 120, 119, 136, 119, 120
        .byte   135, 136, 120, 135, 120, 135, 119, 120, 136, 103, 102, 120, 119, 118, 119, 119, 102, 119, 103, 118, 119, 118, 120, 119, 135, 119, 120, 119, 118, 134, 120, 103
        .byte   119, 120, 119, 120, 118, 120, 103, 136, 119, 120, 119, 136, 119, 120, 120, 104, 120, 120, 135, 120, 103, 103, 119, 119, 136, 118, 119, 103, 119, 103, 119, 120
        .byte   120, 120, 103, 119, 103, 103, 120, 117, 118, 69, 86, 101, 86, 104, 84, 103, 86, 134, 118, 117, 102, 103, 86, 103, 101, 102, 85, 135, 134, 103, 103, 70
        .byte   104, 119, 118, 103, 135, 118, 151, 102, 119, 119, 120, 103, 120, 119, 103, 119, 120, 135, 135, 134, 120, 119, 101, 88, 87, 118, 102, 119, 118, 134, 101, 134
        .byte   103, 103, 86, 119, 118, 103, 134, 101, 119, 102, 135, 119, 121, 101, 119, 104, 120, 117, 119, 120, 134, 116, 103, 119, 86, 104, 118, 119, 86, 119, 134, 119
        .byte   103, 119, 120, 119, 120, 118, 103, 135, 103, 118, 119, 118, 119, 152, 119, 119, 134, 102, 135, 86, 104, 101, 135, 116, 135, 101, 135, 135, 87, 120, 119, 136
        .byte   135, 120, 135, 135, 104, 119, 120, 119, 135, 136, 120, 118, 136, 118, 102, 120, 120, 120, 135, 119, 102, 104, 135, 104, 118, 88, 119, 136, 119, 86, 119, 119
        .byte   102, 135, 102, 117, 101, 119, 101, 116, 87, 118, 103, 119, 104, 120, 135, 135, 136, 136, 119, 103, 119, 135, 119, 118, 119, 119, 104, 103, 136, 136, 136, 135
        .byte   120, 119, 119, 135, 135, 120, 118, 136, 119, 118, 119, 135, 134, 104, 119, 119, 117, 135, 118, 120, 134, 102, 119, 102, 119, 87, 86, 117, 102, 119, 101, 119
        .byte   117, 87, 119, 103, 101, 116, 118, 118, 119, 119, 119, 104, 135, 118, 86, 119, 119, 135, 119, 135, 119, 118, 119, 135, 120, 102, 119, 134, 103, 119, 120, 120
        .byte   119, 135, 103, 120, 120, 135, 136, 135, 119, 103, 119, 118, 120, 119, 119, 119, 120, 119, 103, 120, 102, 136, 119, 117, 135, 119, 118, 103, 119, 119, 119, 118
        .byte   119, 118, 120, 118, 134, 104, 133, 119, 103, 118, 102, 87, 120, 119, 119, 135, 119, 120, 103, 119, 119, 104, 119, 104, 136, 87, 102, 135, 134, 136, 119, 136
        .byte   119, 102, 103, 103, 117, 104, 120, 117, 134, 117, 101, 71, 104, 86, 103, 135, 102, 134, 119, 135, 119, 103, 134, 103, 103, 87, 136, 119, 103, 119, 135, 119
        .byte   118, 103, 135, 136, 118, 151, 104, 120, 103, 118, 119, 134, 135, 118, 133, 119, 135, 117, 87, 103, 134, 100, 135, 133, 119, 133, 86, 120, 101, 103, 104, 117
        .byte   103, 103, 135, 101, 87, 135, 119, 87, 118, 104, 70, 119, 103, 119, 117, 119, 104, 120, 119, 104, 119, 119, 119, 102, 118, 103, 102, 104, 120, 134, 119, 135
        .byte   136, 118, 120, 136, 119, 103, 135, 119, 120, 118, 134, 103, 100, 55, 102, 70, 118, 70, 103, 116, 118, 116, 136, 100, 101, 118, 103, 120, 103, 118, 103, 118
        .byte   102, 120, 119, 86, 119, 118, 119, 103, 134, 103, 136, 118, 101, 134, 119, 119, 119, 120, 88, 102, 104, 135, 135, 117, 119, 119, 68, 119, 134, 87, 117, 101
        .byte   133, 133, 134, 119, 118, 117, 118, 103, 120, 87, 120, 117, 103, 102, 102, 134, 103, 117, 117, 103, 118, 134, 119, 119, 133, 119, 103, 102, 120, 119, 120, 134
        .byte   118, 119, 102, 119, 119, 119, 85, 135, 103, 118, 134, 119, 135, 103, 87, 134, 119, 118, 71, 118, 119, 103, 119, 104, 119, 102, 118, 119, 119, 104, 119, 103
        .byte   118, 103, 118, 135, 120, 135, 120, 119, 120, 135, 118, 136, 136, 136, 119, 118, 119, 119, 120, 119, 120, 102, 103, 119, 119, 136, 119, 120, 103, 119, 104, 119
        .byte   135, 118, 119, 102, 87, 135, 134, 119, 102, 119, 119, 118, 119, 102, 120, 135, 119, 133, 120, 135, 136, 134, 104, 135, 136, 119, 120, 119, 102, 136, 136, 119
        .byte   135, 135, 135, 119, 136, 119, 120, 135, 136, 119, 120, 135, 136, 136, 119, 136, 119, 135, 120, 103, 120, 120, 136, 119, 134, 136, 136, 120, 103, 104, 103, 104
        .byte   133, 72, 135, 87, 135, 135, 135, 120, 133, 86, 134, 119, 119, 119, 119, 135, 136, 119, 119, 120, 120, 104, 135, 119, 119, 118, 119, 119, 119, 119, 151, 134
        .byte   135, 135, 135, 105, 118, 136, 120, 120, 119, 119, 134, 104, 118, 119, 119, 120, 119, 119, 118, 135, 120, 119, 102, 119, 104, 133, 119, 120, 135, 120, 119, 119
        .byte   119, 134, 135, 119, 102, 119, 135, 118, 119, 120, 117, 134, 119, 87, 119, 103, 118, 134, 103, 118, 134, 118, 119, 86, 119, 119, 102, 118, 101, 117, 85, 104
        .byte   102, 116, 86, 119, 102, 120, 135, 118, 103, 120, 103, 119, 136, 120, 118, 118, 135, 119, 119, 119, 102, 120, 120, 104, 120, 118, 104, 134, 120, 118, 101, 119
        .byte   120, 119, 119, 120, 119, 120, 120, 120, 119, 120, 134, 103, 118, 120, 119, 136, 119, 119, 119, 119, 136, 120, 135, 119, 119, 104, 120, 134, 119, 135, 135, 121
        .byte   135, 102, 118, 136, 103, 135, 101, 136, 88, 135, 104, 103, 152, 118, 104, 119, 120, 135, 135, 119, 119, 120, 135, 136, 119, 119, 136, 135, 103, 136, 135, 119
        .byte   134, 119, 120, 120, 102, 120, 136, 119, 134, 136, 135, 86, 134, 120, 135, 104, 119, 135, 120, 136, 135, 120, 119, 135, 119, 136, 135, 135, 135, 119, 119, 135
        .byte   117, 119, 119, 118, 136, 135, 103, 119, 118, 119, 134, 104, 119, 136, 135, 119, 119, 135, 118, 118, 119, 135, 135, 120, 119, 119, 118, 136, 104, 119, 120, 103
        .byte   88, 136, 119, 104, 136, 120, 135, 135, 135, 134, 117, 136, 135, 103, 103, 120, 104, 104, 120, 119, 119, 135, 119, 119, 134, 135, 120, 136, 119, 136, 136, 103
        .byte   120, 136, 120, 135, 119, 136, 119, 136, 119, 119, 119, 136, 103, 119, 120, 119, 103, 134, 103, 103, 136, 136, 117, 104, 118, 85, 119, 119, 119, 87, 135, 101
        .byte   117, 103, 103, 102, 103, 116, 87, 119, 86, 119, 117, 118, 84, 135, 117, 103, 103, 118, 102, 136, 86, 120, 120, 120, 120, 119, 119, 135, 118, 103, 136, 136
        .byte   103, 120, 104, 119, 135, 150, 135, 103, 119, 135, 136, 135, 119, 119, 136, 152, 119, 104, 136, 119, 119, 119, 103, 120, 134, 119, 104, 134, 101, 119, 135, 102
        .byte   134, 135, 119, 120, 120, 103, 120, 119, 103, 120, 119, 135, 135, 120, 119, 135, 136, 135, 135, 119, 103, 134, 118, 135, 120, 103, 119, 136, 119, 120, 136, 120
        .byte   119, 87, 87, 133, 104, 118, 133, 119, 135, 86, 87, 119, 117, 116, 118, 120, 119, 119, 119, 118, 135, 119, 102, 135, 118, 118, 120, 119, 118, 120, 102, 119
        .byte   119, 103, 118, 119, 103, 119, 119, 103, 119, 103, 86, 117, 135, 134, 136, 134, 118, 103, 135, 104, 136, 120, 134, 117, 134, 120, 119, 118, 133, 119, 103, 117
        .byte   118, 134, 134, 103, 103, 119, 119, 134, 120, 119, 119, 135, 134, 103, 103, 120, 104, 119, 119, 87, 103, 119, 119, 119, 119, 119, 135, 135, 135, 102, 119, 135
        .byte   136, 120, 118, 119, 135, 136, 118, 135, 136, 135, 103, 119, 120, 119, 103, 135, 135, 103, 118, 119, 103, 136, 119, 119, 103, 135, 136, 119, 118, 104, 118, 120
        .byte   120, 87, 135, 104, 102, 119, 119, 119, 120, 136, 118, 119, 103, 87, 119, 120, 104, 135, 103, 135, 102, 135, 134, 119, 135, 118, 120, 119, 136, 117, 119, 102
        .byte   135, 119, 104, 136, 134, 133, 119, 103, 104, 102, 118, 136, 119, 104, 118, 118, 104, 136, 103, 119, 103, 135, 119, 120, 103, 120, 135, 136, 119, 135, 135, 136
        .byte   119, 134, 119, 135, 118, 117, 119, 119, 118, 119, 119, 135, 135, 119, 134, 103, 136, 103, 117, 119, 104, 117, 117, 135, 120, 84, 87, 118, 119, 87, 88, 135
        .byte   87, 69, 119, 119, 103, 72, 103, 71, 55, 118, 135, 87, 70, 103, 88, 101, 135, 104, 103, 119, 134, 102, 118, 120, 88, 119, 119, 103, 133, 118, 119, 134
        .byte   104, 136, 118, 118, 118, 133, 103, 88, 119, 103, 103, 135, 119, 119, 134, 120, 119, 118, 87, 119, 133, 119, 103, 134, 102, 119, 120, 119, 103, 119, 84, 119
        .byte   100, 117, 131, 103, 119, 116, 118, 118, 119, 100, 86, 117, 102, 103, 102, 104, 118, 103, 118, 86, 119, 118, 103, 103, 118, 103, 134, 104, 136, 104, 119, 118
        .byte   104, 118, 120, 117, 119, 119, 104, 134, 119, 118, 135, 134, 135, 133, 119, 134, 135, 135, 118, 136, 120, 120, 118, 120, 119, 134, 120, 118, 134, 119, 135, 119
        .byte   102, 117, 119, 103, 119, 119, 135, 134, 135, 119, 119, 135, 135, 104, 118, 119, 135, 135, 136, 118, 119, 118, 135, 118, 119, 135, 118, 103, 135, 119, 104, 119
        .byte   119, 118, 135, 119, 120, 133, 135, 119, 136, 103, 135, 135, 119, 103, 103, 119, 120, 120, 119, 120, 135, 133, 104, 120, 102, 119, 134, 137, 119, 104, 151, 104
        .byte   135, 119, 119, 119, 119, 136, 135, 136, 136, 120, 136, 136, 136, 136, 136, 135, 136, 135, 135, 120, 136, 136, 103, 135, 120, 136, 135, 136, 135, 135, 119, 135
        .byte   120, 119, 135, 135, 120, 135, 119, 119, 120, 135, 104, 135, 136, 120, 120, 136, 136, 136, 119, 120, 136, 119, 120, 136, 119, 104, 135, 120, 119, 135, 135, 118
        .byte   136, 135, 135, 120, 135, 103, 136, 136, 136, 135, 136, 135, 136, 136, 136, 134, 135, 136, 119, 134, 120, 136, 119, 135, 135, 135, 120, 119, 120, 135, 135, 135
        .byte   119, 136, 136, 136, 135, 135, 135, 136, 135, 136, 135, 120, 120, 119, 120, 102, 103, 119, 88, 118, 102, 118, 134, 135, 134, 119, 102, 119, 119, 103, 120, 136
        .byte   104, 104, 136, 135, 119, 135, 135, 135, 119, 136, 135, 135, 118, 104, 135, 87, 70, 136, 136, 103, 119, 119, 117, 120, 120, 88, 135, 135, 134, 119, 119, 119
        .byte   120, 120, 119, 135, 136, 135, 118, 134, 119, 119, 119, 120, 119, 119, 136, 120, 135, 134, 135, 136, 120, 103, 118, 119, 132, 119, 120, 102, 88, 117, 119, 137
        .byte   119, 134, 102, 135, 119, 88, 135, 134, 118, 119, 119, 119, 119, 103, 104, 119, 136, 119, 118, 136, 103, 119, 118, 102, 119, 120, 120, 119, 120, 136, 118, 119
        .byte   103, 120, 136, 135, 120, 136, 120, 119, 120, 104, 119, 119, 135, 120, 119, 104, 120, 120, 120, 120, 120, 120, 118, 118, 120, 135, 135, 102, 120, 120, 104, 103
        .byte   136, 120, 88, 134, 120, 135, 118, 103, 119, 119, 136, 120, 118, 120, 135, 119, 120, 103, 136, 120, 136, 136, 119, 136, 119, 135, 120, 136, 120, 120, 136, 136
        .byte   120, 119, 119, 102, 136, 135, 104, 104, 119, 135, 104, 120, 103, 134, 88, 119, 136, 119, 119, 119, 119, 103, 120, 135, 103, 135, 119, 136, 136, 136, 119, 120
        .byte   101, 103, 135, 120, 118, 135, 120, 119, 102, 104, 120, 119, 104, 119, 102, 104, 135, 104, 135, 135, 134, 118, 120, 87, 103, 119, 103, 119, 104, 136, 135, 118
        .byte   135, 136, 120, 136, 136, 135, 119, 119, 136, 120, 135, 118, 135, 119, 136, 136, 135, 120, 136, 120, 135, 119, 136, 103, 118, 136, 119, 136, 120, 102, 120, 135
        .byte   119, 119, 135, 119, 118, 119, 119, 120, 119, 135, 119, 118, 135, 135, 119, 135, 135, 104, 119, 104, 135, 120, 120, 119, 119, 120, 120, 136, 135, 119, 119, 136
        .byte   136, 136, 135, 120, 119, 120, 135, 135, 71, 117, 87, 119, 103, 118, 85, 135, 117, 134, 120, 118, 85, 119, 135, 135, 103, 118, 118, 119, 119, 87, 136, 118
        .byte   118, 118, 103, 119, 104, 119, 135, 104, 120, 119, 120, 120, 134, 103, 119, 119, 102, 117, 136, 135, 120, 119, 102, 87, 120, 136, 103, 118, 119, 135, 103, 119
        .byte   118, 119, 134, 135, 118, 103, 118, 118, 135, 134, 135, 118, 120, 104, 103, 103, 87, 119, 103, 119, 119, 119, 103, 119, 102, 119, 120, 119, 119, 103, 135, 135
        .byte   119, 135, 135, 103, 119, 135, 119, 135, 120, 119, 135, 103, 119, 87, 102, 119, 102, 103, 119, 102, 119, 136, 119, 119, 134, 103, 135, 86, 103, 135, 119, 87
        .byte   135, 119, 119, 119, 119, 120, 118, 118, 102, 102, 103, 119, 119, 120, 118, 120, 120, 135, 119, 119, 136, 120, 135, 135, 119, 119, 118, 119, 120, 119, 87, 103
        .byte   103, 119, 103, 103, 104, 120, 119, 120, 119, 119, 103, 135, 136, 135, 102, 135, 134, 118, 119, 120, 119, 136, 120, 119, 119, 135, 119, 135, 119, 120, 136, 135
        .byte   135, 136, 103, 136, 136, 136, 119, 119, 118, 135, 119, 118, 104, 103, 103, 119, 102, 120, 119, 119, 103, 135, 117, 103, 87, 118, 103, 104, 101, 119, 134, 103
        .byte   135, 118, 119, 118, 134, 135, 118, 103, 118, 119, 87, 119, 119, 87, 87, 119, 88, 87, 118, 120, 119, 117, 104, 132, 120, 133, 104, 136, 135, 103, 119, 119
        .byte   103, 104, 119, 120, 135, 120, 119, 135, 103, 118, 119, 119, 119, 119, 119, 119, 119, 118, 119, 120, 136, 119, 103, 135, 119, 119, 120, 119, 136, 135, 135, 134
        .byte   136, 120, 135, 134, 136, 134, 135, 136, 103, 120, 136, 135, 119, 120, 101, 134, 119, 119, 120, 118, 119, 118, 103, 119, 135, 120, 135, 102, 120, 120, 136, 134
        .byte   135, 135, 135, 104, 103, 102, 120, 136, 104, 134, 134, 118, 135, 119, 133, 134, 134, 117, 135, 103, 102, 103, 135, 104, 118, 102, 102, 103, 135, 86, 119, 86
        .byte   134, 119, 136, 135, 120, 135, 136, 120, 135, 104, 103, 134, 135, 119, 135, 119, 104, 134, 119, 120, 120, 119, 119, 119, 118, 119, 119, 119, 120, 119, 118, 119
        .byte   119, 103, 120, 103, 119, 118, 134, 135, 119, 120, 135, 120, 119, 120, 134, 119, 135, 102, 120, 102, 119, 135, 104, 103, 119, 119, 120, 120, 102, 151, 135, 136
        .byte   119, 135, 136, 136, 136, 120, 120, 136, 136, 136, 120, 120, 119, 119, 120, 120, 135, 119, 135, 136, 134, 135, 136, 135, 119, 136, 120, 119, 136, 135, 120, 117
        .byte   119, 118, 135, 118, 135, 120, 119, 134, 103, 134, 136, 103, 136, 119, 119, 135, 136, 135, 119, 119, 136, 103, 119, 136, 119, 135, 119, 119, 136, 135, 135, 120
        .byte   135, 136, 136, 119, 136, 136, 104, 120, 136, 119, 119, 103, 120, 119, 135, 135, 136, 117, 119, 118, 134, 134, 119, 120, 102, 120, 136, 103, 104, 136, 119, 136
        .byte   119, 119, 135, 119, 120, 119, 118, 104, 120, 119, 87, 103, 135, 120, 103, 119, 103, 120, 103, 120, 118, 120, 119, 103, 135, 135, 120, 119, 118, 119, 120, 120
        .byte   118, 119, 135, 118, 119, 119, 103, 119, 118, 119, 119, 103, 119, 120, 119, 135, 103, 119, 119, 121, 136, 135, 135, 134, 135, 135, 135, 119, 136, 135, 120, 135
        .byte   136, 119, 118, 135, 135, 136, 119, 118, 135, 120, 119, 135, 119, 135, 103, 135, 119, 103, 104, 118, 120, 134, 103, 120, 120, 120, 134, 117, 136, 118, 119, 134
        .byte   119, 119, 135, 135, 119, 118, 120, 119, 119, 135, 102, 119, 119, 119, 135, 120, 119, 119, 120, 136, 119, 135, 103, 135, 119, 119, 136, 119, 136, 119, 118, 119
        .byte   104, 104, 103, 118, 120, 118, 88, 120, 134, 104, 134, 120, 103, 134, 117, 136, 133, 135, 135, 102, 119, 119, 88, 116, 136, 119, 134, 87, 119, 120, 119, 135
        .byte   120, 119, 135, 120, 135, 135, 136, 104, 135, 102, 120, 119, 120, 119, 120, 135, 120, 135, 102, 120, 119, 104, 119, 135, 120, 135, 135, 119, 135, 119, 120, 119
        .byte   103, 135, 135, 120, 135, 118, 104, 135, 120, 119, 136, 136, 103, 136, 120, 104, 119, 136, 119, 119, 135, 119, 135, 136, 135, 88, 118, 133, 102, 132, 120, 119
        .byte   103, 118, 88, 119, 119, 136, 133, 134, 104, 87, 134, 134, 120, 104, 102, 102, 104, 136, 88, 104, 88, 104, 118, 87, 119, 72, 119, 87, 119, 117, 119, 101
        .byte   120, 133, 71, 135, 119, 104, 119, 104, 135, 119, 120, 117, 135, 134, 134, 119, 135, 118, 103, 103, 119, 87, 118, 117, 87, 132, 119, 119, 103, 117, 88, 135
        .byte   119, 120, 116, 103, 135, 118, 135, 118, 104, 117, 136, 120, 118, 134, 136, 135, 133, 118, 135, 135, 136, 119, 120, 135, 120, 118, 119, 119, 120, 119, 120, 104
        .byte   120, 134, 136, 135, 119, 117, 103, 119, 102, 119, 120, 135, 104, 134, 103, 135, 120, 87, 102, 120, 135, 135, 118, 104, 120, 119, 135, 102, 118, 118, 120, 103
        .byte   134, 135, 120, 118, 118, 135, 118, 119, 118, 119, 133, 135, 118, 118, 103, 120, 119, 104, 135, 119, 103, 135, 118, 135, 136, 119, 119, 135, 135, 119, 103, 119
        .byte   120, 119, 119, 120, 120, 119, 120, 103, 119, 119, 119, 119, 135, 135, 119, 119, 120, 136, 119, 120, 120, 118, 118, 120, 135, 120, 102, 136, 135, 103, 120, 120
        .byte   120, 119, 135, 120, 134, 120, 135, 119, 136, 119, 119, 87, 119, 103, 103, 118, 119, 119, 102, 119, 102, 103, 103, 135, 119, 119, 117, 103, 104, 120, 104, 135
        .byte   134, 87, 119, 119, 103, 119, 118, 103, 119, 135, 118, 119, 103, 118, 104, 135, 103, 134, 119, 119, 119, 103, 119, 135, 119, 134, 120, 118, 134, 120, 135, 103
        .byte   119, 120, 135, 103, 102, 117, 134, 104, 119, 103, 119, 103, 120, 119, 120, 87, 120, 102, 102, 103, 119, 102, 120, 119, 119, 103, 119, 135, 103, 136, 135, 119
        .byte   135, 119, 120, 119, 119, 103, 134, 119, 120, 119, 118, 118, 119, 119, 135, 120, 119, 135, 135, 135, 120, 135, 119, 120, 136, 120, 118, 136, 119, 136, 120, 120
        .byte   135, 118, 120, 86, 87, 118, 120, 87, 118, 119, 119, 85, 103, 100, 119, 102, 103, 119, 101, 87, 117, 119, 86, 102, 119, 71, 103, 118, 134, 117, 118, 118
        .byte   135, 135, 120, 104, 135, 119, 120, 119, 119, 118, 119, 103, 135, 136, 120, 134, 135, 119, 103, 133, 118, 120, 118, 118, 120, 134, 118, 119, 135, 119, 135, 120
        .byte   136, 119, 118, 119, 119, 120, 136, 136, 135, 118, 135, 120, 120, 136, 120, 119, 120, 120, 120, 120, 136, 136, 136, 135, 134, 136, 136, 135, 120, 118, 119, 135
        .byte   104, 118, 134, 119, 103, 118, 103, 136, 104, 119, 117, 134, 136, 103, 104, 103, 134, 118, 118, 103, 120, 118, 103, 136, 119, 88, 134, 119, 133, 151, 133, 116
        .byte   136, 136, 86, 120, 135, 118, 134, 135, 133, 135, 135, 119, 120, 136, 135, 135, 134, 119, 118, 120, 136, 119, 119, 120, 119, 120, 136, 119, 134, 119, 135, 118
        .byte   135, 135, 118, 120, 135, 120, 119, 120, 118, 133, 101, 120, 132, 135, 120, 135, 133, 119, 134, 134, 133, 135, 119, 119, 120, 120, 120, 119, 104, 135, 134, 119
        .byte   119, 135, 103, 136, 135, 135, 120, 119, 135, 134, 135, 134, 120, 104, 136, 119, 119, 135, 135, 104, 118, 119, 119, 102, 101, 118, 118, 87, 103, 118, 118, 119
        .byte   102, 119, 103, 119, 118, 135, 118, 119, 135, 118, 119, 104, 101, 119, 119, 102, 104, 119, 120, 136, 136, 120, 136, 136, 120, 136, 136, 120, 120, 120, 136, 136
        .byte   135, 134, 119, 134, 118, 118, 118, 135, 120, 120, 134, 120, 119, 118, 133, 103, 135, 135, 135, 135, 119, 119, 120, 135, 150, 120, 152, 152, 135, 120, 135, 119
        .byte   119, 136, 119, 120, 103, 135, 135, 120, 135, 104, 120, 120, 136, 135, 119, 104, 135, 135, 119, 119, 118, 120, 136, 135, 120, 119, 135, 134, 119, 136, 118, 103
        .byte   135, 103, 119, 103, 136, 118, 134, 88, 119, 119, 103, 120, 120, 120, 136, 104, 135, 135, 135, 120, 136, 136, 119, 120, 136, 120, 120, 119, 135, 119, 103, 136
        .byte   136, 104, 135, 104, 119, 86, 136, 135, 135, 103, 117, 120, 119, 102, 135, 118, 120, 119, 103, 136, 119, 134, 119, 119, 119, 119, 120, 119, 136, 119, 119, 119
        .byte   119, 119, 120, 135, 135, 136, 104, 103, 135, 119, 135, 119, 119, 119, 136, 135, 136, 118, 119, 120, 119, 103, 119, 135, 135, 135, 119, 119, 135, 119, 136, 135
        .byte   135, 118, 134, 136, 135, 135, 104, 118, 102, 120, 119, 103, 86, 120, 103, 88, 103, 119, 134, 118, 103, 103, 118, 104, 135, 102, 135, 120, 117, 135, 101, 103
        .byte   119, 119, 118, 119, 136, 120, 136, 135, 119, 135, 135, 135, 120, 136, 136, 120, 137, 135, 119, 134, 120, 136, 119, 119, 119, 120, 104, 120, 119, 136, 119, 120
        .byte   136, 119, 136, 120, 136, 136, 135, 135, 136, 136, 120, 136, 120, 135, 135, 135, 136, 119, 136, 135, 120, 135, 135, 120, 119, 119, 119, 119, 120, 102, 119, 135
        .byte   119, 136, 119, 119, 118, 135, 120, 135, 119, 136, 119, 135, 136, 152, 134, 119, 119, 118, 120, 120, 119, 120, 119, 118, 134, 119, 103, 135, 120, 103, 134, 134
        .byte   136, 118, 104, 118, 103, 134, 119, 103, 118, 102, 119, 87, 87, 135, 119, 135, 119, 119, 119, 119, 120, 135, 103, 134, 102, 136, 135, 120, 118, 133, 134, 118
        .byte   135, 118, 119, 119, 134, 134, 136, 119, 102, 135, 119, 118, 134, 120, 103, 120, 119, 134, 104, 119, 133, 118, 119, 119, 119, 136, 134, 119, 119, 119, 119, 119
        .byte   134, 120, 104, 118, 119, 118, 119, 119, 103, 103, 119, 119, 120, 118, 120, 120, 120, 135, 135, 120, 136, 119, 119, 119, 119, 116, 103, 103, 119, 102, 118, 135
        .byte   87, 87, 133, 119, 103, 104, 87, 88, 119, 102, 135, 134, 102, 134, 134, 86, 103, 118, 104, 119, 87, 102, 135, 119, 135, 134, 119, 135, 135, 136, 119, 120
        .byte   120, 136, 119, 103, 118, 103, 120, 135, 136, 104, 136, 120, 119, 135, 119, 119, 120, 120, 119, 136, 119, 135, 103, 120, 120, 119, 120, 120, 135, 118, 120, 120
        .byte   120, 103, 120, 119, 117, 119, 102, 103, 119, 118, 103, 119, 100, 103, 103, 85, 134, 119, 119, 135, 136, 103, 134, 135, 134, 120, 134, 135, 135, 119, 135, 119
        .byte   120, 135, 104, 119, 119, 119, 119, 119, 104, 135, 119, 120, 119, 118, 120, 103, 117, 119, 135, 136, 86, 117, 103, 118, 119, 104, 135, 103, 104, 71, 120, 117
        .byte   135, 119, 135, 117, 117, 119, 118, 119, 102, 136, 116, 118, 119, 118, 136, 135, 119, 135, 135, 135, 135, 135, 120, 119, 120, 118, 119, 118, 120, 119, 134, 120
        .byte   119, 136, 135, 135, 120, 136, 102, 119, 135, 119, 119, 119, 119, 136, 118, 102, 136, 135, 119, 118, 136, 119, 120, 119, 104, 119, 136, 103, 136, 135, 118, 119
        .byte   120, 118, 103, 135, 120, 120, 120, 104, 120, 136, 118, 135, 134, 103, 103, 117, 120, 119, 104, 119, 135, 118, 119, 135, 103, 104, 119, 134, 118, 134, 135, 134
        .byte   134, 120, 118, 101, 119, 119, 118, 119, 119, 134, 135, 118, 119, 118, 119, 119, 135, 119, 118, 119, 120, 119, 118, 119, 135, 120, 135, 136, 135, 119, 103, 134
        .byte   103, 135, 120, 136, 119, 119, 88, 119, 103, 135, 120, 119, 102, 120, 134, 119, 136, 136, 102, 102, 135, 118, 135, 136, 135, 103, 104, 102, 103, 119, 119, 118
        .byte   120, 119, 135, 103, 135, 120, 136, 120, 120, 135, 119, 135, 104, 104, 120, 120, 120, 120, 119, 119, 118, 117, 87, 103, 85, 87, 119, 103, 117, 102, 116, 135
        .byte   103, 87, 118, 119, 120, 119, 118, 119, 119, 104, 120, 120, 119, 135, 119, 136, 134, 86, 103, 119, 118, 118, 135, 102, 119, 119, 134, 118, 119, 119, 118, 120
        .byte   119, 135, 136, 103, 135, 120, 135, 134, 120, 134, 118, 136, 135, 119, 120, 118, 134, 119, 87, 135, 118, 103, 120, 104, 135, 119, 136, 119, 135, 135, 118, 136
        .byte   135, 118, 119, 103, 119, 118, 135, 134, 135, 134, 120, 120, 133, 103, 119, 103, 103, 104, 119, 117, 102, 118, 119, 119, 119, 103, 119, 119, 120, 136, 120, 119
        .byte   120, 136, 104, 136, 120, 119, 120, 136, 119, 119, 135, 103, 136, 135, 119, 136, 136, 135, 135, 119, 119, 103, 136, 120, 136, 120, 119, 136, 120, 136, 136, 135
        .byte   120, 119, 135, 135, 120, 119, 136, 120, 118, 120, 134, 119, 136, 135, 135, 135, 120, 136, 119, 136, 151, 136, 135, 136, 120, 136, 120, 120, 135, 120, 119, 119
        .byte   135, 136, 120, 135, 120, 136, 135, 135, 136, 136, 120, 120, 135, 120, 120, 136, 120, 120, 135, 136, 136, 136, 104, 136, 119, 136, 118, 136, 119, 136, 135, 135
        .byte   119, 135, 136, 119, 134, 119, 104, 119, 103, 118, 102, 118, 118, 103, 118, 119, 118, 119, 119, 135, 119, 87, 120, 135, 135, 120, 118, 103, 119, 136, 119, 119
        .byte   118, 120, 134, 119, 136, 136, 135, 104, 119, 104, 120, 119, 136, 136, 120, 119, 136, 118, 136, 135, 135, 136, 120, 119, 135, 120, 136, 134, 136, 119, 136, 135
        .byte   104, 118, 135, 136, 104, 119, 104, 135, 119, 136, 117, 135, 119, 118, 134, 136, 119, 119, 136, 136, 136, 119, 136, 136, 136, 135, 136, 135, 135, 136, 136, 119
        .byte   135, 118, 119, 118, 135, 118, 120, 135, 135, 135, 119, 135, 118, 119, 135, 120, 117, 135, 119, 134, 134, 104, 103, 119, 119, 119, 119, 119, 102, 120, 102, 103
        .byte   134, 119, 118, 135, 118, 119, 102, 102, 120, 119, 135, 87, 103, 135, 135, 119, 117, 103, 135, 120, 134, 119, 134, 119, 134, 136, 118, 119, 103, 120, 119, 119
        .byte   120, 104, 103, 135, 136, 134, 103, 133, 119, 102, 119, 103, 135, 119, 119, 118, 103, 120, 119, 103, 119, 119, 119, 119, 120, 102, 119, 135, 119, 135, 120, 119
        .byte   119, 136, 119, 135, 136, 120, 135, 119, 119, 120, 103, 120, 119, 103, 135, 135, 119, 120, 136, 134, 120, 136, 119, 134, 87, 120, 103, 119, 117, 103, 118, 103
        .byte   135, 119, 102, 102, 104, 119, 120, 134, 119, 136, 120, 119, 118, 119, 119, 119, 119, 103, 120, 119, 120, 134, 103, 135, 104, 119, 119, 119, 119, 136, 135, 136
        .byte   135, 119, 135, 135, 120, 135, 135, 120, 135, 135, 119, 136, 119, 120, 135, 119, 119, 103, 119, 87, 119, 120, 119, 120, 135, 119, 134, 135, 119, 102, 135, 104
        .byte   120, 104, 135, 120, 120, 120, 119, 119, 135, 118, 88, 136, 135, 103, 135, 136, 104, 103, 103, 120, 119, 119, 104, 103, 104, 119, 120, 119, 119, 117, 119, 118
        .byte   135, 120, 119, 135, 119, 120, 119, 120, 119, 119, 135, 120, 118, 135, 118, 136, 119, 118, 136, 120, 136, 119, 136, 119, 135, 119, 137, 136, 119, 135, 135, 151
        .byte   135, 135, 136, 136, 119, 136, 136, 119, 120, 136, 135, 135, 137, 136, 136, 135, 120, 119, 136, 135, 136, 135, 135, 135, 120, 151, 118, 119, 120, 136, 135, 136
        .byte   120, 120, 136, 136, 135, 120, 136, 120, 135, 135, 136, 134, 136, 135, 136, 118, 120, 119, 120, 135, 135, 135, 120, 134, 120, 119, 136, 135, 120, 136, 136, 135
        .byte   136, 136, 135, 120, 119, 136, 136, 136, 136, 135, 135, 119, 120, 136, 136, 151, 119, 135, 119, 136, 151, 119, 136, 134, 135, 102, 120, 136, 120, 104, 119, 119
        .byte   119, 136, 119, 103, 119, 104, 119, 120, 119, 119, 120, 136, 135, 120, 134, 104, 120, 120, 120, 136, 135, 119, 135, 135, 136, 103, 136, 120, 119, 135, 136, 135
        .byte   135, 120, 136, 119, 136, 104, 135, 104, 119, 120, 136, 120, 135, 120, 118, 136, 136, 134, 135, 136, 136, 103, 135, 136, 120, 136, 119, 120, 135, 135, 119, 119
        .byte   120, 120, 104, 120, 135, 135, 103, 119, 119, 104, 120, 135, 119, 135, 119, 102, 134, 119, 120, 103, 119, 135, 136, 135, 120, 136, 120, 120, 136, 120, 120, 136
        .byte   135, 120, 119, 103, 118, 119, 120, 117, 135, 135, 102, 119, 119, 118, 102, 135, 119, 119, 118, 103, 118, 87, 118, 118, 102, 102, 104, 87, 118, 86, 103, 134
        .byte   119, 134, 119, 136, 135, 119, 120, 120, 136, 136, 120, 119, 119, 104, 117, 117, 120, 118, 134, 134, 135, 103, 134, 104, 119, 134, 119, 135, 120, 134, 103, 136
        .byte   119, 119, 135, 119, 120, 135, 120, 119, 120, 135, 119, 136, 118, 136, 118, 119, 120, 135, 104, 136, 120, 119, 119, 119, 120, 119, 119, 135, 135, 135, 118, 119
        .byte   119, 134, 119, 134, 118, 136, 103, 119, 134, 119, 117, 103, 119, 119, 117, 119, 103, 118, 103, 119, 118, 119, 84, 103, 102, 117, 120, 135, 87, 119, 103, 118
        .byte   119, 120, 70, 135, 118, 87, 120, 103, 120, 136, 118, 120, 135, 135, 120, 135, 119, 135, 135, 118, 119, 135, 102, 134, 120, 135, 117, 119, 120, 104, 134, 134
        .byte   119, 134, 135, 120, 136, 134, 119, 120, 136, 119, 119, 120, 119, 135, 135, 120, 134, 119, 119, 135, 119, 120, 135, 119, 136, 119, 135, 136, 135, 120, 136, 136
        .byte   134, 136, 134, 136, 103, 136, 135, 103, 119, 119, 101, 135, 87, 118, 102, 119, 120, 118, 135, 100, 118, 119, 70, 119, 118, 103, 101, 102, 115, 116, 85, 103
        .byte   134, 101, 132, 102, 118, 100, 119, 135, 53, 104, 120, 86, 116, 87, 102, 86, 103, 118, 118, 119, 134, 135, 135, 117, 88, 136, 119, 119, 135, 135, 119, 135
        .byte   103, 118, 119, 103, 118, 103, 119, 88, 120, 119, 119, 135, 135, 135, 135, 119, 136, 118, 104, 119, 135, 103, 119, 88, 136, 87, 135, 136, 104, 119, 103, 119
        .byte   101, 135, 119, 118, 135, 134, 134, 135, 134, 118, 119, 120, 86, 118, 104, 119, 118, 119, 119, 119, 102, 104, 103, 104, 102, 88, 134, 119, 136, 87, 117, 87
        .byte   120, 119, 117, 71, 119, 119, 88, 119, 119, 87, 104, 119, 103, 119, 119, 103, 118, 119, 119, 119, 119, 102, 119, 86, 119, 119, 104, 119, 118, 135, 134, 119
        .byte   119, 135, 120, 135, 101, 135, 119, 134, 135, 119, 135, 120, 119, 118, 104, 135, 102, 119, 120, 119, 119, 102, 136, 103, 135, 136, 135, 120, 120, 151, 119, 119
        .byte   136, 120, 134, 135, 135, 120, 104, 119, 136, 120, 135, 120, 134, 135, 119, 135, 120, 135, 136, 119, 119, 104, 134, 103, 135, 118, 135, 135, 120, 119, 135, 103
        .byte   120, 120, 119, 103, 119, 136, 134, 119, 120, 119, 120, 119, 120, 118, 120, 135, 119, 119, 120, 120, 119, 120, 118, 103, 119, 119, 119, 102, 118, 119, 135, 119
        .byte   103, 119, 119, 135, 135, 119, 136, 119, 134, 136, 135, 136, 119, 135, 135, 120, 120, 136, 120, 120, 136, 118, 136, 120, 120, 119, 120, 135, 135, 136, 135, 135
        .byte   119, 87, 104, 71, 119, 119, 118, 118, 117, 118, 104, 136, 104, 120, 117, 119, 86, 119, 120, 104, 119, 120, 119, 101, 118, 118, 116, 119, 135, 119, 87, 87
        .byte   119, 118, 119, 119, 120, 103, 102, 120, 135, 118, 103, 118, 119, 103, 136, 118, 118, 119, 119, 119, 103, 118, 120, 118, 102, 119, 101, 118, 119, 119, 119, 136
        .byte   135, 103, 120, 120, 119, 119, 119, 102, 119, 119, 120, 120, 134, 136, 119, 135, 103, 119, 119, 120, 135, 120, 136, 118, 120, 120, 119, 102, 120, 118, 118, 119
        .byte   119, 119, 133, 103, 102, 118, 120, 103, 119, 101, 120, 120, 135, 119, 120, 119, 119, 135, 120, 103, 104, 119, 120, 135, 119, 103, 120, 119, 136, 120, 136, 120
        .byte   120, 135, 135, 119, 119, 136, 135, 135, 102, 136, 136, 119, 134, 120, 119, 86, 135, 120, 119, 104, 119, 119, 118, 104, 118, 119, 119, 103, 104, 119, 119, 103
        .byte   134, 119, 118, 86, 119, 135, 118, 119, 120, 119, 104, 119, 119, 87, 119, 120, 135, 134, 119, 134, 118, 135, 136, 119, 120, 136, 135, 119, 136, 120, 104, 136
        .byte   119, 119, 120, 120, 119, 120, 120, 136, 136, 135, 119, 136, 119, 120, 119, 120, 136, 136, 136, 104, 119, 119, 119, 120, 135, 120, 103, 118, 152, 120, 137, 136
        .byte   120, 135, 118, 119, 136, 102, 104, 103, 104, 118, 119, 119, 118, 104, 87, 119, 119, 136, 120, 136, 135, 136, 120, 135, 136, 136, 120, 136, 135, 136, 120, 136
        .byte   120, 119, 120, 136, 135, 120, 136, 135, 120, 135, 120, 103, 135, 135, 120, 135, 118, 120, 135, 120, 120, 120, 135, 103, 135, 120, 136, 135, 136, 118, 119, 136
        .byte   120, 136, 135, 119, 136, 136, 120, 135, 136, 136, 119, 103, 119, 120, 119, 136, 135, 136, 120, 119, 136, 136, 136, 136, 120, 136, 120, 152, 103, 119, 135, 119
        .byte   118, 120, 135, 120, 120, 135, 119, 120, 136, 135, 136, 136, 136, 136, 119, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 117, 117, 135, 104, 86, 119
        .byte   88, 119, 87, 120, 116, 119, 103, 120, 87, 119, 102, 120, 134, 102, 117, 118, 120, 102, 102, 134, 87, 134, 104, 103, 119, 119, 119, 119, 135, 119, 120, 119
        .byte   135, 118, 118, 103, 120, 120, 135, 102, 120, 119, 86, 119, 87, 87, 102, 136, 118, 117, 104, 102, 118, 104, 118, 135, 119, 120, 134, 134, 104, 102, 104, 119
        .byte   120, 87, 119, 120, 103, 103, 120, 120, 135, 136, 119, 103, 119, 120, 136, 120, 118, 120, 135, 120, 104, 102, 103, 118, 119, 118, 119, 119, 119, 134, 86, 134
        .byte   119, 135, 135, 135, 119, 120, 120, 120, 120, 119, 136, 136, 134, 104, 120, 134, 119, 135, 136, 119, 119, 136, 120, 136, 119, 135, 135, 136, 119, 135, 135, 120
        .byte   119, 136, 136, 135, 136, 136, 136, 136, 136, 120, 120, 120, 119, 136, 136, 120, 104, 136, 136, 119, 119, 120, 119, 120, 136, 135, 135, 119, 119, 135, 136, 120
        .byte   120, 119, 136, 135, 136, 136, 135, 119, 136, 136, 135, 135, 120, 119, 120, 136, 120, 119, 136, 120, 136, 136, 120, 119, 135, 134, 135, 120, 119, 137, 135, 119
        .byte   136, 120, 136, 136, 136, 120, 120, 136, 136, 136, 136, 136, 135, 120, 134, 120, 118, 120, 117, 103, 135, 135, 118, 134, 136, 103, 119, 104, 119, 120, 135, 119
        .byte   120, 119, 119, 118, 119, 103, 104, 120, 119, 120, 87, 135, 103, 119, 103, 103, 118, 119, 102, 119, 103, 119, 104, 119, 119, 103, 136, 119, 120, 136, 120, 119
        .byte   118, 134, 119, 133, 119, 136, 136, 103, 135, 135, 104, 136, 136, 135, 120, 119, 120, 120, 120, 103, 136, 119, 120, 120, 136, 136, 119, 119, 136, 135, 136, 136
        .byte   120, 136, 136, 120, 120, 136, 102, 118, 87, 118, 118, 102, 86, 103, 118, 102, 103, 87, 135, 119, 119, 118, 118, 135, 118, 134, 134, 117, 103, 119, 103, 103
        .byte   134, 118, 119, 102, 103, 134, 118, 120, 135, 118, 152, 119, 119, 135, 135, 135, 135, 118, 104, 136, 119, 119, 136, 135, 120, 136, 135, 135, 136, 135, 135, 136
        .byte   119, 118, 117, 136, 120, 103, 103, 119, 103, 118, 119, 119, 118, 136, 120, 119, 102, 135, 136, 135, 120, 135, 119, 136, 120, 120, 136, 136, 135, 120, 120, 136
        .byte   119, 119, 119, 119, 102, 119, 120, 135, 120, 134, 88, 103, 118, 135, 134, 135, 120, 136, 120, 120, 120, 120, 136, 136, 135, 135, 136, 120, 135, 120, 103, 135
        .byte   118, 135, 103, 103, 118, 136, 103, 118, 118, 136, 119, 120, 117, 136, 135, 135, 119, 136, 135, 135, 136, 136, 119, 120, 135, 119, 134, 120, 119, 102, 119, 103
        .byte   119, 134, 136, 118, 103, 119, 119, 88, 119, 134, 120, 103, 119, 87, 135, 135, 119, 102, 120, 134, 119, 120, 103, 135, 136, 120, 103, 136, 119, 136, 119, 136
        .byte   118, 136, 135, 104, 103, 135, 87, 120, 135, 120, 104, 120, 136, 151, 119, 136, 135, 120, 120, 136, 120, 120, 136, 119, 119, 120, 135, 135, 135, 120, 104, 119
        .byte   120, 120, 136, 105, 120, 120, 135, 119, 119, 120, 103, 119, 135, 103, 119, 119, 119, 104, 118, 118, 119, 136, 104, 120, 120, 104, 134, 88, 135, 103, 120, 119
        .byte   136, 136, 118, 102, 119, 119, 102, 103, 119, 119, 86, 119, 120, 119, 119, 119, 118, 135, 119, 103, 103, 120, 119, 119, 119, 120, 120, 103, 120, 119, 119, 104
        .byte   119, 120, 120, 103, 119, 88, 119, 120, 119, 104, 118, 136, 120, 103, 120, 135, 135, 104, 103, 120, 103, 119, 120, 119, 104, 86, 119, 119, 135, 103, 119, 133
        .byte   134, 136, 120, 119, 136, 135, 119, 136, 119, 136, 120, 136, 134, 135, 119, 135, 118, 135, 136, 119, 120, 119, 88, 120, 134, 103, 119, 103, 119, 104, 119, 87
        .byte   119, 119, 120, 119, 104, 118, 120, 120, 102, 120, 119, 102, 136, 136, 135, 136, 136, 119, 136, 136, 136, 136, 120, 103, 136, 135, 120, 135, 136, 135, 136, 120
        .byte   120, 120, 118, 120, 136, 136, 136, 136, 120, 135, 119, 120, 119, 119, 120, 120, 119, 119, 104, 136, 118, 119, 103, 120, 135, 119, 135, 136, 120, 136, 135, 120
        .byte   120, 135, 120, 135, 136, 135, 120, 136, 135, 135, 118, 119, 120, 119, 87, 120, 119, 119, 104, 102, 102, 120, 103, 135, 101, 135, 119, 119, 118, 119, 119, 119
        .byte   102, 135, 120, 119, 136, 118, 103, 135, 117, 103, 135, 117, 120, 117, 116, 87, 104, 103, 103, 118, 119, 119, 103, 117, 103, 120, 103, 87, 134, 103, 86, 103
        .byte   103, 103, 119, 118, 103, 116, 118, 120, 135, 119, 120, 120, 119, 120, 136, 119, 135, 136, 104, 136, 136, 120, 119, 120, 135, 119, 136, 135, 119, 134, 119, 135
        .byte   119, 136, 103, 119, 119, 104, 120, 135, 120, 135, 120, 120, 119, 135, 118, 104, 135, 119, 136, 135, 135, 119, 134, 135, 120, 118, 104, 136, 120, 136, 136, 119
        .byte   135, 136, 103, 103, 134, 118, 102, 103, 118, 102, 118, 87, 119, 103, 101, 102, 101, 133, 118, 119, 119, 102, 134, 120, 103, 135, 103, 119, 134, 120, 119, 134
        .byte   117, 102, 118, 103, 86, 118, 135, 103, 119, 119, 119, 104, 119, 103, 119, 119, 136, 119, 119, 103, 135, 118, 119, 119, 120, 104, 136, 119, 103, 119, 118, 104
        .byte   135, 135, 119, 119, 119, 119, 120, 120, 119, 134, 118, 134, 119, 103, 104, 119, 120, 118, 119, 120, 118, 135, 136, 119, 135, 119, 119, 119, 135, 135, 136, 119
        .byte   136, 120, 135, 135, 119, 118, 119, 136, 119, 120, 136, 104, 135, 118, 135, 88, 103, 119, 136, 119, 102, 103, 119, 102, 119, 118, 118, 102, 119, 118, 119, 135
        .byte   104, 119, 119, 119, 117, 104, 103, 102, 120, 102, 118, 119, 118, 119, 119, 135, 103, 118, 119, 119, 119, 119, 119, 119, 103, 119, 103, 103, 102, 102, 102, 86
        .byte   87, 103, 102, 103, 119, 86, 102, 87, 102, 119, 119, 135, 134, 103, 102, 119, 119, 119, 103, 119, 103, 135, 86, 103, 103, 117, 104, 134, 103, 102, 134, 136
        .byte   103, 119, 119, 119, 118, 119, 120, 119, 136, 119, 135, 135, 119, 136, 136, 119, 119, 136, 120, 136, 119, 102, 103, 102, 118, 104, 120, 118, 117, 103, 118, 118
        .byte   103, 117, 118, 134, 119, 117, 119, 134, 118, 134, 136, 88, 119, 134, 119, 119, 119, 118, 102, 133, 119, 118, 104, 118, 120, 87, 134, 119, 119, 88, 119, 136
        .byte   102, 102, 87, 88, 84, 119, 102, 119, 100, 115, 118, 103, 86, 102, 118, 116, 86, 119, 118, 103, 118, 102, 119, 102, 118, 120, 134, 118, 120, 103, 118, 134
        .byte   102, 103, 119, 118, 87, 118, 119, 103, 103, 103, 133, 102, 103, 103, 83, 71, 119, 116, 117, 133, 100, 71, 118, 102, 87, 135, 85, 102, 117, 119, 120, 119
        .byte   151, 136, 119, 135, 135, 135, 136, 120, 119, 136, 135, 120, 117, 136, 119, 103, 135, 118, 120, 135, 103, 136, 136, 135, 119, 120, 120, 118, 87, 119, 104, 119
        .byte   135, 120, 102, 120, 103, 104, 119, 87, 134, 120, 134, 120, 102, 135, 118, 135, 134, 120, 133, 136, 119, 149, 136, 119, 118, 86, 104, 118, 118, 134, 119, 134
        .byte   87, 135, 101, 103, 117, 103, 119, 103, 119, 119, 118, 119, 119, 134, 135, 119, 119, 135, 119, 136, 136, 119, 136, 87, 119, 118, 117, 120, 135, 134, 119, 135
        .byte   118, 102, 135, 136, 118, 135, 120, 103, 119, 103, 118, 119, 119, 119, 101, 120, 119, 119, 118, 134, 102, 119, 103, 134, 118, 134, 86, 135, 120, 120, 134, 102
        .byte   135, 134, 103, 119, 135, 119, 150, 118, 119, 102, 120, 103, 120, 120, 119, 119, 120, 119, 135, 119, 118, 104, 100, 136, 86, 87, 136, 118, 103, 119, 118, 117
        .byte   101, 120, 85, 135, 119, 134, 102, 118, 102, 103, 135, 118, 118, 118, 102, 103, 104, 102, 150, 103, 133, 119, 103, 118, 118, 104, 118, 88, 118, 120, 135, 103
        .byte   68, 120, 118, 117, 117, 103, 119, 85, 87, 119, 134, 85, 87, 150, 101, 118, 119, 135, 120, 134, 118, 118, 103, 103, 135, 135, 117, 135, 120, 119, 120, 103
        .byte   119, 135, 135, 103, 119, 119, 119, 104, 118, 119, 119, 104, 120, 119, 102, 102, 102, 119, 86, 119, 103, 119, 102, 86, 101, 104, 86, 102, 119, 119, 119, 119
        .byte   119, 104, 120, 104, 119, 135, 119, 103, 119, 119, 135, 118, 134, 119, 119, 135, 135, 120, 104, 119, 119, 104, 120, 120, 136, 120, 100, 102, 118, 86, 101, 101
        .byte   102, 87, 102, 87, 118, 85, 86, 118, 102, 120, 118, 103, 104, 119, 120, 119, 119, 118, 102, 87, 135, 119, 134, 102, 119, 102, 120, 118, 119, 103, 120, 119
        .byte   118, 135, 120, 118, 119, 120, 135, 134, 119, 118, 118, 118, 118, 119, 119, 86, 119, 118, 120, 136, 119, 118, 120, 136, 136, 119, 119, 119, 120, 119, 135, 120
        .byte   135, 135, 136, 135, 104, 118, 119, 135, 103, 134, 119, 119, 103, 103, 120, 119, 119, 119, 135, 119, 118, 120, 119, 101, 120, 119, 118, 102, 118, 118, 103, 135
        .byte   104, 119, 118, 120, 103, 136, 119, 119, 120, 119, 120, 103, 119, 135, 119, 119, 103, 103, 102, 120, 119, 117, 119, 102, 101, 103, 102, 119, 135, 118, 118, 102
        .byte   119, 135, 119, 119, 103, 119, 102, 119, 104, 120, 120, 120, 119, 136, 120, 103, 117, 102, 118, 119, 117, 116, 134, 102, 103, 117, 135, 117, 119, 120, 134, 119
        .byte   88, 135, 134, 119, 118, 119, 118, 119, 104, 104, 119, 120, 103, 119, 87, 135, 101, 116, 119, 133, 117, 119, 136, 117, 86, 135, 135, 101, 103, 134, 135, 119
        .byte   119, 135, 134, 119, 120, 120, 119, 134, 135, 120, 119, 120, 87, 102, 119, 104, 87, 86, 103, 103, 119, 102, 119, 102, 70, 87, 119, 103, 118, 101, 135, 120
        .byte   118, 118, 118, 102, 118, 136, 133, 119, 120, 118, 120, 119, 119, 118, 119, 119, 120, 135, 119, 104, 120, 119, 119, 119, 119, 118, 119, 102, 103, 135, 117, 118
        .byte   118, 103, 104, 136, 118, 87, 119, 104, 119, 118, 119, 120, 118, 102, 119, 118, 119, 119, 119, 118, 103, 102, 119, 119, 119, 120, 135, 104, 119, 135, 118, 119
        .byte   120, 119, 135, 119, 104, 119, 103, 119, 118, 119, 86, 103, 118, 102, 102, 102, 101, 117, 102, 119, 102, 102, 103, 117, 134, 136, 134, 119, 133, 103, 118, 118
        .byte   118, 103, 118, 118, 87, 119, 118, 117, 135, 134, 118, 135, 135, 118, 102, 136, 136, 118, 119, 136, 120, 119, 103, 135, 136, 119, 136, 118, 120, 103, 119, 135
        .byte   136, 118, 101, 120, 102, 102, 103, 119, 102, 103, 119, 118, 87, 87, 102, 119, 119, 135, 136, 119, 119, 119, 135, 136, 119, 136, 120, 119, 120, 120, 120, 136
        .byte   118, 120, 119, 101, 103, 118, 101, 103, 119, 119, 135, 119, 118, 86, 119, 118, 103, 118, 119, 118, 119, 118, 119, 134, 119, 118, 133, 135, 119, 119, 102, 119
        .byte   104, 117, 134, 119, 102, 103, 119, 135, 118, 120, 118, 118, 136, 119, 119, 119, 119, 120, 119, 120, 135, 103, 103, 134, 134, 103, 119, 103, 119, 119, 119, 119
        .byte   119, 119, 103, 119, 135, 119, 102, 120, 103, 135, 103, 120, 134, 120, 120, 135, 119, 134, 136, 135, 119, 119, 119, 120, 119, 119, 103, 135, 119, 136, 102, 87
        .byte   103, 119, 102, 118, 102, 136, 119, 119, 118, 101, 102, 119, 119, 102, 118, 119, 103, 119, 119, 118, 103, 119, 103, 103, 120, 118, 104, 135, 119, 120, 118, 136
        .byte   134, 117, 104, 119, 134, 102, 135, 120, 135, 119, 119, 135, 120, 119, 135, 104, 118, 135, 135, 119, 119, 119, 135, 119, 119, 119, 120, 135, 135, 136, 118, 119
        .byte   120, 119, 120, 120, 119, 103, 118, 118, 119, 118, 102, 120, 103, 119, 104, 117, 119, 103, 135, 103, 120, 118, 118, 136, 136, 119, 135, 119, 119, 135, 135, 136
        .byte   103, 135, 135, 104, 119, 119, 102, 101, 103, 86, 102, 101, 86, 103, 101, 117, 102, 116, 119, 119, 101, 102, 136, 118, 120, 120, 135, 118, 117, 119, 135, 118
        .byte   118, 135, 101, 86, 118, 135, 118, 136, 135, 134, 119, 119, 135, 103, 104, 134, 119, 70, 102, 133, 120, 133, 135, 87, 119, 135, 87, 119, 134, 119, 118, 134
        .byte   103, 85, 118, 119, 118, 104, 120, 118, 135, 134, 135, 134, 118, 135, 103, 118, 103, 102, 103, 87, 103, 119, 120, 103, 87, 134, 119, 119, 104, 134, 87, 119
        .byte   103, 136, 136, 135, 117, 120, 119, 119, 134, 104, 119, 136, 86, 136, 135, 136, 102, 101, 120, 120, 104, 134, 135, 118, 103, 136, 135, 87, 119, 119, 119, 119
        .byte   118, 103, 119, 104, 120, 119, 135, 102, 118, 136, 118, 135, 102, 102, 119, 87, 119, 119, 103, 118, 118, 118, 135, 103, 119, 99, 117, 119, 84, 119, 134, 134
        .byte   132, 118, 133, 101, 118, 70, 135, 118, 118, 88, 88, 100, 135, 118, 119, 100, 115, 103, 103, 86, 102, 135, 116, 118, 119, 85, 133, 102, 119, 87, 103, 116
        .byte   104, 119, 87, 119, 117, 101, 102, 133, 103, 118, 119, 119, 118, 119, 119, 103, 118, 135, 119, 120, 88, 118, 120, 133, 103, 134, 119, 119, 102, 120, 104, 134
        .byte   119, 88, 134, 135, 135, 104, 102, 103, 104, 87, 120, 103, 103, 119, 119, 118, 119, 103, 134, 99, 118, 117, 100, 87, 134, 71, 86, 102, 134, 116, 120, 118
        .byte   118, 133, 118, 133, 87, 100, 103, 102, 70, 103, 102, 86, 102, 103, 100, 99, 119, 86, 102, 104, 119, 102, 101, 104, 119, 88, 120, 120, 134, 102, 118, 135
        .byte   134, 136, 120, 136, 120, 136, 135, 136, 134, 119, 119, 119, 135, 135, 104, 118, 136, 120, 135, 120, 136, 136, 135, 136, 120, 136, 136, 120, 136, 120, 135, 134
        .byte   119, 119, 135, 135, 119, 134, 135, 118, 118, 119, 103, 119, 119, 103, 119, 135, 119, 104, 119, 119, 119, 103, 103, 103, 118, 103, 119, 118, 118, 103, 134, 119
        .byte   119, 119, 119, 103, 135, 120, 119, 135, 120, 118, 120, 103, 118, 118, 118, 102, 119, 136, 117, 103, 119, 119, 134, 103, 134, 119, 135, 119, 119, 118, 119, 119
        .byte   135, 135, 134, 135, 119, 134, 120, 135, 119, 119, 102, 103, 102, 135, 135, 120, 119, 102, 102, 118, 135, 117, 117, 103, 119, 120, 120, 135, 120, 104, 135, 119
        .byte   135, 119, 118, 135, 135, 119, 120, 119, 136, 119, 104, 103, 119, 119, 120, 135, 135, 121, 118, 120, 151, 120, 134, 133, 136, 119, 85, 101, 135, 119, 118, 133
        .byte   120, 132, 102, 120, 102, 134, 101, 102, 116, 86, 101, 103, 119, 117, 134, 136, 101, 101, 102, 119, 119, 119, 104, 118, 119, 119, 119, 135, 118, 119, 119, 118
        .byte   120, 135, 119, 104, 136, 118, 120, 119, 120, 120, 119, 119, 136, 119, 136, 120, 119, 118, 136, 120, 119, 119, 134, 119, 103, 119, 119, 118, 119, 119, 135, 134
        .byte   118, 118, 119, 103, 135, 102, 120, 119, 87, 119, 135, 102, 119, 134, 120, 118, 119, 118, 134, 119, 120, 119, 119, 118, 119, 135, 119, 119, 120, 135, 136, 103
        .byte   102, 118, 119, 119, 135, 118, 119, 119, 119, 119, 118, 119, 120, 135, 71, 118, 103, 117, 103, 134, 86, 135, 102, 119, 119, 119, 85, 118, 135, 119, 118, 103
        .byte   120, 134, 135, 119, 103, 119, 136, 135, 119, 120, 119, 135, 86, 119, 119, 103, 118, 102, 119, 85, 71, 118, 118, 88, 119, 103, 87, 119, 136, 120, 119, 136
        .byte   136, 136, 135, 119, 120, 135, 136, 120, 118, 135, 118, 136, 104, 136, 119, 135, 135, 119, 120, 135, 136, 103, 120, 119, 118, 119, 136, 118, 136, 135, 118, 136
        .byte   118, 120, 135, 119, 119, 120, 119, 135, 103, 119, 119, 118, 119, 136, 118, 120, 135, 135, 119, 135, 136, 119, 136, 135, 119, 120, 102, 120, 118, 119, 119, 119
        .byte   119, 104, 120, 119, 102, 136, 103, 119, 119, 135, 119, 118, 118, 119, 118, 119, 102, 119, 118, 103, 120, 118, 117, 135, 103, 104, 119, 103, 135, 102, 119, 118
        .byte   120, 104, 135, 119, 119, 119, 135, 136, 103, 136, 135, 120, 119, 119, 134, 120, 120, 120, 118, 119, 120, 135, 120, 135, 120, 135, 119, 119, 136, 134, 135, 120
        .byte   119, 120, 120, 120, 118, 104, 118, 119, 118, 102, 134, 120, 135, 134, 119, 133, 102, 137, 119, 119, 120, 135, 136, 135, 135, 134, 119, 104, 135, 120, 151, 118
        .byte   120, 104, 119, 136, 119, 103, 135, 104, 120, 135, 135, 119, 135, 120, 119, 119, 118, 120, 136, 135, 119, 136, 135, 120, 119, 135, 136, 119, 119, 136, 117, 118
        .byte   134, 118, 102, 117, 119, 103, 118, 119, 118, 102, 119, 104, 103, 119, 120, 135, 135, 134, 119, 120, 120, 104, 136, 119, 119, 136, 135, 136, 118, 119, 120, 136
        .byte   119, 135, 103, 136, 120, 136, 135, 119, 135, 136, 120, 102, 119, 135, 135, 119, 119, 135, 104, 103, 120, 119, 119, 120, 136, 119, 119, 118, 120, 119, 119, 135
        .byte   118, 119, 119, 135, 119, 135, 119, 118, 119, 102, 119, 135, 118, 135, 135, 103, 120, 119, 119, 119, 136, 119, 119, 120, 119, 119, 119, 103, 135, 135, 120, 103
        .byte   103, 136, 120, 120, 135, 134, 136, 103, 103, 119, 103, 120, 119, 119, 119, 103, 119, 119, 119, 103, 135, 118, 103, 134, 134, 118, 120, 133, 119, 118, 120, 103
        .byte   119, 119, 103, 118, 103, 135, 119, 119, 135, 120, 134, 119, 120, 118, 119, 119, 119, 119, 135, 104, 119, 117, 120, 133, 88, 135, 87, 119, 116, 103, 119, 87
        .byte   86, 118, 136, 119, 119, 135, 135, 119, 134, 134, 119, 118, 119, 135, 103, 120, 136, 118, 117, 119, 135, 103, 103, 118, 118, 119, 103, 103, 118, 119, 103, 119
        .byte   102, 120, 120, 119, 104, 119, 120, 120, 134, 102, 135, 119, 120, 134, 117, 119, 120, 103, 103, 119, 136, 120, 119, 120, 119, 134, 120, 119, 119, 136, 134, 118
        .byte   119, 101, 103, 134, 103, 119, 103, 120, 119, 119, 119, 86, 86, 120, 135, 118, 102, 119, 135, 135, 119, 119, 117, 118, 119, 118, 86, 119, 118, 103, 134, 120
        .byte   118, 117, 120, 136, 119, 134, 119, 119, 120, 134, 135, 117, 87, 121, 135, 103, 119, 104, 136, 102, 120, 119, 102, 119, 120, 135, 103, 118, 72, 119, 71, 104
        .byte   84, 118, 87, 104, 86, 87, 119, 116, 54, 119, 150, 70, 118, 83, 102, 116, 119, 85, 101, 118, 71, 119, 117, 103, 116, 118, 103, 86, 118, 103, 118, 118
        .byte   119, 119, 118, 87, 102, 103, 87, 104, 119, 135, 103, 118, 102, 86, 135, 118, 119, 103, 135, 118, 119, 117, 102, 134, 103, 120, 103, 87, 104, 103, 101, 120
        .byte   119, 103, 118, 103, 103, 118, 135, 136, 119, 103, 118, 118, 135, 104, 119, 119, 135, 119, 119, 136, 118, 118, 119, 119, 117, 103, 119, 104, 118, 118, 135, 102
        .byte   136, 119, 118, 118, 136, 119, 119, 119, 119, 119, 134, 119, 119, 118, 104, 118, 118, 87, 135, 117, 119, 120, 116, 118, 119, 117, 133, 119, 117, 87, 134, 86
        .byte   119, 119, 134, 119, 136, 119, 119, 119, 135, 119, 102, 135, 136, 120, 135, 135, 135, 102, 102, 119, 120, 87, 117, 116, 103, 101, 119, 119, 118, 119, 87, 118
        .byte   118, 119, 119, 103, 135, 102, 120, 135, 120, 119, 103, 120, 119, 118, 135, 135, 119, 103, 102, 104, 104, 103, 119, 119, 120, 120, 134, 134, 119, 121, 118, 119
        .byte   102, 101, 119, 103, 118, 118, 136, 118, 103, 119, 103, 102, 120, 103, 135, 120, 135, 103, 119, 119, 104, 135, 119, 119, 136, 120, 119, 135, 119, 136, 117, 103
        .byte   117, 101, 104, 119, 71, 119, 118, 103, 135, 102, 117, 133, 103, 117, 84, 116, 101, 134, 135, 104, 101, 102, 101, 103, 117, 118, 119, 118, 119, 134, 120, 119
        .byte   118, 103, 135, 133, 103, 120, 120, 120, 135, 135, 135, 119, 120, 135, 120, 119, 104, 135, 119, 120, 136, 136, 118, 136, 134, 120, 118, 118, 133, 103, 135, 135
        .byte   103, 103, 135, 104, 136, 118, 135, 134, 87, 117, 100, 101, 117, 134, 136, 103, 117, 102, 102, 119, 133, 118, 135, 119, 103, 118, 135, 119, 119, 120, 103, 121
        .byte   136, 136, 135, 118, 120, 104, 119, 136, 119, 119, 120, 119, 120, 118, 136, 119, 119, 119, 135, 136, 135, 133, 136, 134, 86, 101, 136, 119, 118, 133, 120, 132
        .byte   103, 120, 103, 119, 135, 119, 104, 101, 120, 88, 134, 135, 104, 87, 102, 120, 102, 104, 118, 133, 119, 117, 102, 134, 119, 118, 134, 86, 101, 103, 135, 118
        .byte   71, 135, 120, 135, 119, 102, 119, 135, 119, 104, 120, 118, 119, 105, 135, 119, 120, 103, 118, 135, 136, 120, 103, 118, 87, 119, 119, 118, 118, 104, 118, 117
        .byte   135, 119, 117, 103, 103, 70, 102, 102, 135, 101, 135, 134, 119, 117, 118, 135, 135, 119, 119, 118, 103, 119, 136, 135, 103, 135, 119, 102, 120, 101, 119, 119
        .byte   116, 87, 102, 87, 101, 117, 119, 117, 135, 118, 119, 101, 103, 102, 102, 87, 101, 86, 87, 119, 86, 135, 70, 118, 118, 103, 102, 69, 120, 119, 119, 86
        .byte   102, 87, 87, 118, 118, 119, 72, 102, 119, 102, 117, 70, 135, 85, 120, 135, 87, 86, 120, 103, 84, 118, 103, 119, 103, 98, 86, 103, 115, 116, 118, 83
        .byte   55, 118, 101, 103, 118, 68, 85, 133, 103, 119, 68, 115, 118, 117, 115, 87, 134, 99, 37, 118, 119, 85, 69, 70, 135, 118, 103, 102, 101, 101, 119, 103
        .byte   133, 85, 118, 103, 104, 103, 119, 88, 86, 103, 87, 70, 119, 102, 86, 118, 104, 101, 102, 102, 133, 119, 119, 135, 119, 119, 104, 121, 119, 120, 119, 104
        .byte   119, 104, 119, 136, 103, 119, 135, 119, 104, 135, 134, 119, 134, 119, 119, 119, 103, 118, 120, 119, 119, 135, 119, 103, 134, 119, 120, 119, 135, 118, 135, 120
        .byte   135, 135, 85, 120, 135, 118, 134, 118, 119, 102, 104, 135, 119, 102, 104, 135, 118, 119, 120, 119, 133, 135, 103, 120, 134, 118, 136, 119, 119, 119, 119, 118
        .byte   85, 119, 136, 102, 120, 119, 102, 119, 104, 104, 118, 120, 102, 103, 119, 119, 119, 104, 117, 136, 103, 103, 120, 135, 120, 136, 134, 134, 118, 120, 119, 119
        .byte   135, 103, 102, 119, 135, 119, 118, 119, 118, 134, 103, 135, 102, 104, 103, 119, 120, 133, 103, 135, 135, 120, 103, 117, 104, 135, 134, 119, 103, 102, 118, 103
        .byte   102, 103, 120, 103, 119, 119, 103, 103, 87, 118, 119, 102, 135, 104, 103, 87, 120, 102, 102, 117, 133, 133, 70, 119, 119, 86, 119, 119, 118, 103, 134, 134
        .byte   119, 86, 134, 117, 121, 86, 119, 120, 102, 118, 119, 86, 136, 103, 103, 136, 120, 120, 118, 104, 103, 120, 119, 103, 118, 72, 84, 87, 88, 117, 101, 88
        .byte   103, 102, 88, 135, 118, 88, 87, 134, 120, 135, 117, 103, 120, 102, 103, 135, 120, 119, 118, 120, 103, 120, 119, 119, 118, 101, 134, 118, 117, 102, 88, 134
        .byte   103, 119, 119, 86, 119, 87, 116, 87, 119, 119, 118, 119, 117, 87, 117, 86, 118, 87, 118, 119, 119, 119, 119, 103, 119, 119, 119, 120, 119, 118, 118, 136
        .byte   120, 119, 135, 103, 135, 119, 120, 119, 135, 119, 119, 118, 120, 135, 120, 102, 120, 134, 120, 102, 120, 134, 120, 135, 119, 103, 119, 135, 119, 119, 135, 136
        .byte   119, 135, 119, 135, 135, 119, 135, 103, 118, 103, 119, 135, 103, 136, 120, 88, 118, 103, 104, 119, 118, 134, 134, 119, 118, 119, 119, 134, 133, 103, 102, 119
        .byte   102, 103, 133, 120, 133, 118, 102, 135, 103, 103, 135, 102, 103, 133, 118, 119, 85, 119, 103, 119, 103, 102, 134, 135, 102, 119, 103, 104, 134, 118, 103, 103
        .byte   119, 87, 119, 134, 119, 134, 103, 103, 120, 103, 102, 120, 117, 103, 101, 134, 117, 119, 117, 70, 119, 103, 118, 87, 86, 86, 135, 118, 118, 135, 118, 102
        .byte   102, 87, 102, 103, 118, 118, 119, 85, 119, 117, 118, 102, 119, 104, 103, 135, 119, 118, 103, 119, 103, 136, 87, 135, 119, 135, 119, 135, 86, 119, 134, 103
        .byte   104, 86, 104, 103, 120, 119, 119, 119, 120, 86, 119, 117, 119, 100, 134, 134, 119, 103, 87, 119, 119, 103, 103, 102, 85, 118, 85, 118, 86, 103, 70, 103
        .byte   118, 86, 102, 120, 119, 118, 119, 119, 103, 87, 103, 88, 119, 120, 135, 118, 119, 118, 135, 119, 119, 101, 117, 101, 103, 133, 116, 103, 119, 103, 102, 118
        .byte   101, 119, 102, 119, 101, 135, 118, 135, 101, 136, 119, 70, 120, 86, 119, 87, 118, 134, 118, 119, 119, 103, 119, 104, 119, 120, 135, 119, 103, 119, 120, 103
        .byte   150, 118, 119, 135, 134, 120, 103, 103, 120, 135, 119, 134, 119, 119, 118, 119, 104, 133, 119, 134, 136, 102, 134, 119, 103, 134, 104, 119, 102, 119, 119, 86
        .byte   117, 119, 118, 103, 86, 118, 103, 102, 102, 103, 119, 103, 120, 103, 103, 120, 135, 117, 120, 119, 120, 120, 102, 104, 120, 103, 103, 119, 104, 103, 135, 120
        .byte   119, 118, 119, 119, 119, 117, 103, 104, 119, 102, 119, 118, 103, 120, 119, 119, 119, 136, 119, 119, 136, 102, 120, 135, 134, 119, 119, 119, 119, 135, 103, 119
        .byte   135, 119, 120, 136, 103, 135, 104, 119, 120, 136, 119, 118, 120, 135, 104, 119, 118, 103, 120, 88, 119, 119, 134, 118, 136, 117, 104, 102, 119, 134, 119, 133
        .byte   135, 118, 118, 135, 103, 120, 118, 87, 119, 104, 119, 118, 134, 118, 120, 118, 119, 134, 118, 85, 102, 120, 118, 119, 103, 119, 104, 87, 120, 104, 119, 102
        .byte   134, 133, 134, 119, 117, 132, 120, 132, 118, 118, 88, 117, 117, 119, 119, 86, 135, 120, 119, 85, 119, 134, 116, 118, 119, 134, 101, 102, 118, 88, 120, 119
        .byte   119, 87, 119, 103, 135, 102, 103, 119, 103, 102, 103, 118, 120, 117, 103, 118, 103, 86, 134, 102, 135, 120, 119, 118, 103, 119, 134, 135, 120, 133, 119, 104
        .byte   118, 88, 120, 119, 119, 119, 103, 119, 135, 119, 103, 119, 103, 119, 118, 118, 119, 134, 103, 119, 119, 120, 136, 119, 120, 118, 88, 136, 119, 104, 120, 136
        .byte   88, 117, 118, 135, 119, 116, 86, 119, 134, 87, 119, 119, 87, 85, 119, 119, 134, 88, 134, 119, 87, 103, 133, 103, 134, 119, 103, 118, 103, 102, 102, 117
        .byte   119, 134, 72, 119, 87, 103, 119, 119, 85, 117, 136, 135, 87, 119, 134, 117, 119, 120, 117, 103, 136, 133, 102, 119, 102, 102, 102, 134, 119, 119, 119, 102
        .byte   118, 103, 103, 102, 103, 119, 119, 103, 136, 119, 87, 118, 119, 119, 101, 71, 136, 118, 70, 87, 103, 119, 101, 118, 135, 85, 119, 103, 134, 87, 103, 119
        .byte   118, 119, 119, 102, 104, 118, 136, 119, 118, 103, 119, 102, 119, 103, 102, 118, 135, 118, 103, 136, 103, 136, 88, 119, 134, 103, 104, 103, 102, 119, 104, 102
        .byte   88, 118, 104, 119, 103, 118, 117, 120, 102, 102, 119, 102, 104, 118, 103, 102, 101, 119, 117, 103, 86, 120, 103, 117, 103, 135, 85, 103, 119, 134, 84, 118
        .byte   116, 117, 134, 87, 119, 118, 103, 120, 119, 135, 103, 136, 135, 119, 103, 120, 120, 119, 134, 119, 119, 102, 120, 135, 118, 119, 119, 118, 101, 120, 119, 103
        .byte   134, 119, 104, 102, 118, 103, 134, 118, 103, 103, 118, 103, 120, 103, 119, 101, 120, 120, 103, 120, 118, 103, 119, 134, 119, 103, 120, 103, 119, 103, 118, 135
        .byte   119, 119, 120, 100, 104, 104, 119, 103, 135, 119, 104, 87, 117, 119, 119, 119, 87, 134, 119, 119, 102, 119, 119, 132, 104, 135, 88, 119, 117, 120, 120, 87
        .byte   104, 119, 120, 119, 136, 118, 119, 103, 119, 119, 104, 102, 120, 104, 135, 102, 119, 136, 87, 118, 118, 119, 120, 104, 118, 119, 119, 118, 134, 134, 104, 119
        .byte   119, 118, 86, 103, 119, 118, 117, 118, 118, 86, 118, 119, 71, 103, 71, 85, 135, 119, 101, 119, 104, 133, 120, 135, 87, 118, 103, 104, 135, 120, 118, 119
        .byte   119, 134, 119, 120, 135, 134, 135, 119, 135, 120, 119, 135, 103, 118, 119, 119, 135, 119, 134, 119, 103, 119, 119, 104, 136, 120, 104, 118, 119, 136, 120, 136
        .byte   136, 119, 120, 135, 118, 119, 119, 134, 119, 104, 103, 118, 136, 103, 120, 103, 135, 119, 134, 117, 135, 103, 103, 119, 135, 135, 135, 119, 102, 119, 120, 104
        .byte   136, 120, 118, 120, 135, 118, 135, 120, 119, 119, 118, 104, 119, 135, 117, 119, 136, 104, 119, 118, 104, 103, 87, 119, 101, 120, 104, 104, 134, 102, 134, 119
        .byte   102, 136, 103, 120, 103, 119, 119, 135, 136, 119, 119, 118, 120, 135, 119, 118, 135, 119, 119, 119, 119, 135, 135, 135, 136, 135, 136, 136, 136, 120, 136, 136
        .byte   119, 136, 135, 120, 103, 135, 120, 136, 135, 119, 120, 137, 120, 121, 103, 135, 120, 120, 120, 120, 103, 120, 136, 136, 119, 120, 135, 135, 119, 120, 119, 135
        .byte   136, 120, 119, 136, 120, 120, 135, 135, 119, 120, 136, 119, 135, 119, 103, 118, 120, 119, 119, 119, 134, 119, 136, 118, 135, 136, 119, 135, 119, 135, 119, 119
        .byte   119, 103, 102, 118, 120, 118, 119, 134, 118, 119, 103, 103, 134, 118, 135, 119, 119, 135, 135, 120, 135, 104, 119, 135, 119, 119, 136, 119, 119, 119, 135, 103
        .byte   136, 119, 120, 120, 103, 135, 119, 135, 104, 103, 135, 119, 103, 102, 88, 119, 119, 135, 102, 103, 134, 102, 102, 103, 120, 134, 104, 119, 101, 118, 135, 103
        .byte   134, 119, 135, 134, 118, 119, 102, 104, 120, 119, 103, 117, 86, 88, 119, 88, 134, 135, 118, 100, 104, 117, 85, 119, 104, 104, 118, 86, 135, 87, 118, 88
        .byte   136, 134, 118, 103, 117, 86, 120, 118, 135, 103, 86, 135, 103, 101, 136, 119, 103, 136, 119, 118, 119, 119, 87, 118, 103, 119, 103, 118, 102, 119, 102, 120
        .byte   102, 102, 118, 87, 119, 118, 118, 119, 118, 102, 118, 119, 101, 104, 119, 102, 117, 120, 101, 102, 134, 119, 133, 117, 103, 101, 119, 87, 119, 133, 120, 116
        .byte   120, 102, 87, 135, 119, 119, 103, 135, 103, 120, 119, 118, 119, 118, 103, 104, 103, 119, 119, 118, 118, 86, 119, 119, 119, 119, 119, 118, 102, 119, 119, 103
        .byte   102, 118, 101, 103, 87, 118, 118, 119, 134, 102, 118, 119, 119, 104, 102, 118, 120, 117, 119, 103, 103, 103, 119, 119, 103, 102, 103, 119, 119, 103, 118, 102
        .byte   118, 135, 117, 119, 117, 119, 117, 104, 118, 119, 102, 118, 119, 102, 118, 102, 55, 102, 134, 71, 118, 131, 88, 100, 102, 71, 101, 70, 71, 119, 103, 87
        .byte   119, 87, 135, 119, 135, 101, 102, 103, 103, 118, 103, 118, 119, 102, 115, 103, 118, 116, 118, 136, 115, 84, 102, 116, 116, 87, 116, 102, 119, 119, 135, 119
        .byte   135, 119, 136, 119, 119, 119, 103, 118, 118, 135, 119, 119, 119, 119, 104, 119, 103, 136, 103, 135, 119, 118, 135, 103, 119, 120, 102, 118, 102, 102, 118, 87
        .byte   119, 119, 119, 102, 101, 117, 119, 104, 104, 119, 135, 86, 135, 119, 103, 135, 104, 119, 119, 103, 119, 119, 120, 103, 118, 117, 102, 134, 119, 134, 135, 102
        .byte   134, 119, 118, 119, 87, 134, 118, 134, 103, 118, 120, 135, 133, 119, 119, 103, 119, 135, 119, 135, 119, 134, 119, 119, 120, 119, 119, 119, 119, 104, 120, 135
        .byte   102, 135, 136, 119, 136, 119, 135, 118, 119, 104, 120, 119, 135, 120, 135, 119, 119, 135, 103, 103, 102, 118, 135, 103, 120, 120, 103, 118, 87, 103, 118, 118
        .byte   119, 134, 119, 118, 119, 118, 103, 119, 134, 120, 135, 119, 119, 119, 118, 119, 119, 118, 119, 118, 103, 136, 119, 118, 120, 119, 119, 102, 88, 118, 119, 88
        .byte   135, 135, 102, 87, 134, 119, 102, 120, 135, 136, 102, 135, 133, 135, 117, 104, 120, 88, 119, 119, 119, 120, 118, 136, 135, 104, 135, 103, 103, 119, 120, 135
        .byte   118, 103, 135, 119, 118, 88, 135, 104, 103, 119, 103, 103, 103, 103, 135, 136, 135, 102, 136, 119, 135, 135, 135, 119, 119, 135, 119, 136, 135, 120, 104, 135
        .byte   103, 102, 104, 134, 120, 103, 118, 135, 87, 119, 119, 119, 119, 85, 103, 104, 136, 102, 120, 120, 103, 119, 119, 103, 102, 118, 135, 120, 119, 135, 136, 135
        .byte   119, 120, 135, 104, 136, 135, 120, 136, 136, 103, 120, 135, 102, 135, 135, 136, 104, 119, 118, 135, 103, 119, 119, 135, 119, 119, 119, 136, 120, 135, 136, 135
        .byte   103, 120, 135, 118, 119, 120, 136, 119, 135, 120, 119, 135, 136, 119, 136, 136, 152, 135, 135, 136, 120, 135, 136, 136, 136, 135, 119, 118, 118, 136, 120, 120
        .byte   120, 119, 103, 120, 135, 135, 120, 118, 118, 104, 119, 119, 119, 87, 119, 119, 119, 119, 120, 118, 136, 119, 103, 134, 103, 118, 119, 119, 120, 118, 119, 117
        .byte   120, 119, 134, 119, 119, 120, 120, 119, 120, 135, 119, 136, 120, 104, 136, 120, 103, 135, 118, 118, 119, 104, 119, 118, 103, 135, 119, 119, 120, 103, 119, 119
        .byte   119, 103, 118, 85, 104, 135, 102, 117, 119, 118, 118, 135, 119, 102, 103, 103, 103, 118, 135, 120, 120, 104, 120, 119, 119, 134, 134, 133, 87, 119, 119, 103
        .byte   103, 119, 120, 119, 119, 104, 117, 119, 104, 102, 120, 120, 103, 135, 118, 118, 87, 120, 120, 117, 87, 120, 135, 88, 87, 120, 71, 87, 120, 119, 118, 119
        .byte   135, 119, 102, 103, 103, 119, 103, 119, 119, 119, 119, 104, 117, 135, 102, 120, 135, 118, 135, 88, 135, 119, 103, 119, 103, 119, 103, 103, 120, 120, 102, 119
        .byte   120, 103, 118, 103, 104, 134, 103, 118, 118, 86, 120, 135, 104, 103, 102, 103, 119, 135, 136, 118, 103, 120, 119, 118, 104, 118, 136, 119, 117, 120, 120, 120
        .byte   119, 103, 119, 103, 119, 104, 135, 120, 103, 135, 119, 134, 119, 135, 119, 85, 103, 103, 135, 134, 103, 135, 103, 119, 119, 104, 118, 119, 88, 103, 135, 120
        .byte   104, 119, 119, 120, 120, 136, 134, 135, 119, 102, 119, 101, 86, 104, 136, 120, 118, 102, 119, 119, 102, 119, 119, 118, 101, 119, 119, 118, 103, 119, 118, 135
        .byte   135, 119, 119, 119, 134, 119, 104, 119, 135, 119, 119, 136, 119, 119, 119, 119, 120, 120, 135, 136, 135, 120, 104, 119, 135, 120, 136, 120, 135, 103, 119, 119
        .byte   119, 136, 119, 103, 103, 102, 119, 135, 119, 87, 119, 119, 103, 86, 104, 101, 118, 119, 101, 86, 71, 103, 103, 86, 102, 118, 103, 102, 102, 117, 119, 102
        .byte   119, 116, 101, 70, 86, 103, 86, 119, 118, 87, 117, 101, 119, 102, 102, 103, 116, 134, 86, 101, 118, 102, 87, 119, 103, 102, 101, 102, 102, 119, 103, 86
        .byte   98, 103, 117, 115, 102, 119, 99, 67, 102, 115, 100, 70, 116, 85, 118, 116, 119, 119, 87, 103, 71, 103, 86, 119, 101, 118, 103, 103, 102, 102, 103, 83
        .byte   54, 119, 101, 40, 71, 55, 102, 52, 102, 118, 68, 85, 103, 119, 101, 118, 116, 118, 117, 103, 117, 102, 117, 117, 119, 101, 102, 102, 119, 136, 134, 119
        .byte   103, 101, 104, 119, 104, 118, 117, 120, 120, 103, 104, 119, 118, 135, 117, 103, 119, 119, 135, 134, 118, 104, 118, 103, 103, 136, 118, 119, 119, 118, 86, 120
        .byte   119, 119, 118, 120, 119, 118, 102, 134, 116, 86, 103, 103, 88, 102, 119, 102, 103, 118, 133, 118, 102, 134, 87, 118, 135, 118, 103, 119, 103, 104, 103, 135
        .byte   102, 87, 120, 119, 119, 103, 103, 151, 103, 135, 86, 119, 103, 103, 136, 117, 71, 120, 119, 134, 133, 116, 103, 133, 88, 86, 101, 118, 135, 104, 117, 101
        .byte   119, 117, 86, 134, 120, 119, 120, 119, 120, 103, 103, 135, 119, 102, 135, 119, 120, 119, 120, 120, 119, 103, 134, 119, 135, 119, 119, 135, 119, 135, 120, 103
        .byte   118, 136, 119, 120, 102, 117, 103, 118, 103, 103, 134, 104, 119, 103, 119, 118, 135, 102, 119, 102, 103, 119, 135, 104, 119, 135, 103, 102, 120, 86, 119, 120
        .byte   119, 102, 119, 120, 120, 134, 103, 103, 119, 135, 120, 119, 103, 120, 120, 118, 119, 103, 119, 136, 119, 135, 119, 119, 119, 136, 134, 103, 136, 135, 120, 136
        .byte   102, 119, 135, 104, 135, 119, 119, 120, 119, 120, 120, 136, 118, 135, 102, 119, 118, 120, 136, 118, 102, 135, 86, 135, 102, 104, 134, 117, 88, 134, 103, 119
        .byte   103, 120, 118, 118, 133, 135, 118, 120, 102, 104, 88, 135, 104, 103, 103, 87, 103, 117, 104, 116, 104, 104, 103, 119, 87, 135, 131, 102, 134, 72, 70, 100
        .byte   102, 134, 103, 100, 100, 134, 118, 69, 134, 116, 119, 118, 87, 118, 102, 135, 119, 119, 87, 135, 134, 87, 119, 118, 102, 118, 104, 119, 101, 87, 118, 118
        .byte   103, 87, 118, 87, 103, 116, 119, 102, 104, 104, 87, 119, 119, 119, 118, 134, 117, 117, 119, 117, 132, 120, 102, 120, 102, 118, 135, 119, 85, 136, 102, 102
        .byte   134, 104, 134, 102, 119, 103, 119, 102, 103, 133, 104, 118, 103, 118, 85, 134, 102, 103, 135, 134, 103, 102, 88, 120, 102, 103, 120, 119, 135, 119, 120, 102
        .byte   104, 134, 120, 133, 86, 120, 102, 87, 119, 133, 69, 119, 133, 118, 133, 103, 120, 117, 119, 103, 102, 104, 117, 119, 102, 87, 118, 119, 102, 118, 119, 118
        .byte   119, 118, 119, 119, 119, 134, 119, 119, 103, 118, 120, 118, 119, 103, 134, 119, 118, 103, 118, 103, 119, 119, 119, 102, 120, 103, 102, 134, 86, 103, 119, 120
        .byte   120, 135, 134, 119, 102, 120, 134, 119, 135, 103, 120, 120, 136, 135, 121, 134, 119, 120, 104, 104, 120, 136, 118, 120, 135, 119, 87, 119, 104, 103, 118, 135
        .byte   118, 103, 117, 135, 119, 118, 119, 103, 135, 119, 134, 119, 118, 88, 101, 104, 104, 133, 118, 103, 104, 119, 103, 119, 119, 103, 103, 118, 119, 120, 103, 119
        .byte   135, 119, 119, 102, 102, 103, 120, 86, 103, 87, 103, 135, 119, 136, 119, 119, 119, 119, 136, 119, 102, 136, 134, 120, 103, 135, 135, 104, 104, 120, 104, 136
        .byte   136, 135, 119, 136, 119, 135, 135, 120, 119, 135, 135, 135, 119, 119, 88, 119, 135, 103, 135, 102, 119, 103, 118, 120, 103, 117, 103, 120, 135, 133, 103, 104
        .byte   135, 104, 120, 119, 102, 120, 103, 118, 104, 102, 120, 119, 119, 134, 119, 118, 87, 135, 102, 149, 103, 101, 88, 118, 118, 102, 102, 118, 104, 133, 118, 102
        .byte   103, 102, 119, 102, 87, 120, 87, 103, 116, 103, 101, 102, 115, 103, 86, 120, 100, 119, 100, 116, 101, 119, 120, 85, 101, 118, 87, 118, 118, 102, 117, 135
        .byte   120, 117, 99, 102, 102, 86, 71, 85, 103, 118, 87, 118, 116, 102, 119, 135, 70, 135, 135, 135, 134, 134, 118, 119, 120, 135, 136, 118, 119, 119, 135, 120
        .byte   118, 134, 118, 118, 118, 119, 119, 103, 135, 118, 119, 135, 86, 119, 118, 103, 103, 86, 119, 119, 118, 119, 119, 118, 119, 118, 119, 120, 118, 118, 103, 134
        .byte   102, 119, 117, 70, 136, 103, 87, 136, 134, 87, 136, 102, 103, 116, 120, 118, 118, 117, 135, 134, 86, 118, 119, 119, 87, 103, 103, 119, 102, 103, 103, 87
        .byte   119, 70, 119, 87, 104, 88, 103, 118, 119, 87, 136, 116, 119, 120, 86, 136, 135, 104, 135, 119, 87, 102, 119, 87, 118, 120, 119, 119, 119, 119, 119, 135
        .byte   135, 120, 118, 119, 135, 118, 135, 120, 119, 104, 119, 104, 119, 136, 120, 135, 118, 135, 118, 119, 120, 119, 133, 135, 119, 87, 136, 118, 136, 118, 119, 135
        .byte   119, 119, 102, 119, 119, 135, 103, 118, 103, 134, 102, 119, 118, 134, 119, 88, 117, 101, 119, 136, 103, 102, 103, 119, 118, 119, 120, 117, 135, 120, 104, 120
        .byte   119, 103, 120, 120, 118, 119, 103, 119, 120, 119, 119, 120, 119, 120, 134, 104, 120, 120, 119, 118, 134, 119, 119, 103, 102, 119, 103, 119, 119, 118, 102, 120
        .byte   135, 118, 135, 120, 118, 120, 136, 103, 120, 120, 136, 119, 104, 119, 119, 135, 119, 104, 119, 120, 135, 136, 135, 119, 136, 119, 119, 136, 136, 120, 136, 120
        .byte   136, 117, 118, 119, 119, 102, 118, 103, 104, 102, 119, 133, 134, 119, 134, 118, 135, 118, 88, 119, 118, 103, 135, 118, 102, 119, 119, 119, 103, 118, 135, 118
        .byte   135, 103, 119, 103, 103, 104, 135, 119, 135, 103, 119, 103, 119, 119, 118, 103, 119, 119, 103, 102, 136, 120, 120, 103, 120, 135, 120, 119, 119, 119, 119, 119
        .byte   136, 120, 118, 120, 119, 103, 135, 119, 119, 103, 135, 135, 135, 119, 103, 119, 120, 119, 118, 119, 119, 118, 120, 103, 119, 103, 135, 102, 104, 103, 120, 135
        .byte   103, 119, 118, 119, 102, 135, 117, 119, 135, 118, 132, 103, 134, 87, 117, 117, 88, 119, 72, 118, 135, 119, 85, 102, 117, 119, 104, 118, 118, 103, 119, 118
        .byte   119, 103, 118, 88, 135, 104, 136, 119, 119, 102, 119, 135, 119, 119, 118, 103, 135, 119, 134, 119, 119, 118, 135, 119, 103, 118, 103, 119, 118, 119, 119, 119
        .byte   120, 118, 103, 119, 120, 119, 135, 116, 86, 119, 87, 101, 86, 119, 119, 85, 71, 136, 118, 87, 120, 103, 119, 87, 119, 120, 118, 102, 119, 119, 119, 104
        .byte   120, 118, 135, 119, 103, 119, 119, 104, 120, 136, 119, 118, 135, 120, 120, 119, 135, 119, 120, 118, 104, 118, 104, 87, 117, 119, 134, 88, 103, 103, 103, 104
        .byte   119, 135, 120, 135, 118, 119, 119, 118, 119, 119, 118, 119, 120, 135, 135, 119, 120, 119, 103, 87, 119, 119, 104, 134, 135, 119, 120, 135, 134, 135, 119, 136
        .byte   103, 87, 118, 87, 103, 103, 103, 103, 118, 103, 134, 103, 101, 133, 102, 119, 134, 119, 135, 119, 102, 86, 120, 104, 103, 119, 103, 119, 103, 120, 103, 119
        .byte   135, 134, 135, 119, 118, 120, 135, 103, 135, 120, 87, 135, 119, 104, 135, 103, 120, 119, 121, 135, 119, 119, 119, 120, 120, 120, 135, 118, 104, 118, 103, 119
        .byte   119, 119, 119, 118, 135, 118, 119, 136, 103, 101, 118, 103, 135, 103, 135, 119, 135, 118, 119, 133, 119, 135, 120, 103, 120, 104, 104, 135, 103, 104, 119, 87
        .byte   135, 103, 118, 104, 119, 103, 120, 119, 118, 135, 136, 136, 136, 136, 120, 120, 135, 119, 136, 136, 136, 135, 135, 135, 118, 103, 119, 87, 119, 119, 103, 119
        .byte   102, 103, 102, 119, 103, 135, 119, 119, 119, 119, 103, 102, 103, 118, 102, 118, 103, 119, 119, 118, 87, 119, 117, 103, 119, 118, 103, 135, 87, 103, 103, 119
        .byte   118, 120, 118, 120, 133, 115, 119, 118, 100, 86, 134, 116, 70, 119, 70, 101, 100, 103, 120, 55, 118, 102, 117, 102, 118, 118, 120, 102, 119, 103, 103, 102
        .byte   87, 118, 103, 135, 55, 86, 70, 118, 100, 119, 100, 70, 104, 102, 70, 101, 115, 135, 119, 87, 103, 135, 103, 118, 118, 119, 101, 120, 119, 103, 118, 88
        .byte   135, 102, 117, 118, 119, 119, 102, 103, 103, 103, 118, 118, 118, 102, 119, 119, 135, 120, 120, 120, 135, 119, 104, 120, 120, 136, 119, 118, 120, 120, 135, 120
        .byte   117, 87, 136, 118, 71, 120, 135, 88, 118, 135, 135, 101, 103, 135, 152, 103, 133, 103, 135, 103, 119, 102, 104, 119, 135, 103, 119, 118, 119, 134, 118, 119
        .byte   119, 101, 103, 120, 119, 118, 135, 118, 136, 118, 102, 135, 117, 119, 118, 102, 133, 101, 102, 136, 86, 87, 135, 100, 101, 102, 103, 87, 119, 136, 120, 134
        .byte   102, 135, 104, 136, 119, 134, 119, 119, 119, 120, 102, 134, 119, 135, 120, 118, 135, 135, 119, 119, 135, 136, 135, 119, 119, 136, 135, 119, 119, 135, 119, 119
        .byte   120, 120, 134, 119, 136, 118, 119, 119, 118, 118, 119, 119, 119, 119, 120, 119, 119, 135, 134, 118, 119, 119, 118, 116, 103, 135, 118, 86, 117, 86, 103, 103
        .byte   88, 119, 71, 119, 87, 119, 119, 116, 103, 118, 87, 117, 87, 119, 119, 86, 71, 120, 119, 87, 119, 120, 118, 103, 119, 119, 119, 119, 119, 135, 118, 119
        .byte   118, 135, 118, 119, 119, 104, 118, 119, 120, 119, 119, 119, 119, 135, 118, 120, 120, 120, 119, 118, 118, 118, 118, 118, 119, 120, 118, 120, 119, 119, 119, 87
        .byte   119, 104, 118, 119, 103, 135, 119, 118, 119, 120, 119, 118, 136, 119, 103, 119, 135, 103, 135, 102, 119, 136, 134, 118, 120, 135, 119, 87, 135, 120, 120, 104
        .byte   103, 132, 119, 135, 88, 136, 102, 119, 101, 104, 118, 103, 87, 120, 103, 102, 119, 118, 119, 118, 102, 136, 119, 103, 120, 119, 135, 119, 119, 119, 102, 119
        .byte   135, 119, 135, 119, 135, 135, 119, 104, 135, 135, 119, 120, 135, 134, 104, 119, 102, 102, 118, 119, 120, 119, 118, 87, 119, 135, 103, 134, 118, 103, 118, 101
        .byte   119, 118, 117, 103, 88, 116, 86, 119, 135, 102, 102, 120, 119, 120, 120, 104, 135, 135, 135, 135, 119, 119, 134, 103, 102, 120, 120, 136, 136, 135, 136, 119
        .byte   120, 136, 136, 119, 119, 136, 135, 136, 135, 136, 135, 136, 119, 135, 136, 119, 119, 119, 136, 119, 136, 120, 120, 136, 136, 102, 104, 119, 120, 88, 119, 134
        .byte   88, 104, 136, 102, 120, 119, 104, 120, 135, 120, 136, 119, 134, 136, 119, 135, 119, 135, 135, 136, 135, 135, 120, 118, 103, 134, 119, 103, 135, 134, 103, 134
        .byte   87, 119, 118, 135, 119, 103, 120, 119, 136, 119, 119, 134, 136, 118, 135, 119, 134, 120, 136, 119, 136, 119, 135, 120, 151, 120, 120, 136, 119, 119, 119, 120
        .byte   118, 120, 119, 135, 136, 135, 119, 136, 136, 120, 135, 135, 119, 135, 120, 119, 134, 118, 103, 135, 136, 119, 120, 120, 120, 119, 136, 136, 136, 136, 119, 136
        .byte   136, 120, 137, 136, 136, 136, 119, 135, 136, 136, 136, 136, 120, 136, 136, 119, 119, 119, 119, 135, 135, 119, 119, 136, 134, 119, 135, 120, 135, 104, 119, 103
        .byte   120, 119, 137, 134, 119, 151, 119, 103, 135, 151, 119, 135, 118, 135, 120, 103, 104, 119, 136, 104, 136, 119, 104, 119, 120, 119, 119, 135, 119, 120, 119, 102
        .byte   136, 119, 119, 119, 119, 119, 119, 119, 103, 103, 120, 119, 118, 119, 118, 119, 119, 119, 119, 135, 120, 136, 120, 119, 103, 135, 119, 86, 135, 135, 72, 119
        .byte   87, 120, 85, 120, 102, 101, 103, 136, 119, 71, 87, 118, 134, 120, 116, 87, 118, 85, 118, 119, 101, 119, 118, 119, 116, 119, 104, 119, 118, 135, 119, 119
        .byte   102, 119, 120, 119, 119, 119, 119, 118, 104, 103, 119, 103, 119, 119, 118, 119, 119, 119, 120, 119, 119, 103, 120, 118, 134, 87, 118, 118, 103, 119, 119, 103
        .byte   119, 119, 134, 119, 135, 119, 104, 119, 119, 104, 136, 136, 118, 120, 119, 117, 134, 136, 134, 134, 134, 135, 104, 136, 119, 135, 135, 135, 135, 136, 135, 118
        .byte   135, 120, 120, 119, 135, 135, 135, 136, 102, 119, 120, 136, 120, 151, 136, 135, 119, 136, 135, 104, 119, 118, 103, 120, 103, 119, 120, 120, 118, 119, 133, 134
        .byte   118, 103, 88, 119, 120, 105, 120, 103, 120, 104, 136, 119, 103, 135, 118, 103, 136, 135, 135, 119, 134, 119, 104, 119, 120, 119, 120, 135, 120, 136, 104, 119
        .byte   136, 136, 119, 119, 119, 119, 120, 136, 136, 136, 120, 136, 119, 136, 136, 88, 120, 103, 120, 118, 119, 119, 118, 134, 102, 135, 87, 119, 118, 135, 118, 120
        .byte   135, 120, 135, 135, 120, 135, 104, 136, 136, 136, 118, 135, 119, 116, 103, 135, 87, 133, 117, 119, 102, 136, 87, 103, 117, 88, 118, 119, 135, 119, 119, 135
        .byte   134, 119, 118, 136, 133, 120, 135, 134, 135, 119, 135, 118, 119, 119, 119, 134, 118, 119, 135, 119, 120, 118, 119, 119, 136, 119, 119, 120, 135, 119, 119, 119
        .byte   120, 120, 119, 120, 134, 136, 119, 119, 135, 135, 135, 104, 136, 102, 104, 135, 134, 119, 103, 119, 118, 119, 117, 119, 135, 120, 120, 136, 136, 136, 119, 120
        .byte   136, 120, 119, 119, 120, 135, 135, 104, 103, 103, 119, 120, 119, 119, 120, 117, 119, 136, 104, 119, 103, 134, 87, 104, 118, 120, 118, 87, 103, 103, 87, 119
        .byte   118, 102, 119, 103, 119, 119, 119, 135, 119, 120, 119, 120, 135, 120, 135, 136, 136, 151, 135, 120, 133, 118, 103, 86, 102, 102, 134, 119, 118, 118, 120, 134
        .byte   119, 119, 135, 134, 117, 118, 118, 103, 118, 103, 102, 118, 119, 119, 102, 118, 87, 117, 103, 120, 119, 120, 119, 118, 136, 135, 118, 120, 119, 120, 119, 119
        .byte   119, 120, 119, 119, 103, 88, 119, 120, 120, 119, 118, 102, 120, 119, 118, 118, 103, 88, 119, 88, 104, 118, 118, 103, 135, 119, 102, 135, 119, 103, 136, 103
        .byte   118, 101, 119, 103, 119, 118, 103, 119, 104, 118, 103, 87, 134, 103, 116, 118, 103, 86, 120, 135, 104, 119, 119, 87, 118, 119, 86, 117, 119, 102, 117, 87
        .byte   119, 70, 54, 134, 135, 85, 102, 102, 116, 104, 119, 72, 99, 135, 103, 133, 72, 119, 117, 87, 118, 102, 100, 118, 119, 104, 71, 86, 119, 102, 120, 101
        .byte   69, 136, 119, 87, 136, 134, 87, 136, 102, 119, 119, 118, 136, 120, 120, 133, 120, 136, 119, 134, 119, 134, 119, 120, 136, 136, 135, 120, 134, 135, 119, 120
        .byte   136, 135, 135, 136, 120, 118, 136, 136, 136, 118, 103, 119, 135, 87, 119, 135, 104, 135, 136, 135, 118, 119, 135, 134, 119, 120, 103, 120, 135, 119, 120, 118
        .byte   120, 119, 120, 120, 135, 119, 103, 136, 104, 119, 119, 136, 103, 118, 120, 104, 88, 105, 119, 135, 120, 103, 119, 120, 119, 118, 87, 119, 103, 119, 119, 102
        .byte   104, 136, 118, 120, 135, 136, 136, 135, 136, 136, 135, 135, 134, 136, 119, 135, 136, 136, 135, 119, 102, 120, 119, 119, 118, 135, 87, 119, 104, 136, 119, 118
        .byte   103, 134, 120, 104, 120, 120, 119, 135, 136, 120, 118, 119, 136, 120, 135, 119, 103, 120, 87, 87, 120, 102, 118, 118, 120, 100, 118, 136, 87, 134, 87, 135
        .byte   134, 135, 119, 120, 119, 135, 118, 135, 119, 119, 119, 119, 119, 120, 135, 134, 104, 119, 102, 134, 118, 119, 119, 119, 103, 87, 103, 103, 135, 104, 88, 120
        .byte   88, 119, 134, 120, 103, 101, 119, 104, 119, 87, 135, 132, 120, 104, 119, 118, 103, 103, 86, 120, 119, 118, 103, 102, 118, 103, 134, 87, 121, 135, 119, 135
        .byte   135, 119, 118, 120, 135, 135, 104, 119, 136, 120, 119, 135, 118, 119, 120, 135, 136, 135, 104, 118, 119, 120, 135, 135, 120, 135, 135, 119, 152, 119, 119, 120
        .byte   134, 136, 120, 119, 120, 119, 104, 136, 135, 104, 135, 102, 136, 119, 118, 119, 136, 101, 119, 120, 133, 120, 120, 102, 135, 120, 119, 135, 134, 103, 135, 136
        .byte   135, 120, 135, 118, 119, 119, 119, 120, 119, 136, 136, 135, 135, 136, 120, 135, 136, 119, 120, 136, 136, 120, 120, 118, 103, 119, 135, 118, 135, 103, 136, 102
        .byte   120, 133, 135, 133, 119, 120, 103, 103, 134, 136, 135, 136, 119, 119, 135, 119, 136, 119, 119, 119, 119, 103, 103, 119, 136, 135, 120, 120, 135, 120, 120, 136
        .byte   120, 136, 119, 134, 118, 136, 118, 117, 119, 120, 133, 102, 136, 134, 135, 87, 135, 119, 134, 134, 87, 119, 119, 104, 120, 135, 103, 134, 119, 135, 119, 136
        .byte   120, 102, 118, 119, 103, 87, 103, 102, 119, 136, 117, 102, 119, 103, 119, 119, 120, 136, 135, 135, 119, 119, 134, 119, 136, 119, 103, 135, 120, 120, 119, 120
        .byte   136, 135, 120, 119, 103, 120, 120, 119, 135, 103, 135, 135, 119, 135, 119, 120, 118, 87, 120, 102, 119, 120, 103, 118, 119, 118, 135, 119, 119, 119, 102, 119
        .byte   120, 135, 119, 119, 119, 119, 119, 119, 103, 120, 135, 104, 117, 119, 118, 102, 103, 118, 102, 120, 117, 103, 102, 118, 104, 103, 118, 101, 103, 119, 88, 103
        .byte   101, 135, 119, 104, 102, 118, 119, 118, 103, 119, 102, 118, 135, 119, 120, 119, 120, 119, 135, 118, 118, 135, 118, 118, 103, 118, 135, 102, 103, 119, 87, 88
        .byte   134, 119, 118, 102, 118, 120, 103, 120, 119, 120, 102, 119, 117, 103, 119, 119, 118, 135, 118, 119, 136, 134, 119, 134, 119, 117, 103, 120, 103, 87, 120, 119
        .byte   118, 116, 119, 120, 87, 120, 119, 119, 119, 118, 135, 120, 119, 119, 120, 120, 118, 135, 136, 135, 119, 103, 136, 102, 119, 118, 120, 102, 119, 120, 135, 87
        .byte   103, 118, 119, 104, 87, 119, 119, 119, 86, 71, 120, 120, 103, 120, 119, 103, 87, 135, 104, 135, 136, 119, 135, 135, 119, 120, 136, 136, 119, 120, 119, 136
        .byte   102, 120, 119, 119, 119, 119, 103, 135, 119, 118, 135, 119, 119, 120, 120, 118, 119, 103, 119, 103, 120, 118, 120, 118, 118, 133, 119, 119, 120, 119, 103, 104
        .byte   104, 103, 135, 103, 103, 102, 119, 88, 119, 119, 102, 135, 87, 135, 134, 119, 135, 136, 136, 119, 118, 136, 118, 120, 136, 119, 119, 103, 119, 120, 103, 103
        .byte   135, 102, 118, 86, 119, 120, 118, 119, 86, 135, 119, 118, 118, 104, 119, 120, 119, 120, 120, 119, 119, 102, 119, 119, 119, 119, 135, 103, 103, 120, 120, 119
        .byte   119, 120, 136, 119, 136, 120, 119, 119, 120, 119, 135, 103, 135, 118, 118, 118, 120, 119, 120, 104, 119, 134, 104, 119, 118, 135, 87, 135, 120, 103, 119, 104
        .byte   104, 103, 119, 120, 135, 135, 102, 135, 120, 135, 118, 119, 135, 118, 102, 118, 119, 119, 103, 119, 135, 102, 88, 104, 134, 103, 117, 103, 119, 135, 87, 104
        .byte   104, 102, 103, 119, 119, 118, 120, 116, 118, 119, 86, 119, 135, 103, 116, 119, 101, 117, 133, 101, 134, 117, 102, 118, 101, 134, 118, 118, 118, 103, 120, 103
        .byte   119, 119, 86, 134, 120, 103, 86, 103, 103, 87, 103, 118, 103, 118, 88, 119, 102, 104, 103, 104, 118, 119, 100, 103, 117, 101, 133, 118, 116, 135, 119, 117
        .byte   120, 119, 86, 119, 119, 118, 119, 119, 119, 119, 134, 104, 119, 104, 119, 119, 119, 119, 120, 103, 120, 134, 120, 135, 119, 134, 119, 119, 104, 119, 120, 103
        .byte   135, 103, 135, 120, 136, 136, 136, 119, 136, 120, 120, 119, 104, 136, 119, 119, 117, 119, 135, 134, 103, 103, 103, 104, 119, 103, 118, 119, 103, 103, 134, 103
        .byte   134, 118, 135, 119, 119, 120, 119, 104, 119, 120, 118, 120, 135, 135, 119, 120, 104, 120, 119, 103, 118, 119, 118, 135, 120, 119, 135, 118, 119, 119, 120, 120
        .byte   104, 120, 120, 136, 119, 120, 136, 119, 120, 136, 134, 136, 118, 119, 103, 103, 119, 102, 136, 120, 120, 119, 135, 119, 135, 103, 120, 120, 103, 102, 135, 119
        .byte   102, 135, 120, 118, 119, 135, 119, 136, 119, 120, 119, 119, 119, 136, 119, 136, 136, 136, 119, 103, 118, 120, 136, 135, 135, 118, 120, 133, 133, 119, 118, 118
        .byte   71, 119, 119, 119, 87, 135, 134, 87, 103, 135, 135, 119, 136, 119, 103, 119, 119, 119, 118, 120, 103, 119, 120, 119, 119, 135, 119, 102, 103, 120, 119, 135
        .byte   119, 119, 135, 135, 103, 119, 135, 103, 69, 118, 119, 88, 119, 119, 118, 120, 136, 103, 120, 88, 119, 103, 135, 118, 120, 117, 104, 135, 102, 134, 119, 102
        .byte   120, 119, 136, 117, 103, 88, 134, 102, 103, 118, 135, 118, 119, 103, 101, 102, 103, 134, 86, 118, 104, 119, 103, 101, 134, 135, 119, 119, 118, 117, 118, 103
        .byte   135, 102, 136, 118, 117, 88, 136, 118, 104, 104, 135, 119, 120, 117, 136, 118, 103, 134, 118, 120, 118, 87, 86, 72, 119, 103, 85, 102, 84, 119, 87, 86
        .byte   104, 118, 120, 116, 119, 118, 87, 118, 118, 103, 119, 119, 117, 101, 119, 102, 120, 86, 119, 120, 120, 118, 102, 103, 135, 119, 119, 121, 118, 135, 54, 103
        .byte   100, 71, 103, 70, 119, 68, 103, 102, 100, 86, 120, 102, 72, 103, 104, 119, 119, 102, 88, 117, 120, 119, 118, 133, 118, 118, 102, 119, 84, 103, 118, 70
        .byte   135, 119, 118, 117, 103, 116, 115, 118, 103, 134, 86, 118, 117, 135, 134, 103, 116, 88, 118, 135, 117, 118, 117, 103, 104, 118, 103, 119, 135, 103, 136, 103
        .byte   103, 119, 103, 118, 135, 117, 119, 135, 119, 71, 87, 119, 72, 118, 70, 103, 55, 118, 102, 135, 119, 101, 86, 133, 118, 86, 70, 102, 135, 87, 102, 119
        .byte   87, 103, 103, 117, 121, 118, 119, 119, 102, 118, 134, 118, 133, 102, 134, 118, 119, 118, 117, 104, 119, 103, 119, 135, 134, 120, 103, 119, 119, 120, 136, 120
        .byte   103, 136, 136, 103, 136, 118, 135, 119, 135, 119, 119, 120, 119, 136, 136, 135, 134, 119, 134, 119, 120, 118, 134, 104, 119, 136, 104, 134, 88, 135, 134, 119
        .byte   119, 118, 120, 104, 118, 119, 104, 119, 119, 103, 134, 88, 120, 104, 119, 104, 119, 136, 119, 120, 119, 103, 135, 119, 135, 102, 104, 119, 118, 118, 119, 135
        .byte   119, 88, 119, 118, 88, 103, 104, 102, 102, 104, 134, 120, 135, 102, 118, 119, 104, 117, 136, 117, 119, 118, 104, 135, 134, 118, 136, 120, 102, 102, 119, 87
        .byte   102, 120, 120, 117, 85, 120, 102, 71, 104, 135, 88, 103, 120, 134, 102, 119, 120, 102, 119, 117, 119, 119, 103, 119, 119, 119, 119, 119, 136, 136, 133, 135
        .byte   136, 88, 135, 87, 120, 102, 104, 118, 119, 104, 103, 134, 102, 119, 87, 119, 135, 119, 118, 103, 102, 135, 119, 118, 120, 119, 104, 54, 117, 119, 104, 116
        .byte   71, 116, 103, 102, 71, 116, 102, 70, 102, 103, 135, 119, 117, 119, 101, 85, 117, 104, 71, 102, 103, 86, 119, 103, 100, 120, 135, 118, 116, 135, 118, 101
        .byte   119, 119, 101, 87, 118, 135, 118, 119, 136, 118, 119, 135, 119, 120, 104, 119, 103, 87, 120, 104, 135, 102, 118, 119, 119, 118, 118, 119, 119, 120, 117, 119
        .byte   118, 103, 118, 118, 118, 118, 136, 88, 103, 136, 119, 118, 134, 119, 103, 120, 135, 103, 118, 118, 134, 120, 136, 118, 136, 119, 136, 135, 135, 103, 136, 135
        .byte   120, 135, 136, 103, 119, 120, 119, 135, 135, 120, 135, 135, 104, 135, 136, 118, 120, 120, 120, 87, 120, 103, 117, 120, 119, 103, 84, 119, 103, 88, 119, 119
        .byte   119, 85, 104, 120, 120, 119, 136, 135, 119, 134, 102, 119, 118, 136, 120, 136, 119, 102, 103, 120, 101, 103, 87, 117, 102, 120, 101, 70, 119, 102, 119, 119
        .byte   120, 103, 104, 103, 119, 103, 104, 102, 120, 119, 87, 119, 119, 136, 119, 119, 136, 135, 136, 135, 119, 135, 134, 119, 135, 118, 136, 119, 120, 118, 136, 120
        .byte   118, 135, 119, 119, 119, 136, 120, 135, 119, 119, 134, 119, 103, 101, 119, 117, 103, 103, 103, 101, 87, 120, 103, 104, 119, 102, 71, 119, 103, 103, 119, 104
        .byte   120, 119, 119, 102, 119, 119, 119, 118, 120, 135, 134, 120, 118, 120, 103, 135, 119, 119, 118, 119, 102, 120, 119, 118, 117, 118, 103, 119, 119, 102, 119, 120
        .byte   119, 120, 120, 119, 119, 135, 119, 120, 136, 117, 119, 134, 119, 118, 87, 134, 103, 134, 134, 103, 135, 102, 86, 119, 119, 119, 134, 118, 119, 119, 135, 103
        .byte   136, 119, 135, 119, 120, 119, 135, 119, 120, 103, 119, 135, 103, 118, 119, 104, 119, 120, 118, 135, 102, 119, 134, 135, 119, 136, 119, 120, 119, 119, 119, 119
        .byte   136, 118, 135, 102, 120, 135, 134, 120, 119, 119, 120, 120, 119, 103, 119, 119, 103, 119, 104, 104, 119, 120, 119, 104, 118, 119, 119, 118, 88, 119, 120, 101
        .byte   119, 118, 118, 103, 119, 136, 134, 119, 120, 135, 137, 120, 119, 150, 120, 104, 135, 120, 117, 135, 119, 102, 120, 120, 104, 136, 119, 104, 134, 136, 103, 119
        .byte   119, 103, 119, 135, 119, 135, 118, 136, 119, 120, 119, 120, 103, 119, 104, 119, 120, 118, 121, 102, 136, 102, 120, 119, 135, 103, 136, 119, 119, 87, 135, 88
        .byte   119, 136, 104, 119, 104, 103, 103, 119, 119, 135, 102, 136, 119, 119, 136, 134, 118, 119, 118, 136, 102, 120, 118, 136, 117, 118, 119, 103, 135, 103, 119, 118
        .byte   104, 118, 103, 102, 119, 103, 134, 117, 119, 135, 119, 134, 136, 120, 119, 119, 135, 103, 102, 120, 119, 104, 120, 117, 136, 134, 104, 120, 119, 119, 103, 135
        .byte   103, 103, 119, 87, 136, 104, 135, 134, 119, 118, 119, 120, 118, 119, 120, 120, 119, 119, 135, 118, 119, 104, 104, 119, 103, 119, 104, 136, 118, 136, 135, 120
        .byte   134, 118, 120, 118, 120, 120, 135, 119, 120, 135, 120, 136, 120, 136, 119, 136, 136, 119, 119, 134, 120, 135, 119, 134, 135, 119, 119, 119, 119, 119, 120, 136
        .byte   119, 136, 134, 120, 103, 119, 87, 135, 119, 117, 119, 136, 116, 103, 119, 85, 133, 119, 135, 117, 120, 103, 87, 119, 118, 103, 134, 118, 103, 118, 134, 88
        .byte   118, 102, 120, 103, 84, 102, 134, 135, 85, 116, 102, 88, 103, 120, 119, 88, 119, 87, 119, 102, 120, 134, 119, 119, 119, 103, 103, 137, 103, 117, 118, 120
        .byte   103, 134, 119, 119, 86, 134, 135, 102, 103, 119, 135, 135, 135, 118, 135, 103, 120, 119, 118, 102, 101, 87, 117, 85, 102, 118, 102, 87, 118, 103, 70, 119
        .byte   87, 134, 118, 136, 104, 103, 118, 120, 104, 118, 134, 120, 103, 120, 135, 86, 134, 134, 120, 87, 86, 119, 136, 120, 102, 119, 133, 70, 119, 103, 119, 101
        .byte   102, 118, 103, 134, 103, 103, 104, 102, 86, 136, 135, 102, 118, 117, 102, 118, 117, 103, 118, 133, 71, 119, 103, 118, 102, 120, 118, 104, 103, 119, 134, 120
        .byte   118, 119, 118, 119, 104, 102, 133, 118, 86, 134, 118, 87, 134, 119, 103, 87, 86, 135, 119, 119, 118, 119, 117, 70, 103, 103, 103, 118, 86, 118, 103, 103
        .byte   118, 117, 103, 120, 103, 119, 103, 103, 104, 119, 103, 119, 102, 119, 117, 103, 102, 87, 119, 119, 102, 119, 118, 102, 103, 103, 119, 119, 136, 119, 120, 119
        .byte   103, 119, 135, 118, 119, 135, 119, 135, 119, 135, 135, 120, 135, 136, 119, 135, 119, 120, 135, 119, 119, 135, 135, 119, 135, 119, 119, 118, 136, 102, 119, 135
        .byte   119, 135, 135, 119, 120, 136, 104, 135, 135, 151, 135, 119, 119, 104, 120, 134, 135, 119, 135, 135, 135, 103, 103, 118, 119, 119, 117, 104, 119, 120, 119, 134
        .byte   134, 117, 135, 135, 119, 118, 136, 134, 119, 103, 136, 120, 120, 135, 103, 135, 119, 120, 104, 134, 103, 119, 118, 88, 135, 118, 104, 103, 117, 135, 136, 119
        .byte   87, 104, 134, 118, 135, 104, 118, 120, 119, 119, 119, 135, 136, 120, 120, 134, 135, 87, 119, 119, 117, 135, 120, 103, 118, 120, 104, 135, 134, 120, 118, 133
        .byte   119, 135, 119, 102, 118, 136, 103, 136, 120, 120, 134, 136, 134, 118, 119, 119, 135, 135, 120, 136, 135, 118, 120, 119, 119, 120, 136, 119, 119, 120, 118, 120
        .byte   103, 103, 136, 104, 118, 87, 135, 103, 135, 104, 103, 120, 104, 118, 118, 120, 102, 119, 87, 118, 119, 117, 119, 134, 102, 119, 119, 103, 135, 118, 134, 119
        .byte   118, 103, 119, 120, 103, 119, 118, 119, 135, 119, 103, 135, 136, 119, 119, 103, 118, 119, 103, 120, 120, 118, 120, 136, 120, 135, 118, 118, 135, 118, 119, 135
        .byte   119, 119, 118, 103, 119, 119, 103, 118, 117, 116, 117, 104, 87, 86, 87, 103, 101, 118, 102, 132, 88, 118, 87, 119, 103, 120, 136, 135, 119, 120, 135, 119
        .byte   119, 118, 119, 120, 136, 120, 103, 103, 118, 102, 118, 118, 134, 86, 86, 103, 88, 103, 119, 118, 102, 118, 87, 102, 103, 119, 103, 118, 104, 120, 87, 135
        .byte   118, 102, 102, 136, 103, 118, 103, 103, 103, 118, 103, 135, 118, 102, 103, 119, 103, 86, 103, 103, 100, 87, 134, 87, 87, 118, 119, 87, 102, 86, 117, 88
        .byte   120, 72, 135, 118, 135, 119, 135, 135, 136, 136, 135, 119, 119, 135, 120, 136, 120, 136, 102, 120, 134, 120, 117, 134, 120, 135, 119, 103, 136, 119, 119, 120
        .byte   120, 101, 135, 104, 120, 134, 136, 86, 135, 118, 103, 134, 120, 136, 135, 136, 120, 103, 88, 136, 104, 135, 103, 136, 118, 136, 118, 135, 119, 135, 104, 120
        .byte   118, 119, 120, 103, 120, 103, 120, 119, 120, 103, 136, 120, 119, 103, 120, 118, 136, 135, 119, 120, 119, 136, 151, 136, 119, 119, 136, 120, 136, 104, 119, 134
        .byte   136, 119, 118, 120, 119, 135, 134, 135, 119, 134, 119, 104, 119, 119, 120, 120, 120, 120, 134, 134, 102, 119, 118, 120, 119, 101, 103, 119, 119, 119, 101, 104
        .byte   103, 119, 119, 102, 102, 88, 120, 102, 120, 103, 135, 103, 135, 136, 135, 119, 118, 135, 119, 119, 136, 118, 135, 104, 86, 135, 119, 101, 119, 135, 116, 118
        .byte   104, 85, 117, 119, 119, 117, 119, 119, 136, 135, 135, 135, 119, 118, 136, 119, 119, 104, 135, 104, 136, 136, 119, 120, 119, 135, 135, 120, 119, 103, 135, 120
        .byte   136, 120, 136, 104, 136, 119, 119, 119, 135, 136, 119, 119, 119, 104, 120, 136, 103, 135, 104, 119, 103, 118, 118, 119, 119, 103, 135, 136, 118, 118, 135, 119
        .byte   103, 119, 119, 85, 118, 118, 104, 133, 102, 119, 118, 103, 119, 134, 120, 69, 119, 135, 135, 102, 119, 119, 104, 134, 87, 87, 103, 104, 102, 119, 102, 104
        .byte   118, 134, 119, 103, 118, 118, 134, 118, 134, 118, 119, 119, 133, 119, 119, 119, 87, 120, 135, 135, 134, 104, 135, 119, 136, 119, 134, 135, 119, 104, 119, 87
        .byte   119, 117, 119, 101, 85, 119, 119, 70, 134, 116, 87, 119, 119, 117, 103, 119, 86, 117, 119, 102, 103, 119, 135, 135, 119, 118, 136, 102, 120, 134, 117, 134
        .byte   118, 103, 119, 103, 87, 102, 120, 118, 87, 120, 136, 104, 134, 102, 119, 103, 118, 103, 119, 87, 119, 119, 119, 102, 119, 120, 136, 120, 88, 120, 133, 136
        .byte   118, 119, 136, 119, 88, 104, 103, 103, 135, 119, 120, 151, 118, 116, 136, 118, 117, 119, 135, 117, 87, 119, 135, 118, 119, 102, 119, 88, 135, 119, 120, 103
        .byte   119, 119, 120, 103, 135, 119, 103, 120, 54, 87, 119, 136, 70, 71, 71, 72, 102, 104, 103, 71, 72, 104, 102, 119, 134, 119, 119, 87, 86, 88, 136, 103
        .byte   101, 119, 100, 118, 103, 87, 104, 119, 103, 120, 118, 103, 71, 118, 87, 119, 88, 117, 117, 134, 101, 120, 119, 102, 135, 104, 120, 117, 120, 135, 87, 104
        .byte   117, 119, 119, 72, 136, 102, 119, 103, 136, 104, 119, 117, 87, 103, 119, 135, 102, 87, 120, 119, 118, 103, 134, 136, 103, 103, 118, 88, 103, 119, 104, 135
        .byte   87, 119, 70, 102, 105, 132, 102, 120, 54, 134, 116, 103, 119, 71, 68, 136, 118, 104, 135, 119, 118, 119, 119, 87, 87, 119, 136, 119, 103, 134, 117, 120
        .byte   103, 136, 135, 119, 119, 135, 134, 118, 88, 119, 119, 104, 119, 119, 103, 119, 136, 119, 118, 135, 102, 103, 120, 103, 135, 136, 119, 135, 119, 135, 119, 120
        .byte   135, 119, 119, 119, 150, 119, 118, 119, 102, 120, 103, 120, 119, 119, 135, 118, 120, 119, 118, 104, 119, 135, 103, 135, 87, 104, 104, 135, 87, 117, 119, 120
        .byte   119, 102, 136, 102, 120, 103, 118, 135, 119, 104, 134, 120, 119, 119, 133, 119, 102, 103, 118, 118, 119, 102, 134, 120, 104, 134, 135, 119, 119, 135, 103, 120
        .byte   104, 119, 104, 120, 135, 119, 119, 119, 119, 87, 87, 103, 119, 118, 104, 102, 136, 118, 104, 136, 102, 102, 104, 119, 119, 119, 119, 120, 119, 102, 103, 120
        .byte   119, 120, 118, 135, 119, 119, 120, 85, 87, 120, 134, 118, 102, 134, 102, 118, 87, 102, 104, 119, 134, 117, 134, 134, 119, 120, 119, 119, 119, 118, 119, 119
        .byte   119, 104, 120, 120, 118, 103, 85, 104, 119, 102, 103, 118, 103, 103, 103, 101, 118, 104, 120, 88, 120, 103, 101, 102, 117, 117, 117, 120, 117, 103, 86, 116
        .byte   118, 118, 87, 103, 118, 101, 118, 118, 103, 119, 103, 102, 135, 118, 86, 120, 103, 103, 120, 103, 119, 103, 119, 102, 118, 102, 86, 119, 104, 103, 119, 102
        .byte   119, 101, 103, 119, 103, 117, 69, 135, 102, 103, 119, 103, 103, 117, 87, 119, 119, 120, 104, 119, 120, 102, 136, 119, 135, 135, 103, 119, 120, 119, 119, 135
        .byte   119, 120, 135, 136, 134, 120, 119, 136, 103, 119, 119, 135, 119, 120, 120, 135, 134, 119, 119, 119, 102, 103, 119, 118, 119, 119, 119, 87, 120, 120, 120, 118
        .byte   120, 119, 103, 134, 119, 118, 117, 102, 118, 135, 119, 118, 119, 120, 119, 120, 119, 119, 119, 135, 120, 134, 136, 103, 134, 120, 119, 102, 87, 120, 103, 102
        .byte   87, 134, 133, 134, 118, 102, 116, 87, 119, 119, 120, 119, 119, 119, 120, 136, 102, 120, 118, 119, 119, 120, 119, 120, 135, 119, 119, 120, 135, 120, 119, 120
        .byte   136, 135, 135, 118, 104, 104, 119, 120, 103, 135, 135, 135, 119, 134, 119, 119, 135, 120, 135, 119, 119, 120, 104, 104, 102, 119, 118, 103, 103, 118, 120, 119
        .byte   103, 119, 103, 87, 103, 119, 104, 103, 135, 120, 135, 118, 119, 136, 120, 135, 135, 120, 103, 136, 136, 119, 119, 119, 134, 120, 118, 134, 118, 120, 135, 103
        .byte   119, 120, 119, 136, 120, 104, 120, 104, 135, 119, 135, 119, 119, 119, 120, 119, 135, 104, 136, 102, 117, 134, 103, 69, 119, 100, 104, 115, 118, 117, 119, 135
        .byte   70, 104, 119, 151, 118, 103, 134, 119, 120, 118, 102, 135, 134, 120, 119, 133, 118, 136, 103, 119, 119, 135, 120, 118, 87, 136, 136, 119, 133, 136, 118, 120
        .byte   118, 70, 104, 118, 101, 103, 117, 132, 117, 119, 119, 99, 71, 120, 118, 119, 102, 119, 136, 119, 119, 119, 103, 103, 119, 119, 135, 117, 119, 102, 104, 134
        .byte   103, 104, 119, 103, 87, 135, 119, 101, 103, 102, 101, 103, 103, 119, 136, 118, 136, 118, 118, 134, 120, 103, 118, 120, 118, 117, 103, 87, 135, 118, 120, 104
        .byte   120, 119, 136, 119, 135, 134, 119, 134, 103, 136, 135, 118, 134, 120, 119, 134, 135, 120, 136, 135, 119, 119, 135, 119, 135, 135, 136, 103, 119, 119, 120, 135
        .byte   119, 119, 135, 119, 119, 119, 120, 104, 104, 104, 118, 134, 87, 134, 104, 86, 103, 119, 135, 118, 119, 135, 102, 134, 119, 104, 136, 118, 135, 119, 119, 119
        .byte   103, 134, 120, 120, 119, 119, 119, 104, 119, 135, 120, 119, 119, 103, 135, 119, 120, 118, 136, 136, 104, 120, 136, 118, 120, 120, 88, 119, 88, 119, 102, 119
        .byte   118, 136, 103, 120, 136, 118, 117, 116, 103, 118, 117, 119, 101, 87, 119, 119, 117, 70, 134, 87, 117, 118, 133, 101, 102, 119, 103, 101, 135, 118, 102, 135
        .byte   70, 102, 119, 71, 120, 119, 120, 116, 87, 119, 85, 118, 103, 101, 119, 118, 119, 116, 37, 119, 117, 55, 87, 55, 119, 51, 88, 85, 83, 85, 119, 101
        .byte   55, 118, 87, 103, 71, 119, 69, 136, 101, 103, 70, 104, 101, 101, 54, 103, 119, 88, 102, 131, 103, 101, 103, 100, 100, 134, 87, 102, 102, 135, 116, 85
        .byte   119, 70, 102, 118, 119, 101, 118, 117, 118, 102, 117, 104, 119, 104, 134, 119, 118, 86, 119, 118, 120, 135, 118, 133, 135, 119, 101, 116, 120, 135, 119, 119
        .byte   119, 119, 119, 136, 120, 102, 120, 135, 120, 103, 134, 120, 119, 120, 120, 135, 136, 134, 104, 119, 119, 119, 136, 120, 103, 120, 136, 119, 119, 119, 119, 118
        .byte   118, 136, 118, 119, 119, 136, 119, 118, 118, 118, 119, 119, 103, 103, 120, 119, 104, 119, 120, 102, 119, 135, 135, 104, 134, 118, 117, 119, 103, 119, 104, 87
        .byte   118, 70, 120, 133, 118, 135, 118, 118, 120, 135, 117, 135, 134, 103, 118, 103, 135, 134, 118, 120, 119, 102, 119, 87, 103, 118, 118, 134, 103, 103, 103, 151
        .byte   135, 118, 103, 119, 119, 136, 87, 71, 119, 86, 103, 102, 103, 85, 103, 103, 86, 101, 87, 119, 118, 88, 88, 135, 134, 118, 102, 103, 103, 135, 120, 102
        .byte   103, 120, 120, 135, 103, 119, 118, 102, 119, 118, 118, 120, 134, 133, 102, 119, 134, 119, 102, 118, 120, 117, 71, 133, 87, 134, 86, 135, 117, 118, 101, 120
        .byte   117, 117, 118, 119, 120, 118, 119, 135, 119, 102, 134, 118, 135, 104, 119, 135, 117, 135, 103, 120, 102, 88, 104, 120, 101, 102, 103, 104, 119, 102, 119, 117
        .byte   119, 135, 103, 135, 103, 134, 120, 120, 135, 120, 120, 135, 136, 103, 119, 119, 117, 135, 119, 134, 118, 136, 103, 118, 87, 134, 102, 119, 102, 104, 118, 119
        .byte   119, 119, 119, 119, 135, 119, 104, 136, 118, 135, 120, 135, 135, 135, 136, 118, 135, 120, 136, 118, 120, 119, 120, 119, 135, 135, 118, 136, 133, 135, 135, 118
        .byte   104, 120, 118, 104, 119, 102, 118, 120, 119, 104, 103, 136, 136, 119, 120, 103, 103, 135, 120, 119, 104, 120, 119, 120, 119, 104, 120, 119, 136, 136, 136, 135
        .byte   136, 136, 135, 119, 119, 136, 136, 136, 120, 104, 119, 119, 136, 119, 119, 119, 102, 135, 120, 118, 120, 118, 103, 119, 87, 87, 119, 104, 119, 103, 104, 71
        .byte   119, 119, 134, 103, 101, 119, 117, 118, 118, 103, 135, 118, 119, 117, 119, 102, 103, 117, 118, 86, 118, 104, 119, 119, 103, 119, 120, 119, 118, 119, 120, 102
        .byte   119, 119, 103, 119, 119, 103, 103, 102, 104, 117, 102, 134, 88, 88, 101, 118, 104, 118, 118, 118, 118, 119, 118, 102, 119, 102, 102, 86, 119, 118, 102, 103
        .byte   135, 119, 88, 102, 102, 133, 85, 119, 117, 117, 71, 102, 86, 103, 102, 103, 133, 103, 119, 119, 101, 120, 135, 119, 118, 103, 120, 119, 119, 103, 102, 103
        .byte   119, 118, 119, 118, 103, 119, 119, 103, 119, 104, 119, 119, 119, 103, 119, 118, 119, 136, 135, 87, 120, 119, 134, 118, 120, 103, 103, 119, 136, 119, 88, 120
        .byte   120, 134, 119, 133, 119, 118, 118, 134, 119, 103, 119, 118, 135, 133, 119, 72, 119, 133, 120, 117, 102, 87, 119, 119, 87, 135, 117, 102, 117, 135, 72, 135
        .byte   87, 120, 117, 119, 87, 119, 119, 88, 120, 133, 86, 120, 134, 119, 103, 119, 119, 135, 136, 118, 120, 118, 119, 135, 119, 135, 119, 87, 117, 71, 118, 136
        .byte   120, 135, 117, 103, 116, 87, 117, 103, 117, 101, 119, 102, 103, 119, 119, 118, 104, 120, 104, 104, 119, 119, 103, 118, 135, 101, 135, 119, 118, 120, 119, 134
        .byte   103, 104, 104, 135, 134, 119, 120, 87, 120, 135, 119, 136, 119, 119, 118, 135, 103, 135, 119, 135, 119, 119, 118, 119, 87, 119, 103, 136, 134, 134, 118, 103
        .byte   119, 135, 104, 119, 117, 134, 103, 119, 119, 103, 119, 119, 135, 118, 118, 135, 118, 119, 119, 119, 102, 86, 87, 118, 85, 120, 136, 118, 84, 119, 103, 71
        .byte   103, 120, 135, 85, 119, 103, 120, 103, 119, 120, 135, 103, 119, 102, 103, 102, 120, 119, 118, 119, 117, 104, 135, 120, 104, 117, 136, 103, 103, 134, 134, 118
        .byte   135, 103, 136, 119, 134, 134, 119, 119, 103, 103, 102, 118, 103, 87, 136, 119, 102, 119, 134, 118, 119, 136, 135, 136, 135, 119, 136, 136, 120, 119, 120, 135
        .byte   119, 118, 120, 103, 120, 119, 119, 135, 103, 102, 119, 134, 119, 120, 119, 119, 120, 119, 102, 135, 119, 88, 120, 135, 118, 135, 120, 134, 118, 135, 120, 119
        .byte   120, 119, 118, 120, 119, 120, 120, 135, 119, 119, 135, 120, 134, 119, 133, 102, 119, 119, 118, 102, 119, 119, 117, 119, 102, 102, 119, 119, 101, 119, 118, 118
        .byte   103, 134, 119, 118, 135, 119, 103, 118, 103, 119, 88, 119, 135, 120, 120, 103, 119, 119, 134, 104, 118, 118, 120, 135, 135, 119, 119, 135, 133, 120, 134, 134
        .byte   120, 118, 103, 119, 118, 119, 136, 134, 102, 135, 119, 119, 135, 119, 136, 134, 103, 119, 120, 134, 135, 118, 104, 135, 120, 119, 135, 103, 119, 135, 104, 135
        .byte   118, 103, 135, 135, 118, 135, 118, 135, 133, 135, 134, 134, 102, 118, 119, 134, 133, 119, 117, 102, 118, 119, 118, 119, 103, 103, 119, 120, 119, 103, 119, 119
        .byte   118, 119, 120, 119, 119, 119, 103, 120, 119, 119, 120, 118, 103, 119, 135, 119, 134, 119, 120, 118, 101, 135, 136, 118, 104, 104, 103, 104, 120, 119, 118, 120
        .byte   119, 120, 134, 119, 120, 135, 136, 135, 120, 135, 136, 119, 136, 136, 136, 119, 136, 120, 135, 135, 120, 135, 120, 136, 119, 136, 134, 120, 103, 120, 136, 120
        .byte   120, 134, 119, 119, 119, 118, 136, 119, 119, 120, 119, 103, 118, 119, 134, 120, 135, 136, 136, 119, 136, 120, 120, 120, 136, 120, 136, 120, 136, 135, 119, 88
        .byte   119, 119, 136, 135, 135, 134, 135, 119, 118, 134, 135, 119, 119, 119, 118, 119, 103, 136, 119, 103, 120, 103, 119, 120, 118, 103, 119, 120, 119, 119, 120, 119
        .byte   134, 134, 135, 119, 118, 120, 135, 120, 118, 119, 135, 120, 135, 136, 119, 119, 136, 136, 120, 103, 136, 135, 120, 135, 120, 135, 120, 136, 135, 119, 120, 104
        .byte   136, 119, 120, 135, 134, 120, 121, 135, 135, 119, 135, 135, 133, 102, 119, 118, 118, 103, 102, 118, 118, 102, 120, 118, 117, 120, 134, 133, 104, 118, 134, 136
        .byte   119, 103, 135, 118, 119, 120, 134, 118, 103, 104, 103, 104, 103, 103, 120, 136, 135, 103, 120, 104, 87, 120, 135, 104, 103, 118, 103, 104, 119, 102, 119, 120
        .byte   87, 103, 104, 87, 135, 104, 134, 104, 118, 119, 135, 134, 136, 119, 120, 120, 104, 119, 119, 119, 120, 134, 103, 136, 119, 118, 119, 135, 119, 119, 136, 120
        .byte   119, 118, 119, 119, 120, 119, 119, 119, 119, 120, 120, 135, 134, 103, 118, 120, 119, 120, 119, 136, 118, 120, 137, 136, 120, 120, 136, 119, 120, 135, 136, 136
        .byte   135, 136, 119, 136, 119, 136, 120, 136, 119, 119, 135, 119, 119, 136, 120, 119, 119, 119, 118, 119, 120, 120, 120, 119, 104, 136, 119, 103, 120, 119, 103, 119
        .byte   119, 118, 103, 119, 135, 119, 119, 102, 119, 119, 119, 118, 119, 118, 118, 118, 104, 119, 120, 104, 118, 135, 118, 104, 135, 119, 119, 120, 119, 119, 119, 119
        .byte   134, 135, 118, 118, 118, 119, 104, 120, 119, 119, 120, 119, 119, 118, 118, 87, 119, 118, 120, 120, 119, 119, 103, 103, 135, 119, 118, 135, 71, 103, 118, 71
        .byte   119, 103, 87, 102, 118, 117, 119, 135, 85, 117, 120, 118, 116, 104, 116, 120, 134, 87, 134, 118, 117, 119, 120, 85, 133, 120, 120, 120, 120, 136, 136, 135
        .byte   136, 136, 135, 135, 119, 136, 135, 135, 136, 118, 103, 102, 134, 119, 135, 119, 119, 119, 119, 119, 119, 120, 136, 103, 135, 103, 135, 120, 119, 135, 120, 119
        .byte   120, 136, 118, 135, 103, 120, 120, 135, 136, 103, 118, 136, 136, 120, 135, 119, 136, 104, 136, 136, 119, 119, 87, 118, 119, 119, 87, 119, 102, 118, 135, 118
        .byte   102, 119, 103, 135, 102, 134, 135, 117, 133, 120, 119, 102, 135, 119, 118, 101, 120, 136, 103, 118, 120, 119, 135, 135, 119, 135, 119, 136, 120, 135, 119, 136
        .byte   120, 135, 120, 120, 103, 86, 120, 118, 104, 104, 104, 102, 102, 119, 88, 119, 87, 103, 102, 118, 119, 103, 135, 119, 119, 118, 135, 103, 118, 134, 104, 135
        .byte   119, 132, 103, 118, 103, 117, 118, 86, 119, 72, 119, 119, 120, 85, 136, 117, 120, 119, 102, 119, 118, 118, 119, 120, 103, 119, 103, 119, 119, 119, 118, 102
        .byte   102, 118, 134, 134, 135, 101, 135, 119, 102, 117, 103, 119, 117, 104, 135, 103, 136, 119, 120, 135, 120, 135, 119, 120, 118, 119, 119, 120, 120, 119, 116, 103
        .byte   118, 88, 133, 88, 135, 119, 86, 70, 135, 119, 87, 119, 120, 134, 119, 120, 119, 103, 119, 120, 119, 134, 120, 119, 119, 136, 136, 103, 118, 87, 120, 118
        .byte   102, 103, 104, 102, 119, 119, 87, 119, 119, 120, 118, 119, 120, 119, 119, 134, 119, 120, 118, 119, 134, 104, 120, 120, 119, 86, 102, 103, 118, 117, 118, 117
        .byte   102, 102, 119, 101, 120, 134, 119, 118, 134, 87, 104, 133, 135, 119, 102, 86, 118, 136, 119, 119, 134, 136, 134, 103, 119, 135, 118, 118, 119, 119, 103, 119
        .byte   135, 102, 119, 119, 120, 119, 135, 120, 103, 119, 136, 135, 136, 136, 135, 135, 119, 136, 120, 136, 120, 119, 119, 101, 103, 120, 103, 136, 104, 135, 118, 118
        .byte   119, 119, 103, 118, 119, 102, 116, 118, 120, 133, 119, 119, 119, 117, 117, 118, 119, 134, 101, 103, 102, 118, 104, 119, 118, 118, 103, 119, 101, 102, 119, 119
        .byte   102, 104, 103, 103, 119, 104, 119, 119, 135, 118, 118, 87, 118, 104, 103, 104, 86, 103, 103, 134, 118, 119, 101, 118, 103, 103, 87, 119, 103, 103, 118, 119
        .byte   118, 102, 119, 117, 104, 118, 119, 132, 103, 87, 86, 119, 87, 103, 87, 102, 102, 88, 119, 104, 103, 134, 118, 136, 101, 102, 118, 103, 118, 118, 135, 103
        .byte   86, 119, 134, 103, 120, 119, 118, 135, 134, 134, 120, 135, 134, 135, 119, 118, 135, 119, 119, 103, 135, 119, 135, 118, 119, 119, 103, 134, 134, 118, 120, 119
        .byte   119, 118, 120, 136, 119, 119, 135, 135, 119, 136, 119, 136, 119, 119, 104, 119, 103, 136, 120, 136, 119, 135, 119, 120, 134, 120, 135, 120, 135, 136, 119, 135
        .byte   135, 120, 120, 135, 104, 135, 119, 136, 136, 134, 119, 104, 136, 135, 119, 136, 119, 120, 119, 120, 119, 103, 118, 136, 118, 120, 119, 119, 119, 136, 120, 119
        .byte   119, 120, 135, 119, 119, 118, 119, 119, 118, 134, 104, 87, 135, 120, 120, 118, 119, 118, 136, 104, 103, 119, 103, 101, 117, 118, 117, 101, 87, 118, 86, 103
        .byte   116, 118, 119, 117, 102, 119, 117, 132, 88, 103, 118, 119, 87, 118, 119, 134, 134, 104, 117, 103, 135, 102, 104, 102, 88, 103, 120, 102, 102, 119, 104, 135
        .byte   86, 119, 117, 119, 134, 103, 133, 119, 134, 88, 135, 119, 86, 119, 120, 100, 117, 103, 118, 118, 119, 135, 101, 103, 103, 120, 134, 118, 118, 119, 118, 103
        .byte   103, 102, 135, 118, 118, 119, 118, 102, 119, 134, 133, 101, 119, 118, 120, 102, 135, 120, 135, 119, 134, 135, 120, 136, 119, 120, 119, 119, 118, 134, 118, 134
        .byte   103, 120, 118, 120, 119, 104, 134, 135, 102, 135, 103, 87, 88, 135, 119, 119, 134, 118, 119, 135, 119, 103, 103, 119, 119, 87, 103, 135, 104, 120, 103, 120
        .byte   120, 119, 119, 120, 120, 120, 135, 118, 120, 135, 135, 134, 103, 117, 103, 118, 119, 118, 119, 120, 136, 118, 103, 135, 119, 120, 103, 119, 103, 119, 136, 134
        .byte   103, 134, 119, 120, 120, 136, 102, 119, 103, 119, 102, 119, 135, 135, 117, 103, 136, 118, 119, 118, 118, 119, 119, 120, 118, 119, 135, 135, 103, 102, 87, 88
        .byte   119, 120, 103, 119, 103, 119, 103, 119, 135, 120, 118, 119, 135, 118, 117, 103, 118, 119, 103, 119, 134, 104, 119, 120, 135, 136, 120, 135, 119, 120, 118, 120
        .byte   119, 119, 119, 119, 119, 104, 118, 119, 118, 119, 102, 119, 136, 118, 119, 119, 119, 103, 119, 135, 103, 119, 120, 119, 120, 103, 120, 135, 119, 135, 118, 119
        .byte   118, 119, 136, 103, 119, 104, 119, 135, 119, 135, 136, 120, 136, 119, 136, 135, 119, 135, 119, 102, 136, 118, 119, 88, 119, 103, 135, 103, 135, 134, 120, 119
        .byte   87, 86, 120, 103, 135, 119, 120, 102, 135, 136, 134, 135, 119, 135, 135, 103, 136, 119, 119, 103, 120, 135, 119, 119, 103, 104, 103, 135, 103, 119, 135, 119
        .byte   118, 134, 119, 134, 120, 119, 134, 88, 119, 136, 120, 120, 103, 136, 120, 117, 117, 119, 117, 120, 135, 103, 117, 119, 117, 119, 119, 69, 134, 135, 120, 119
        .byte   120, 119, 104, 119, 119, 119, 119, 103, 136, 119, 119, 118, 135, 119, 103, 87, 134, 119, 120, 120, 119, 134, 120, 135, 104, 119, 118, 136, 87, 119, 119, 135
        .byte   133, 119, 118, 102, 118, 135, 102, 120, 134, 136, 134, 104, 136, 86, 120, 119, 134, 133, 134, 118, 104, 103, 118, 135, 119, 103, 103, 118, 119, 120, 119, 134
        .byte   120, 119, 119, 120, 119, 119, 104, 135, 119, 117, 135, 135, 136, 103, 134, 104, 119, 136, 103, 135, 88, 135, 104, 120, 102, 117, 102, 135, 103, 134, 103, 119
        .byte   120, 103, 86, 120, 103, 102, 119, 120, 119, 104, 135, 104, 135, 119, 120, 134, 119, 104, 119, 102, 103, 136, 103, 118, 119, 134, 104, 135, 86, 135, 101, 119
        .byte   120, 104, 102, 102, 104, 136, 136, 135, 135, 119, 136, 135, 119, 120, 136, 135, 120, 120, 135, 135, 104, 103, 120, 118, 120, 133, 133, 119, 135, 102, 103, 119
        .byte   103, 119, 136, 103, 86, 135, 120, 120, 135, 118, 103, 119, 103, 118, 102, 88, 136, 135, 119, 118, 119, 135, 134, 134, 118, 103, 117, 135, 118, 119, 118, 119
        .byte   118, 119, 102, 119, 119, 103, 102, 119, 134, 118, 103, 118, 118, 87, 119, 103, 118, 118, 119, 134, 118, 134, 87, 119, 118, 119, 117, 103, 135, 103, 104, 103
        .byte   134, 103, 135, 103, 119, 120, 118, 118, 119, 118, 103, 119, 135, 86, 118, 119, 119, 103, 119, 119, 119, 119, 135, 103, 119, 119, 102, 103, 102, 102, 119, 135
        .byte   117, 119, 102, 101, 102, 102, 104, 119, 118, 119, 119, 103, 103, 120, 118, 135, 102, 120, 118, 103, 120, 118, 119, 119, 135, 87, 119, 120, 118, 119, 119, 119
        .byte   119, 119, 118, 103, 119, 135, 119, 118, 103, 118, 119, 136, 117, 135, 104, 119, 103, 119, 119, 119, 134, 120, 135, 103, 103, 119, 135, 135, 119, 103, 120, 134
        .byte   119, 135, 119, 119, 119, 118, 120, 118, 135, 135, 135, 120, 102, 119, 134, 119, 119, 118, 119, 120, 117, 103, 118, 119, 119, 118, 119, 135, 135, 119, 136, 135
        .byte   135, 136, 120, 135, 136, 119, 119, 119, 136, 135, 135, 135, 120, 119, 136, 135, 135, 120, 120, 120, 135, 119, 119, 119, 120, 119, 135, 135, 120, 135, 120, 119
        .byte   136, 120, 119, 136, 104, 103, 135, 135, 135, 119, 119, 119, 119, 120, 119, 103, 135, 135, 118, 103, 85, 86, 118, 102, 118, 102, 119, 118, 118, 102, 103, 102
        .byte   119, 103, 119, 103, 102, 118, 103, 118, 119, 118, 119, 119, 120, 135, 103, 103, 102, 119, 102, 102, 101, 102, 118, 117, 118, 118, 102, 103, 119, 119, 103, 134
        .byte   119, 102, 103, 102, 101, 119, 103, 119, 118, 134, 119, 87, 117, 134, 102, 119, 71, 104, 135, 119, 117, 103, 120, 118, 119, 119, 103, 133, 87, 119, 118, 119
        .byte   118, 119, 136, 135, 120, 118, 120, 103, 119, 119, 119, 119, 103, 136, 136, 135, 134, 119, 136, 120, 119, 119, 119, 119, 104, 119, 119, 103, 118, 117, 135, 118
        .byte   135, 118, 118, 119, 134, 132, 103, 118, 85, 119, 120, 136, 117, 135, 119, 102, 134, 135, 135, 118, 118, 103, 118, 104, 118, 120, 135, 120, 103, 136, 136, 119
        .byte   120, 136, 119, 136, 135, 103, 119, 120, 119, 136, 120, 135, 119, 118, 119, 135, 119, 135, 103, 103, 120, 119, 120, 134, 120, 118, 119, 119, 119, 103, 119, 104
        .byte   119, 119, 119, 119, 103, 103, 135, 120, 101, 118, 136, 119, 134, 104, 119, 119, 104, 133, 135, 103, 103, 103, 119, 119, 119, 120, 120, 102, 136, 119, 119, 134
        .byte   119, 119, 103, 104, 119, 117, 102, 134, 102, 120, 133, 117, 87, 103, 103, 103, 103, 103, 134, 118, 118, 119, 103, 118, 135, 118, 87, 119, 103, 118, 118, 104
        .byte   118, 119, 118, 119, 102, 119, 136, 103, 119, 119, 119, 119, 119, 118, 102, 118, 119, 103, 119, 103, 119, 102, 118, 86, 119, 133, 102, 104, 118, 102, 103, 119
        .byte   102, 120, 102, 88, 119, 135, 103, 103, 119, 103, 135, 135, 120, 117, 134, 134, 103, 119, 117, 135, 120, 118, 104, 88, 135, 120, 135, 102, 120, 136, 103, 133
        .byte   119, 135, 103, 135, 136, 136, 117, 120, 134, 118, 118, 119, 120, 118, 103, 103, 135, 102, 136, 135, 119, 101, 103, 87, 87, 119, 119, 135, 102, 135, 119, 120
        .byte   135, 120, 135, 118, 119, 135, 135, 120, 135, 120, 136, 136, 119, 118, 117, 134, 118, 117, 118, 120, 133, 135, 118, 118, 135, 119, 103, 119, 136, 119, 136, 135
        .byte   135, 135, 120, 119, 119, 119, 119, 120, 135, 135, 119, 119, 118, 135, 104, 119, 119, 118, 119, 118, 119, 134, 120, 119, 119, 103, 103, 84, 103, 119, 87, 103
        .byte   103, 118, 104, 118, 104, 103, 87, 104, 102, 118, 103, 103, 85, 85, 103, 119, 119, 86, 119, 102, 100, 86, 120, 102, 103, 135, 104, 103, 119, 103, 103, 103
        .byte   103, 118, 120, 101, 119, 117, 104, 102, 118, 103, 104, 103, 134, 103, 103, 86, 103, 135, 86, 119, 101, 118, 102, 118, 102, 120, 134, 102, 86, 119, 88, 117
        .byte   118, 104, 118, 120, 118, 103, 119, 135, 119, 134, 136, 134, 119, 119, 135, 119, 119, 103, 103, 136, 120, 119, 135, 121, 120, 135, 121, 120, 136, 135, 118, 136
        .byte   135, 104, 104, 136, 86, 103, 135, 120, 104, 120, 118, 120, 103, 120, 120, 135, 134, 119, 117, 119, 102, 119, 134, 136, 119, 134, 118, 120, 134, 135, 119, 135
        .byte   119, 119, 136, 119, 119, 135, 135, 102, 119, 118, 135, 118, 120, 119, 133, 120, 118, 135, 118, 119, 119, 135, 103, 119, 119, 119, 118, 136, 119, 134, 136, 87
        .byte   102, 119, 120, 119, 135, 118, 118, 135, 135, 102, 103, 119, 119, 118, 103, 118, 104, 119, 133, 118, 119, 103, 134, 119, 119, 118, 103, 119, 120, 119, 133, 135
        .byte   118, 120, 119, 118, 120, 119, 118, 133, 103, 118, 136, 119, 119, 101, 134, 119, 120, 103, 119, 119, 119, 102, 135, 103, 118, 104, 136, 117, 103, 115, 120, 117
        .byte   120, 132, 85, 102, 70, 119, 103, 119, 71, 119, 88, 118, 117, 136, 118, 119, 118, 87, 120, 103, 104, 119, 119, 102, 103, 135, 119, 119, 118, 119, 119, 102
        .byte   102, 103, 134, 119, 118, 119, 101, 86, 115, 119, 119, 117, 100, 119, 102, 117, 72, 117, 102, 118, 70, 118, 117, 118, 88, 104, 119, 118, 120, 103, 103, 104
        .byte   119, 119, 135, 134, 103, 120, 135, 119, 119, 119, 103, 119, 119, 120, 118, 119, 119, 103, 103, 119, 103, 101, 86, 101, 86, 135, 71, 86, 117, 120, 119, 85
        .byte   70, 118, 135, 135, 117, 118, 101, 86, 116, 103, 134, 85, 119, 117, 86, 135, 118, 72, 119, 119, 120, 119, 119, 119, 119, 119, 119, 103, 103, 135, 103, 104
        .byte   118, 103, 118, 119, 120, 118, 135, 103, 118, 118, 103, 101, 118, 119, 118, 102, 119, 135, 102, 120, 119, 118, 119, 103, 101, 119, 134, 117, 135, 104, 102, 103
        .byte   119, 102, 103, 119, 118, 103, 87, 86, 102, 87, 103, 135, 118, 102, 135, 118, 119, 118, 135, 134, 136, 118, 117, 119, 119, 103, 118, 103, 119, 135, 103, 119
        .byte   102, 118, 118, 134, 119, 118, 104, 87, 118, 118, 119, 88, 135, 136, 136, 119, 134, 135, 88, 118, 103, 120, 119, 135, 118, 119, 134, 136, 119, 119, 136, 136
        .byte   136, 103, 136, 136, 119, 120, 120, 104, 119, 136, 119, 71, 87, 119, 119, 117, 119, 119, 117, 118, 136, 88, 101, 88, 135, 135, 103, 120, 120, 120, 119, 119
        .byte   136, 103, 119, 135, 120, 135, 118, 135, 136, 135, 134, 136, 119, 119, 135, 104, 120, 135, 136, 119, 135, 136, 104, 119, 120, 136, 120, 120, 119, 120, 135, 103
        .byte   118, 120, 119, 120, 136, 119, 104, 120, 118, 119, 119, 120, 119, 119, 103, 135, 119, 120, 119, 135, 136, 136, 118, 118, 103, 103, 117, 103, 135, 87, 118, 87
        .byte   118, 120, 103, 134, 135, 120, 136, 135, 135, 135, 119, 136, 119, 120, 135, 136, 119, 136, 135, 103, 118, 118, 119, 103, 119, 102, 119, 117, 103, 117, 135, 120
        .byte   103, 134, 120, 120, 135, 120, 119, 136, 135, 136, 119, 119, 135, 120, 135, 120, 136, 103, 134, 120, 136, 120, 135, 119, 118, 135, 119, 136, 119, 119, 135, 134
        .byte   102, 118, 120, 119, 136, 134, 103, 120, 135, 119, 119, 119, 120, 119, 135, 103, 100, 87, 118, 120, 133, 135, 102, 104, 117, 87, 135, 103, 118, 119, 119, 87
        .byte   118, 69, 104, 135, 100, 85, 102, 133, 86, 118, 104, 102, 117, 119, 103, 103, 135, 119, 134, 119, 119, 119, 135, 102, 103, 103, 120, 119, 118, 120, 118, 118
        .byte   120, 135, 118, 119, 103, 118, 120, 119, 135, 120, 120, 87, 118, 135, 119, 87, 103, 133, 103, 135, 100, 101, 119, 102, 104, 102, 120, 102, 118, 135, 118, 119
        .byte   135, 135, 118, 119, 117, 119, 102, 119, 103, 103, 120, 103, 135, 119, 119, 103, 104, 119, 119, 119, 118, 119, 135, 118, 72, 119, 69, 119, 119, 117, 133, 102
        .byte   133, 119, 86, 118, 104, 104, 87, 119, 102, 118, 117, 87, 102, 117, 102, 133, 104, 103, 117, 118, 71, 103, 134, 119, 119, 119, 119, 119, 136, 118, 136, 119
        .byte   135, 119, 136, 102, 119, 102, 135, 134, 103, 102, 119, 104, 86, 103, 102, 135, 87, 102, 134, 117, 104, 117, 117, 87, 118, 118, 104, 72, 104, 118, 117, 103
        .byte   119, 117, 134, 118, 103, 119, 119, 134, 149, 118, 119, 103, 119, 118, 102, 104, 120, 120, 120, 120, 135, 120, 135, 136, 120, 136, 119, 136, 135, 119, 134, 136
        .byte   119, 87, 119, 135, 119, 118, 104, 135, 136, 135, 119, 134, 120, 103, 104, 136, 88, 119, 135, 103, 135, 104, 103, 104, 119, 120, 119, 103, 102, 134, 135, 119
        .byte   119, 136, 136, 119, 136, 120, 102, 135, 119, 136, 120, 135, 136, 119, 119, 135, 119, 135, 120, 135, 104, 119, 135, 135, 135, 104, 120, 120, 134, 119, 103, 119
        .byte   119, 134, 102, 118, 119, 104, 134, 103, 87, 103, 119, 120, 120, 135, 135, 104, 120, 120, 119, 136, 136, 119, 135, 120, 120, 120, 136, 119, 120, 135, 119, 103
        .byte   136, 135, 135, 119, 134, 119, 104, 120, 118, 119, 119, 119, 119, 103, 118, 103, 103, 103, 87, 118, 119, 119, 118, 135, 118, 119, 120, 135, 134, 119, 135, 118
        .byte   103, 120, 103, 119, 101, 136, 135, 103, 136, 119, 118, 136, 135, 119, 120, 136, 118, 136, 119, 118, 135, 136, 119, 120, 118, 135, 103, 119, 104, 136, 119, 136
        .byte   88, 118, 136, 136, 104, 103, 120, 119, 120, 135, 136, 136, 134, 119, 120, 120, 134, 135, 119, 120, 119, 119, 116, 86, 103, 119, 117, 119, 118, 119, 85, 119
        .byte   133, 134, 133, 118, 120, 135, 120, 119, 119, 135, 135, 120, 135, 136, 119, 119, 103, 136, 120, 120, 118, 86, 101, 102, 119, 117, 104, 119, 134, 103, 120, 118
        .byte   103, 135, 119, 102, 103, 119, 119, 102, 135, 120, 119, 135, 119, 120, 119, 103, 135, 120, 104, 119, 103, 136, 119, 119, 104, 120, 120, 119, 120, 119, 119, 120
        .byte   119, 135, 118, 119, 118, 118, 119, 119, 134, 119, 134, 118, 103, 118, 119, 119, 101, 103, 120, 104, 135, 135, 119, 119, 118, 103, 119, 87, 120, 119, 119, 103
        .byte   119, 120, 119, 135, 120, 104, 120, 136, 119, 119, 103, 135, 104, 135, 120, 135, 135, 119, 120, 135, 136, 136, 120, 136, 120, 120, 120, 135, 119, 119, 103, 103
        .byte   136, 119, 104, 120, 119, 135, 120, 119, 120, 136, 135, 104, 103, 103, 103, 104, 119, 118, 120, 135, 103, 103, 119, 120, 119, 104, 103, 119, 119, 135, 118, 135
        .byte   119, 119, 118, 136, 136, 136, 118, 120, 118, 120, 86, 103, 134, 103, 102, 104, 104, 119, 103, 102, 102, 102, 119, 134, 119, 87, 103, 104, 119, 134, 119, 102
        .byte   118, 119, 103, 102, 102, 103, 119, 119, 120, 120, 119, 136, 135, 136, 118, 120, 118, 136, 119, 104, 135, 134, 136, 134, 120, 104, 135, 136, 120, 120, 103, 120
        .byte   120, 136, 135, 135, 119, 135, 102, 88, 119, 120, 103, 135, 119, 135, 103, 136, 118, 120, 134, 135, 104, 119, 102, 118, 117, 103, 86, 136, 134, 103, 134, 104
        .byte   120, 102, 119, 120, 118, 118, 118, 119, 119, 133, 104, 119, 118, 103, 136, 119, 103, 120, 102, 118, 119, 119, 119, 134, 103, 104, 119, 119, 119, 135, 119, 119
        .byte   119, 118, 135, 135, 118, 119, 119, 103, 120, 120, 135, 119, 119, 102, 120, 103, 120, 119, 134, 135, 119, 135, 120, 120, 119, 120, 119, 151, 102, 135, 103, 119
        .byte   86, 135, 87, 135, 134, 119, 104, 118, 71, 86, 119, 135, 103, 87, 103, 86, 103, 120, 119, 119, 104, 119, 118, 119, 86, 104, 134, 118, 118, 88, 119, 103
        .byte   134, 55, 88, 102, 100, 116, 120, 117, 71, 88, 119, 70, 102, 119, 119, 104, 103, 118, 102, 103, 119, 118, 119, 102, 101, 86, 120, 86, 119, 115, 88, 119
        .byte   100, 103, 87, 103, 102, 103, 116, 102, 117, 72, 101, 135, 86, 120, 103, 118, 118, 103, 118, 102, 104, 103, 119, 103, 104, 135, 87, 135, 117, 119, 118, 103
        .byte   118, 87, 104, 102, 103, 119, 135, 102, 134, 119, 120, 119, 118, 120, 136, 135, 119, 135, 119, 135, 86, 118, 119, 118, 119, 134, 134, 133, 119, 120, 135, 103
        .byte   119, 118, 118, 119, 134, 119, 103, 120, 118, 102, 119, 119, 119, 119, 135, 119, 120, 135, 103, 118, 119, 103, 104, 119, 120, 135, 119, 103, 120, 103, 119, 119
        .byte   120, 135, 120, 118, 118, 120, 136, 119, 103, 135, 86, 103, 87, 119, 119, 135, 101, 119, 116, 118, 100, 103, 102, 119, 118, 87, 118, 87, 103, 85, 119, 103
        .byte   102, 119, 102, 103, 118, 135, 118, 119, 134, 118, 120, 119, 119, 118, 101, 119, 119, 119, 86, 103, 136, 119, 135, 103, 119, 119, 87, 118, 118, 118, 134, 118
        .byte   119, 54, 71, 103, 119, 101, 104, 102, 88, 119, 118, 87, 116, 100, 118, 87, 119, 102, 71, 117, 103, 69, 102, 88, 99, 85, 119, 84, 132, 119, 104, 86
        .byte   119, 119, 102, 119, 119, 118, 118, 135, 117, 102, 102, 118, 87, 119, 119, 117, 134, 119, 134, 119, 102, 119, 136, 102, 119, 103, 118, 88, 117, 135, 102, 135
        .byte   118, 118, 120, 119, 104, 135, 120, 117, 135, 136, 102, 103, 88, 134, 103, 102, 118, 102, 120, 119, 102, 117, 120, 101, 102, 118, 87, 103, 135, 135, 104, 102
        .byte   119, 136, 103, 119, 119, 134, 103, 118, 117, 87, 119, 103, 119, 119, 102, 119, 134, 119, 119, 119, 135, 119, 118, 120, 103, 87, 102, 55, 135, 118, 120, 84
        .byte   71, 120, 87, 86, 102, 132, 118, 117, 102, 87, 104, 118, 134, 119, 119, 103, 103, 118, 118, 135, 134, 120, 118, 119, 133, 117, 118, 118, 133, 103, 135, 86
        .byte   118, 116, 120, 118, 87, 103, 134, 120, 136, 103, 119, 118, 118, 119, 117, 102, 118, 104, 119, 118, 70, 55, 102, 119, 87, 100, 117, 118, 70, 101, 85, 72
        .byte   87, 102, 102, 118, 120, 118, 119, 119, 119, 134, 119, 104, 135, 102, 119, 136, 120, 120, 119, 136, 135, 118, 118, 119, 119, 117, 120, 134, 119, 118, 120, 118
        .byte   134, 135, 119, 136, 119, 104, 135, 103, 120, 120, 88, 119, 104, 120, 104, 119, 135, 134, 134, 135, 118, 120, 136, 103, 135, 119, 135, 119, 120, 120, 103, 136
        .byte   135, 135, 136, 120, 120, 104, 102, 103, 120, 119, 119, 136, 135, 120, 120, 119, 84, 119, 118, 117, 120, 119, 87, 119, 88, 104, 135, 135, 85, 135, 119, 118
        .byte   136, 119, 119, 136, 120, 134, 136, 136, 118, 135, 136, 118, 119, 100, 118, 101, 135, 117, 86, 87, 117, 118, 103, 102, 102, 103, 135, 120, 100, 86, 103, 118
        .byte   87, 118, 88, 86, 118, 103, 118, 102, 118, 135, 119, 118, 84, 104, 114, 53, 104, 86, 55, 103, 100, 55, 135, 84, 85, 85, 38, 119, 103, 70, 83, 102
        .byte   102, 53, 118, 69, 55, 71, 87, 85, 100, 87, 71, 103, 117, 117, 119, 118, 117, 104, 119, 85, 103, 118, 119, 135, 100, 119, 132, 119, 101, 103, 103, 117
        .byte   102, 119, 103, 101, 86, 119, 86, 104, 103, 88, 119, 103, 86, 102, 104, 101, 102, 118, 84, 101, 119, 103, 135, 135, 134, 119, 103, 104, 118, 119, 119, 104
        .byte   104, 101, 135, 87, 134, 135, 135, 119, 118, 119, 87, 104, 134, 87, 135, 71, 119, 88, 120, 118, 119, 136, 87, 103, 103, 135, 101, 120, 101, 119, 117, 102
        .byte   119, 116, 119, 99, 70, 102, 118, 100, 134, 134, 120, 68, 119, 132, 118, 132, 102, 151, 117, 102, 119, 103, 118, 119, 135, 119, 102, 87, 135, 120, 88, 118
        .byte   120, 88, 118, 120, 119, 119, 136, 135, 119, 104, 120, 103, 87, 135, 119, 135, 104, 118, 135, 136, 119, 87, 135, 120, 103, 119, 103, 88, 103, 119, 119, 120
        .byte   135, 118, 118, 86, 135, 119, 136, 119, 120, 120, 118, 103, 119, 119, 103, 119, 87, 104, 119, 136, 102, 104, 135, 105, 119, 119, 134, 118, 88, 117, 104, 119
        .byte   119, 101, 118, 135, 119, 102, 102, 119, 135, 103, 119, 87, 118, 118, 119, 134, 118, 119, 102, 119, 119, 118, 103, 118, 119, 103, 120, 136, 117, 120, 119, 104
        .byte   120, 135, 120, 133, 118, 119, 119, 119, 134, 117, 120, 119, 86, 102, 118, 87, 100, 119, 99, 117, 100, 103, 103, 116, 118, 54, 86, 118, 101, 135, 134, 100
        .byte   117, 104, 119, 84, 72, 118, 118, 119, 134, 120, 119, 136, 135, 101, 119, 103, 104, 135, 134, 135, 135, 104, 120, 102, 119, 135, 102, 119, 135, 119, 119, 119
        .byte   119, 121, 135, 103, 119, 119, 103, 120, 135, 102, 104, 118, 118, 118, 119, 120, 117, 103, 118, 118, 118, 102, 117, 135, 118, 118, 118, 103, 102, 119, 134, 119
        .byte   117, 102, 102, 120, 119, 119, 136, 119, 136, 120, 103, 120, 136, 120, 120, 119, 136, 104, 104, 135, 119, 119, 135, 136, 87, 135, 135, 134, 135, 119, 102, 150
        .byte   120, 135, 119, 136, 135, 135, 120, 103, 136, 120, 120, 135, 152, 118, 152, 135, 119, 136, 120, 119, 119, 104, 135, 104, 118, 120, 119, 120, 136, 120, 119, 102
        .byte   119, 119, 118, 118, 119, 119, 136, 119, 136, 135, 120, 135, 135, 119, 119, 102, 103, 118, 103, 120, 118, 87, 117, 119, 119, 102, 119, 102, 136, 101, 71, 102
        .byte   119, 102, 134, 118, 85, 102, 119, 135, 101, 88, 102, 119, 103, 119, 119, 136, 104, 118, 119, 120, 119, 119, 135, 136, 119, 119, 118, 103, 118, 103, 120, 119
        .byte   120, 135, 119, 119, 119, 119, 120, 102, 118, 119, 118, 119, 119, 119, 118, 135, 117, 118, 119, 117, 103, 119, 100, 88, 118, 135, 134, 119, 119, 103, 119, 119
        .byte   136, 119, 135, 102, 135, 120, 136, 120, 119, 118, 119, 103, 104, 120, 136, 118, 135, 119, 119, 120, 120, 135, 120, 119, 103, 102, 119, 119, 119, 134, 136, 134
        .byte   103, 102, 136, 135, 119, 119, 118, 135, 119, 119, 102, 135, 101, 118, 119, 133, 103, 120, 100, 88, 119, 118, 117, 100, 119, 104, 135, 101, 88, 102, 135, 102
        .byte   119, 120, 88, 104, 103, 119, 103, 87, 119, 135, 104, 103, 104, 118, 103, 119, 102, 135, 135, 120, 103, 120, 137, 136, 120, 119, 103, 119, 135, 119, 135, 118
        .byte   136, 134, 120, 135, 119, 136, 136, 120, 120, 135, 120, 120, 135, 120, 135, 104, 119, 119, 102, 120, 119, 119, 119, 135, 136, 135, 136, 135, 119, 119, 136, 104
        .byte   135, 118, 135, 120, 103, 103, 120, 119, 119, 102, 118, 134, 120, 119, 86, 104, 118, 134, 120, 135, 136, 135, 119, 135, 135, 135, 119, 119, 136, 119, 119, 104
        .byte   120, 120, 135, 135, 118, 118, 119, 134, 119, 104, 119, 120, 118, 119, 118, 120, 134, 135, 136, 135, 135, 135, 135, 135, 136, 136, 120, 119, 119, 119, 134, 134
        .byte   118, 119, 119, 103, 119, 120, 118, 135, 102, 118, 103, 119, 136, 136, 135, 136, 120, 119, 135, 136, 136, 136, 135, 120, 120, 119, 119, 119, 104, 120, 119, 119
        .byte   120, 136, 136, 119, 104, 135, 103, 135, 135, 119, 102, 119, 103, 119, 103, 120, 120, 103, 119, 119, 135, 135, 119, 118, 119, 103, 118, 120, 103, 134, 117, 104
        .byte   102, 135, 119, 134, 119, 103, 119, 102, 135, 118, 119, 118, 135, 133, 103, 134, 134, 135, 118, 135, 103, 136, 119, 118, 136, 119, 118, 120, 120, 120, 135, 135
        .byte   135, 120, 103, 119, 137, 119, 102, 118, 103, 134, 119, 134, 120, 119, 119, 119, 119, 119, 119, 119, 103, 119, 103, 136, 135, 119, 119, 134, 103, 120, 135, 119
        .byte   135, 135, 104, 103, 103, 86, 102, 102, 101, 136, 135, 103, 87, 101, 120, 119, 104, 101, 103, 103, 103, 102, 102, 104, 120, 85, 102, 87, 104, 87, 88, 103
        .byte   102, 86, 103, 117, 87, 119, 119, 87, 71, 102, 103, 102, 87, 118, 101, 119, 135, 119, 118, 120, 119, 135, 120, 118, 104, 119, 119, 119, 119, 102, 136, 102
        .byte   103, 102, 120, 86, 119, 134, 118, 118, 103, 103, 103, 86, 101, 102, 119, 119, 119, 135, 120, 119, 103, 119, 119, 119, 103, 135, 103, 103, 134, 119, 135, 136
        .byte   119, 119, 119, 119, 136, 136, 134, 135, 135, 135, 120, 119, 119, 135, 119, 135, 134, 118, 104, 103, 135, 119, 135, 118, 120, 119, 119, 119, 102, 119, 87, 103
        .byte   101, 135, 118, 103, 136, 118, 104, 120, 134, 120, 119, 103, 118, 88, 120, 135, 88, 120, 104, 135, 102, 135, 136, 103, 119, 118, 103, 134, 119, 119, 103, 119
        .byte   118, 135, 120, 119, 134, 87, 120, 103, 119, 87, 119, 120, 103, 120, 134, 104, 118, 119, 119, 102, 119, 119, 135, 135, 87, 135, 120, 104, 118, 120, 135, 102
        .byte   120, 118, 103, 119, 136, 103, 119, 118, 135, 136, 135, 119, 120, 120, 120, 119, 120, 135, 135, 104, 120, 119, 133, 117, 119, 104, 102, 135, 135, 118, 102, 119
        .byte   133, 103, 119, 103, 136, 118, 86, 120, 119, 103, 135, 136, 120, 118, 103, 135, 119, 103, 120, 103, 135, 135, 104, 118, 136, 133, 103, 118, 88, 103, 134, 103
        .byte   120, 104, 103, 119, 103, 119, 136, 120, 133, 119, 134, 104, 120, 134, 119, 134, 104, 120, 119, 135, 104, 120, 119, 136, 119, 136, 120, 119, 135, 104, 120, 104
        .byte   119, 117, 103, 119, 103, 103, 135, 136, 103, 104, 118, 118, 136, 120, 88, 101, 87, 102, 102, 118, 101, 103, 117, 119, 102, 102, 102, 101, 70, 118, 103, 115
        .byte   70, 99, 102, 101, 55, 118, 69, 69, 100, 103, 83, 98, 119, 119, 71, 87, 118, 103, 119, 117, 103, 119, 103, 118, 118, 117, 116, 119, 86, 118, 84, 103
        .byte   103, 86, 87, 103, 118, 102, 118, 103, 69, 87, 102, 101, 120, 118, 86, 102, 117, 135, 101, 72, 102, 102, 86, 103, 135, 87, 39, 102, 53, 118, 70, 102
        .byte   99, 100, 131, 87, 84, 69, 103, 119, 54, 103, 100, 86, 102, 102, 102, 102, 86, 102, 87, 102, 119, 103, 85, 118, 119, 120, 118, 119, 136, 119, 119, 119
        .byte   136, 119, 119, 118, 119, 118, 135, 119, 119, 119, 119, 86, 86, 118, 103, 102, 102, 120, 103, 102, 103, 119, 119, 102, 118, 118, 119, 117, 119, 118, 103, 120
        .byte   102, 120, 104, 119, 118, 119, 118, 135, 135, 102, 135, 120, 133, 104, 119, 119, 118, 102, 118, 103, 103, 119, 101, 102, 103, 119, 103, 119, 118, 119, 102, 120
        .byte   86, 87, 118, 103, 134, 102, 120, 119, 103, 103, 86, 87, 103, 135, 104, 103, 103, 102, 118, 119, 102, 119, 119, 119, 119, 134, 103, 119, 119, 119, 120, 135
        .byte   119, 119, 118, 119, 135, 119, 103, 119, 118, 119, 135, 120, 135, 119, 102, 135, 136, 103, 102, 117, 102, 85, 103, 119, 102, 103, 120, 102, 135, 117, 118, 103
        .byte   119, 102, 118, 119, 102, 133, 103, 120, 134, 87, 135, 135, 103, 104, 135, 119, 135, 118, 119, 118, 119, 135, 104, 120, 135, 119, 103, 103, 119, 86, 102, 71
        .byte   103, 103, 135, 102, 101, 87, 118, 102, 119, 87, 117, 119, 102, 118, 119, 117, 104, 117, 103, 103, 135, 119, 135, 134, 118, 102, 119, 86, 103, 103, 134, 103
        .byte   119, 86, 70, 85, 119, 118, 87, 118, 103, 86, 119, 135, 120, 120, 136, 104, 118, 119, 103, 119, 119, 136, 135, 119, 136, 117, 104, 119, 86, 135, 87, 88
        .byte   133, 104, 100, 101, 118, 103, 103, 102, 117, 135, 135, 101, 120, 119, 71, 135, 120, 88, 133, 104, 103, 103, 120, 119, 135, 119, 135, 136, 135, 118, 103, 120
        .byte   120, 136, 135, 120, 120, 120, 120, 87, 104, 120, 120, 104, 134, 103, 135, 119, 135, 118, 120, 119, 120, 136, 120, 118, 103, 136, 120, 119, 120, 103, 119, 103
        .byte   135, 135, 119, 136, 88, 134, 102, 119, 136, 135, 103, 119, 103, 103, 103, 135, 103, 120, 119, 135, 119, 136, 136, 119, 134, 120, 120, 135, 119, 119, 135, 120
        .byte   136, 135, 102, 119, 119, 103, 135, 120, 134, 103, 120, 133, 102, 119, 118, 118, 119, 120, 103, 103, 120, 119, 119, 135, 104, 134, 118, 118, 119, 103, 135, 120
        .byte   103, 119, 120, 136, 119, 120, 103, 118, 119, 119, 101, 118, 120, 120, 104, 118, 103, 103, 119, 120, 118, 103, 104, 119, 119, 119, 118, 119, 104, 120, 120, 120
        .byte   135, 119, 135, 135, 104, 120, 120, 135, 103, 119, 136, 119, 135, 104, 103, 103, 119, 119, 120, 118, 119, 135, 118, 117, 134, 119, 118, 136, 103, 119, 135, 135
        .byte   136, 135, 135, 119, 135, 120, 136, 136, 134, 119, 119, 71, 102, 104, 119, 119, 135, 102, 85, 135, 119, 104, 134, 119, 119, 117, 103, 103, 103, 119, 103, 119
        .byte   119, 118, 119, 118, 119, 103, 118, 101, 119, 134, 134, 118, 135, 119, 119, 118, 120, 120, 119, 134, 103, 120, 119, 104, 103, 135, 120, 136, 117, 120, 102, 103
        .byte   136, 88, 119, 71, 120, 117, 135, 104, 119, 102, 119, 119, 136, 102, 119, 117, 119, 119, 104, 120, 119, 120, 120, 134, 134, 119, 119, 119, 135, 104, 135, 103
        .byte   135, 120, 103, 120, 119, 120, 135, 120, 136, 136, 119, 104, 136, 136, 104, 136, 120, 120, 120, 135, 119, 135, 103, 118, 120, 135, 134, 119, 134, 119, 119, 119
        .byte   135, 119, 119, 119, 119, 119, 119, 135, 119, 118, 104, 103, 136, 119, 120, 119, 119, 120, 117, 119, 119, 120, 104, 119, 119, 118, 87, 119, 134, 102, 119, 120
        .byte   103, 119, 120, 119, 119, 120, 120, 118, 119, 103, 120, 135, 135, 119, 120, 118, 87, 102, 119, 103, 103, 120, 119, 69, 103, 118, 87, 136, 119, 135, 117, 87
        .byte   118, 120, 135, 118, 119, 119, 117, 118, 119, 116, 118, 135, 135, 87, 119, 118, 118, 136, 119, 135, 134, 119, 119, 119, 119, 119, 119, 135, 119, 103, 71, 103
        .byte   118, 118, 104, 87, 119, 120, 87, 118, 86, 86, 118, 136, 119, 87, 103, 119, 119, 119, 119, 118, 118, 118, 118, 103, 118, 102, 119, 119, 118, 119, 119, 120
        .byte   120, 119, 118, 119, 135, 102, 120, 103, 135, 120, 136, 118, 119, 120, 120, 103, 135, 104, 136, 135, 119, 120, 119, 121, 120, 118, 119, 118, 119, 135, 119, 136
        .byte   119, 119, 104, 136, 103, 120, 120, 119, 104, 119, 118, 88, 135, 120, 118, 103, 118, 72, 87, 119, 103, 120, 87, 120, 135, 104, 136, 119, 120, 104, 136, 136
        .byte   104, 120, 136, 119, 119, 135, 87, 117, 71, 119, 119, 120, 134, 133, 119, 117, 86, 135, 119, 117, 119, 119, 119, 119, 118, 119, 119, 134, 119, 103, 135, 120
        .byte   136, 119, 135, 119, 102, 120, 119, 104, 103, 118, 135, 119, 88, 135, 118, 118, 134, 135, 87, 134, 119, 119, 119, 136, 119, 119, 134, 104, 120, 135, 119, 120
        .byte   103, 136, 120, 104, 135, 104, 119, 119, 136, 87, 120, 119, 104, 119, 136, 135, 119, 119, 118, 103, 120, 134, 135, 135, 135, 118, 119, 117, 134, 119, 134, 120
        .byte   119, 136, 120, 120, 118, 119, 120, 120, 136, 120, 119, 119, 135, 151, 135, 102, 119, 86, 118, 118, 119, 118, 119, 134, 135, 103, 134, 135, 119, 104, 104, 119
        .byte   103, 118, 102, 119, 135, 135, 135, 120, 119, 135, 119, 102, 120, 134, 120, 135, 119, 120, 119, 119, 136, 119, 136, 135, 134, 152, 119, 120, 119, 134, 119, 120
        .byte   103, 119, 120, 119, 119, 119, 103, 120, 102, 119, 102, 103, 102, 102, 104, 103, 119, 104, 104, 103, 134, 86, 103, 135, 119, 134, 103, 119, 119, 119, 120, 119
        .byte   119, 119, 104, 119, 134, 134, 119, 120, 103, 120, 103, 119, 135, 119, 119, 119, 135, 134, 119, 103, 118, 119, 119, 120, 103, 118, 103, 118, 117, 119, 119, 134
        .byte   118, 104, 102, 118, 135, 133, 103, 120, 103, 119, 119, 119, 103, 135, 136, 119, 135, 119, 120, 118, 103, 136, 103, 103, 119, 102, 120, 118, 118, 119, 103, 119
        .byte   119, 119, 119, 103, 135, 102, 119, 118, 101, 103, 118, 103, 118, 87, 102, 101, 102, 118, 118, 103, 119, 135, 118, 135, 135, 118, 119, 120, 136, 103, 119, 118
        .byte   120, 119, 120, 87, 101, 86, 119, 119, 120, 101, 118, 102, 104, 102, 118, 120, 102, 103, 136, 120, 119, 119, 136, 136, 136, 120, 135, 119, 135, 135, 136, 136
        .byte   135, 119, 104, 86, 119, 119, 103, 119, 103, 118, 118, 135, 103, 119, 102, 118, 120, 134, 119, 119, 118, 120, 120, 136, 118, 120, 119, 120, 118, 119, 104, 136
        .byte   120, 135, 135, 134, 136, 135, 136, 119, 135, 134, 119, 135, 135, 135, 103, 103, 103, 136, 118, 120, 135, 119, 134, 119, 119, 135, 103, 119, 135, 102, 103, 119
        .byte   119, 119, 119, 119, 119, 104, 135, 119, 103, 119, 103, 135, 119, 120, 135, 119, 120, 119, 119, 119, 119, 136, 135, 134, 136, 120, 120, 134, 117, 102, 102, 119
        .byte   119, 102, 119, 118, 101, 103, 118, 84, 118, 87, 71, 119, 70, 103, 54, 88, 69, 85, 102, 115, 37, 118, 86, 118, 115, 120, 116, 87, 119, 102, 118, 103
        .byte   103, 135, 101, 71, 135, 135, 87, 119, 85, 104, 136, 102, 86, 101, 88, 103, 102, 88, 134, 88, 103, 71, 102, 39, 87, 54, 102, 133, 118, 71, 67, 85
        .byte   87, 119, 71, 118, 115, 87, 102, 102, 84, 118, 103, 101, 102, 103, 134, 118, 87, 134, 86, 103, 88, 86, 119, 84, 103, 119, 87, 87, 104, 119, 103, 119
        .byte   103, 69, 87, 103, 118, 119, 119, 119, 120, 135, 136, 136, 119, 135, 119, 136, 119, 119, 120, 135, 117, 118, 119, 120, 119, 103, 119, 104, 119, 102, 136, 120
        .byte   119, 118, 136, 134, 103, 119, 136, 103, 119, 119, 120, 135, 120, 120, 135, 120, 119, 136, 135, 135, 135, 135, 120, 136, 120, 120, 120, 136, 136, 120, 119, 136
        .byte   119, 102, 119, 120, 119, 119, 119, 136, 135, 103, 136, 118, 119, 120, 120, 119, 120, 119, 119, 104, 120, 120, 134, 118, 120, 119, 103, 120, 103, 89, 104, 119
        .byte   119, 119, 119, 119, 120, 118, 103, 119, 103, 120, 103, 135, 103, 136, 136, 120, 120, 136, 121, 135, 119, 136, 136, 136, 120, 135, 135, 136, 118, 104, 120, 103
        .byte   103, 103, 119, 103, 103, 104, 119, 135, 118, 135, 117, 118, 118, 103, 118, 118, 103, 135, 103, 119, 135, 119, 120, 103, 119, 120, 119, 103, 135, 136, 120, 119
        .byte   120, 136, 119, 120, 118, 120, 119, 119, 119, 102, 134, 103, 103, 134, 119, 120, 134, 104, 118, 134, 119, 118, 117, 119, 118, 118, 135, 119, 119, 119, 119, 104
        .byte   119, 118, 118, 119, 136, 119, 136, 119, 119, 102, 104, 120, 136, 104, 120, 119, 135, 103, 136, 136, 120, 119, 120, 119, 120, 120, 120, 104, 135, 136, 103, 135
        .byte   119, 119, 119, 120, 135, 134, 120, 119, 104, 134, 134, 119, 119, 86, 104, 136, 119, 101, 135, 135, 134, 135, 136, 103, 134, 118, 135, 120, 136, 88, 136, 133
        .byte   104, 136, 120, 103, 135, 119, 135, 135, 120, 120, 103, 119, 120, 119, 119, 120, 135, 135, 135, 119, 119, 118, 120, 118, 119, 120, 136, 119, 135, 118, 135, 103
        .byte   135, 119, 119, 118, 120, 136, 119, 103, 120, 104, 119, 119, 120, 103, 120, 135, 136, 135, 135, 119, 135, 135, 136, 135, 103, 136, 120, 119, 136, 135, 118, 135
        .byte   119, 135, 152, 119, 135, 134, 119, 119, 134, 119, 104, 134, 103, 103, 101, 120, 119, 136, 101, 118, 103, 87, 119, 102, 87, 70, 135, 88, 102, 133, 119, 136
        .byte   120, 86, 118, 135, 86, 119, 134, 119, 117, 135, 136, 116, 136, 134, 119, 135, 134, 135, 136, 136, 120, 119, 136, 119, 135, 119, 119, 88, 119, 104, 134, 119
        .byte   120, 119, 118, 136, 119, 103, 102, 119, 102, 120, 120, 120, 119, 119, 120, 119, 103, 135, 120, 120, 119, 119, 104, 120, 120, 103, 134, 103, 135, 134, 119, 103
        .byte   117, 104, 119, 119, 103, 103, 118, 103, 119, 103, 119, 135, 119, 102, 118, 120, 119, 120, 120, 135, 136, 120, 120, 119, 102, 86, 102, 135, 102, 119, 119, 103
        .byte   119, 119, 103, 118, 118, 119, 119, 119, 118, 87, 102, 103, 103, 103, 103, 135, 103, 103, 120, 134, 119, 102, 117, 87, 104, 119, 119, 119, 118, 103, 118, 102
        .byte   135, 102, 134, 120, 87, 119, 102, 119, 118, 103, 102, 119, 120, 102, 134, 118, 118, 87, 119, 118, 102, 119, 134, 118, 102, 119, 118, 88, 119, 120, 103, 120
        .byte   104, 119, 119, 120, 119, 119, 117, 136, 118, 119, 134, 118, 118, 118, 118, 135, 119, 119, 118, 103, 120, 119, 119, 119, 134, 118, 103, 104, 118, 119, 101, 118
        .byte   120, 85, 104, 118, 71, 87, 120, 117, 88, 118, 88, 119, 87, 134, 101, 135, 118, 101, 102, 120, 119, 133, 104, 118, 118, 103, 120, 119, 103, 104, 103, 118
        .byte   85, 119, 119, 135, 102, 103, 102, 120, 102, 135, 103, 103, 118, 87, 104, 101, 134, 118, 102, 118, 134, 87, 134, 118, 101, 118, 134, 118, 86, 118, 119, 118
        .byte   118, 103, 118, 119, 119, 86, 134, 102, 85, 102, 119, 120, 118, 120, 135, 135, 102, 120, 120, 119, 120, 135, 119, 118, 103, 120, 70, 86, 87, 117, 86, 86
        .byte   84, 103, 117, 83, 84, 70, 103, 87, 101, 102, 86, 51, 86, 98, 84, 114, 69, 113, 101, 100, 98, 118, 68, 67, 55, 102, 70, 86, 117, 101, 84, 103
        .byte   115, 102, 103, 118, 84, 102, 101, 22, 84, 38, 69, 87, 101, 35, 102, 102, 53, 38, 71, 54, 68, 71, 87, 54, 69, 101, 117, 86, 101, 101, 100, 117
        .byte   100, 69, 87, 117, 102, 69, 54, 70, 103, 86, 71, 116, 102, 118, 84, 99, 84, 86, 102, 86, 100, 87, 119, 85, 69, 116, 71, 86, 85, 71, 117, 71
        .byte   87, 55, 86, 120, 119, 135, 119, 120, 104, 103, 103, 136, 134, 120, 135, 119, 119, 120, 118, 135, 136, 134, 104, 120, 101, 103, 118, 119, 134, 103, 103, 118
        .byte   86, 134, 135, 135, 134, 102, 120, 88, 103, 120, 120, 118, 119, 103, 136, 133, 104, 118, 102, 136, 118, 103, 120, 118, 119, 136, 118, 119, 119, 119, 102, 120
        .byte   102, 120, 134, 119, 135, 136, 119, 135, 119, 120, 135, 135, 119, 135, 103, 119, 118, 135, 135, 135, 119, 103, 119, 135, 119, 135, 118, 119, 119, 136, 136, 135
        .byte   135, 120, 135, 119, 119, 120, 136, 136, 135, 135, 120, 136, 136, 135, 136, 120, 135, 136, 136, 135, 136, 135, 136, 135, 136, 120, 136, 120, 119, 120, 119, 119
        .byte   119, 119, 119, 119, 119, 118, 135, 119, 134, 118, 103, 119, 135, 136, 120, 120, 135, 136, 134, 135, 119, 136, 136, 119, 136, 118, 103, 118, 120, 119, 119, 119
        .byte   119, 135, 135, 119, 103, 103, 120, 120, 119, 119, 119, 120, 119, 119, 119, 119, 136, 120, 136, 136, 135, 119, 119, 102, 119, 119, 104, 104, 119, 118, 119, 118
        .byte   119, 119, 103, 119, 119, 118, 119, 118, 118, 120, 119, 102, 118, 119, 135, 119, 103, 119, 118, 119, 119, 136, 120, 135, 136, 136, 136, 120, 120, 119, 119, 118
        .byte   135, 136, 119, 135, 119, 119, 120, 120, 118, 103, 119, 119, 120, 118, 119, 103, 118, 118, 136, 104, 119, 119, 136, 119, 103, 136, 119, 119, 135, 119, 135, 102
        .byte   136, 103, 103, 103, 119, 119, 119, 104, 118, 120, 119, 134, 133, 118, 119, 118, 136, 104, 104, 119, 120, 120, 120, 118, 119, 136, 103, 103, 103, 86, 103, 120
        .byte   102, 119, 119, 136, 119, 135, 120, 119, 119, 120, 118, 120, 120, 104, 135, 136, 119, 120, 136, 119, 119, 136, 134, 120, 136, 136, 135, 119, 119, 120, 118, 134
        .byte   101, 120, 102, 103, 100, 86, 86, 120, 119, 118, 118, 86, 118, 119, 70, 71, 53, 103, 37, 102, 86, 117, 55, 87, 84, 85, 54, 102, 120, 119, 84, 102
        .byte   120, 71, 119, 120, 135, 117, 118, 118, 103, 87, 118, 103, 100, 85, 102, 119, 102, 103, 86, 103, 87, 102, 119, 119, 101, 134, 86, 116, 87, 119, 118, 87
        .byte   120, 69, 87, 103, 118, 103, 119, 135, 101, 101, 134, 136, 102, 101, 117, 117, 104, 120, 86, 134, 100, 101, 102, 88, 39, 101, 55, 86, 104, 118, 52, 119
        .byte   118, 70, 55, 88, 71, 85, 88, 104, 119, 119, 103, 119, 88, 119, 103, 118, 119, 120, 120, 119, 119, 135, 103, 103, 118, 86, 119, 103, 120, 102, 118, 104
        .byte   87, 103, 120, 119, 87, 120, 118, 119, 120, 119, 119, 135, 119, 119, 134, 119, 136, 118, 118, 136, 103, 87, 103, 118, 119, 103, 103, 87, 102, 119, 119, 102
        .byte   119, 104, 102, 119, 119, 118, 119, 119, 117, 119, 118, 88, 135, 136, 102, 120, 136, 103, 87, 103, 86, 119, 118, 120, 102, 102, 118, 119, 102, 118, 119, 119
        .byte   103, 103, 103, 119, 118, 119, 102, 119, 119, 103, 119, 119, 103, 135, 103, 119, 119, 134, 118, 119, 118, 119, 103, 136, 102, 120, 117, 119, 136, 104, 119, 102
        .byte   135, 104, 104, 120, 135, 119, 134, 119, 134, 103, 120, 118, 117, 119, 135, 104, 119, 120, 119, 119, 104, 119, 120, 119, 136, 102, 119, 102, 118, 119, 119, 119
        .byte   104, 103, 118, 119, 135, 102, 119, 104, 134, 119, 119, 120, 136, 119, 119, 120, 119, 136, 103, 134, 134, 118, 103, 119, 119, 118, 120, 103, 119, 101, 136, 118
        .byte   120, 118, 104, 135, 104, 118, 119, 135, 102, 119, 120, 120, 135, 120, 103, 120, 119, 120, 135, 103, 135, 103, 119, 135, 104, 104, 117, 103, 135, 87, 103, 102
        .byte   118, 102, 120, 119, 119, 104, 119, 120, 103, 135, 135, 119, 119, 118, 104, 119, 135, 103, 135, 118, 119, 120, 120, 119, 71, 118, 104, 119, 118, 135, 101, 103
        .byte   119, 103, 133, 86, 119, 117, 118, 120, 102, 104, 118, 120, 134, 104, 134, 118, 119, 119, 119, 119, 135, 120, 102, 103, 135, 119, 135, 103, 120, 119, 86, 119
        .byte   120, 135, 118, 119, 103, 119, 120, 119, 102, 119, 136, 119, 135, 119, 134, 135, 118, 135, 119, 136, 102, 104, 120, 70, 87, 136, 119, 86, 119, 103, 119, 102
        .byte   119, 133, 136, 102, 103, 117, 119, 86, 119, 135, 118, 119, 120, 118, 135, 103, 119, 135, 135, 101, 120, 101, 102, 117, 119, 102, 135, 119, 133, 136, 119, 102
        .byte   101, 118, 120, 103, 119, 117, 136, 119, 119, 134, 118, 118, 118, 120, 119, 103, 103, 119, 120, 119, 117, 136, 119, 103, 103, 119, 103, 120, 119, 119, 103, 71
        .byte   72, 117, 103, 119, 134, 116, 99, 119, 119, 69, 87, 134, 101, 118, 70, 71, 87, 118, 55, 150, 118, 117, 70, 119, 84, 87, 86, 103, 117, 101, 103, 102
        .byte   119, 103, 103, 119, 102, 103, 102, 119, 103, 119, 119, 121, 118, 118, 134, 134, 135, 103, 136, 118, 120, 135, 118, 135, 134, 119, 103, 86, 135, 118, 103, 118
        .byte   135, 102, 88, 117, 103, 88, 119, 104, 102, 103, 87, 135, 118, 103, 119, 118, 87, 136, 103, 103, 134, 86, 103, 134, 119, 102, 120, 135, 103, 103, 104, 135
        .byte   135, 103, 133, 102, 119, 118, 88, 119, 117, 69, 118, 118, 87, 120, 119, 87, 120, 87, 103, 136, 135, 87, 119, 133, 102, 119, 119, 119, 118, 88, 104, 103
        .byte   104, 103, 136, 134, 102, 119, 86, 69, 118, 119, 87, 102, 120, 117, 88, 119, 87, 134, 86, 119, 119, 118, 119, 104, 117, 135, 134, 103, 118, 119, 118, 134
        .byte   136, 119, 134, 136, 119, 135, 135, 119, 103, 119, 119, 118, 120, 120, 119, 135, 120, 118, 104, 119, 119, 103, 118, 88, 134, 134, 120, 104, 118, 119, 119, 103
        .byte   119, 119, 104, 119, 135, 136, 119, 118, 119, 135, 135, 119, 120, 119, 120, 134, 118, 120, 135, 118, 117, 103, 119, 103, 135, 135, 120, 103, 135, 103, 136, 88
        .byte   135, 103, 120, 103, 119, 134, 134, 102, 118, 134, 119, 120, 134, 120, 120, 136, 136, 120, 135, 119, 135, 119, 136, 119, 136, 135, 135, 118, 136, 119, 135, 118
        .byte   102, 104, 102, 119, 120, 87, 120, 120, 120, 103, 119, 118, 118, 88, 119, 86, 102, 117, 103, 117, 72, 102, 119, 87, 117, 85, 136, 87, 135, 101, 119, 134
        .byte   101, 119, 118, 103, 118, 133, 134, 119, 102, 134, 104, 119, 119, 135, 103, 118, 119, 119, 118, 119, 134, 119, 134, 118, 103, 120, 117, 84, 120, 119, 87, 134
        .byte   88, 119, 101, 101, 135, 103, 88, 117, 118, 120, 119, 118, 103, 103, 117, 101, 118, 102, 104, 102, 119, 135, 101, 119, 104, 102, 104, 120, 119, 136, 118, 134
        .byte   119, 119, 119, 103, 135, 133, 134, 119, 119, 119, 103, 118, 119, 119, 103, 119, 134, 118, 135, 135, 87, 119, 119, 119, 135, 103, 119, 119, 119, 134, 119, 120
        .byte   119, 136, 104, 120, 104, 135, 104, 118, 136, 135, 87, 118, 103, 118, 103, 135, 135, 119, 119, 119, 117, 120, 119, 103, 104, 104, 120, 102, 120, 134, 104, 103
        .byte   119, 136, 104, 119, 135, 120, 135, 120, 135, 119, 136, 120, 135, 120, 120, 120, 103, 136, 135, 135, 119, 118, 119, 119, 136, 119, 135, 119, 135, 120, 119, 120
        .byte   120, 136, 102, 104, 136, 119, 103, 118, 118, 118, 120, 134, 136, 119, 117, 119, 119, 120, 118, 119, 135, 119, 119, 135, 104, 120, 103, 103, 136, 119, 135, 135
        .byte   120, 135, 119, 104, 135, 136, 120, 136, 136, 136, 135, 119, 135, 104, 119, 103, 135, 120, 120, 102, 118, 119, 120, 135, 135, 135, 120, 118, 120, 136, 119, 120
        .byte   120, 136, 120, 135, 136, 120, 135, 120, 136, 120, 120, 120, 136, 118, 104, 134, 119, 118, 103, 119, 119, 119, 119, 135, 119, 118, 136, 119, 119, 136, 119, 136
        .byte   118, 135, 119, 120, 120, 119, 118, 119, 119, 119, 101, 119, 120, 104, 120, 103, 120, 102, 120, 118, 103, 104, 120, 136, 119, 120, 120, 102, 135, 135, 119, 119
        .byte   134, 120, 120, 104, 135, 136, 120, 119, 120, 118, 119, 102, 103, 134, 103, 87, 120, 135, 87, 118, 88, 103, 87, 118, 119, 120, 118, 120, 103, 104, 119, 120
        .byte   103, 104, 103, 103, 119, 120, 103, 119, 120, 136, 135, 136, 134, 134, 135, 136, 119, 119, 135, 134, 119, 135, 119, 87, 120, 102, 120, 119, 135, 118, 119, 102
        .byte   103, 135, 119, 119, 100, 87, 119, 119, 87, 120, 119, 87, 133, 118, 103, 85, 118, 135, 119, 135, 119, 119, 119, 120, 101, 119, 134, 118, 119, 119, 134, 102
        .byte   119, 136, 119, 118, 117, 120, 135, 103, 135, 119, 119, 119, 136, 102, 118, 134, 119, 120, 119, 119, 119, 103, 119, 120, 119, 120, 119, 118, 119, 119, 120, 103
        .byte   120, 134, 103, 103, 119, 102, 103, 118, 135, 103, 87, 118, 119, 119, 103, 104, 120, 88, 103, 103, 103, 104, 119, 119, 88, 119, 102, 103, 136, 135, 135, 136
        .byte   119, 136, 134, 120, 120, 119, 136, 136, 119, 118, 135, 120, 118, 134, 119, 119, 135, 119, 135, 135, 135, 119, 134, 135, 119, 135, 119, 118, 120, 136, 87, 134
        .byte   120, 120, 136, 120, 103, 119, 119, 103, 135, 136, 136, 120, 136, 120, 120, 120, 120, 136, 119, 136, 104, 120, 120, 119, 119, 136, 135, 151, 136, 136, 136, 136
        .byte   137, 151, 120, 136, 152, 136, 136, 136, 135, 135, 135, 119, 136, 135, 135, 120, 135, 119, 136, 136, 136, 119, 136, 119, 136, 135, 120, 136, 103, 151, 135, 136
        .byte   135, 135, 134, 136, 120, 135, 103, 136, 120, 120, 135, 118, 119, 120, 136, 120, 120, 135, 120, 120, 136, 118, 136, 137, 136, 135, 119, 120, 103, 120, 136, 136
        .byte   120, 136, 135, 136, 119, 120, 120, 136, 120, 119, 136, 136, 135, 136, 119, 119, 136, 136, 119, 104, 119, 101, 104, 118, 119, 135, 135, 119, 119, 103, 120, 103
        .byte   119, 103, 118, 119, 117, 119, 118, 119, 119, 104, 119, 119, 134, 120, 103, 134, 134, 134, 115, 119, 133, 120, 133, 102, 118, 133, 71, 100, 118, 120, 118, 72
        .byte   119, 101, 119, 134, 136, 135, 119, 102, 134, 118, 120, 119, 102, 119, 101, 88, 135, 119, 120, 117, 103, 136, 119, 119, 135, 118, 136, 119, 135, 134, 135, 117
        .byte   103, 104, 115, 70, 103, 120, 101, 101, 117, 134, 100, 71, 120, 117, 104, 87, 119, 133, 104, 118, 104, 118, 135, 135, 118, 102, 119, 134, 119, 103, 118, 103
        .byte   118, 120, 120, 119, 119, 119, 119, 103, 135, 134, 119, 119, 104, 119, 119, 120, 135, 119, 103, 136, 119, 119, 119, 135, 120, 118, 71, 103, 103, 119, 104, 103
        .byte   87, 87, 135, 103, 119, 88, 87, 120, 119, 103, 119, 119, 103, 119, 119, 119, 104, 119, 134, 118, 119, 119, 135, 134, 120, 103, 86, 71, 103, 87, 135, 103
        .byte   118, 133, 118, 117, 119, 118, 118, 134, 103, 103, 103, 120, 119, 136, 118, 120, 102, 103, 134, 87, 135, 119, 120, 118, 119, 119, 119, 118, 135, 118, 135, 135
        .byte   120, 119, 103, 119, 102, 120, 103, 104, 120, 103, 120, 119, 135, 118, 119, 135, 120, 117, 118, 136, 103, 103, 103, 103, 133, 120, 118, 117, 120, 72, 135, 87
        .byte   103, 101, 119, 118, 134, 118, 118, 119, 134, 118, 86, 120, 118, 135, 103, 103, 135, 103, 119, 117, 87, 134, 134, 119, 88, 134, 103, 87, 118, 119, 102, 116
        .byte   119, 102, 117, 86, 119, 103, 71, 120, 119, 87, 104, 102, 118, 120, 134, 87, 118, 119, 84, 119, 119, 88, 119, 103, 119, 104, 135, 104, 119, 86, 104, 120
        .byte   119, 102, 119, 119, 118, 119, 119, 102, 120, 103, 120, 103, 135, 119, 119, 136, 135, 118, 120, 119, 119, 119, 103, 119, 120, 135, 103, 135, 103, 102, 103, 118
        .byte   102, 118, 102, 118, 85, 119, 116, 134, 117, 102, 135, 117, 103, 135, 119, 119, 119, 119, 103, 103, 135, 103, 118, 120, 103, 120, 120, 103, 118, 118, 136, 119
        .byte   118, 118, 104, 119, 119, 119, 120, 135, 119, 135, 136, 118, 120, 135, 119, 119, 120, 119, 102, 119, 136, 120, 119, 135, 135, 103, 103, 102, 88, 119, 70, 118
        .byte   87, 103, 87, 103, 118, 119, 87, 120, 116, 103, 84, 86, 135, 118, 103, 103, 117, 87, 102, 118, 87, 119, 101, 118, 119, 104, 119, 119, 120, 103, 102, 119
        .byte   119, 135, 118, 119, 136, 135, 135, 120, 103, 135, 120, 120, 135, 135, 135, 135, 104, 120, 136, 136, 119, 135, 119, 104, 120, 134, 136, 119, 119, 119, 103, 120
        .byte   119, 135, 135, 135, 136, 120, 119, 104, 120, 136, 87, 103, 103, 135, 103, 119, 151, 119, 134, 118, 72, 102, 87, 135, 103, 136, 85, 104, 119, 87, 101, 88
        .byte   119, 87, 120, 104, 135, 119, 103, 136, 134, 119, 136, 120, 120, 119, 120, 136, 104, 136, 119, 119, 120, 87, 134, 104, 135, 118, 119, 103, 135, 118, 102, 135
        .byte   119, 120, 119, 104, 136, 120, 134, 120, 134, 120, 120, 120, 120, 135, 103, 87, 104, 103, 118, 102, 119, 118, 118, 134, 118, 119, 103, 119, 120, 117, 150, 119
        .byte   119, 120, 103, 135, 118, 103, 118, 137, 135, 119, 103, 88, 119, 134, 117, 104, 119, 135, 104, 119, 119, 102, 120, 119, 119, 119, 119, 119, 119, 118, 119, 120
        .byte   119, 118, 136, 120, 136, 119, 119, 102, 119, 119, 103, 104, 119, 85, 86, 136, 104, 117, 104, 135, 102, 71, 119, 120, 104, 88, 102, 120, 85, 119, 118, 72
        .byte   119, 104, 103, 120, 103, 88, 135, 87, 104, 119, 119, 120, 136, 86, 103, 120, 120, 119, 134, 103, 119, 119, 120, 134, 120, 120, 119, 120, 120, 119, 104, 118
        .byte   119, 120, 119, 104, 135, 135, 119, 135, 119, 135, 119, 119, 118, 135, 134, 102, 135, 119, 119, 119, 119, 119, 135, 152, 119, 135, 136, 135, 118, 120, 136, 119
        .byte   136, 136, 135, 135, 135, 135, 135, 117, 118, 136, 118, 120, 119, 136, 134, 134, 135, 135, 134, 134, 118, 136, 136, 119, 88, 120, 119, 135, 119, 135, 118, 136
        .byte   136, 119, 103, 103, 103, 120, 103, 120, 119, 119, 120, 119, 136, 103, 119, 119, 119, 136, 120, 135, 103, 135, 134, 119, 104, 135, 120, 134, 103, 136, 135, 135
        .byte   136, 119, 134, 119, 102, 119, 135, 87, 136, 104, 119, 103, 120, 118, 119, 104, 118, 120, 135, 135, 119, 134, 118, 136, 120, 135, 118, 120, 120, 120, 120, 117
        .byte   120, 85, 102, 118, 72, 118, 104, 103, 119, 104, 87, 118, 87, 104, 134, 88, 102, 134, 135, 104, 134, 119, 136, 118, 87, 118, 120, 119, 120, 120, 119, 120
        .byte   136, 135, 118, 136, 136, 135, 120, 135, 135, 136, 119, 119, 120, 133, 88, 134, 134, 120, 88, 119, 104, 88, 118, 120, 118, 116, 104, 120, 104, 120, 71, 135
        .byte   87, 119, 104, 135, 87, 104, 119, 119, 88, 135, 104, 135, 119, 103, 103, 104, 119, 119, 134, 135, 135, 119, 120, 135, 135, 119, 119, 135, 119, 103, 135, 119
        .byte   119, 120, 119, 119, 120, 135, 118, 103, 117, 120, 136, 71, 135, 120, 104, 120, 104, 87, 103, 119, 87, 120, 136, 103, 135, 119, 104, 118, 118, 119, 119, 120
        .byte   120, 118, 120, 136, 118, 103, 136, 136, 119, 120, 136, 135, 119, 135, 136, 120, 120, 135, 136, 119, 103, 119, 103, 136, 118, 135, 103, 119, 103, 120, 134, 119
        .byte   120, 103, 120, 135, 120, 136, 120, 120, 119, 135, 136, 135, 119, 120, 120, 120, 136, 119, 136, 118, 102, 119, 103, 119, 102, 103, 119, 87, 103, 118, 135, 117
        .byte   88, 118, 119, 135, 135, 136, 135, 135, 136, 119, 119, 120, 134, 134, 120, 120, 119, 133, 87, 101, 103, 119, 103, 120, 104, 118, 104, 119, 119, 102, 135, 118
        .byte   118, 101, 104, 119, 120, 103, 88, 119, 104, 119, 135, 119, 134, 135, 102, 135, 119, 120, 120, 119, 120, 119, 135, 119, 135, 119, 118, 136, 119, 104, 103, 118
        .byte   118, 136, 118, 87, 104, 119, 104, 120, 117, 103, 119, 118, 135, 102, 120, 104, 135, 85, 103, 120, 134, 103, 120, 119, 119, 102, 133, 118, 119, 117, 120, 101
        .byte   119, 119, 117, 117, 103, 100, 86, 136, 85, 135, 71, 135, 87, 118, 119, 104, 119, 135, 102, 120, 118, 120, 118, 87, 119, 118, 103, 56, 70, 103, 102, 71
        .byte   135, 70, 102, 118, 119, 116, 100, 103, 84, 118, 120, 119, 118, 103, 119, 71, 118, 86, 119, 118, 119, 117, 103, 117, 120, 117, 103, 135, 120, 134, 88, 136
        .byte   104, 103, 102, 135, 118, 133, 134, 104, 120, 118, 135, 88, 101, 103, 119, 103, 103, 118, 135, 119, 135, 118, 135, 119, 119, 136, 119, 135, 119, 103, 104, 120
        .byte   135, 118, 135, 118, 104, 117, 119, 118, 118, 117, 119, 86, 87, 102, 88, 118, 71, 103, 88, 119, 118, 118, 135, 120, 104, 135, 135, 102, 104, 119, 119, 119
        .byte   87, 119, 133, 86, 133, 101, 119, 101, 87, 88, 119, 87, 103, 100, 103, 103, 117, 119, 133, 133, 102, 119, 118, 119, 120, 103, 136, 118, 103, 104, 119, 103
        .byte   103, 119, 104, 118, 120, 119, 119, 135, 118, 119, 119, 135, 135, 102, 135, 103, 119, 119, 118, 103, 119, 103, 118, 135, 119, 103, 119, 119, 102, 87, 103, 120
        .byte   136, 136, 134, 120, 120, 135, 119, 119, 135, 119, 120, 137, 135, 118, 118, 103, 119, 119, 104, 118, 117, 120, 136, 102, 118, 118, 119, 119, 87, 119, 119, 135
        .byte   119, 135, 134, 104, 121, 120, 118, 135, 120, 103, 135, 135, 120, 119, 103, 119, 134, 120, 135, 135, 120, 119, 103, 120, 119, 103, 103, 103, 102, 120, 120, 104
        .byte   87, 136, 118, 118, 136, 136, 118, 88, 119, 104, 117, 86, 103, 103, 104, 119, 135, 119, 103, 119, 118, 103, 118, 134, 103, 119, 119, 118, 120, 136, 119, 134
        .byte   120, 136, 119, 136, 120, 135, 120, 135, 135, 118, 119, 103, 118, 120, 119, 119, 135, 103, 102, 135, 119, 134, 87, 103, 118, 103, 117, 103, 118, 117, 118, 134
        .byte   134, 102, 87, 136, 104, 87, 118, 102, 119, 135, 119, 134, 119, 120, 135, 103, 118, 119, 120, 119, 120, 119, 118, 104, 119, 102, 120, 101, 118, 135, 102, 119
        .byte   118, 118, 101, 119, 119, 134, 102, 120, 118, 135, 118, 120, 119, 133, 104, 119, 119, 120, 118, 119, 102, 103, 135, 118, 118, 135, 88, 136, 119, 120, 119, 102
        .byte   119, 118, 120, 71, 86, 119, 119, 86, 135, 87, 119, 119, 135, 133, 101, 118, 101, 119, 102, 120, 118, 120, 119, 119, 120, 119, 103, 104, 119, 120, 119, 120
        .byte   118, 134, 120, 135, 103, 119, 135, 120, 135, 119, 135, 134, 118, 120, 119, 102, 119, 100, 136, 134, 117, 103, 120, 87, 135, 134, 119, 135, 118, 133, 135, 102
        .byte   103, 135, 69, 87, 120, 119, 86, 119, 102, 119, 102, 118, 133, 134, 134, 102, 136, 103, 120, 89, 119, 103, 119, 118, 119, 119, 119, 119, 104, 119, 102, 119
        .byte   135, 119, 104, 119, 119, 103, 135, 102, 118, 151, 119, 104, 135, 119, 104, 120, 104, 136, 103, 119, 135, 119, 136, 119, 135, 151, 88, 104, 103, 119, 119, 104
        .byte   103, 102, 135, 103, 88, 119, 120, 136, 117, 119, 118, 134, 118, 119, 135, 102, 118, 103, 135, 135, 103, 117, 118, 88, 118, 118, 133, 103, 103, 117, 87, 103
        .byte   119, 118, 116, 118, 119, 86, 134, 103, 71, 52, 118, 102, 70, 102, 103, 100, 104, 119, 72, 118, 71, 104, 118, 87, 118, 102, 103, 102, 119, 117, 102, 87
        .byte   119, 88, 70, 87, 103, 118, 85, 71, 117, 103, 86, 118, 134, 119, 86, 104, 117, 104, 117, 103, 119, 102, 103, 135, 103, 119, 104, 120, 135, 103, 117, 118
        .byte   119, 117, 103, 135, 135, 135, 119, 119, 120, 119, 136, 119, 135, 135, 136, 119, 135, 119, 102, 102, 103, 134, 104, 118, 104, 103, 118, 102, 117, 87, 120, 120
        .byte   87, 103, 87, 87, 104, 119, 119, 104, 119, 118, 119, 104, 103, 135, 120, 118, 119, 120, 103, 119, 120, 118, 118, 104, 103, 135, 119, 103, 119, 135, 118, 136
        .byte   119, 119, 135, 135, 120, 119, 103, 135, 135, 102, 135, 119, 136, 119, 119, 102, 119, 134, 118, 119, 120, 118, 103, 136, 135, 119, 87, 135, 120, 119, 102, 102
        .byte   118, 119, 117, 119, 135, 118, 119, 118, 134, 119, 118, 103, 103, 136, 120, 136, 119, 119, 119, 136, 119, 135, 120, 120, 119, 135, 134, 119, 88, 119, 103, 136
        .byte   134, 120, 103, 136, 136, 104, 136, 118, 104, 118, 135, 120, 119, 121, 119, 104, 119, 136, 135, 135, 135, 136, 119, 104, 136, 134, 135, 120, 135, 135, 136, 104
        .byte   119, 119, 120, 136, 103, 119, 119, 136, 152, 135, 103, 135, 120, 119, 135, 135, 119, 120, 136, 134, 120, 135, 104, 134, 135, 136, 119, 118, 135, 134, 120, 119
        .byte   118, 135, 119, 136, 120, 119, 119, 103, 119, 134, 104, 134, 119, 120, 102, 119, 104, 88, 103, 135, 104, 120, 136, 119, 135, 120, 135, 104, 135, 136, 135, 120
        .byte   135, 136, 136, 120, 119, 117, 118, 119, 101, 101, 119, 135, 119, 102, 119, 118, 134, 103, 120, 135, 103, 119, 119, 120, 119, 119, 135, 120, 104, 151, 135, 135
        .byte   102, 136, 135, 88, 102, 118, 135, 135, 117, 120, 119, 104, 135, 135, 118, 134, 135, 135, 118, 118, 135, 134, 134, 119, 120, 119, 136, 135, 120, 135, 135, 119
        .byte   135, 135, 103, 135, 136, 119, 120, 135, 104, 120, 135, 119, 135, 119, 119, 120, 103, 119, 134, 120, 117, 120, 135, 135, 120, 103, 120, 119, 119, 120, 119, 120
        .byte   135, 118, 119, 119, 136, 119, 119, 103, 136, 119, 119, 104, 119, 119, 103, 119, 87, 119, 133, 120, 117, 71, 119, 119, 102, 103, 101, 119, 70, 119, 87, 119
        .byte   119, 119, 118, 133, 104, 118, 118, 119, 103, 117, 119, 103, 120, 119, 119, 119, 135, 119, 104, 134, 119, 102, 119, 136, 120, 119, 119, 102, 118, 102, 136, 117
        .byte   135, 135, 103, 103, 104, 120, 119, 103, 120, 119, 103, 120, 119, 119, 133, 134, 118, 119, 103, 120, 103, 118, 103, 134, 120, 103, 120, 119, 135, 120, 119, 87
        .byte   118, 135, 134, 120, 102, 136, 134, 120, 120, 119, 135, 136, 120, 135, 120, 136, 120, 120, 134, 136, 118, 136, 135, 120, 118, 101, 136, 118, 119, 118, 102, 119
        .byte   119, 102, 136, 104, 118, 136, 135, 120, 135, 135, 119, 103, 136, 119, 120, 134, 134, 135, 136, 119, 135, 136, 135, 119, 136, 119, 120, 120, 135, 136, 136, 104
        .byte   136, 136, 120, 119, 119, 135, 118, 118, 119, 135, 120, 120, 103, 119, 88, 136, 118, 120, 119, 118, 103, 119, 136, 118, 136, 119, 135, 118, 119, 135, 135, 135
        .byte   119, 134, 102, 119, 103, 119, 119, 119, 103, 119, 119, 119, 119, 119, 119, 135, 135, 120, 136, 120, 120, 120, 120, 135, 119, 135, 134, 135, 136, 136, 135, 86
        .byte   103, 119, 119, 102, 103, 134, 135, 119, 134, 134, 102, 103, 119, 103, 103, 118, 118, 85, 135, 86, 103, 119, 118, 133, 135, 100, 103, 119, 103, 134, 134, 152
        .byte   119, 103, 119, 119, 119, 119, 119, 119, 134, 120, 119, 119, 118, 100, 119, 117, 135, 117, 119, 134, 133, 134, 103, 118, 86, 119, 117, 134, 119, 103, 134, 119
        .byte   135, 134, 104, 119, 119, 119, 135, 134, 119, 134, 120, 135, 135, 104, 119, 119, 135, 119, 119, 120, 120, 102, 136, 136, 119, 136, 120, 119, 119, 136, 120, 135
        .byte   119, 119, 135, 104, 136, 136, 119, 120, 135, 135, 119, 136, 120, 118, 119, 120, 135, 120, 119, 135, 119, 119, 135, 120, 119, 102, 119, 103, 87, 135, 119, 118
        .byte   135, 103, 119, 135, 102, 104, 88, 134, 103, 118, 133, 119, 120, 102, 118, 119, 103, 119, 102, 119, 118, 103, 87, 103, 133, 104, 134, 135, 86, 118, 103, 119
        .byte   119, 118, 118, 118, 103, 119, 86, 102, 120, 135, 118, 120, 118, 135, 102, 119, 119, 103, 103, 103, 118, 86, 118, 118, 119, 103, 119, 119, 119, 88, 118, 103
        .byte   119, 103, 136, 120, 135, 120, 136, 136, 136, 120, 120, 120, 119, 135, 135, 136, 135, 119, 104, 135, 133, 103, 119, 134, 103, 103, 134, 103, 119, 119, 119, 118
        .byte   120, 119, 119, 118, 136, 103, 119, 120, 118, 120, 136, 119, 135, 104, 135, 120, 119, 136, 135, 136, 118, 136, 135, 135, 120, 120, 120, 119, 119, 135, 119, 133
        .byte   118, 118, 104, 118, 103, 135, 134, 134, 120, 118, 104, 120, 119, 119, 117, 104, 136, 120, 119, 120, 135, 120, 134, 104, 135, 104, 136, 134, 135, 119, 104, 119
        .byte   135, 120, 120, 136, 119, 136, 135, 119, 135, 135, 134, 136, 135, 120, 136, 136, 120, 136, 152, 136, 136, 136, 136, 120, 135, 135, 119, 137, 135, 103, 135, 135
        .byte   119, 119, 119, 136, 119, 104, 136, 135, 103, 136, 136, 136, 120, 120, 120, 119, 119, 135, 120, 120, 136, 120, 136, 119, 119, 103, 120, 120, 136, 136, 136, 120
        .byte   135, 136, 119, 119, 135, 136, 135, 136, 136, 136, 136, 135, 135, 120, 136, 136, 120, 136, 136, 136, 119, 120, 135, 135, 135, 135, 120, 136, 136, 120, 119, 136
        .byte   120, 119, 120, 135, 104, 119, 103, 103, 136, 136, 119, 136, 136, 135, 136, 135, 119, 119, 120, 136, 135, 103, 136, 120, 119, 135, 135, 119, 135, 119, 118, 134
        .byte   134, 119, 104, 87, 134, 136, 136, 104, 103, 134, 135, 136, 102, 134, 135, 103, 119, 119, 118, 134, 103, 119, 121, 119, 118, 120, 120, 133, 103, 135, 134, 103
        .byte   135, 134, 135, 135, 119, 118, 120, 104, 136, 120, 120, 119, 136, 119, 120, 136, 118, 135, 118, 103, 119, 118, 120, 119, 120, 103, 104, 118, 135, 118, 88, 135
        .byte   136, 119, 119, 135, 135, 118, 136, 120, 119, 120, 135, 120, 119, 120, 135, 119, 118, 119, 135, 119, 103, 120, 119, 120, 102, 104, 135, 119, 120, 134, 119, 135
        .byte   119, 134, 119, 135, 135, 104, 120, 103, 119, 119, 119, 135, 134, 116, 119, 117, 135, 133, 119, 135, 117, 133, 119, 135, 85, 119, 134, 135, 119, 119, 104, 134
        .byte   120, 135, 136, 119, 119, 134, 136, 134, 118, 135, 136, 135, 119, 118, 134, 104, 120, 119, 104, 120, 119, 87, 136, 118, 120, 134, 135, 136, 119, 119, 136, 136
        .byte   118, 136, 120, 120, 103, 120, 135, 135, 103, 119, 120, 119, 119, 134, 119, 119, 134, 103, 119, 119, 135, 119, 119, 119, 135, 136, 118, 135, 120, 87, 136, 103
        .byte   103, 135, 118, 118, 134, 136, 135, 119, 120, 119, 120, 120, 134, 136, 120, 135, 118, 134, 136, 120, 119, 136, 119, 119, 119, 120, 120, 134, 119, 135, 135, 136
        .byte   119, 119, 104, 136, 103, 120, 120, 103, 120, 119, 135, 103, 135, 119, 135, 103, 135, 135, 118, 119, 118, 135, 135, 135, 135, 120, 136, 135, 119, 134, 120, 120
        .byte   136, 119, 136, 120, 136, 104, 120, 120, 136, 118, 136, 136, 120, 135, 120, 136, 135, 150, 119, 152, 119, 103, 151, 102, 119, 120, 120, 119, 119, 120, 120, 120
        .byte   136, 119, 119, 119, 120, 135, 135, 136, 135, 118, 104, 136, 135, 120, 120, 135, 135, 136, 136, 119, 136, 119, 120, 136, 120, 135, 135, 135, 136, 103, 102, 119
        .byte   120, 103, 118, 120, 103, 103, 104, 86, 119, 105, 101, 102, 119, 103, 103, 104, 135, 103, 119, 103, 118, 120, 118, 87, 119, 119, 118, 118, 119, 103, 119, 119
        .byte   136, 135, 119, 118, 119, 135, 135, 120, 119, 118, 120, 118, 119, 86, 119, 119, 119, 119, 120, 119, 135, 104, 119, 136, 120, 104, 103, 135, 118, 119, 135, 117
        .byte   119, 119, 119, 120, 119, 134, 119, 135, 103, 136, 104, 118, 135, 135, 118, 134, 120, 120, 121, 119, 120, 135, 151, 135, 135, 119, 135, 104, 120, 135, 136, 119
        .byte   119, 119, 135, 136, 120, 119, 118, 103, 118, 119, 103, 104, 119, 118, 102, 87, 101, 103, 120, 103, 102, 101, 88, 101, 102, 119, 118, 102, 119, 118, 119, 118
        .byte   102, 103, 119, 102, 135, 118, 136, 120, 135, 135, 119, 119, 120, 119, 134, 120, 119, 135, 120, 120, 119, 118, 118, 117, 135, 118, 118, 119, 103, 120, 119, 103
        .byte   119, 134, 119, 119, 120, 119, 118, 136, 119, 135, 118, 134, 118, 119, 119, 103, 119, 117, 119, 103, 101, 102, 120, 102, 120, 119, 119, 119, 119, 120, 134, 87
        .byte   120, 118, 134, 104, 120, 134, 136, 119, 87, 120, 88, 136, 103, 135, 118, 119, 119, 103, 104, 135, 118, 120, 120, 119, 120, 120, 135, 119, 133, 118, 119, 119
        .byte   120, 101, 135, 120, 102, 119, 104, 119, 103, 120, 103, 120, 103, 104, 136, 120, 135, 136, 120, 135, 119, 119, 103, 136, 135, 120, 120, 120, 135, 134, 136, 136
        .byte   119, 119, 135, 118, 119, 119, 104, 135, 119, 136, 119, 120, 119, 134, 118, 134, 118, 134, 136, 119, 117, 118, 120, 119, 135, 135, 103, 103, 118, 118, 135, 134
        .byte   119, 119, 135, 135, 119, 118, 135, 120, 135, 119, 120, 104, 120, 119, 120, 136, 103, 120, 135, 119, 120, 119, 120, 136, 135, 118, 135, 120, 119, 117, 119, 120
        .byte   134, 104, 102, 103, 103, 120, 118, 88, 136, 119, 136, 134, 118, 135, 119, 135, 119, 103, 119, 119, 120, 134, 136, 104, 88, 103, 120, 119, 119, 119, 135, 118
        .byte   120, 135, 103, 119, 103, 136, 119, 120, 118, 136, 119, 136, 119, 136, 120, 134, 119, 120, 120, 120, 119, 120, 135, 136, 136, 104, 120, 120, 119, 135, 120, 136
        .byte   104, 120, 135, 136, 136, 119, 120, 103, 136, 135, 136, 120, 119, 88, 104, 120, 136, 119, 104, 119, 119, 136, 134, 135, 104, 119, 120, 136, 119, 135, 104, 118
        .byte   136, 120, 119, 152, 132, 119, 133, 119, 117, 88, 135, 119, 117, 119, 135, 85, 136, 103, 136, 103, 135, 119, 134, 118, 135, 133, 119, 136, 136, 118, 119, 119
        .byte   103, 120, 103, 119, 120, 134, 103, 136, 119, 104, 88, 104, 120, 135, 120, 119, 104, 121, 134, 136, 120, 136, 133, 134, 120, 135, 119, 119, 119, 118, 136, 104
        .byte   120, 103, 136, 104, 135, 119, 135, 88, 119, 119, 120, 104, 120, 117, 135, 135, 102, 119, 135, 103, 119, 136, 103, 134, 120, 103, 120, 136, 135, 136, 135, 120
        .byte   103, 136, 135, 120, 136, 120, 119, 135, 119, 103, 135, 119, 103, 118, 135, 118, 102, 118, 102, 88, 120, 119, 86, 104, 135, 118, 119, 117, 103, 118, 120, 103
        .byte   120, 119, 102, 119, 120, 119, 119, 134, 119, 119, 119, 120, 135, 136, 135, 119, 103, 118, 135, 135, 120, 103, 135, 135, 103, 134, 119, 119, 136, 135, 103, 120
        .byte   135, 119, 118, 104, 119, 119, 119, 134, 102, 118, 118, 135, 117, 118, 120, 103, 119, 120, 103, 119, 118, 136, 135, 119, 119, 103, 136, 118, 118, 119, 120, 135
        .byte   119, 119, 120, 135, 119, 119, 135, 135, 136, 136, 136, 119, 136, 135, 120, 120, 136, 136, 135, 120, 119, 102, 120, 119, 103, 118, 135, 134, 86, 120, 136, 103
        .byte   103, 119, 103, 120, 136, 136, 119, 120, 120, 119, 120, 135, 119, 136, 103, 104, 120, 119, 136, 102, 136, 119, 120, 135, 119, 104, 134, 103, 120, 119, 120, 119
        .byte   120, 119, 118, 86, 120, 120, 103, 120, 104, 104, 120, 104, 119, 103, 136, 103, 134, 117, 102, 119, 119, 135, 119, 104, 104, 103, 135, 119, 118, 134, 120, 136
        .byte   120, 136, 120, 119, 119, 120, 136, 135, 136, 135, 119, 119, 136, 104, 135, 120, 102, 119, 136, 135, 119, 135, 118, 135, 119, 103, 103, 135, 117, 103, 120, 103
        .byte   103, 135, 135, 117, 136, 118, 119, 135, 119, 135, 120, 119, 118, 134, 119, 104, 119, 103, 120, 119, 118, 118, 117, 134, 119, 104, 118, 135, 119, 119, 119, 120
        .byte   135, 135, 119, 136, 119, 104, 119, 135, 104, 119, 118, 103, 119, 134, 120, 119, 120, 102, 135, 119, 119, 104, 88, 135, 135, 119, 120, 136, 136, 119, 136, 119
        .byte   119, 136, 136, 134, 135, 120, 119, 120, 149, 120, 136, 119, 102, 134, 119, 102, 120, 120, 119, 103, 119, 103, 120, 136, 135, 136, 119, 119, 135, 118, 135, 119
        .byte   120, 135, 135, 135, 136, 120, 119, 118, 118, 119, 118, 118, 102, 134, 103, 119, 117, 102, 134, 118, 119, 103, 102, 118, 102, 119, 120, 134, 88, 119, 119, 120
        .byte   119, 103, 118, 120, 134, 118, 118, 117, 120, 118, 103, 135, 134, 119, 119, 119, 118, 102, 135, 119, 135, 119, 119, 119, 118, 120, 136, 136, 135, 103, 134, 134
        .byte   119, 119, 135, 103, 119, 134, 118, 119, 119, 135, 135, 119, 120, 118, 135, 134, 118, 103, 120, 135, 135, 135, 135, 134, 119, 119, 134, 119, 136, 118, 136, 119
        .byte   102, 120, 119, 135, 103, 133, 103, 135, 119, 120, 119, 120, 119, 103, 120, 86, 87, 103, 102, 119, 117, 103, 102, 103, 103, 103, 120, 134, 103, 119, 118, 101
        .byte   102, 120, 68, 118, 55, 101, 86, 102, 69, 101, 103, 69, 119, 133, 103, 102, 103, 103, 118, 103, 119, 118, 134, 119, 119, 119, 102, 119, 104, 119, 120, 104
        .byte   101, 104, 119, 119, 119, 104, 118, 103, 120, 118, 104, 134, 136, 133, 118, 134, 102, 118, 119, 87, 136, 119, 119, 118, 119, 118, 118, 102, 99, 100, 136, 116
        .byte   86, 119, 86, 117, 101, 118, 116, 132, 117, 119, 136, 118, 119, 136, 118, 103, 136, 120, 134, 119, 135, 135, 119, 119, 119, 119, 118, 120, 103, 120, 104, 104
        .byte   120, 118, 120, 104, 119, 119, 135, 135, 104, 120, 135, 119, 119, 119, 119, 103, 119, 120, 120, 103, 135, 151, 134, 119, 135, 119, 118, 135, 118, 117, 120, 103
        .byte   135, 118, 120, 118, 119, 135, 104, 119, 119, 119, 119, 136, 136, 120, 104, 120, 119, 135, 118, 135, 119, 118, 117, 103, 135, 118, 119, 104, 135, 135, 119, 120
        .byte   118, 118, 119, 136, 120, 135, 120, 120, 120, 119, 120, 119, 136, 135, 136, 119, 120, 136, 119, 134, 136, 119, 119, 119, 134, 103, 120, 119, 135, 134, 119, 134
        .byte   120, 102, 102, 118, 87, 118, 104, 134, 86, 103, 86, 101, 87, 102, 103, 104, 102, 102, 101, 133, 88, 103, 117, 102, 103, 70, 103, 102, 87, 101, 117, 117
        .byte   117, 100, 117, 120, 117, 87, 103, 102, 101, 116, 102, 133, 117, 117, 118, 119, 86, 119, 119, 118, 120, 103, 118, 119, 120, 119, 118, 104, 102, 120, 136, 134
        .byte   119, 103, 119, 135, 136, 119, 120, 136, 119, 119, 134, 119, 118, 118, 135, 135, 103, 118, 103, 120, 119, 119, 119, 118, 119, 135, 119, 135, 120, 120, 119, 136
        .byte   120, 103, 136, 120, 135, 135, 118, 135, 136, 136, 119, 119, 118, 102, 136, 119, 103, 135, 120, 134, 117, 120, 119, 103, 118, 120, 119, 103, 119, 119, 135, 119
        .byte   119, 134, 134, 104, 103, 135, 120, 118, 135, 102, 103, 134, 119, 103, 120, 119, 118, 135, 120, 119, 119, 119, 119, 119, 104, 118, 134, 135, 117, 119, 103, 120
        .byte   119, 104, 104, 135, 118, 120, 135, 102, 120, 119, 135, 119, 120, 118, 136, 119, 120, 136, 135, 104, 120, 135, 104, 119, 104, 135, 119, 136, 119, 136, 119, 119
        .byte   136, 119, 103, 135, 135, 120, 135, 118, 104, 134, 119, 135, 136, 134, 119, 119, 103, 135, 120, 119, 117, 118, 117, 119, 119, 103, 117, 103, 87, 85, 119, 85
        .byte   119, 70, 135, 135, 101, 135, 119, 120, 119, 119, 134, 104, 103, 135, 120, 119, 102, 134, 85, 101, 117, 119, 100, 103, 118, 117, 119, 119, 117, 135, 119, 86
        .byte   118, 118, 119, 134, 134, 117, 87, 134, 119, 103, 118, 118, 102, 103, 119, 119, 118, 102, 134, 135, 120, 103, 102, 136, 102, 117, 119, 102, 101, 134, 103, 119
        .byte   103, 119, 119, 134, 119, 103, 135, 119, 119, 134, 136, 135, 136, 135, 135, 135, 120, 135, 135, 120, 136, 135, 136, 136, 137, 103, 135, 119, 117, 102, 118, 119
        .byte   102, 101, 119, 102, 102, 134, 119, 104, 103, 103, 86, 103, 86, 103, 87, 133, 118, 103, 102, 117, 103, 103, 103, 117, 119, 100, 120, 135, 136, 104, 119, 120
        .byte   120, 120, 135, 119, 120, 119, 120, 136, 120, 117, 103, 135, 118, 103, 118, 104, 103, 134, 119, 102, 118, 119, 87, 119, 118, 71, 118, 133, 119, 101, 102, 87
        .byte   119, 101, 88, 119, 118, 101, 118, 118, 120, 103, 119, 120, 119, 120, 135, 135, 119, 135, 119, 103, 119, 119, 119, 119, 120, 118, 120, 120, 119, 136, 103, 119
        .byte   102, 119, 120, 135, 119, 104, 119, 103, 119, 104, 120, 104, 119, 103, 118, 86, 119, 118, 135, 102, 120, 135, 136, 119, 119, 136, 135, 119, 119, 102, 119, 119
        .byte   119, 119, 118, 86, 102, 119, 103, 102, 103, 102, 102, 87, 87, 103, 103, 118, 102, 118, 104, 119, 119, 103, 119, 103, 103, 134, 120, 104, 119, 119, 135, 87
        .byte   119, 119, 135, 119, 135, 86, 119, 134, 136, 118, 119, 119, 119, 119, 102, 120, 118, 103, 102, 101, 119, 133, 103, 118, 102, 119, 102, 119, 104, 119, 102, 120
        .byte   119, 120, 136, 120, 103, 119, 120, 118, 135, 135, 135, 136, 120, 120, 120, 136, 119, 135, 136, 119, 119, 135, 136, 119, 120, 135, 136, 119, 135, 135, 102, 119
        .byte   118, 119, 135, 119, 118, 119, 135, 103, 120, 119, 135, 87, 118, 119, 104, 133, 119, 136, 150, 134, 135, 117, 103, 136, 103, 135, 136, 87, 135, 102, 118, 118
        .byte   103, 118, 135, 117, 101, 102, 120, 102, 86, 118, 120, 119, 120, 118, 119, 118, 119, 119, 103, 118, 103, 120, 120, 104, 135, 134, 120, 136, 118, 103, 136, 135
        .byte   135, 119, 135, 119, 135, 119, 119, 120, 134, 118, 103, 119, 134, 118, 135, 150, 103, 103, 135, 118, 86, 117, 119, 120, 119, 119, 118, 135, 103, 102, 118, 103
        .byte   102, 119, 119, 101, 119, 102, 119, 119, 136, 117, 119, 120, 104, 119, 134, 119, 136, 88, 103, 136, 134, 101, 118, 102, 99, 102, 87, 87, 100, 116, 118, 117
        .byte   118, 135, 119, 100, 104, 86, 86, 118, 119, 87, 119, 116, 117, 132, 103, 99, 135, 102, 116, 119, 86, 102, 117, 86, 85, 119, 119, 103, 117, 72, 134, 134
        .byte   102, 117, 134, 119, 102, 118, 86, 136, 102, 120, 135, 104, 102, 135, 119, 101, 135, 119, 103, 119, 104, 119, 102, 103, 119, 104, 120, 120, 119, 135, 119, 119
        .byte   136, 87, 86, 87, 119, 71, 134, 119, 118, 88, 104, 117, 119, 86, 88, 136, 136, 118, 120, 104, 103, 120, 135, 120, 118, 120, 135, 136, 118, 119, 102, 102
        .byte   120, 71, 104, 118, 88, 103, 87, 103, 88, 136, 102, 135, 135, 118, 118, 119, 101, 119, 118, 102, 118, 119, 118, 102, 119, 104, 135, 104, 102, 119, 102, 119
        .byte   118, 118, 101, 119, 135, 87, 103, 117, 119, 103, 72, 88, 136, 104, 118, 119, 104, 103, 119, 119, 119, 104, 118, 118, 119, 120, 119, 119, 119, 119, 102, 118
        .byte   120, 134, 119, 104, 102, 103, 102, 119, 103, 120, 120, 135, 135, 119, 119, 120, 118, 119, 135, 120, 119, 119, 135, 119, 119, 120, 119, 103, 104, 135, 104, 118
        .byte   103, 119, 104, 136, 119, 117, 119, 117, 119, 118, 102, 103, 118, 119, 135, 103, 119, 103, 135, 136, 119, 118, 119, 136, 135, 135, 136, 120, 136, 134, 136, 120
        .byte   120, 136, 119, 135, 120, 104, 119, 102, 135, 103, 119, 119, 133, 103, 120, 119, 103, 118, 118, 103, 120, 119, 119, 119, 135, 119, 119, 135, 103, 120, 103, 134
        .byte   135, 118, 135, 103, 119, 103, 119, 119, 118, 103, 136, 119, 102, 88, 119, 119, 119, 120, 119, 135, 103, 103, 135, 102, 118, 134, 104, 119, 135, 119, 134, 101
        .byte   120, 119, 135, 119, 136, 136, 135, 120, 135, 120, 120, 135, 135, 135, 119, 136, 120, 86, 104, 120, 118, 103, 118, 118, 86, 103, 118, 133, 102, 119, 135, 120
        .byte   135, 119, 120, 120, 119, 119, 135, 136, 120, 120, 135, 119, 135, 119, 135, 118, 118, 135, 118, 118, 134, 119, 103, 119, 119, 119, 119, 135, 119, 119, 119, 120
        .byte   135, 87, 120, 102, 119, 134, 119, 120, 135, 102, 102, 118, 104, 119, 119, 119, 102, 87, 120, 119, 102, 104, 103, 103, 104, 133, 103, 120, 118, 103, 102, 101
        .byte   104, 133, 135, 119, 116, 103, 120, 117, 87, 104, 119, 136, 135, 103, 103, 103, 119, 118, 119, 103, 119, 118, 104, 135, 119, 102, 88, 103, 117, 120, 103, 70
        .byte   102, 119, 118, 120, 101, 133, 133, 118, 117, 135, 118, 132, 119, 119, 87, 117, 117, 135, 117, 134, 135, 103, 117, 118, 134, 119, 133, 120, 103, 117, 134, 104
        .byte   118, 104, 119, 103, 118, 119, 118, 104, 119, 133, 119, 118, 86, 103, 103, 135, 135, 118, 134, 134, 135, 118, 103, 103, 119, 103, 85, 119, 118, 118, 118, 120
        .byte   86, 104, 103, 103, 120, 119, 119, 120, 119, 103, 102, 119, 118, 102, 119, 119, 119, 103, 135, 119, 135, 136, 104, 134, 135, 119, 119, 135, 120, 120, 119, 135
        .byte   135, 104, 118, 119, 102, 118, 102, 119, 118, 120, 135, 104, 118, 135, 119, 101, 119, 102, 103, 103, 84, 103, 103, 133, 118, 103, 117, 85, 119, 103, 118, 103
        .byte   119, 118, 102, 118, 136, 103, 117, 119, 119, 117, 87, 118, 117, 71, 103, 103, 118, 86, 102, 120, 102, 103, 135, 101, 117, 103, 102, 134, 101, 133, 119, 120
        .byte   119, 103, 104, 118, 104, 103, 88, 135, 103, 118, 119, 118, 119, 136, 118, 119, 119, 120, 104, 136, 135, 119, 103, 120, 104, 135, 135, 119, 134, 135, 102, 133
        .byte   117, 71, 103, 118, 88, 120, 118, 87, 136, 103, 119, 119, 103, 119, 119, 119, 103, 135, 119, 119, 120, 119, 118, 120, 119, 136, 116, 117, 135, 87, 117, 101
        .byte   119, 134, 135, 102, 120, 117, 102, 118, 119, 119, 118, 120, 119, 119, 135, 119, 103, 119, 104, 120, 104, 120, 119, 136, 120, 134, 120, 87, 120, 119, 102, 119
        .byte   118, 103, 104, 119, 119, 134, 103, 136, 120, 136, 120, 136, 136, 136, 136, 120, 136, 119, 136, 135, 135, 136, 120, 119, 135, 119, 119, 135, 120, 136, 134, 136
        .byte   119, 119, 136, 120, 120, 103, 135, 134, 119, 119, 119, 135, 119, 103, 136, 136, 119, 120, 119, 120, 120, 135, 119, 119, 119, 119, 120, 135, 120, 119, 120, 134
        .byte   118, 135, 120, 119, 119, 135, 102, 120, 119, 119, 120, 119, 135, 121, 135, 135, 119, 135, 135, 119, 119, 118, 135, 136, 120, 119, 118, 135, 119, 120, 135, 120
        .byte   118, 86, 104, 118, 102, 119, 103, 118, 102, 118, 119, 102, 102, 118, 118, 101, 136, 119, 118, 120, 120, 119, 136, 135, 119, 136, 135, 104, 120, 119, 119, 136
        .byte   136, 134, 119, 136, 135, 136, 136, 120, 120, 120, 135, 120, 136, 135, 103, 117, 136, 118, 119, 118, 136, 119, 102, 119, 119, 104, 135, 135, 119, 87, 88, 119
        .byte   101, 120, 103, 118, 85, 117, 135, 86, 118, 117, 118, 100, 104, 136, 120, 119, 134, 119, 134, 102, 134, 120, 136, 135, 134, 103, 117, 119, 134, 120, 118, 133
        .byte   120, 120, 135, 118, 134, 118, 135, 135, 120, 135, 118, 119, 103, 134, 119, 135, 134, 119, 119, 134, 87, 135, 120, 120, 135, 103, 134, 135, 103, 119, 117, 120
        .byte   119, 120, 134, 135, 118, 136, 135, 120, 135, 135, 119, 134, 119, 134, 136, 135, 119, 119, 120, 104, 136, 119, 118, 119, 118, 119, 119, 136, 135, 119, 134, 119
        .byte   118, 118, 120, 119, 119, 136, 119, 104, 104, 120, 102, 88, 136, 119, 103, 119, 119, 134, 119, 120, 134, 134, 136, 136, 119, 119, 136, 119, 104, 120, 121, 120
        .byte   120, 134, 119, 135, 120, 135, 118, 119, 118, 120, 119, 135, 119, 120, 134, 136, 136, 117, 136, 119, 104, 120, 136, 120, 120, 135, 119, 135, 135, 119, 120, 104
        .byte   136, 136, 119, 120, 103, 119, 104, 120, 120, 102, 120, 119, 102, 120, 119, 119, 119, 135, 103, 120, 103, 119, 102, 119, 135, 136, 102, 119, 119, 134, 86, 119
        .byte   136, 135, 134, 135, 104, 119, 135, 136, 104, 120, 119, 135, 120, 135, 135, 120, 101, 87, 117, 119, 103, 87, 119, 71, 87, 103, 119, 117, 116, 117, 119, 118
        .byte   103, 118, 118, 86, 119, 119, 101, 134, 104, 118, 134, 119, 118, 117, 103, 103, 102, 118, 119, 134, 102, 119, 136, 87, 119, 120, 119, 104, 86, 119, 103, 116
        .byte   103, 102, 104, 101, 117, 119, 118, 119, 119, 119, 117, 103, 103, 136, 135, 135, 135, 120, 119, 134, 136, 119, 119, 120, 135, 136, 136, 136, 119, 119, 120, 119
        .byte   119, 120, 135, 136, 136, 120, 135, 118, 136, 135, 119, 135, 120, 120, 102, 104, 136, 119, 135, 102, 134, 136, 119, 119, 136, 136, 119, 119, 119, 119, 119, 120
        .byte   102, 136, 136, 119, 136, 119, 135, 119, 135, 102, 118, 135, 104, 120, 118, 134, 134, 118, 104, 120, 119, 117, 120, 104, 119, 119, 119, 119, 135, 119, 119, 119
        .byte   120, 135, 119, 118, 120, 120, 104, 103, 118, 119, 119, 102, 104, 135, 120, 119, 135, 117, 134, 134, 119, 136, 119, 135, 135, 136, 119, 103, 120, 120, 104, 120
        .byte   104, 120, 119, 103, 135, 136, 136, 88, 104, 120, 120, 118, 135, 120, 103, 104, 120, 103, 120, 103, 135, 136, 119, 120, 134, 119, 119, 119, 134, 135, 119, 120
        .byte   118, 133, 136, 135, 135, 118, 135, 134, 120, 119, 135, 120, 135, 102, 120, 120, 135, 119, 102, 119, 135, 136, 118, 120, 120, 135, 88, 151, 135, 120, 104, 104
        .byte   135, 120, 135, 119, 119, 120, 136, 134, 136, 135, 120, 119, 120, 135, 103, 87, 87, 104, 86, 71, 136, 103, 87, 135, 120, 117, 118, 104, 117, 118, 134, 104
        .byte   117, 119, 87, 103, 118, 102, 120, 134, 103, 136, 135, 118, 119, 120, 135, 119, 136, 119, 120, 119, 135, 120, 135, 119, 120, 103, 120, 119, 120, 119, 103, 104
        .byte   119, 135, 135, 117, 119, 135, 103, 119, 134, 103, 120, 134, 120, 104, 135, 135, 118, 135, 119, 119, 120, 118, 135, 135, 119, 120, 120, 102, 136, 135, 103, 103
        .byte   135, 119, 119, 120, 102, 119, 87, 120, 117, 103, 136, 119, 102, 118, 135, 119, 135, 120, 119, 119, 135, 104, 135, 102, 120, 120, 119, 136, 135, 119, 120, 119
        .byte   120, 119, 120, 120, 120, 119, 136, 134, 119, 135, 120, 135, 119, 103, 119, 134, 103, 120, 135, 136, 119, 135, 135, 135, 136, 135, 119, 120, 104, 120, 120, 120
        .byte   120, 136, 119, 135, 135, 88, 134, 118, 119, 102, 136, 134, 120, 104, 103, 104, 103, 119, 120, 135, 120, 135, 133, 103, 135, 134, 135, 120, 134, 103, 136, 119
        .byte   119, 136, 119, 104, 103, 118, 120, 135, 103, 120, 120, 135, 120, 120, 118, 133, 135, 71, 102, 120, 134, 87, 88, 87, 87, 101, 118, 103, 87, 85, 118, 119
        .byte   119, 135, 120, 118, 104, 103, 119, 135, 119, 135, 103, 133, 118, 119, 103, 119, 136, 103, 134, 118, 120, 103, 103, 117, 119, 119, 103, 136, 136, 119, 120, 120
        .byte   102, 119, 118, 119, 134, 118, 101, 119, 120, 118, 136, 135, 102, 119, 135, 136, 135, 118, 119, 119, 102, 135, 136, 136, 119, 119, 135, 135, 104, 135, 119, 119
        .byte   119, 119, 103, 119, 118, 120, 120, 118, 119, 119, 104, 102, 120, 135, 119, 133, 119, 119, 102, 134, 119, 118, 102, 120, 134, 135, 117, 119, 118, 100, 119, 134
        .byte   85, 87, 119, 119, 119, 120, 117, 117, 135, 103, 118, 119, 119, 103, 119, 102, 119, 87, 88, 120, 104, 118, 102, 118, 119, 119, 119, 104, 119, 120, 119, 120
        .byte   118, 119, 118, 119, 103, 135, 103, 120, 134, 119, 104, 119, 136, 135, 135, 118, 104, 119, 120, 119, 135, 119, 118, 119, 118, 118, 117, 119, 119, 118, 134, 119
        .byte   87, 119, 102, 135, 102, 119, 120, 120, 136, 136, 136, 119, 136, 136, 136, 135, 120, 136, 136, 120, 120, 88, 103, 119, 117, 118, 104, 119, 135, 103, 103, 103
        .byte   118, 102, 136, 104, 119, 118, 135, 119, 120, 103, 119, 103, 120, 119, 118, 119, 119, 120, 101, 104, 117, 103, 104, 118, 119, 136, 103, 118, 118, 119, 120, 135
        .byte   118, 119, 119, 119, 119, 119, 103, 120, 104, 120, 119, 119, 120, 118, 135, 103, 135, 104, 136, 104, 136, 136, 120, 118, 120, 136, 120, 136, 136, 135, 120, 103
        .byte   119, 135, 120, 135, 118, 119, 120, 120, 119, 135, 120, 118, 118, 119, 104, 120, 120, 120, 135, 119, 120, 118, 119, 120, 120, 119, 120, 119, 135, 119, 135, 85
        .byte   87, 103, 71, 119, 119, 104, 133, 103, 133, 135, 87, 119, 133, 135, 135, 103, 135, 135, 120, 135, 103, 134, 118, 103, 120, 135, 135, 136, 103, 103, 119, 119
        .byte   135, 136, 135, 101, 136, 120, 103, 120, 135, 119, 135, 133, 118, 135, 136, 119, 119, 136, 119, 104, 118, 119, 136, 135, 103, 135, 135, 120, 118, 118, 120, 135
        .byte   135, 135, 119, 119, 135, 135, 103, 119, 102, 119, 119, 119, 134, 135, 135, 86, 117, 103, 136, 103, 102, 134, 117, 120, 103, 102, 102, 104, 103, 103, 103, 135
        .byte   119, 103, 119, 117, 134, 118, 136, 135, 103, 119, 119, 103, 119, 135, 119, 134, 103, 119, 135, 104, 120, 119, 101, 120, 117, 103, 119, 117, 103, 135, 116, 86
        .byte   119, 85, 119, 120, 120, 135, 103, 103, 103, 120, 102, 135, 101, 135, 119, 135, 119, 103, 134, 119, 118, 120, 119, 119, 103, 119, 136, 120, 119, 118, 119, 136
        .byte   119, 119, 119, 120, 102, 134, 119, 136, 102, 119, 118, 134, 87, 103, 135, 135, 103, 119, 118, 120, 136, 137, 135, 118, 135, 136, 118, 120, 120, 135, 120, 135
        .byte   136, 86, 104, 119, 120, 134, 119, 136, 118, 135, 136, 103, 118, 104, 135, 104, 135, 119, 87, 135, 120, 103, 119, 103, 134, 103, 136, 119, 135, 135, 120, 133
        .byte   119, 120, 119, 119, 104, 119, 103, 135, 134, 135, 119, 103, 119, 119, 103, 119, 120, 119, 119, 135, 135, 103, 119, 119, 135, 135, 120, 135, 136, 119, 118, 136
        .byte   119, 135, 104, 119, 119, 120, 117, 136, 136, 103, 135, 119, 135, 119, 120, 134, 120, 135, 119, 120, 104, 119, 104, 152, 135, 119, 119, 103, 119, 135, 120, 119
        .byte   118, 118, 119, 118, 118, 119, 118, 87, 119, 136, 118, 103, 120, 103, 120, 135, 119, 117, 135, 119, 119, 103, 119, 136, 120, 135, 135, 120, 120, 120, 135, 120
        .byte   119, 136, 136, 136, 135, 119, 136, 118, 118, 104, 88, 118, 87, 135, 136, 102, 118, 120, 118, 118, 103, 136, 134, 119, 135, 119, 103, 119, 134, 120, 134, 119
        .byte   103, 119, 119, 120, 120, 118, 118, 119, 134, 119, 119, 119, 134, 118, 118, 120, 120, 86, 136, 135, 118, 119, 119, 118, 119, 136, 119, 119, 103, 119, 103, 120
        .byte   103, 118, 119, 134, 119, 104, 120, 136, 119, 120, 136, 135, 119, 135, 136, 135, 135, 136, 120, 119, 103, 119, 120, 103, 134, 119, 118, 119, 119, 135, 136, 119
        .byte   136, 136, 120, 118, 119, 134, 135, 119, 119, 120, 120, 119, 136, 135, 119, 119, 120, 118, 104, 119, 132, 103, 135, 133, 118, 119, 118, 133, 119, 149, 136, 119
        .byte   71, 119, 103, 135, 120, 119, 101, 103, 119, 103, 133, 87, 135, 135, 119, 119, 86, 119, 118, 135, 119, 103, 118, 136, 119, 119, 135, 135, 102, 104, 135, 104
        .byte   135, 119, 120, 102, 120, 119, 118, 87, 119, 118, 119, 103, 120, 120, 119, 120, 118, 120, 136, 118, 120, 120, 103, 118, 120, 103, 119, 118, 103, 102, 102, 104
        .byte   85, 104, 118, 86, 102, 119, 102, 118, 85, 134, 117, 101, 88, 101, 87, 135, 88, 102, 116, 120, 119, 88, 87, 119, 135, 102, 118, 87, 116, 102, 102, 86
        .byte   104, 118, 104, 104, 119, 101, 117, 119, 120, 118, 103, 134, 119, 102, 86, 136, 71, 104, 120, 103, 117, 117, 133, 118, 135, 120, 103, 119, 136, 119, 135, 119
        .byte   103, 103, 119, 86, 118, 103, 120, 118, 103, 118, 119, 119, 103, 119, 103, 103, 104, 104, 118, 117, 120, 119, 120, 119, 135, 119, 135, 103, 134, 136, 135, 103
        .byte   119, 119, 118, 135, 102, 119, 103, 117, 119, 118, 103, 117, 102, 119, 118, 103, 119, 118, 102, 103, 118, 119, 86, 103, 118, 119, 118, 101, 103, 103, 86, 120
        .byte   119, 103, 103, 135, 119, 119, 119, 104, 117, 119, 103, 103, 135, 118, 103, 135, 103, 103, 119, 136, 87, 119, 103, 103, 119, 103, 119, 103, 135, 103, 135, 119
        .byte   119, 119, 119, 118, 135, 135, 135, 104, 135, 119, 120, 119, 134, 118, 134, 135, 120, 119, 136, 119, 103, 134, 119, 102, 135, 136, 120, 135, 120, 119, 119, 135
        .byte   120, 136, 119, 135, 135, 135, 136, 136, 120, 136, 136, 120, 136, 119, 120, 119, 136, 87, 120, 102, 135, 134, 135, 119, 119, 119, 103, 135, 119, 120, 117, 136
        .byte   119, 120, 118, 103, 119, 136, 119, 118, 120, 103, 135, 119, 135, 119, 135, 136, 120, 104, 134, 118, 119, 120, 119, 120, 119, 134, 119, 103, 120, 118, 104, 119
        .byte   102, 120, 135, 120, 120, 119, 103, 119, 136, 119, 118, 134, 135, 135, 117, 103, 120, 119, 134, 117, 118, 119, 103, 136, 135, 119, 135, 103, 118, 134, 119, 118
        .byte   102, 119, 118, 118, 136, 133, 103, 120, 103, 87, 118, 118, 104, 104, 118, 117, 120, 120, 102, 119, 133, 136, 118, 101, 120, 136, 85, 119, 133, 87, 132, 103
        .byte   120, 117, 86, 119, 119, 135, 119, 119, 119, 119, 103, 135, 135, 134, 103, 136, 119, 118, 135, 102, 118, 135, 117, 88, 117, 119, 120, 133, 88, 117, 117, 118
        .byte   103, 132, 102, 135, 103, 119, 119, 120, 104, 120, 119, 120, 118, 119, 103, 118, 118, 103, 103, 120, 118, 103, 86, 103, 134, 102, 135, 119, 119, 135, 103, 118
        .byte   133, 135, 120, 134, 103, 103, 119, 136, 119, 119, 119, 120, 119, 134, 119, 118, 119, 135, 119, 119, 104, 104, 120, 119, 135, 119, 120, 119, 118, 134, 118, 103
        .byte   118, 103, 119, 104, 104, 117, 119, 117, 87, 119, 103, 119, 118, 103, 103, 135, 118, 104, 103, 120, 102, 119, 119, 88, 103, 104, 104, 103, 104, 134, 135, 134
        .byte   120, 87, 119, 104, 119, 119, 120, 103, 136, 136, 103, 119, 119, 120, 119, 120, 119, 119, 103, 120, 119, 118, 119, 120, 119, 119, 104, 119, 135, 119, 135, 134
        .byte   118, 118, 103, 119, 135, 119, 135, 135, 119, 118, 119, 119, 119, 135, 119, 119, 119, 135, 134, 135, 119, 136, 120, 119, 119, 119, 119, 119, 102, 135, 119, 103
        .byte   119, 118, 135, 104, 103, 134, 133, 119, 119, 119, 119, 119, 135, 135, 135, 119, 119, 103, 135, 136, 135, 118, 118, 103, 118, 102, 118, 118, 119, 118, 103, 117
        .byte   117, 118, 119, 134, 135, 118, 102, 103, 102, 103, 119, 118, 87, 119, 103, 119, 86, 104, 119, 103, 103, 102, 103, 102, 120, 85, 120, 102, 136, 117, 101, 102
        .byte   103, 104, 118, 118, 119, 103, 102, 119, 119, 118, 103, 118, 119, 118, 118, 119, 102, 87, 103, 116, 136, 118, 100, 102, 118, 56, 102, 70, 118, 116, 120, 100
        .byte   119, 116, 116, 119, 119, 118, 87, 119, 134, 103, 118, 103, 117, 102, 119, 120, 71, 103, 118, 101, 119, 102, 102, 104, 119, 118, 118, 102, 119, 86, 103, 118
        .byte   119, 71, 87, 103, 119, 102, 103, 118, 104, 119, 118, 102, 117, 132, 135, 136, 71, 70, 135, 71, 102, 100, 103, 131, 103, 103, 70, 102, 71, 119, 119, 117
        .byte   102, 119, 103, 119, 119, 102, 118, 103, 103, 119, 103, 118, 119, 120, 134, 118, 134, 135, 119, 118, 119, 119, 134, 119, 120, 119, 103, 135, 135, 135, 120, 103
        .byte   120, 119, 104, 119, 103, 119, 119, 119, 104, 119, 134, 119, 119, 135, 87, 120, 118, 118, 118, 103, 103, 135, 119, 120, 118, 103, 118, 117, 119, 119, 116, 116
        .byte   119, 119, 118, 88, 119, 86, 119, 85, 119, 120, 135, 119, 118, 135, 103, 119, 119, 119, 119, 119, 119, 119, 118, 136, 119, 104, 135, 103, 119, 135, 119, 134
        .byte   119, 119, 118, 119, 119, 119, 104, 104, 87, 70, 119, 118, 119, 119, 116, 85, 119, 103, 86, 119, 134, 87, 119, 135, 118, 119, 121, 118, 103, 87, 151, 135
        .byte   119, 103, 135, 104, 104, 135, 119, 102, 134, 119, 119, 118, 120, 119, 118, 87, 135, 135, 135, 104, 120, 117, 87, 117, 119, 119, 119, 117, 103, 117, 70, 119
        .byte   120, 135, 87, 119, 103, 103, 102, 103, 118, 136, 135, 119, 104, 87, 119, 120, 134, 103, 103, 136, 104, 136, 135, 120, 118, 119, 101, 120, 120, 119, 119, 135
        .byte   119, 86, 118, 135, 119, 102, 87, 118, 104, 119, 103, 118, 119, 103, 120, 135, 101, 135, 120, 102, 119, 102, 119, 119, 103, 119, 119, 119, 136, 119, 120, 119
        .byte   103, 87, 136, 136, 119, 103, 119, 102, 102, 135, 103, 135, 88, 135, 133, 119, 120, 103, 117, 117, 117, 119, 136, 87, 119, 116, 104, 119, 87, 117, 104, 136
        .byte   87, 119, 133, 120, 118, 87, 118, 120, 120, 118, 102, 119, 136, 118, 85, 87, 119, 118, 87, 119, 87, 119, 71, 119, 119, 119, 86, 103, 102, 118, 119, 118
        .byte   119, 133, 120, 135, 118, 118, 119, 120, 133, 136, 119, 104, 119, 104, 135, 119, 119, 119, 119, 119, 134, 135, 135, 119, 135, 120, 133, 86, 119, 119, 103, 118
        .byte   119, 103, 117, 88, 135, 118, 103, 135, 102, 117, 119, 132, 119, 117, 102, 119, 117, 134, 133, 119, 118, 118, 119, 102, 120, 135, 118, 102, 135, 103, 119, 103
        .byte   136, 103, 134, 135, 119, 118, 103, 120, 120, 119, 135, 119, 119, 120, 119, 136, 104, 135, 135, 103, 136, 118, 119, 136, 119, 118, 118, 119, 119, 103, 118, 103
        .byte   103, 119, 120, 120, 103, 87, 87, 103, 135, 88, 103, 102, 101, 103, 103, 71, 119, 119, 103, 102, 119, 120, 103, 118, 103, 103, 102, 119, 103, 120, 87, 119
        .byte   134, 119, 135, 119, 136, 103, 119, 119, 119, 135, 119, 119, 104, 119, 120, 135, 135, 119, 103, 103, 120, 120, 103, 118, 117, 104, 118, 135, 118, 102, 119, 103
        .byte   117, 135, 120, 86, 103, 119, 87, 119, 118, 71, 119, 86, 87, 88, 136, 117, 135, 118, 118, 102, 118, 103, 133, 102, 119, 119, 102, 103, 136, 87, 119, 118
        .byte   117, 119, 118, 102, 135, 118, 103, 120, 102, 136, 120, 134, 134, 118, 118, 119, 119, 87, 118, 134, 102, 119, 118, 103, 120, 118, 103, 102, 104, 120, 101, 104
        .byte   103, 119, 102, 117, 117, 118, 134, 134, 118, 86, 118, 136, 133, 85, 86, 135, 118, 88, 119, 86, 118, 71, 120, 102, 118, 87, 135, 119, 134, 119, 133, 118
        .byte   119, 135, 119, 103, 118, 118, 135, 118, 119, 119, 88, 119, 119, 118, 118, 119, 135, 103, 119, 119, 102, 119, 135, 120, 104, 120, 136, 120, 119, 120, 102, 119
        .byte   119, 133, 118, 119, 135, 119, 136, 86, 119, 119, 119, 85, 119, 117, 101, 133, 119, 117, 86, 120, 102, 71, 119, 120, 134, 136, 134, 119, 135, 120, 135, 152
        .byte   136, 119, 119, 119, 119, 118, 136, 120, 120, 104, 119, 135, 102, 119, 118, 135, 118, 119, 119, 117, 119, 102, 103, 104, 120, 103, 118, 119, 134, 87, 102, 119
        .byte   118, 118, 88, 104, 119, 137, 119, 136, 119, 135, 120, 119, 135, 135, 136, 119, 135, 136, 118, 136, 120, 119, 119, 119, 135, 119, 135, 120, 120, 119, 135, 119
        .byte   103, 118, 120, 135, 119, 119, 119, 135, 119, 135, 119, 119, 119, 103, 118, 103, 136, 136, 103, 119, 136, 120, 136, 136, 135, 135, 119, 119, 136, 135, 119, 120
        .byte   135, 103, 119, 119, 119, 104, 135, 119, 135, 120, 120, 136, 119, 134, 134, 119, 134, 134, 103, 134, 103, 136, 120, 133, 101, 119, 136, 120, 134, 119, 120, 135
        .byte   119, 103, 136, 87, 104, 136, 119, 103, 119, 136, 104, 119, 137, 135, 119, 135, 120, 136, 135, 136, 136, 119, 119, 120, 120, 136, 136, 133, 135, 119, 104, 102
        .byte   134, 119, 135, 104, 135, 120, 120, 102, 119, 135, 117, 120, 151, 104, 118, 118, 118, 120, 119, 104, 103, 102, 102, 119, 119, 136, 120, 120, 136, 103, 119, 135
        .byte   136, 118, 120, 120, 134, 119, 135, 135, 135, 120, 118, 135, 135, 119, 135, 104, 135, 120, 119, 120, 135, 119, 118, 104, 119, 120, 135, 135, 136, 118, 119, 119
        .byte   119, 119, 119, 118, 136, 103, 136, 120, 120, 119, 135, 136, 136, 135, 135, 135, 119, 134, 136, 118, 120, 119, 119, 103, 136, 135, 135, 120, 119, 136, 134, 119
        .byte   103, 119, 118, 119, 135, 136, 118, 120, 103, 134, 119, 103, 118, 103, 120, 102, 120, 119, 88, 135, 120, 119, 119, 87, 119, 104, 134, 102, 136, 134, 103, 135
        .byte   119, 103, 120, 119, 119, 119, 119, 119, 103, 119, 102, 120, 120, 118, 119, 119, 102, 120, 103, 86, 103, 119, 136, 117, 103, 118, 87, 102, 118, 134, 119, 103
        .byte   135, 120, 134, 86, 120, 117, 103, 103, 119, 104, 103, 134, 134, 133, 103, 104, 120, 103, 119, 119, 104, 118, 119, 119, 135, 104, 120, 119, 119, 118, 104, 120
        .byte   120, 136, 135, 119, 136, 135, 136, 120, 134, 135, 120, 135, 119, 134, 119, 120, 119, 135, 136, 119, 135, 118, 135, 135, 136, 118, 119, 135, 118, 102, 136, 118
        .byte   118, 102, 119, 118, 85, 119, 119, 103, 102, 119, 134, 135, 119, 120, 119, 120, 135, 120, 135, 119, 135, 120, 120, 102, 135, 104, 120, 135, 136, 120, 119, 119
        .byte   119, 118, 120, 135, 135, 104, 136, 119, 120, 119, 135, 120, 135, 136, 136, 136, 119, 119, 135, 120, 120, 136, 135, 134, 136, 136, 119, 119, 119, 135, 135, 136
        .byte   134, 119, 136, 135, 135, 118, 135, 136, 119, 120, 120, 135, 135, 136, 135, 136, 120, 136, 119, 119, 104, 136, 136, 134, 136, 119, 119, 119, 135, 136, 136, 120
        .byte   119, 135, 135, 120, 120, 135, 135, 136, 103, 103, 103, 119, 135, 119, 119, 104, 134, 120, 136, 119, 120, 119, 119, 118, 119, 120, 118, 119, 119, 119, 135, 103
        .byte   103, 118, 118, 103, 103, 104, 120, 119, 119, 118, 119, 133, 104, 120, 103, 135, 103, 136, 118, 103, 103, 103, 118, 103, 118, 118, 119, 104, 119, 119, 118, 117
        .byte   118, 136, 119, 136, 135, 135, 136, 120, 104, 134, 119, 120, 136, 134, 135, 119, 135, 103, 135, 87, 120, 120, 119, 104, 119, 103, 103, 120, 103, 120, 134, 134
        .byte   134, 135, 87, 118, 103, 119, 135, 104, 102, 118, 120, 119, 103, 135, 135, 135, 135, 119, 120, 119, 118, 119, 135, 119, 120, 135, 135, 103, 119, 119, 119, 136
        .byte   103, 135, 102, 135, 135, 120, 118, 120, 102, 119, 135, 136, 102, 119, 136, 119, 119, 119, 120, 103, 120, 119, 118, 119, 102, 135, 119, 118, 135, 102, 119, 118
        .byte   104, 135, 118, 135, 119, 103, 103, 136, 118, 88, 103, 120, 119, 119, 102, 120, 134, 118, 118, 120, 134, 103, 135, 119, 87, 88, 104, 119, 119, 104, 119, 117
        .byte   88, 119, 87, 104, 119, 70, 103, 118, 120, 103, 135, 119, 102, 88, 136, 102, 103, 104, 104, 88, 88, 136, 119, 103, 119, 103, 102, 86, 71, 119, 119, 87
        .byte   103, 86, 135, 119, 135, 101, 120, 120, 118, 103, 104, 88, 104, 135, 103, 102, 103, 103, 117, 135, 86, 101, 71, 102, 71, 71, 102, 70, 71, 119, 103, 54
        .byte   104, 118, 71, 118, 136, 103, 119, 135, 119, 104, 103, 103, 135, 86, 120, 104, 134, 103, 117, 118, 117, 119, 135, 85, 119, 117, 103, 116, 87, 135, 101, 86
        .byte   118, 118, 118, 120, 119, 104, 136, 120, 119, 119, 120, 118, 117, 136, 136, 120, 119, 120, 135, 119, 118, 135, 136, 136, 135, 135, 135, 134, 135, 135, 118, 134
        .byte   120, 104, 103, 103, 119, 119, 135, 118, 104, 119, 135, 118, 118, 133, 120, 118, 120, 103, 119, 118, 87, 136, 120, 103, 136, 136, 104, 120, 119, 120, 119, 119
        .byte   117, 101, 133, 117, 120, 120, 119, 87, 119, 87, 104, 116, 120, 119, 120, 120, 120, 135, 119, 104, 118, 120, 120, 103, 103, 135, 119, 119, 103, 118, 119, 119
        .byte   118, 103, 120, 118, 119, 118, 119, 102, 119, 103, 135, 135, 119, 120, 120, 119, 119, 135, 135, 104, 119, 119, 103, 103, 135, 136, 104, 119, 104, 119, 119, 103
        .byte   119, 136, 119, 119, 120, 136, 119, 103, 134, 104, 118, 102, 120, 102, 87, 119, 136, 103, 119, 119, 102, 119, 104, 119, 102, 119, 120, 119, 119, 104, 120, 119
        .byte   120, 135, 135, 119, 118, 119, 135, 102, 135, 120, 135, 119, 103, 119, 135, 119, 120, 134, 135, 119, 136, 120, 136, 134, 118, 134, 101, 102, 120, 120, 101, 136
        .byte   118, 104, 135, 134, 104, 120, 135, 119, 135, 135, 136, 119, 119, 119, 134, 134, 104, 120, 118, 119, 152, 135, 119, 103, 136, 120, 136, 120, 136, 120, 120, 136
        .byte   135, 120, 136, 134, 135, 120, 119, 120, 120, 119, 119, 136, 119, 119, 136, 120, 104, 120, 118, 119, 136, 103, 120, 103, 118, 118, 104, 119, 119, 135, 119, 135
        .byte   119, 120, 120, 136, 135, 120, 119, 104, 119, 135, 119, 119, 104, 120, 120, 135, 136, 135, 120, 135, 136, 136, 120, 136, 135, 120, 136, 136, 135, 120, 136, 135
        .byte   135, 120, 136, 135, 136, 136, 119, 120, 151, 120, 120, 136, 135, 120, 119, 119, 120, 103, 136, 119, 136, 119, 120, 134, 120, 135, 102, 135, 119, 104, 120, 119
        .byte   120, 120, 119, 119, 120, 135, 136, 136, 136, 118, 103, 118, 120, 136, 136, 119, 135, 120, 136, 118, 120, 104, 119, 135, 119, 120, 119, 118, 120, 135, 116, 136
        .byte   120, 118, 101, 120, 120, 87, 120, 120, 120, 87, 119, 135, 120, 118, 104, 119, 119, 119, 118, 118, 120, 120, 120, 119, 119, 120, 119, 120, 118, 104, 119, 119
        .byte   119, 119, 119, 120, 119, 135, 118, 135, 119, 102, 87, 119, 119, 120, 86, 136, 118, 86, 119, 72, 119, 86, 119, 119, 118, 135, 119, 117, 133, 120, 135, 118
        .byte   104, 103, 103, 120, 102, 119, 120, 120, 103, 135, 136, 119, 119, 136, 135, 118, 135, 135, 119, 136, 120, 119, 135, 136, 118, 118, 119, 119, 103, 135, 135, 135
        .byte   119, 119, 119, 135, 118, 119, 120, 119, 101, 104, 134, 135, 118, 120, 135, 134, 119, 134, 119, 119, 118, 103, 119, 118, 103, 103, 118, 118, 102, 103, 118, 119
        .byte   133, 104, 119, 118, 103, 104, 103, 119, 103, 118, 103, 134, 87, 103, 118, 119, 88, 136, 119, 120, 119, 120, 119, 120, 120, 119, 119, 104, 119, 119, 135, 119
        .byte   120, 119, 119, 118, 120, 119, 119, 119, 118, 119, 136, 120, 103, 118, 118, 119, 119, 103, 135, 119, 118, 119, 120, 119, 120, 119, 120, 103, 103, 119, 136, 119
        .byte   120, 136, 119, 135, 119, 136, 118, 120, 135, 119, 120, 119, 136, 104, 119, 103, 135, 103, 120, 118, 119, 133, 120, 120, 103, 120, 135, 103, 120, 119, 120, 135
        .byte   120, 136, 135, 135, 135, 135, 135, 119, 103, 118, 120, 103, 119, 134, 120, 119, 103, 135, 119, 119, 136, 135, 135, 119, 120, 119, 118, 136, 119, 119, 120, 103
        .byte   136, 120, 136, 119, 120, 136, 120, 120, 136, 135, 103, 120, 102, 104, 118, 136, 136, 135, 104, 87, 135, 120, 135, 104, 104, 119, 135, 119, 119, 118, 120, 120
        .byte   135, 136, 118, 120, 120, 136, 119, 120, 120, 119, 120, 119, 120, 136, 120, 135, 135, 104, 136, 120, 119, 120, 120, 135, 135, 119, 119, 119, 103, 119, 118, 119
        .byte   119, 118, 135, 118, 118, 134, 134, 104, 118, 120, 119, 103, 135, 119, 102, 118, 119, 134, 133, 119, 119, 119, 119, 119, 119, 103, 118, 135, 118, 119, 135, 119
        .byte   118, 119, 135, 134, 119, 102, 118, 118, 118, 118, 119, 102, 118, 87, 136, 134, 119, 101, 119, 119, 103, 103, 119, 102, 120, 119, 104, 118, 119, 119, 135, 118
        .byte   135, 120, 102, 103, 119, 135, 119, 118, 120, 119, 118, 119, 103, 101, 120, 119, 117, 120, 120, 119, 87, 103, 119, 85, 136, 133, 135, 133, 119, 135, 116, 117
        .byte   135, 135, 119, 102, 119, 119, 103, 103, 120, 135, 87, 119, 119, 120, 120, 117, 103, 120, 119, 119, 118, 119, 103, 118, 87, 135, 119, 120, 135, 136, 101, 88
        .byte   119, 117, 119, 118, 117, 119, 87, 119, 101, 119, 132, 103, 120, 103, 102, 120, 119, 119, 103, 119, 134, 136, 119, 136, 119, 119, 119, 119, 118, 118, 135, 118
        .byte   119, 120, 135, 119, 135, 119, 119, 103, 119, 119, 120, 120, 119, 135, 120, 120, 119, 120, 136, 134, 135, 104, 136, 136, 135, 135, 120, 135, 120, 120, 135, 119
        .byte   120, 103, 120, 120, 136, 118, 135, 135, 134, 136, 134, 104, 119, 103, 120, 120, 135, 120, 119, 135, 120, 119, 120, 119, 119, 85, 103, 102, 119, 118, 119, 116
        .byte   118, 119, 102, 119, 118, 117, 136, 120, 135, 119, 136, 120, 120, 136, 135, 135, 118, 119, 118, 119, 135, 119, 118, 120, 117, 120, 104, 118, 135, 119, 103, 101
        .byte   136, 118, 134, 103, 119, 117, 87, 120, 134, 119, 118, 118, 119, 87, 119, 133, 119, 132, 104, 120, 120, 119, 120, 120, 136, 119, 120, 118, 119, 120, 120, 119
        .byte   120, 119, 152, 120, 136, 136, 135, 119, 120, 136, 120, 120, 136, 104, 120, 136, 135, 135, 120, 136, 136, 117, 104, 136, 119, 104, 135, 119, 103, 119, 135, 119
        .byte   119, 103, 87, 118, 119, 119, 120, 101, 102, 103, 103, 103, 119, 135, 88, 118, 102, 120, 119, 87, 117, 119, 103, 102, 135, 103, 103, 119, 119, 104, 120, 119
        .byte   103, 135, 103, 119, 119, 119, 118, 135, 120, 118, 103, 103, 135, 136, 135, 119, 119, 119, 136, 119, 136, 119, 120, 120, 135, 120, 136, 119, 118, 119, 135, 119
        .byte   102, 135, 118, 103, 135, 119, 118, 134, 103, 135, 117, 120, 120, 135, 136, 102, 120, 135, 135, 102, 119, 135, 104, 118, 119, 88, 104, 87, 85, 103, 119, 103
        .byte   87, 104, 117, 87, 120, 71, 119, 86, 103, 134, 118, 119, 86, 87, 102, 119, 120, 116, 102, 135, 87, 135, 104, 88, 120, 103, 103, 102, 135, 120, 118, 102
        .byte   118, 86, 120, 102, 101, 102, 119, 102, 119, 119, 119, 86, 72, 119, 119, 88, 118, 102, 119, 119, 134, 117, 103, 120, 135, 103, 88, 87, 104, 104, 120, 135
        .byte   119, 118, 119, 135, 103, 135, 118, 104, 120, 119, 119, 119, 120, 119, 135, 120, 135, 119, 135, 135, 120, 119, 135, 134, 136, 119, 136, 135, 119, 120, 136, 135
        .byte   136, 120, 119, 119, 119, 86, 117, 119, 119, 103, 119, 134, 118, 102, 103, 103, 120, 134, 104, 119, 103, 119, 119, 103, 119, 119, 103, 135, 103, 120, 119, 120
        .byte   119, 135, 118, 102, 103, 135, 120, 134, 86, 118, 117, 120, 118, 120, 102, 117, 135, 118, 136, 135, 103, 119, 136, 135, 119, 135, 135, 119, 103, 119, 119, 135
        .byte   119, 119, 119, 88, 103, 102, 119, 119, 119, 103, 134, 135, 103, 119, 120, 104, 119, 118, 119, 103, 118, 119, 119, 120, 120, 118, 120, 103, 120, 120, 119, 118
        .byte   103, 133, 118, 116, 101, 101, 136, 135, 117, 135, 102, 119, 103, 103, 120, 119, 102, 102, 118, 101, 119, 119, 135, 133, 103, 134, 119, 103, 120, 119, 103, 119
        .byte   119, 104, 119, 119, 119, 119, 119, 120, 135, 120, 120, 104, 119, 119, 134, 104, 88, 119, 134, 104, 103, 104, 117, 104, 119, 103, 69, 87, 118, 86, 87, 119
        .byte   118, 104, 103, 120, 85, 103, 119, 102, 135, 135, 119, 103, 87, 135, 104, 118, 103, 118, 103, 86, 135, 119, 102, 101, 119, 119, 86, 87, 117, 118, 135, 136
        .byte   116, 117, 103, 134, 71, 135, 135, 119, 119, 120, 119, 119, 119, 120, 120, 103, 119, 134, 120, 120, 118, 119, 117, 85, 103, 119, 87, 120, 118, 72, 119, 87
        .byte   102, 120, 136, 71, 119, 135, 118, 119, 133, 120, 134, 119, 102, 135, 118, 118, 103, 118, 135, 118, 103, 119, 135, 88, 103, 118, 103, 135, 120, 119, 118, 119
        .byte   118, 102, 135, 103, 119, 86, 136, 119, 119, 102, 103, 119, 102, 119, 120, 102, 120, 118, 118, 103, 135, 117, 103, 119, 134, 103, 119, 103, 102, 102, 135, 119
        .byte   102, 135, 118, 103, 119, 119, 103, 120, 103, 119, 87, 104, 118, 118, 103, 104, 104, 136, 102, 120, 102, 88, 103, 120, 103, 136, 104, 118, 86, 136, 135, 119
        .byte   135, 119, 119, 135, 120, 120, 136, 102, 135, 120, 118, 119, 120, 118, 119, 118, 133, 136, 135, 118, 104, 135, 120, 120, 119, 118, 119, 119, 119, 134, 120, 135
        .byte   134, 120, 119, 135, 119, 119, 119, 135, 103, 136, 119, 135, 120, 120, 135, 118, 135, 118, 120, 135, 136, 135, 134, 119, 120, 135, 119, 120, 120, 135, 104, 135
        .byte   118, 136, 119, 119, 120, 103, 120, 119, 119, 103, 119, 119, 119, 119, 119, 134, 119, 118, 119, 118, 135, 118, 103, 120, 104, 120, 118, 103, 102, 87, 119, 86
        .byte   136, 118, 119, 133, 104, 134, 135, 118, 119, 102, 88, 118, 87, 119, 102, 87, 134, 101, 118, 120, 102, 119, 119, 134, 136, 118, 119, 119, 135, 120, 119, 119
        .byte   120, 119, 103, 119, 119, 119, 103, 103, 135, 119, 120, 102, 119, 120, 120, 120, 119, 119, 118, 134, 118, 104, 119, 119, 119, 135, 104, 135, 135, 120, 119, 119
        .byte   119, 103, 120, 120, 120, 119, 120, 135, 119, 120, 119, 103, 119, 104, 119, 102, 120, 102, 118, 103, 134, 117, 119, 117, 87, 104, 102, 104, 134, 103, 119, 118
        .byte   135, 135, 119, 135, 102, 135, 118, 134, 118, 87, 135, 120, 120, 134, 118, 103, 87, 85, 87, 135, 103, 120, 102, 101, 102, 132, 87, 133, 104, 118, 117, 118
        .byte   120, 120, 87, 119, 87, 119, 119, 135, 118, 119, 118, 119, 118, 120, 86, 118, 119, 87, 133, 70, 119, 135, 118, 87, 133, 120, 119, 87, 120, 119, 120, 119
        .byte   119, 102, 103, 134, 104, 104, 103, 136, 102, 136, 117, 118, 119, 119, 103, 103, 88, 103, 119, 151, 103, 102, 119, 119, 102, 133, 102, 103, 119, 118, 118, 103
        .byte   117, 103, 119, 103, 119, 103, 134, 102, 118, 118, 120, 134, 120, 117, 119, 103, 135, 116, 103, 118, 87, 120, 103, 104, 89, 88, 118, 84, 119, 119, 103, 117
        .byte   102, 134, 71, 86, 117, 120, 102, 87, 102, 104, 119, 102, 72, 87, 119, 104, 135, 135, 135, 117, 135, 135, 86, 135, 104, 103, 103, 102, 87, 119, 119, 103
        .byte   103, 88, 102, 102, 104, 102, 135, 118, 119, 135, 118, 119, 119, 104, 119, 119, 103, 103, 135, 118, 118, 102, 120, 119, 87, 119, 88, 134, 119, 134, 118, 135
        .byte   118, 119, 134, 119, 135, 118, 118, 120, 118, 104, 135, 135, 120, 134, 119, 119, 119, 119, 135, 119, 135, 135, 119, 118, 119, 120, 136, 118, 120, 134, 135, 118
        .byte   119, 133, 119, 119, 120, 120, 118, 119, 119, 119, 102, 120, 135, 104, 103, 118, 135, 103, 120, 135, 120, 134, 119, 104, 119, 104, 103, 120, 120, 86, 119, 118
        .byte   119, 104, 136, 133, 120, 119, 103, 120, 119, 119, 119, 119, 134, 118, 136, 103, 119, 86, 103, 119, 103, 102, 117, 102, 133, 118, 118, 119, 118, 103, 103, 135
        .byte   102, 118, 103, 119, 119, 117, 87, 103, 120, 103, 119, 118, 103, 118, 87, 119, 118, 119, 103, 133, 102, 103, 118, 103, 118, 119, 134, 119, 119, 104, 120, 136
        .byte   119, 136, 119, 119, 135, 134, 119, 118, 119, 120, 119, 120, 136, 134, 119, 119, 120, 118, 119, 119, 134, 134, 135, 136, 120, 133, 119, 119, 120, 104, 104, 119
        .byte   119, 120, 120, 119, 119, 135, 120, 119, 119, 135, 120, 118, 118, 136, 136, 87, 103, 136, 103, 119, 102, 119, 103, 88, 119, 103, 119, 134, 136, 151, 120, 118
        .byte   136, 119, 119, 135, 119, 135, 119, 119, 120, 117, 103, 136, 119, 120, 120, 136, 118, 118, 120, 135, 119, 118, 134, 135, 103, 119, 118, 119, 136, 102, 103, 120
        .byte   135, 87, 120, 135, 103, 118, 120, 103, 135, 135, 136, 119, 119, 135, 135, 136, 119, 119, 135, 120, 102, 119, 103, 120, 120, 120, 133, 120, 134, 118, 120, 135
        .byte   118, 103, 135, 135, 133, 134, 136, 149, 120, 134, 117, 102, 120, 118, 118, 103, 118, 136, 119, 101, 121, 135, 73, 119, 86, 120, 117, 119, 87, 119, 87, 88
        .byte   119, 135, 104, 133, 88, 136, 119, 89, 102, 103, 119, 102, 135, 120, 102, 136, 118, 134, 117, 135, 132, 103, 133, 102, 117, 119, 133, 101, 118, 101, 119, 118
        .byte   134, 119, 119, 135, 119, 119, 136, 120, 136, 118, 120, 119, 135, 135, 120, 135, 135, 136, 104, 120, 135, 135, 135, 120, 119, 136, 103, 119, 135, 119, 102, 102
        .byte   134, 102, 118, 119, 103, 101, 119, 135, 119, 134, 120, 117, 135, 120, 103, 119, 119, 119, 119, 119, 119, 136, 119, 119, 102, 102, 134, 119, 135, 118, 119, 118
        .byte   119, 119, 103, 135, 119, 102, 103, 135, 102, 119, 119, 103, 120, 119, 102, 103, 134, 103, 103, 134, 120, 117, 119, 136, 103, 119, 135, 103, 120, 119, 119, 102
        .byte   119, 102, 135, 118, 119, 136, 120, 119, 119, 119, 119, 119, 119, 119, 136, 120, 118, 120, 119, 136, 135, 135, 120, 136, 104, 135, 119, 135, 119, 119, 136, 136
        .byte   118, 103, 119, 135, 134, 119, 119, 101, 88, 120, 102, 101, 136, 119, 135, 118, 119, 118, 104, 119, 135, 119, 103, 119, 87, 119, 103, 134, 88, 119, 118, 120
        .byte   118, 120, 119, 135, 120, 119, 119, 104, 135, 104, 120, 119, 103, 119, 136, 119, 119, 103, 118, 119, 103, 87, 136, 103, 103, 134, 119, 119, 103, 119, 134, 103
        .byte   103, 119, 120, 104, 119, 118, 120, 119, 119, 119, 119, 119, 103, 119, 102, 118, 118, 119, 117, 119, 120, 119, 118, 119, 118, 103, 121, 134, 136, 102, 119, 134
        .byte   136, 119, 135, 103, 104, 103, 119, 134, 120, 103, 120, 120, 103, 87, 104, 104, 134, 103, 102, 103, 102, 120, 118, 135, 86, 86, 119, 119, 101, 87, 104, 118
        .byte   103, 103, 120, 119, 132, 136, 117, 86, 119, 117, 120, 119, 87, 103, 117, 102, 118, 133, 103, 118, 135, 102, 103, 118, 119, 119, 120, 119, 134, 103, 119, 135
        .byte   116, 134, 119, 119, 101, 103, 104, 118, 133, 119, 133, 102, 120, 120, 118, 119, 103, 88, 103, 119, 136, 119, 103, 119, 120, 120, 135, 119, 136, 136, 119, 120
        .byte   119, 120, 120, 136, 119, 136, 120, 136, 135, 136, 134, 136, 136, 120, 136, 120, 120, 120, 135, 135, 136, 135, 135, 136, 135, 118, 136, 135, 135, 119, 136, 136
        .byte   134, 136, 135, 136, 135, 120, 135, 136, 137, 135, 135, 136, 136, 120, 135, 134, 120, 135, 104, 135, 135, 135, 136, 120, 136, 136, 135, 119, 120, 136, 135, 136
        .byte   136, 136, 135, 136, 136, 134, 119, 120, 135, 119, 120, 103, 120, 119, 135, 135, 120, 136, 135, 120, 135, 120, 137, 152, 119, 135, 135, 119, 135, 120, 136, 135
        .byte   136, 136, 136, 119, 103, 135, 104, 103, 119, 119, 105, 119, 103, 118, 118, 119, 119, 102, 120, 103, 135, 103, 134, 103, 135, 118, 104, 133, 102, 87, 118, 118
        .byte   120, 104, 69, 86, 119, 103, 101, 72, 134, 87, 118, 87, 88, 117, 133, 133, 135, 119, 120, 119, 104, 120, 119, 134, 103, 118, 119, 103, 119, 134, 87, 101
        .byte   119, 118, 118, 100, 87, 118, 103, 133, 119, 102, 103, 101, 87, 103, 103, 119, 120, 134, 101, 87, 119, 119, 104, 119, 104, 103, 103, 136, 118, 119, 119, 119
        .byte   103, 103, 103, 119, 136, 117, 103, 134, 103, 118, 119, 103, 119, 118, 118, 119, 120, 119, 118, 103, 119, 118, 102, 119, 120, 136, 119, 119, 135, 135, 119, 103
        .byte   119, 135, 103, 102, 133, 103, 104, 135, 103, 118, 135, 103, 101, 119, 102, 85, 135, 119, 69, 134, 118, 102, 119, 103, 133, 135, 119, 118, 119, 88, 118, 120
        .byte   119, 103, 134, 103, 101, 135, 118, 102, 118, 136, 103, 119, 135, 103, 136, 118, 135, 136, 119, 135, 120, 120, 119, 103, 134, 103, 135, 119, 119, 136, 117, 103
        .byte   119, 120, 103, 119, 133, 102, 87, 102, 101, 69, 103, 86, 119, 87, 134, 118, 119, 119, 118, 102, 103, 103, 118, 135, 119, 119, 119, 103, 135, 135, 103, 118
        .byte   120, 120, 102, 88, 120, 135, 119, 120, 119, 119, 118, 120, 119, 104, 119, 103, 136, 119, 120, 135, 120, 120, 120, 119, 119, 135, 102, 136, 120, 135, 118, 119
        .byte   103, 120, 119, 120, 136, 119, 119, 136, 118, 135, 119, 120, 119, 103, 120, 136, 120, 103, 118, 102, 118, 119, 134, 87, 103, 119, 135, 103, 120, 135, 120, 135
        .byte   102, 103, 119, 134, 88, 104, 118, 88, 135, 118, 104, 104, 102, 136, 118, 135, 120, 103, 120, 103, 119, 120, 136, 120, 135, 119, 136, 103, 119, 135, 104, 119
        .byte   135, 103, 134, 119, 120, 119, 120, 117, 119, 119, 118, 134, 120, 104, 118, 135, 134, 102, 135, 103, 118, 118, 134, 117, 87, 117, 134, 87, 87, 103, 119, 117
        .byte   119, 134, 71, 103, 133, 120, 102, 87, 85, 135, 119, 103, 103, 101, 86, 103, 103, 118, 102, 135, 102, 135, 102, 119, 103, 86, 119, 135, 104, 87, 135, 135
        .byte   135, 135, 119, 102, 119, 135, 118, 102, 102, 119, 135, 120, 119, 118, 119, 118, 135, 103, 119, 118, 119, 120, 134, 135, 120, 119, 120, 104, 103, 104, 117, 120
        .byte   134, 101, 134, 102, 119, 119, 104, 103, 120, 118, 119, 103, 119, 135, 102, 102, 134, 103, 118, 135, 135, 117, 119, 135, 135, 135, 119, 135, 119, 119, 119, 135
        .byte   120, 120, 118, 135, 134, 119, 135, 121, 103, 104, 135, 103, 119, 104, 133, 103, 120, 119, 137, 134, 119, 120, 118, 103, 119, 120, 119, 103, 135, 135, 134, 103
        .byte   135, 135, 119, 134, 120, 120, 87, 119, 118, 136, 119, 104, 118, 119, 120, 102, 134, 119, 135, 119, 135, 134, 119, 120, 136, 134, 120, 104, 135, 119, 120, 120
        .byte   120, 119, 120, 117, 134, 119, 134, 134, 120, 119, 120, 119, 119, 119, 134, 120, 120, 135, 136, 135, 120, 135, 136, 136, 136, 136, 135, 120, 120, 119, 121, 120
        .byte   120, 136, 120, 136, 136, 136, 136, 135, 120, 135, 120, 136, 120, 136, 136, 120, 119, 136, 119, 120, 135, 135, 120, 136, 120, 135, 136, 120, 136, 119, 135, 136
        .byte   135, 119, 136, 119, 119, 136, 104, 152, 119, 120, 135, 136, 136, 135, 135, 135, 136, 136, 135, 119, 135, 134, 120, 103, 119, 136, 119, 136, 136, 118, 120, 119
        .byte   119, 135, 120, 136, 135, 136, 120, 135, 135, 120, 135, 119, 135, 104, 104, 119, 120, 119, 120, 135, 104, 135, 136, 120, 136, 119, 134, 101, 103, 120, 104, 135
        .byte   119, 135, 118, 103, 136, 119, 120, 103, 119, 119, 135, 119, 119, 118, 103, 120, 134, 103, 119, 135, 119, 118, 118, 103, 120, 120, 101, 136, 119, 134, 101, 118
        .byte   103, 102, 135, 119, 118, 88, 103, 118, 103, 103, 134, 120, 118, 118, 119, 120, 103, 135, 118, 119, 120, 119, 102, 120, 118, 120, 119, 118, 136, 119, 119, 119
        .byte   118, 135, 135, 120, 119, 102, 136, 104, 135, 102, 119, 136, 119, 101, 118, 118, 102, 88, 119, 103, 133, 119, 118, 119, 118, 135, 120, 119, 118, 119, 134, 119
        .byte   119, 103, 119, 120, 136, 103, 119, 103, 152, 103, 136, 120, 119, 135, 136, 136, 119, 120, 136, 135, 120, 119, 136, 136, 135, 136, 136, 135, 136, 120, 135, 135
        .byte   120, 136, 135, 135, 136, 120, 135, 136, 136, 135, 136, 136, 136, 135, 119, 135, 119, 120, 119, 120, 104, 136, 135, 135, 135, 120, 135, 119, 136, 136, 135, 120
        .byte   135, 120, 136, 136, 136, 136, 136, 136, 135, 119, 135, 120, 136, 120, 119, 120, 136, 137, 136, 120, 135, 136, 118, 104, 135, 135, 135, 120, 136, 119, 136, 119
        .byte   135, 119, 120, 136, 119, 135, 136, 136, 136, 135, 135, 136, 120, 119, 104, 135, 136, 120, 136, 119, 151, 119, 136, 136, 120, 136, 120, 136, 136, 136, 136, 136
        .byte   120, 136, 136, 119, 120, 135, 135, 135, 136, 120, 134, 120, 135, 136, 119, 136, 136, 136, 135, 119, 135, 136, 152, 136, 119, 135, 119, 104, 135, 102, 119, 137
        .byte   136, 119, 135, 135, 135, 119, 120, 135, 136, 120, 120, 135, 120, 151, 136, 136, 136, 136, 136, 136, 119, 135, 118, 135, 135, 119, 134, 136, 136, 119, 120, 120
        .byte   135, 120, 104, 135, 120, 119, 136, 136, 119, 136, 136, 120, 136, 135, 119, 119, 120, 135, 135, 135, 119, 104, 119, 119, 119, 119, 135, 120, 119, 135, 119, 120
        .byte   135, 135, 136, 120, 119, 119, 119, 102, 120, 104, 120, 135, 120, 104, 118, 104, 119, 119, 119, 119, 102, 119, 104, 86, 119, 119, 119, 135, 102, 103, 120, 104
        .byte   104, 119, 135, 101, 135, 119, 135, 134, 102, 104, 119, 103, 120, 120, 103, 103, 120, 119, 118, 119, 119, 119, 118, 103, 119, 117, 134, 118, 134, 119, 118, 119
        .byte   135, 134, 118, 135, 135, 136, 135, 119, 135, 103, 119, 119, 120, 119, 102, 101, 86, 119, 119, 103, 102, 133, 103, 103, 86, 118, 102, 119, 103, 118, 120, 119
        .byte   120, 120, 119, 135, 104, 118, 136, 136, 136, 136, 135, 135, 120, 135, 135, 119, 119, 120, 135, 120, 119, 135, 120, 136, 136, 119, 118, 102, 118, 103, 103, 118
        .byte   119, 119, 119, 119, 103, 103, 118, 103, 118, 119, 135, 103, 103, 120, 103, 88, 102, 119, 120, 102, 103, 133, 119, 103, 102, 104, 102, 104, 103, 119, 102, 119
        .byte   118, 119, 134, 119, 117, 103, 135, 119, 135, 118, 104, 119, 119, 135, 119, 119, 119, 118, 86, 135, 134, 118, 120, 135, 119, 136, 102, 119, 120, 119, 104, 103
        .byte   119, 120, 119, 120, 135, 135, 134, 118, 119, 118, 118, 135, 117, 104, 120, 117, 119, 136, 101, 87, 120, 119, 120, 119, 135, 119, 136, 119, 119, 135, 104, 136
        .byte   119, 119, 135, 134, 103, 103, 103, 119, 103, 120, 135, 117, 86, 120, 119, 88, 119, 134, 87, 117, 119, 118, 119, 116, 87, 118, 135, 86, 103, 102, 86, 85
        .byte   118, 135, 134, 103, 103, 119, 103, 119, 118, 120, 119, 119, 120, 119, 119, 118, 120, 117, 103, 119, 72, 119, 87, 119, 102, 103, 85, 101, 136, 135, 86, 119
        .byte   119, 134, 119, 118, 118, 120, 119, 118, 119, 119, 103, 135, 120, 119, 119, 119, 121, 136, 103, 118, 118, 118, 136, 120, 119, 119, 135, 119, 120, 136, 119, 135
        .byte   135, 135, 134, 119, 119, 103, 119, 118, 135, 103, 119, 119, 118, 136, 134, 118, 120, 103, 103, 88, 135, 104, 102, 102, 118, 120, 104, 117, 119, 103, 120, 136
        .byte   118, 87, 136, 119, 104, 103, 134, 87, 103, 135, 136, 118, 119, 135, 119, 134, 118, 103, 119, 119, 104, 119, 104, 120, 117, 120, 119, 135, 135, 104, 135, 103
        .byte   136, 119, 120, 103, 135, 136, 135, 119, 119, 135, 135, 134, 119, 119, 103, 119, 135, 136, 119, 103, 135, 135, 119, 119, 102, 103, 103, 88, 102, 86, 118, 117
        .byte   118, 86, 103, 118, 118, 70, 118, 104, 132, 71, 117, 103, 118, 88, 119, 102, 70, 102, 103, 101, 99, 119, 119, 72, 102, 100, 102, 134, 131, 70, 119, 71
        .byte   102, 100, 102, 116, 120, 101, 102, 100, 86, 119, 102, 103, 86, 119, 87, 119, 86, 70, 102, 87, 115, 118, 117, 53, 85, 99, 103, 83, 39, 87, 85, 53
        .byte   87, 119, 54, 55, 118, 86, 118, 102, 102, 101, 116, 117, 104, 100, 102, 119, 120, 70, 103, 100, 103, 102, 119, 102, 87, 86, 87, 102, 101, 118, 119, 102
        .byte   118, 119, 133, 120, 135, 118, 103, 120, 120, 134, 119, 118, 135, 134, 87, 136, 119, 134, 119, 135, 103, 134, 136, 135, 134, 118, 120, 134, 136, 119, 135, 120
        .byte   120, 136, 135, 120, 136, 119, 120, 119, 135, 135, 136, 135, 119, 135, 104, 120, 118, 134, 134, 103, 133, 104, 120, 118, 104, 136, 118, 87, 119, 134, 120, 120
        .byte   118, 135, 136, 117, 103, 136, 118, 120, 135, 118, 102, 119, 118, 119, 118, 87, 119, 102, 120, 119, 104, 118, 118, 117, 120, 135, 88, 118, 134, 136, 119, 103
        .byte   102, 104, 135, 119, 103, 118, 104, 120, 87, 104, 103, 103, 103, 119, 102, 87, 119, 102, 101, 103, 120, 118, 134, 102, 117, 136, 120, 119, 120, 119, 135, 135
        .byte   120, 135, 119, 120, 120, 118, 119, 135, 119, 119, 119, 119, 119, 134, 136, 118, 119, 119, 119, 135, 119, 135, 118, 102, 118, 119, 119, 119, 120, 102, 118, 103
        .byte   135, 135, 119, 119, 135, 120, 119, 103, 119, 102, 119, 102, 119, 119, 119, 103, 136, 135, 102, 87, 119, 135, 120, 119, 118, 118, 103, 136, 119, 119, 118, 119
        .byte   118, 119, 103, 135, 118, 104, 120, 117, 118, 104, 119, 118, 119, 120, 119, 117, 103, 120, 120, 119, 135, 119, 118, 120, 102, 119, 120, 135, 135, 136, 135, 135
        .byte   119, 136, 119, 119, 104, 136, 119, 103, 136, 119, 119, 119, 120, 120, 135, 135, 136, 135, 119, 136, 119, 120, 135, 135, 136, 120, 119, 119, 119, 119, 119, 119
        .byte   118, 119, 119, 135, 104, 120, 133, 135, 118, 135, 117, 120, 104, 104, 104, 119, 135, 119, 119, 120, 135, 119, 135, 119, 135, 136, 136, 135, 103, 136, 119, 119
        .byte   135, 103, 104, 104, 119, 120, 119, 103, 119, 119, 120, 120, 120, 118, 104, 119, 102, 103, 117, 119, 136, 103, 103, 86, 103, 120, 120, 87, 119, 134, 119, 135
        .byte   119, 119, 134, 120, 135, 118, 119, 119, 119, 119, 103, 104, 136, 120, 120, 119, 120, 119, 136, 152, 135, 120, 135, 119, 136, 135, 120, 134, 120, 120, 103, 134
        .byte   102, 135, 135, 104, 103, 135, 119, 88, 120, 119, 136, 103, 135, 120, 135, 104, 136, 119, 119, 120, 104, 136, 120, 119, 119, 120, 120, 119, 119, 119, 119, 102
        .byte   120, 135, 120, 104, 119, 135, 119, 136, 120, 119, 135, 119, 136, 136, 119, 136, 136, 120, 136, 119, 120, 136, 103, 120, 119, 103, 135, 119, 88, 120, 103, 119
        .byte   103, 104, 102, 120, 119, 104, 119, 103, 103, 118, 120, 103, 120, 135, 102, 86, 119, 120, 134, 103, 120, 135, 120, 119, 119, 135, 135, 120, 136, 135, 119, 136
        .byte   119, 120, 136, 103, 119, 119, 119, 119, 102, 119, 135, 120, 104, 118, 119, 135, 103, 103, 135, 134, 119, 118, 118, 103, 135, 120, 104, 118, 119, 119, 119, 118
        .byte   119, 103, 135, 118, 134, 102, 88, 119, 119, 103, 135, 134, 104, 104, 103, 135, 102, 135, 119, 136, 119, 120, 119, 119, 136, 119, 119, 104, 120, 120, 136, 119
        .byte   118, 120, 118, 102, 102, 104, 119, 119, 134, 119, 101, 119, 118, 103, 134, 135, 119, 135, 118, 103, 117, 119, 102, 119, 119, 134, 134, 87, 119, 135, 87, 88
        .byte   103, 136, 71, 103, 119, 120, 103, 120, 117, 119, 103, 119, 120, 135, 117, 86, 119, 87, 119, 119, 120, 116, 117, 133, 119, 119, 117, 119, 117, 119, 119, 119
        .byte   119, 104, 103, 104, 119, 118, 135, 119, 103, 135, 102, 85, 103, 135, 118, 103, 118, 87, 119, 104, 134, 102, 103, 119, 103, 116, 102, 118, 86, 100, 100, 132
        .byte   102, 103, 70, 118, 99, 104, 102, 71, 71, 118, 102, 119, 119, 119, 101, 134, 103, 87, 104, 119, 88, 119, 119, 104, 103, 102, 118, 119, 119, 103, 120, 117
        .byte   103, 103, 103, 135, 103, 134, 103, 135, 120, 120, 135, 119, 119, 119, 135, 136, 119, 119, 135, 119, 120, 103, 134, 103, 104, 103, 135, 88, 103, 104, 136, 103
        .byte   120, 102, 119, 119, 102, 120, 103, 118, 119, 104, 118, 119, 136, 119, 103, 134, 104, 119, 120, 86, 119, 120, 119, 118, 104, 119, 135, 135, 120, 118, 135, 120
        .byte   120, 104, 119, 119, 101, 102, 117, 85, 119, 119, 70, 119, 118, 87, 135, 119, 117, 135, 135, 118, 117, 103, 102, 135, 120, 104, 119, 103, 119, 135, 118, 119
        .byte   134, 135, 119, 118, 135, 119, 103, 135, 119, 118, 120, 135, 117, 118, 104, 87, 119, 87, 120, 103, 103, 87, 119, 119, 118, 71, 118, 119, 119, 134, 136, 117
        .byte   119, 119, 87, 117, 87, 104, 119, 87, 87, 119, 119, 72, 119, 132, 102, 118, 102, 69, 100, 70, 104, 102, 71, 118, 71, 102, 54, 103, 70, 118, 103, 118
        .byte   119, 119, 85, 86, 119, 118, 120, 86, 134, 102, 120, 120, 135, 117, 119, 120, 119, 118, 103, 119, 135, 120, 134, 103, 104, 119, 118, 118, 117, 103, 135, 119
        .byte   119, 101, 104, 103, 119, 103, 87, 119, 104, 120, 118, 103, 118, 119, 120, 134, 119, 118, 134, 88, 119, 119, 134, 119, 119, 135, 103, 135, 118, 87, 118, 118
        .byte   102, 103, 136, 102, 119, 119, 118, 135, 120, 102, 118, 118, 102, 120, 135, 102, 135, 118, 120, 118, 136, 117, 118, 120, 118, 117, 118, 119, 103, 118, 134, 119
        .byte   118, 103, 134, 119, 118, 119, 120, 117, 119, 87, 119, 85, 87, 136, 119, 86, 118, 135, 71, 119, 120, 135, 135, 103, 120, 119, 119, 118, 119, 102, 118, 119
        .byte   118, 119, 103, 119, 119, 135, 118, 135, 119, 118, 119, 119, 103, 135, 118, 134, 119, 118, 120, 104, 119, 119, 119, 104, 119, 136, 134, 120, 104, 119, 119, 120
        .byte   119, 120, 119, 119, 103, 135, 104, 119, 134, 120, 103, 119, 119, 119, 86, 119, 135, 118, 119, 104, 104, 119, 119, 119, 118, 118, 119, 118, 119, 135, 103, 134
        .byte   103, 104, 103, 134, 104, 118, 118, 102, 119, 119, 117, 103, 135, 119, 135, 120, 136, 135, 118, 102, 119, 119, 103, 118, 119, 87, 119, 136, 119, 134, 104, 135
        .byte   134, 119, 134, 119, 102, 104, 119, 120, 119, 119, 120, 119, 118, 120, 134, 117, 134, 119, 103, 118, 134, 135, 134, 119, 119, 119, 118, 120, 120, 120, 119, 134
        .byte   136, 135, 136, 119, 136, 119, 135, 120, 135, 135, 118, 104, 86, 120, 119, 103, 135, 119, 118, 136, 120, 103, 135, 103, 136, 136, 136, 136, 136, 120, 136, 134
        .byte   120, 119, 119, 135, 135, 135, 120, 119, 119, 119, 135, 119, 119, 119, 103, 119, 119, 135, 134, 102, 136, 103, 120, 119, 120, 135, 119, 119, 118, 120, 119, 119
        .byte   104, 120, 103, 103, 118, 104, 119, 120, 135, 120, 134, 120, 120, 102, 120, 135, 135, 119, 135, 119, 136, 119, 120, 135, 134, 118, 119, 135, 119, 136, 135, 120
        .byte   118, 120, 119, 135, 136, 119, 119, 134, 135, 104, 104, 135, 133, 119, 120, 104, 119, 118, 119, 120, 119, 120, 119, 120, 119, 102, 135, 104, 119, 103, 119, 134
        .byte   119, 103, 118, 118, 119, 119, 117, 119, 135, 102, 136, 103, 119, 102, 119, 118, 119, 119, 136, 136, 119, 119, 119, 103, 120, 102, 104, 135, 120, 118, 120, 133
        .byte   119, 119, 136, 118, 135, 135, 103, 119, 118, 119, 135, 119, 119, 104, 118, 117, 87, 119, 84, 119, 135, 85, 87, 103, 103, 104, 118, 101, 117, 119, 119, 103
        .byte   120, 119, 134, 119, 102, 118, 86, 118, 136, 117, 102, 120, 134, 103, 136, 104, 120, 135, 103, 134, 119, 119, 119, 119, 135, 118, 119, 120, 104, 104, 103, 104
        .byte   119, 87, 119, 119, 135, 120, 120, 134, 120, 120, 120, 119, 136, 134, 119, 120, 104, 119, 135, 135, 134, 119, 151, 119, 104, 135, 135, 118, 135, 118, 103, 119
        .byte   119, 118, 119, 134, 87, 135, 120, 135, 118, 119, 118, 135, 135, 103, 87, 120, 103, 104, 119, 118, 103, 135, 121, 118, 117, 119, 119, 119, 101, 117, 117, 119
        .byte   120, 88, 118, 116, 120, 103, 87, 87, 120, 102, 119, 119, 118, 118, 119, 136, 103, 120, 135, 102, 102, 119, 117, 120, 120, 118, 103, 120, 118, 118, 135, 117
        .byte   103, 104, 103, 119, 134, 119, 120, 85, 120, 118, 119, 102, 119, 132, 119, 119, 134, 136, 119, 117, 87, 103, 104, 119, 117, 119, 86, 119, 117, 134, 135, 120
        .byte   84, 102, 133, 71, 119, 103, 119, 118, 119, 101, 134, 119, 87, 104, 119, 88, 119, 119, 120, 87, 119, 119, 103, 103, 119, 134, 87, 135, 134, 118, 103, 119
        .byte   134, 118, 87, 118, 103, 103, 119, 103, 120, 118, 103, 117, 103, 103, 119, 103, 116, 103, 133, 102, 69, 84, 69, 88, 102, 72, 118, 71, 101, 55, 103, 152
        .byte   136, 120, 119, 119, 120, 120, 120, 135, 119, 135, 120, 119, 103, 120, 120, 103, 120, 119, 120, 103, 119, 134, 120, 136, 119, 119, 119, 135, 120, 119, 120, 135
        .byte   135, 119, 136, 103, 119, 135, 103, 119, 118, 119, 119, 134, 135, 136, 135, 119, 120, 119, 119, 135, 135, 119, 103, 135, 119, 119, 119, 103, 120, 135, 135, 119
        .byte   102, 135, 119, 120, 120, 135, 103, 118, 103, 103, 119, 120, 152, 119, 119, 103, 119, 119, 102, 120, 135, 103, 120, 135, 120, 119, 120, 136, 136, 135, 103, 119
        .byte   120, 120, 119, 135, 103, 120, 136, 136, 119, 120, 136, 120, 135, 119, 135, 135, 135, 134, 135, 135, 135, 135, 136, 136, 134, 136, 135, 119, 119, 120, 136, 135
        .byte   136, 135, 136, 135, 120, 136, 119, 120, 120, 135, 135, 136, 134, 120, 135, 119, 136, 135, 120, 119, 120, 120, 136, 119, 119, 135, 120, 104, 120, 119, 136, 120
        .byte   104, 119, 136, 120, 120, 119, 120, 119, 136, 135, 120, 135, 136, 135, 120, 136, 135, 120, 120, 135, 120, 135, 119, 135, 135, 119, 136, 119, 135, 134, 136, 136
        .byte   136, 119, 136, 151, 136, 136, 120, 120, 136, 136, 136, 136, 136, 136, 120, 136, 119, 119, 119, 119, 136, 119, 120, 119, 136, 119, 134, 120, 135, 118, 119, 135
        .byte   120, 88, 119, 102, 135, 119, 118, 104, 135, 120, 103, 119, 135, 104, 136, 120, 136, 118, 104, 119, 103, 134, 136, 135, 117, 134, 118, 119, 136, 118, 135, 134
        .byte   136, 119, 136, 135, 120, 135, 119, 120, 119, 136, 136, 136, 119, 120, 134, 119, 135, 103, 104, 136, 118, 119, 119, 119, 134, 120, 135, 87, 135, 120, 120, 135
        .byte   135, 135, 135, 136, 135, 120, 136, 135, 136, 119, 119, 118, 135, 136, 135, 103, 135, 119, 119, 136, 103, 120, 120, 103, 120, 135, 119, 118, 119, 103, 119, 103
        .byte   103, 136, 103, 135, 87, 135, 135, 134, 119, 104, 135, 120, 119, 104, 120, 102, 103, 118, 118, 119, 87, 119, 120, 118, 119, 120, 119, 103, 119, 119, 104, 120
        .byte   119, 120, 119, 103, 119, 119, 120, 118, 118, 135, 101, 119, 118, 101, 102, 103, 118, 135, 101, 118, 103, 118, 134, 134, 135, 117, 102, 134, 118, 134, 118, 134
        .byte   103, 135, 103, 119, 119, 119, 134, 119, 102, 119, 119, 103, 118, 87, 135, 134, 120, 119, 102, 135, 119, 120, 136, 119, 135, 119, 119, 135, 119, 103, 118, 119
        .byte   119, 120, 134, 135, 135, 119, 135, 87, 119, 120, 136, 135, 134, 103, 136, 120, 119, 134, 119, 134, 103, 136, 134, 120, 135, 136, 135, 119, 119, 119, 135, 135
        .byte   120, 135, 120, 135, 120, 119, 119, 119, 119, 120, 119, 135, 135, 135, 119, 120, 118, 104, 134, 135, 119, 119, 118, 120, 120, 120, 119, 135, 135, 119, 135, 102
        .byte   135, 120, 134, 103, 119, 118, 135, 118, 104, 118, 134, 120, 120, 87, 119, 134, 119, 103, 103, 102, 134, 103, 102, 87, 134, 102, 135, 119, 87, 119, 118, 119
        .byte   136, 120, 119, 134, 135, 135, 119, 118, 136, 119, 120, 120, 120, 136, 118, 119, 120, 135, 119, 120, 118, 118, 104, 136, 135, 119, 120, 120, 135, 119, 119, 135
        .byte   120, 120, 136, 136, 120, 119, 136, 136, 118, 135, 120, 120, 120, 119, 120, 135, 135, 119, 135, 136, 135, 120, 135, 135, 136, 135, 119, 119, 134, 118, 103, 135
        .byte   103, 119, 104, 136, 119, 119, 104, 135, 118, 119, 136, 104, 119, 118, 134, 118, 87, 119, 136, 102, 120, 136, 104, 103, 119, 120, 119, 135, 119, 136, 134, 135
        .byte   118, 119, 118, 103, 120, 118, 119, 119, 120, 118, 119, 119, 119, 118, 103, 119, 103, 135, 103, 136, 118, 118, 104, 119, 119, 104, 118, 118, 121, 118, 135, 103
        .byte   104, 118, 86, 119, 120, 120, 134, 120, 135, 120, 135, 136, 136, 119, 119, 119, 120, 135, 136, 119, 135, 120, 118, 135, 119, 119, 104, 119, 119, 136, 135, 118
        .byte   120, 135, 134, 134, 135, 134, 120, 134, 120, 134, 119, 118, 136, 135, 86, 120, 120, 120, 120, 136, 135, 120, 135, 135, 136, 135, 136, 136, 135, 136, 136, 136
        .byte   120, 119, 104, 118, 119, 119, 134, 135, 135, 103, 119, 103, 136, 120, 120, 119, 135, 120, 134, 119, 135, 119, 151, 119, 134, 120, 119, 119, 136, 136, 135, 120
        .byte   136, 103, 119, 120, 120, 119, 135, 119, 119, 136, 120, 119, 136, 120, 118, 135, 135, 120, 136, 120, 120, 119, 136, 135, 136, 136, 136, 120, 120, 119, 134, 119
        .byte   136, 119, 120, 119, 119, 136, 104, 120, 136, 135, 135, 118, 136, 135, 119, 136, 135, 120, 136, 120, 119, 135, 135, 134, 135, 135, 134, 136, 136, 135, 136, 135
        .byte   136, 135, 135, 136, 136, 120, 120, 136, 135, 135, 120, 120, 135, 120, 135, 135, 136, 135, 135, 120, 120, 135, 119, 104, 135, 135, 136, 119, 136, 120, 120, 136
        .byte   135, 120, 136, 135, 135, 134, 136, 120, 117, 87, 119, 117, 103, 119, 133, 119, 86, 119, 117, 119, 132, 119, 136, 120, 119, 119, 136, 120, 120, 135, 135, 119
        .byte   120, 120, 118, 135, 120, 134, 103, 119, 118, 119, 103, 119, 118, 135, 103, 119, 102, 87, 119, 120, 134, 102, 103, 101, 103, 101, 104, 119, 103, 134, 118, 117
        .byte   118, 103, 103, 119, 103, 104, 118, 118, 87, 135, 119, 119, 135, 134, 117, 118, 103, 135, 119, 135, 120, 118, 104, 103, 120, 119, 103, 136, 135, 135, 120, 119
        .byte   120, 101, 135, 103, 119, 103, 119, 119, 118, 119, 120, 134, 120, 136, 118, 103, 151, 103, 119, 134, 119, 120, 118, 120, 134, 135, 119, 119, 118, 119, 119, 104
        .byte   120, 103, 103, 119, 120, 104, 119, 120, 119, 87, 134, 135, 135, 119, 119, 134, 135, 136, 119, 135, 119, 121, 135, 118, 103, 120, 135, 104, 135, 117, 119, 136
        .byte   103, 87, 117, 88, 119, 119, 87, 119, 87, 120, 72, 119, 87, 119, 118, 134, 104, 103, 104, 103, 103, 118, 134, 104, 135, 119, 133, 135, 119, 118, 135, 119
        .byte   120, 103, 119, 118, 119, 135, 120, 119, 102, 135, 119, 135, 134, 119, 118, 102, 119, 119, 118, 104, 136, 119, 103, 104, 120, 120, 118, 136, 103, 119, 120, 135
        .byte   119, 119, 119, 102, 135, 120, 120, 119, 134, 119, 103, 119, 120, 120, 136, 136, 119, 135, 119, 136, 135, 135, 119, 120, 136, 136, 135, 120, 136, 118, 136, 120
        .byte   119, 135, 135, 135, 120, 120, 103, 120, 135, 119, 119, 102, 118, 136, 120, 102, 101, 102, 120, 119, 104, 103, 120, 119, 120, 120, 104, 102, 120, 120, 103, 120
        .byte   136, 87, 120, 136, 118, 119, 136, 119, 134, 120, 136, 119, 120, 135, 135, 118, 135, 119, 136, 119, 120, 136, 119, 119, 119, 119, 119, 119, 135, 135, 102, 120
        .byte   119, 119, 103, 103, 134, 103, 120, 119, 102, 118, 119, 88, 103, 120, 103, 119, 103, 135, 119, 135, 119, 103, 135, 118, 119, 136, 102, 119, 119, 103, 118, 103
        .byte   135, 119, 135, 135, 103, 136, 136, 136, 136, 104, 119, 119, 136, 135, 104, 119, 88, 119, 119, 134, 135, 119, 104, 120, 118, 119, 103, 134, 119, 134, 119, 120
        .byte   119, 120, 117, 119, 119, 103, 134, 119, 119, 134, 134, 120, 102, 119, 119, 135, 119, 103, 118, 119, 120, 135, 104, 120, 120, 119, 119, 120, 119, 120, 119, 119
        .byte   104, 119, 120, 134, 136, 119, 135, 136, 135, 120, 119, 119, 136, 119, 136, 136, 134, 87, 135, 120, 103, 120, 102, 136, 103, 119, 119, 135, 120, 119, 134, 119
        .byte   120, 134, 119, 133, 119, 118, 118, 135, 134, 136, 120, 135, 136, 119, 119, 134, 120, 104, 120, 135, 136, 136, 120, 119, 119, 103, 87, 119, 136, 119, 103, 119
        .byte   88, 118, 135, 119, 118, 118, 118, 118, 136, 119, 103, 118, 104, 118, 104, 103, 119, 119, 119, 119, 135, 119, 119, 136, 135, 119, 119, 120, 136, 102, 135, 135
        .byte   103, 136, 136, 135, 119, 87, 119, 118, 117, 119, 134, 118, 132, 133, 118, 133, 119, 119, 134, 85, 71, 136, 136, 103, 103, 104, 117, 118, 103, 133, 117, 119
        .byte   104, 104, 119, 103, 135, 151, 104, 120, 135, 104, 119, 119, 135, 135, 119, 136, 120, 136, 135, 103, 137, 104, 119, 118, 135, 119, 119, 103, 119, 118, 135, 119
        .byte   119, 119, 103, 103, 120, 120, 134, 102, 136, 119, 119, 120, 119, 102, 119, 136, 118, 119, 119, 118, 103, 103, 118, 118, 103, 119, 102, 103, 120, 119, 87, 87
        .byte   120, 135, 102, 102, 118, 116, 119, 118, 101, 117, 120, 120, 103, 119, 135, 119, 136, 120, 120, 135, 135, 120, 119, 120, 119, 103, 135, 135, 104, 136, 120, 119
        .byte   119, 119, 103, 118, 119, 120, 119, 103, 119, 135, 104, 104, 135, 119, 119, 120, 136, 136, 118, 119, 119, 119, 120, 118, 118, 118, 120, 120, 120, 135, 120, 119
        .byte   135, 119, 136, 120, 103, 119, 119, 119, 120, 119, 102, 119, 134, 118, 118, 118, 120, 86, 118, 119, 88, 119, 119, 120, 102, 118, 119, 136, 134, 119, 119, 119
        .byte   101, 102, 104, 135, 102, 103, 134, 103, 119, 104, 135, 119, 119, 103, 119, 120, 118, 119, 134, 119, 103, 119, 103, 102, 119, 119, 117, 119, 118, 86, 134, 120
        .byte   102, 86, 104, 87, 102, 119, 120, 120, 136, 136, 135, 136, 119, 120, 136, 120, 136, 119, 119, 120, 120, 135, 136, 136, 136, 136, 135, 120, 119, 136, 136, 119
        .byte   120, 136, 136, 120, 135, 135, 135, 119, 135, 134, 134, 104, 136, 118, 135, 135, 135, 119, 135, 119, 120, 120, 135, 135, 119, 120, 119, 136, 135, 134, 136, 136
        .byte   136, 120, 136, 136, 136, 119, 136, 119, 136, 119, 121, 136, 136, 136, 135, 136, 136, 135, 120, 120, 135, 135, 136, 120, 120, 135, 136, 136, 136, 120, 136, 136
        .byte   136, 120, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 120, 118, 120, 136, 117, 135, 118, 118, 118, 119, 134, 103, 133, 102, 119, 118, 135, 119
        .byte   135, 135, 120, 136, 135, 134, 104, 151, 136, 136, 119, 120, 135, 120, 119, 135, 134, 136, 135, 120, 136, 119, 119, 135, 104, 135, 119, 135, 136, 134, 135, 119
        .byte   119, 135, 120, 119, 135, 120, 135, 136, 136, 120, 119, 134, 136, 152, 87, 136, 119, 119, 118, 135, 103, 135, 135, 103, 120, 136, 119, 119, 135, 119, 119, 119
        .byte   103, 119, 135, 103, 102, 119, 120, 118, 102, 118, 104, 120, 120, 119, 136, 135, 119, 120, 103, 136, 103, 120, 135, 118, 119, 102, 119, 135, 104, 103, 136, 103
        .byte   103, 119, 119, 103, 118, 135, 133, 135, 119, 135, 103, 119, 135, 120, 119, 102, 135, 118, 119, 135, 104, 135, 103, 136, 119, 104, 136, 119, 135, 136, 103, 135
        .byte   119, 136, 119, 135, 119, 119, 104, 118, 102, 120, 117, 104, 120, 103, 120, 119, 104, 136, 118, 120, 135, 119, 135, 119, 120, 118, 135, 135, 136, 119, 136, 119
        .byte   103, 136, 135, 134, 118, 120, 119, 104, 135, 135, 102, 118, 118, 120, 118, 103, 120, 117, 135, 120, 135, 103, 135, 120, 119, 119, 103, 119, 135, 119, 103, 118
        .byte   136, 119, 117, 119, 119, 117, 101, 118, 117, 86, 117, 119, 116, 103, 117, 119, 118, 120, 135, 117, 118, 103, 135, 118, 136, 103, 119, 135, 101, 120, 104, 134
        .byte   120, 119, 133, 136, 103, 119, 133, 119, 120, 136, 118, 104, 119, 119, 135, 135, 135, 134, 120, 119, 120, 118, 136, 135, 134, 135, 120, 136, 118, 119, 134, 102
        .byte   119, 119, 135, 120, 119, 118, 119, 119, 135, 118, 102, 117, 134, 136, 119, 119, 103, 119, 118, 120, 120, 119, 119, 136, 135, 102, 135, 103, 120, 119, 87, 103
        .byte   102, 119, 104, 120, 103, 103, 103, 136, 135, 103, 135, 120, 134, 104, 135, 103, 104, 120, 104, 103, 118, 119, 135, 87, 134, 119, 135, 135, 134, 136, 119, 118
        .byte   136, 119, 119, 135, 120, 136, 120, 120, 135, 103, 135, 103, 120, 103, 119, 135, 120, 119, 104, 119, 119, 104, 120, 135, 120, 136, 136, 136, 120, 120, 120, 136
        .byte   120, 136, 120, 119, 119, 135, 119, 118, 136, 118, 135, 119, 134, 119, 120, 119, 120, 104, 119, 135, 135, 134, 119, 136, 135, 118, 118, 119, 119, 135, 135, 135
        .byte   120, 120, 120, 136, 118, 136, 120, 119, 119, 135, 134, 103, 119, 103, 104, 119, 119, 119, 119, 120, 136, 136, 120, 136, 136, 135, 136, 120, 135, 135, 119, 135
        .byte   136, 136, 135, 135, 136, 136, 136, 136, 136, 135, 120, 135, 135, 119, 120, 135, 119, 136, 119, 119, 135, 135, 120, 104, 152, 135, 119, 134, 120, 119, 104, 135
        .byte   136, 136, 136, 136, 136, 136, 119, 119, 135, 135, 120, 120, 136, 136, 120, 135, 120, 119, 120, 135, 120, 136, 120, 119, 135, 136, 136, 135, 120, 136, 136, 136
        .byte   136, 119, 136, 136, 136, 120, 135, 136, 135, 120, 136, 136, 119, 120, 136, 135, 120, 104, 104, 120, 119, 136, 136, 136, 119, 120, 136, 120, 119, 135, 136, 103
        .byte   119, 135, 135, 135, 103, 135, 119, 120, 118, 120, 103, 118, 103, 135, 119, 102, 118, 102, 118, 102, 103, 119, 85, 103, 119, 102, 135, 136, 136, 136, 119, 136
        .byte   119, 120, 119, 135, 120, 119, 119, 103, 135, 120, 120, 120, 136, 104, 136, 103, 119, 119, 119, 120, 120, 120, 104, 120, 103, 120, 103, 119, 120, 119, 136, 133
        .byte   104, 120, 103, 103, 119, 134, 103, 120, 118, 119, 135, 119, 135, 134, 136, 119, 119, 119, 135, 119, 119, 119, 120, 120, 120, 120, 119, 120, 103, 136, 103, 118
        .byte   120, 119, 119, 120, 136, 119, 119, 102, 135, 120, 120, 87, 136, 86, 120, 119, 103, 117, 119, 100, 103, 119, 103, 103, 120, 120, 132, 103, 118, 87, 119, 117
        .byte   119, 135, 88, 120, 104, 136, 120, 118, 134, 119, 117, 135, 135, 136, 134, 134, 86, 135, 119, 136, 119, 87, 119, 119, 118, 118, 135, 102, 104, 135, 118, 88
        .byte   103, 103, 119, 135, 118, 102, 104, 87, 119, 117, 121, 119, 104, 86, 120, 119, 70, 88, 102, 100, 134, 135, 54, 70, 120, 103, 119, 71, 132, 132, 118, 119
        .byte   118, 103, 103, 136, 118, 102, 119, 88, 117, 119, 118, 118, 118, 118, 135, 103, 120, 120, 120, 120, 119, 118, 120, 134, 119, 117, 136, 135, 118, 136, 136, 119
        .byte   134, 135, 119, 103, 135, 136, 103, 120, 104, 136, 88, 119, 119, 135, 136, 119, 136, 120, 135, 120, 120, 119, 120, 136, 118, 136, 103, 119, 120, 120, 119, 119
        .byte   120, 134, 135, 120, 119, 118, 120, 119, 134, 136, 86, 118, 120, 117, 103, 135, 84, 103, 119, 85, 88, 104, 87, 104, 120, 119, 119, 103, 135, 103, 135, 103
        .byte   119, 119, 119, 119, 119, 119, 104, 102, 135, 120, 120, 103, 103, 119, 135, 119, 119, 103, 119, 119, 119, 103, 118, 135, 120, 133, 103, 102, 103, 118, 103, 119
        .byte   105, 135, 119, 117, 103, 103, 103, 103, 135, 135, 119, 119, 134, 102, 120, 119, 119, 135, 102, 119, 117, 120, 133, 119, 119, 136, 118, 120, 103, 119, 87, 120
        .byte   104, 119, 102, 119, 101, 102, 103, 101, 101, 118, 86, 86, 101, 87, 102, 71, 118, 86, 102, 104, 135, 135, 119, 119, 118, 120, 101, 135, 119, 135, 103, 120
        .byte   118, 102, 134, 119, 118, 120, 104, 135, 119, 104, 120, 119, 120, 120, 104, 104, 119, 102, 87, 102, 120, 119, 118, 119, 120, 103, 119, 135, 103, 102, 118, 119
        .byte   136, 119, 135, 104, 120, 120, 119, 104, 135, 134, 119, 135, 120, 120, 119, 119, 120, 135, 119, 135, 120, 119, 136, 135, 119, 136, 103, 103, 136, 120, 119, 119
        .byte   135, 135, 135, 119, 119, 118, 119, 119, 118, 120, 119, 136, 118, 135, 103, 134, 119, 103, 103, 120, 120, 104, 118, 102, 136, 135, 118, 133, 135, 136, 136, 104
        .byte   135, 135, 103, 136, 120, 119, 120, 120, 119, 119, 119, 102, 136, 118, 135, 135, 120, 117, 86, 135, 119, 118, 119, 120, 103, 134, 103, 119, 86, 119, 103, 119
        .byte   119, 102, 120, 135, 104, 87, 135, 118, 103, 136, 119, 134, 118, 119, 103, 88, 119, 118, 119, 102, 104, 135, 103, 103, 118, 104, 120, 119, 102, 119, 102, 119
        .byte   120, 120, 87, 119, 120, 104, 119, 103, 119, 119, 136, 134, 136, 103, 119, 119, 135, 103, 103, 136, 136, 136, 119, 135, 119, 103, 135, 120, 103, 134, 87, 134
        .byte   119, 118, 119, 134, 119, 103, 119, 119, 118, 133, 102, 120, 118, 135, 103, 134, 102, 119, 134, 103, 136, 136, 135, 135, 135, 135, 120, 119, 120, 119, 136, 135
        .byte   119, 135, 118, 119, 103, 118, 119, 119, 135, 135, 120, 119, 118, 119, 118, 118, 119, 119, 135, 133, 135, 119, 119, 135, 134, 136, 119, 118, 119, 120, 102, 136
        .byte   135, 120, 119, 136, 135, 135, 120, 119, 119, 104, 104, 135, 119, 119, 119, 135, 136, 120, 134, 136, 119, 120, 119, 119, 135, 119, 135, 119, 104, 119, 134, 134
        .byte   135, 135, 119, 119, 136, 120, 119, 119, 136, 135, 119, 119, 118, 120, 103, 103, 102, 120, 135, 119, 120, 87, 119, 120, 136, 103, 118, 136, 118, 118, 119, 118
        .byte   102, 103, 119, 118, 119, 119, 87, 119, 118, 102, 118, 103, 103, 119, 134, 102, 119, 101, 86, 119, 119, 120, 119, 118, 102, 135, 103, 136, 135, 135, 120, 119
        .byte   135, 135, 135, 136, 118, 120, 135, 136, 120, 135, 136, 135, 119, 136, 135, 119, 120, 135, 104, 135, 136, 136, 135, 120, 119, 135, 120, 120, 135, 135, 136, 104
        .byte   120, 120, 119, 119, 119, 135, 119, 135, 135, 120, 136, 136, 135, 136, 136, 135, 135, 120, 136, 119, 136, 120, 136, 119, 119, 136, 136, 104, 136, 120, 120, 135
        .byte   120, 120, 136, 120, 120, 136, 119, 119, 135, 120, 135, 120, 135, 136, 119, 120, 134, 135, 136, 136, 120, 136, 136, 135, 136, 136, 135, 135, 119, 136, 120, 136
        .byte   135, 136, 135, 136, 136, 87, 136, 119, 119, 118, 120, 120, 136, 118, 119, 120, 118, 103, 120, 119, 119, 135, 119, 119, 119, 103, 135, 120, 134, 119, 118, 135
        .byte   119, 119, 104, 136, 136, 136, 120, 135, 104, 136, 120, 134, 119, 136, 119, 136, 119, 104, 136, 119, 119, 119, 118, 87, 136, 119, 120, 119, 119, 102, 135, 120
        .byte   119, 120, 120, 120, 119, 119, 135, 136, 119, 119, 135, 135, 119, 136, 118, 119, 118, 119, 135, 136, 135, 151, 135, 136, 103, 118, 135, 136, 119, 119, 118, 118
        .byte   119, 118, 118, 119, 102, 103, 118, 88, 118, 88, 119, 102, 103, 135, 118, 119, 119, 135, 119, 119, 136, 119, 118, 135, 103, 118, 103, 134, 119, 136, 136, 119
        .byte   135, 136, 120, 119, 104, 120, 135, 104, 136, 135, 119, 119, 135, 136, 120, 136, 135, 103, 136, 135, 120, 136, 119, 119, 120, 136, 120, 119, 120, 136, 120, 120
        .byte   103, 119, 136, 120, 120, 120, 104, 120, 135, 136, 136, 119, 136, 119, 119, 134, 120, 135, 136, 120, 119, 119, 120, 135, 135, 118, 119, 136, 135, 136, 120, 136
        .byte   120, 119, 136, 119, 136, 135, 136, 136, 120, 119, 120, 119, 120, 136, 135, 119, 135, 119, 119, 119, 135, 105, 136, 136, 136, 120, 134, 119, 135, 135, 120, 120
        .byte   103, 120, 119, 120, 119, 135, 134, 118, 135, 120, 135, 135, 136, 135, 119, 119, 119, 119, 136, 119, 120, 120, 135, 103, 119, 120, 119, 119, 118, 119, 118, 120
        .byte   119, 103, 119, 120, 119, 101, 120, 118, 104, 120, 87, 104, 118, 120, 71, 135, 119, 86, 134, 135, 134, 119, 119, 119, 119, 134, 119, 134, 134, 103, 119, 134
        .byte   119, 119, 135, 135, 135, 118, 118, 136, 134, 119, 119, 120, 119, 135, 135, 119, 119, 133, 119, 118, 119, 136, 71, 102, 87, 119, 133, 120, 118, 134, 136, 134
        .byte   118, 135, 118, 103, 118, 118, 120, 119, 101, 102, 118, 119, 103, 86, 135, 118, 136, 136, 134, 119, 136, 135, 136, 119, 135, 119, 119, 135, 120, 120, 119, 119
        .byte   137, 120, 120, 103, 136, 120, 135, 120, 136, 136, 136, 136, 119, 136, 136, 119, 104, 135, 119, 136, 137, 119, 135, 135, 103, 136, 120, 135, 135, 135, 119, 118
        .byte   119, 103, 120, 119, 120, 119, 120, 135, 135, 120, 119, 135, 120, 120, 135, 120, 119, 135, 119, 120, 135, 136, 103, 136, 120, 120, 119, 118, 119, 136, 135, 104
        .byte   134, 135, 103, 119, 136, 135, 119, 118, 135, 136, 135, 120, 119, 135, 120, 104, 135, 135, 119, 120, 120, 119, 120, 103, 120, 120, 119, 120, 120, 103, 103, 120
        .byte   135, 120, 136, 119, 135, 134, 104, 135, 120, 119, 135, 135, 118, 135, 120, 119, 119, 120, 119, 134, 119, 119, 118, 120, 134, 119, 119, 87, 119, 102, 119, 118
        .byte   104, 103, 135, 135, 120, 134, 103, 119, 119, 119, 135, 135, 103, 103, 134, 119, 119, 135, 87, 135, 117, 120, 120, 102, 103, 134, 120, 117, 118, 119, 134, 102
        .byte   104, 119, 118, 119, 135, 103, 103, 119, 117, 120, 119, 118, 136, 103, 118, 103, 118, 135, 119, 136, 119, 135, 119, 119, 104, 136, 104, 119, 120, 118, 119, 136
        .byte   136, 135, 119, 136, 135, 120, 119, 120, 120, 120, 119, 136, 136, 136, 136, 119, 135, 135, 104, 119, 119, 136, 119, 104, 119, 119, 119, 135, 135, 120, 134, 136
        .byte   135, 120, 87, 134, 134, 136, 134, 119, 135, 104, 119, 104, 103, 119, 104, 120, 134, 136, 136, 119, 117, 119, 136, 119, 118, 103, 119, 119, 120, 102, 104, 119
        .byte   119, 119, 119, 135, 134, 88, 119, 103, 103, 120, 135, 135, 103, 135, 104, 120, 120, 120, 120, 119, 119, 103, 119, 119, 119, 118, 119, 120, 136, 136, 118, 120
        .byte   102, 120, 135, 120, 135, 103, 119, 120, 136, 119, 136, 136, 120, 135, 120, 136, 136, 136, 135, 136, 120, 135, 136, 121, 135, 120, 135, 136, 135, 152, 135, 135
        .byte   135, 136, 120, 136, 120, 135, 135, 119, 136, 136, 120, 119, 136, 119, 119, 135, 119, 120, 120, 120, 135, 136, 135, 136, 135, 136, 136, 136, 136, 136, 136, 135
        .byte   135, 120, 136, 119, 120, 136, 120, 135, 135, 136, 136, 119, 136, 136, 120, 120, 135, 135, 136, 120, 135, 136, 136, 136, 104, 135, 120, 136, 136, 136, 135, 151
        .byte   119, 120, 120, 134, 119, 119, 136, 119, 136, 118, 119, 120, 88, 136, 118, 136, 135, 103, 136, 119, 119, 135, 119, 119, 104, 120, 104, 135, 120, 119, 117, 119
        .byte   102, 119, 136, 120, 119, 136, 119, 119, 136, 135, 134, 135, 104, 120, 135, 135, 87, 135, 118, 133, 119, 135, 118, 132, 133, 119, 117, 119, 120, 135, 85, 135
        .byte   118, 103, 119, 119, 135, 119, 119, 103, 103, 134, 102, 118, 119, 119, 135, 119, 103, 104, 103, 119, 120, 135, 119, 119, 119, 118, 135, 119, 119, 103, 135, 136
        .byte   119, 135, 120, 118, 120, 136, 119, 134, 120, 135, 134, 136, 135, 136, 136, 119, 120, 136, 119, 103, 103, 119, 136, 120, 119, 118, 119, 119, 104, 135, 120, 119
        .byte   118, 119, 119, 120, 118, 119, 135, 118, 87, 103, 119, 119, 134, 120, 135, 120, 119, 120, 136, 119, 135, 119, 102, 104, 135, 118, 134, 134, 102, 119, 118, 86
        .byte   118, 120, 102, 102, 104, 102, 101, 120, 119, 117, 119, 119, 120, 119, 135, 119, 119, 103, 118, 120, 136, 118, 104, 117, 119, 119, 101, 119, 103, 116, 87, 118
        .byte   87, 102, 117, 120, 119, 87, 103, 134, 118, 135, 119, 119, 119, 103, 119, 120, 103, 119, 120, 135, 119, 118, 135, 120, 119, 103, 103, 102, 119, 119, 119, 118
        .byte   102, 120, 119, 88, 120, 120, 135, 102, 102, 103, 119, 119, 103, 134, 118, 103, 135, 119, 117, 134, 103, 102, 118, 101, 102, 103, 104, 103, 103, 135, 86, 119
        .byte   117, 87, 136, 119, 118, 136, 103, 134, 120, 119, 103, 118, 103, 119, 118, 118, 101, 136, 103, 136, 119, 135, 119, 135, 135, 102, 119, 103, 119, 135, 119, 119
        .byte   103, 134, 119, 119, 136, 119, 119, 119, 103, 118, 119, 135, 120, 119, 119, 102, 119, 119, 104, 103, 119, 118, 135, 104, 86, 135, 118, 102, 119, 102, 120, 136
        .byte   119, 119, 119, 103, 134, 120, 120, 119, 120, 104, 136, 103, 136, 119, 88, 118, 71, 135, 119, 119, 85, 88, 119, 87, 118, 118, 117, 119, 101, 118, 119, 102
        .byte   135, 118, 120, 118, 119, 118, 118, 136, 103, 135, 120, 103, 135, 119, 136, 136, 135, 134, 120, 119, 119, 136, 120, 119, 120, 135, 135, 136, 102, 103, 136, 88
        .byte   134, 119, 134, 118, 136, 118, 135, 103, 135, 134, 136, 136, 104, 135, 103, 135, 135, 134, 117, 134, 135, 136, 120, 135, 133, 87, 104, 102, 135, 136, 104, 135
        .byte   118, 103, 102, 103, 103, 120, 120, 136, 119, 118, 118, 103, 134, 119, 133, 102, 136, 104, 134, 103, 119, 118, 119, 118, 134, 118, 118, 118, 118, 118, 102, 103
        .byte   119, 103, 119, 133, 120, 117, 119, 101, 118, 70, 120, 86, 87, 119, 103, 86, 120, 135, 85, 117, 136, 118, 118, 120, 120, 119, 119, 135, 102, 103, 119, 120
        .byte   119, 119, 119, 134, 119, 119, 87, 102, 135, 102, 119, 102, 102, 103, 119, 101, 119, 118, 134, 103, 102, 103, 86, 135, 103, 102, 103, 103, 103, 119, 101, 101
        .byte   102, 103, 118, 120, 118, 104, 119, 103, 102, 134, 119, 118, 104, 134, 119, 87, 119, 103, 118, 86, 135, 117, 87, 118, 72, 120, 87, 119, 135, 119, 118, 119
        .byte   119, 136, 118, 102, 118, 120, 135, 119, 102, 119, 119, 135, 119, 120, 117, 134, 119, 116, 134, 135, 86, 118, 101, 102, 117, 118, 120, 118, 118, 103, 103, 120
        .byte   134, 134, 120, 119, 103, 135, 119, 119, 119, 119, 119, 136, 119, 118, 136, 120, 134, 135, 119, 120, 120, 119, 119, 103, 135, 120, 135, 119, 103, 118, 104, 118
        .byte   134, 103, 119, 102, 119, 87, 120, 133, 102, 118, 135, 134, 119, 103, 120, 119, 120, 118, 119, 119, 119, 119, 119, 102, 118, 86, 120, 103, 116, 120, 119, 101
        .byte   101, 103, 120, 88, 119, 120, 120, 86, 136, 119, 134, 119, 119, 118, 135, 119, 87, 119, 136, 104, 119, 104, 118, 119, 134, 102, 119, 119, 119, 119, 118, 118
        .byte   104, 119, 104, 119, 104, 101, 121, 119, 103, 119, 119, 118, 135, 135, 119, 118, 120, 119, 135, 118, 135, 118, 120, 119, 120, 119, 135, 135, 118, 119, 102, 119
        .byte   103, 104, 119, 103, 119, 87, 119, 104, 102, 103, 135, 135, 104, 86, 120, 71, 88, 119, 119, 134, 120, 135, 118, 135, 136, 101, 102, 119, 119, 135, 118, 119
        .byte   119, 134, 135, 120, 119, 119, 119, 119, 134, 135, 135, 119, 135, 134, 135, 104, 119, 118, 119, 119, 119, 119, 119, 134, 135, 119, 134, 136, 119, 119, 103, 119
        .byte   135, 119, 120, 102, 135, 136, 118, 119, 119, 135, 119, 136, 119, 119, 136, 120, 135, 120, 119, 136, 120, 104, 136, 135, 136, 136, 120, 119, 136, 136, 135, 103
        .byte   120, 87, 135, 135, 135, 103, 119, 134, 103, 136, 118, 119, 135, 119, 102, 119, 104, 118, 135, 117, 103, 119, 119, 104, 102, 120, 120, 135, 136, 103, 120, 104
        .byte   136, 120, 120, 119, 104, 136, 120, 135, 135, 135, 119, 104, 118, 119, 101, 102, 103, 70, 119, 102, 86, 102, 117, 117, 101, 117, 118, 120, 136, 119, 103, 119
        .byte   135, 118, 104, 136, 118, 103, 120, 120, 88, 117, 103, 151, 85, 84, 118, 117, 103, 134, 116, 117, 118, 85, 87, 135, 135, 87, 119, 103, 104, 134, 104, 120
        .byte   135, 118, 118, 103, 133, 102, 119, 119, 118, 117, 103, 150, 135, 120, 133, 103, 118, 118, 103, 103, 134, 102, 119, 118, 136, 134, 118, 119, 118, 103, 119, 86
        .byte   120, 102, 119, 134, 119, 119, 104, 118, 103, 104, 119, 103, 120, 118, 119, 119, 104, 118, 119, 118, 120, 119, 135, 101, 104, 103, 102, 120, 87, 104, 103, 120
        .byte   136, 134, 118, 118, 120, 135, 103, 119, 103, 135, 118, 119, 102, 87, 103, 120, 102, 104, 84, 119, 119, 84, 119, 103, 85, 119, 103, 86, 101, 118, 87, 117
        .byte   119, 119, 102, 136, 118, 104, 135, 119, 103, 119, 119, 119, 119, 118, 118, 103, 119, 86, 103, 103, 118, 120, 118, 102, 102, 119, 104, 85, 103, 120, 104, 135
        .byte   120, 119, 119, 118, 120, 120, 118, 120, 118, 104, 102, 119, 135, 101, 134, 119, 102, 88, 101, 118, 101, 118, 84, 86, 102, 101, 118, 102, 117, 135, 118, 120
        .byte   88, 134, 120, 119, 118, 103, 102, 135, 119, 119, 134, 120, 119, 120, 120, 119, 118, 119, 119, 118, 119, 136, 119, 103, 135, 120, 103, 119, 119, 119, 135, 103
        .byte   136, 103, 135, 119, 119, 120, 119, 120, 135, 119, 119, 119, 119, 119, 135, 136, 118, 118, 135, 120, 134, 119, 120, 136, 119, 120, 120, 119, 120, 103, 119, 135
        .byte   120, 133, 119, 136, 104, 119, 119, 103, 117, 118, 103, 120, 102, 119, 134, 120, 120, 87, 118, 118, 102, 134, 104, 136, 135, 134, 119, 119, 119, 120, 104, 135
        .byte   119, 135, 103, 135, 135, 88, 135, 119, 120, 120, 118, 120, 119, 135, 135, 135, 104, 135, 134, 119, 119, 103, 117, 136, 118, 87, 102, 102, 136, 134, 118, 119
        .byte   103, 102, 120, 102, 117, 120, 119, 119, 102, 102, 134, 103, 119, 135, 118, 103, 119, 103, 104, 135, 136, 119, 136, 118, 88, 120, 136, 104, 120, 104, 104, 118
        .byte   120, 136, 116, 104, 102, 133, 117, 120, 120, 85, 119, 119, 120, 87, 87, 134, 103, 119, 136, 135, 136, 135, 134, 136, 119, 135, 120, 135, 135, 120, 119, 103
        .byte   120, 119, 119, 134, 120, 104, 104, 135, 119, 119, 103, 119, 118, 117, 103, 135, 120, 119, 135, 102, 135, 134, 135, 118, 119, 136, 136, 119, 87, 136, 136, 102
        .byte   136, 117, 120, 134, 118, 118, 118, 117, 104, 135, 102, 119, 103, 118, 118, 118, 117, 88, 135, 134, 87, 119, 118, 103, 103, 119, 119, 102, 135, 120, 119, 119
        .byte   119, 104, 119, 119, 119, 103, 120, 134, 103, 134, 103, 135, 120, 136, 120, 120, 104, 136, 119, 135, 136, 137, 135, 136, 119, 118, 117, 134, 103, 118, 104, 119
        .byte   134, 104, 135, 86, 118, 118, 136, 119, 103, 120, 135, 136, 151, 135, 135, 119, 120, 119, 119, 135, 136, 119, 120, 136, 136, 104, 120, 87, 136, 119, 120, 103
        .byte   136, 119, 104, 120, 135, 119, 120, 119, 135, 120, 135, 104, 120, 103, 119, 119, 135, 119, 119, 135, 135, 118, 120, 103, 119, 120, 102, 136, 135, 136, 120, 135
        .byte   119, 119, 118, 119, 135, 119, 135, 135, 88, 135, 120, 104, 104, 103, 120, 104, 120, 119, 119, 135, 136, 136, 135, 103, 120, 118, 120, 119, 136, 120, 120, 135
        .byte   120, 135, 104, 118, 119, 85, 119, 120, 120, 117, 104, 135, 87, 88, 117, 120, 119, 71, 119, 119, 119, 118, 135, 104, 119, 119, 119, 102, 119, 119, 119, 118
        .byte   118, 120, 118, 119, 120, 86, 87, 120, 135, 119, 103, 118, 117, 119, 119, 71, 118, 119, 136, 118, 104, 102, 119, 117, 118, 118, 103, 103, 119, 87, 102, 132
        .byte   70, 102, 118, 99, 116, 103, 102, 100, 118, 103, 100, 132, 87, 116, 150, 134, 119, 103, 102, 119, 117, 118, 119, 116, 118, 102, 117, 85, 103, 118, 118, 102
        .byte   120, 101, 119, 101, 119, 118, 116, 86, 102, 101, 87, 119, 102, 135, 135, 133, 118, 135, 102, 118, 135, 117, 104, 103, 86, 135, 135, 135, 102, 102, 104, 103
        .byte   119, 102, 119, 101, 87, 118, 103, 119, 102, 119, 136, 119, 102, 120, 136, 104, 120, 136, 119, 104, 87, 119, 136, 119, 103, 119, 119, 119, 120, 119, 119, 102
        .byte   118, 103, 119, 103, 103, 119, 119, 120, 133, 133, 134, 102, 87, 132, 118, 120, 134, 118, 117, 118, 103, 87, 135, 120, 120, 119, 103, 120, 119, 134, 135, 118
        .byte   119, 120, 135, 136, 119, 103, 118, 119, 119, 118, 136, 120, 120, 118, 118, 118, 119, 119, 87, 104, 119, 119, 119, 104, 119, 119, 120, 135, 118, 136, 120, 120
        .byte   119, 120, 135, 103, 117, 102, 103, 117, 103, 104, 87, 119, 136, 103, 116, 117, 118, 119, 102, 135, 119, 119, 134, 119, 135, 135, 136, 135, 119, 103, 135, 135
        .byte   136, 120, 120, 119, 119, 120, 119, 104, 120, 103, 120, 119, 120, 119, 119, 119, 102, 119, 134, 118, 120, 135, 120, 135, 135, 120, 134, 118, 136, 119, 119, 120
        .byte   135, 120, 120, 119, 103, 103, 104, 136, 119, 120, 120, 104, 120, 119, 120, 135, 103, 104, 135, 136, 120, 136, 118, 102, 120, 120, 87, 120, 136, 103, 134, 118
        .byte   135, 118, 119, 119, 104, 104, 119, 118, 120, 135, 101, 134, 119, 120, 136, 119, 104, 135, 120, 120, 120, 120, 120, 120, 120, 119, 134, 136, 119, 103, 103, 136
        .byte   117, 103, 136, 136, 104, 120, 119, 103, 118, 135, 104, 119, 134, 136, 103, 118, 135, 135, 134, 120, 103, 118, 135, 135, 119, 88, 136, 119, 119, 119, 120, 135
        .byte   120, 135, 120, 103, 119, 120, 120, 119, 119, 119, 120, 134, 103, 119, 118, 103, 104, 120, 119, 120, 103, 134, 119, 88, 134, 120, 118, 118, 135, 120, 85, 103
        .byte   120, 118, 118, 119, 119, 104, 103, 120, 135, 120, 119, 135, 103, 103, 136, 136, 119, 104, 120, 135, 119, 119, 118, 103, 119, 119, 118, 119, 120, 104, 119, 120
        .byte   135, 104, 102, 118, 101, 136, 118, 119, 119, 134, 136, 135, 119, 119, 134, 119, 135, 119, 135, 119, 104, 136, 134, 135, 117, 103, 119, 120, 104, 119, 134, 103
        .byte   119, 102, 135, 134, 119, 135, 103, 118, 119, 120, 119, 119, 119, 136, 120, 103, 119, 135, 133, 103, 120, 102, 119, 119, 103, 119, 119, 103, 118, 103, 103, 119
        .byte   136, 119, 120, 119, 135, 120, 135, 103, 104, 136, 119, 104, 119, 119, 120, 135, 136, 135, 119, 119, 135, 103, 119, 135, 119, 135, 103, 120, 135, 120, 119, 135
        .byte   152, 135, 152, 119, 103, 119, 136, 120, 120, 120, 120, 118, 136, 136, 119, 135, 135, 120, 102, 120, 119, 103, 102, 104, 134, 87, 135, 118, 119, 120, 119, 135
        .byte   118, 87, 103, 135, 102, 118, 120, 119, 102, 119, 118, 104, 134, 103, 119, 87, 103, 102, 103, 119, 104, 102, 86, 102, 103, 119, 118, 119, 134, 119, 118, 104
        .byte   119, 104, 118, 119, 103, 103, 103, 119, 86, 118, 87, 135, 101, 119, 119, 135, 103, 102, 119, 120, 102, 104, 120, 103, 103, 119, 119, 134, 136, 119, 135, 119
        .byte   119, 120, 119, 135, 119, 119, 119, 103, 120, 119, 118, 135, 103, 118, 119, 135, 103, 118, 104, 135, 103, 134, 101, 135, 119, 118, 135, 88, 119, 136, 135, 118
        .byte   119, 135, 103, 103, 104, 102, 120, 119, 135, 103, 119, 136, 119, 134, 88, 135, 119, 119, 119, 134, 119, 119, 119, 119, 118, 134, 120, 103, 102, 119, 120, 135
        .byte   101, 135, 134, 119, 134, 119, 120, 119, 118, 136, 119, 119, 135, 104, 135, 103, 118, 119, 118, 135, 134, 120, 119, 119, 119, 120, 119, 118, 88, 134, 104, 118
        .byte   120, 103, 119, 135, 136, 135, 103, 119, 103, 118, 119, 120, 119, 119, 119, 136, 104, 136, 119, 104, 136, 135, 119, 120, 135, 119, 119, 135, 119, 134, 134, 118
        .byte   135, 136, 119, 104, 134, 119, 135, 136, 104, 135, 135, 136, 136, 135, 136, 135, 120, 119, 119, 136, 119, 120, 135, 119, 103, 120, 120, 120, 120, 102, 119, 134
        .byte   102, 135, 120, 103, 118, 119, 119, 134, 119, 104, 118, 88, 119, 119, 103, 120, 134, 119, 119, 119, 102, 134, 119, 103, 118, 118, 119, 133, 120, 134, 119, 135
        .byte   118, 104, 120, 119, 119, 136, 119, 135, 120, 119, 135, 136, 135, 135, 104, 134, 119, 135, 135, 135, 103, 135, 119, 136, 119, 136, 135, 118, 103, 136, 135, 119
        .byte   103, 135, 118, 88, 119, 103, 135, 102, 103, 120, 120, 120, 135, 136, 120, 120, 135, 118, 136, 135, 119, 136, 134, 135, 135, 135, 136, 119, 135, 136, 119, 135
        .byte   118, 119, 136, 119, 135, 118, 119, 102, 104, 136, 118, 118, 119, 118, 87, 136, 119, 119, 135, 86, 119, 135, 118, 119, 119, 118, 104, 120, 102, 104, 135, 119
        .byte   117, 118, 135, 103, 119, 136, 136, 120, 135, 135, 120, 120, 136, 136, 119, 120, 120, 136, 136, 120, 118, 102, 103, 134, 119, 119, 118, 87, 103, 135, 119, 118
        .byte   118, 120, 120, 136, 136, 120, 120, 136, 136, 135, 136, 119, 119, 136, 119, 151, 136, 120, 134, 120, 104, 136, 135, 135, 120, 136, 120, 119, 135, 119, 135, 119
        .byte   135, 103, 136, 103, 120, 119, 135, 118, 135, 118, 133, 118, 104, 135, 118, 120, 119, 120, 103, 119, 103, 119, 120, 136, 135, 135, 120, 120, 119, 103, 120, 134
        .byte   119, 133, 103, 103, 119, 71, 119, 103, 119, 101, 118, 135, 87, 87, 136, 103, 118, 120, 135, 119, 119, 119, 136, 134, 119, 135, 120, 120, 119, 119, 120, 119
        .byte   119, 104, 135, 134, 135, 119, 119, 119, 135, 136, 119, 119, 119, 133, 119, 118, 72, 135, 104, 119, 117, 134, 103, 119, 87, 103, 134, 103, 136, 135, 135, 87
        .byte   104, 135, 120, 135, 134, 119, 104, 103, 136, 135, 136, 136, 118, 104, 134, 119, 118, 135, 134, 119, 119, 117, 135, 119, 119, 88, 120, 104, 103, 119, 120, 118
        .byte   118, 134, 119, 135, 135, 118, 120, 119, 119, 117, 87, 135, 151, 119, 88, 136, 119, 72, 119, 88, 135, 85, 120, 135, 119, 119, 134, 136, 104, 119, 136, 119
        .byte   134, 119, 120, 119, 119, 135, 119, 120, 136, 120, 88, 120, 134, 135, 134, 135, 118, 136, 120, 103, 120, 135, 103, 119, 136, 103, 118, 119, 119, 102, 120, 136
        .byte   88, 136, 120, 103, 119, 119, 119, 120, 135, 136, 119, 104, 135, 120, 135, 103, 119, 119, 119, 119, 135, 119, 135, 119, 120, 135, 136, 119, 135, 120, 120, 118
        .byte   104, 119, 119, 134, 120, 101, 119, 102, 118, 102, 118, 119, 103, 119, 119, 104, 103, 134, 118, 102, 118, 87, 119, 119, 118, 134, 118, 102, 118, 103, 119, 133
        .byte   119, 118, 119, 119, 119, 136, 136, 117, 103, 103, 135, 135, 104, 118, 134, 119, 118, 119, 119, 120, 119, 103, 120, 104, 119, 119, 120, 135, 119, 119, 119, 119
        .byte   120, 119, 119, 119, 103, 119, 134, 136, 119, 120, 119, 135, 119, 121, 135, 135, 87, 134, 104, 120, 120, 135, 102, 135, 86, 135, 134, 119, 103, 119, 119, 119
        .byte   117, 104, 119, 135, 118, 120, 102, 119, 118, 118, 103, 101, 117, 119, 71, 118, 86, 119, 119, 118, 85, 103, 117, 86, 135, 119, 117, 119, 119, 71, 118, 119
        .byte   118, 117, 85, 101, 117, 118, 119, 117, 117, 118, 119, 119, 86, 134, 134, 119, 118, 103, 102, 118, 119, 118, 134, 118, 120, 119, 118, 135, 119, 104, 119, 119
        .byte   119, 120, 119, 119, 136, 102, 102, 135, 119, 119, 119, 103, 136, 118, 119, 135, 101, 119, 118, 134, 102, 86, 119, 118, 135, 102, 104, 135, 120, 133, 118, 103
        .byte   104, 135, 87, 135, 86, 103, 119, 134, 103, 101, 103, 103, 119, 118, 118, 120, 119, 86, 119, 118, 86, 120, 119, 87, 88, 71, 103, 86, 135, 88, 119, 101
        .byte   120, 103, 86, 119, 135, 135, 120, 120, 135, 135, 118, 120, 103, 136, 135, 119, 103, 118, 135, 117, 119, 87, 119, 133, 135, 118, 118, 100, 120, 117, 133, 117
        .byte   118, 135, 119, 117, 119, 102, 102, 103, 120, 103, 118, 88, 134, 103, 103, 118, 103, 104, 119, 135, 135, 136, 118, 120, 119, 119, 136, 103, 119, 136, 120, 119
        .byte   136, 120, 136, 135, 119, 135, 135, 104, 134, 135, 120, 118, 119, 119, 135, 119, 119, 118, 135, 119, 118, 118, 120, 119, 120, 120, 135, 119, 120, 136, 136, 119
        .byte   120, 118, 119, 120, 136, 120, 118, 119, 119, 119, 119, 135, 119, 119, 136, 119, 135, 104, 104, 118, 120, 119, 120, 119, 119, 119, 119, 103, 119, 103, 134, 135
        .byte   119, 120, 101, 136, 135, 104, 120, 136, 136, 102, 134, 119, 118, 135, 101, 134, 119, 120, 103, 134, 102, 119, 102, 134, 117, 119, 118, 118, 119, 103, 119, 87
        .byte   119, 119, 120, 118, 119, 119, 103, 104, 119, 104, 133, 118, 120, 135, 103, 86, 135, 119, 103, 88, 118, 118, 70, 100, 103, 118, 103, 99, 70, 102, 72, 134
        .byte   102, 119, 71, 132, 71, 118, 118, 135, 135, 71, 102, 88, 104, 103, 135, 86, 118, 103, 119, 87, 117, 119, 102, 103, 87, 118, 118, 88, 134, 102, 84, 119
        .byte   69, 133, 85, 119, 120, 118, 136, 117, 103, 118, 103, 134, 118, 118, 103, 103, 119, 87, 119, 104, 118, 119, 102, 102, 87, 103, 118, 87, 103, 118, 88, 88
        .byte   118, 120, 119, 120, 119, 136, 102, 135, 103, 118, 119, 120, 120, 117, 119, 118, 119, 119, 103, 118, 104, 119, 120, 118, 104, 120, 136, 88, 135, 136, 88, 136
        .byte   118, 103, 102, 102, 118, 119, 118, 103, 134, 119, 102, 133, 120, 117, 135, 136, 104, 136, 136, 103, 102, 136, 135, 87, 119, 103, 104, 119, 119, 118, 135, 135
        .byte   134, 120, 118, 102, 119, 104, 88, 119, 119, 104, 120, 119, 134, 119, 136, 119, 119, 119, 134, 135, 135, 102, 119, 136, 104, 135, 103, 120, 104, 120, 135, 103
        .byte   119, 104, 119, 103, 136, 120, 135, 119, 118, 120, 119, 135, 118, 118, 134, 118, 118, 119, 136, 102, 120, 135, 119, 118, 103, 119, 87, 119, 134, 87, 118, 71
        .byte   101, 88, 118, 119, 118, 118, 102, 103, 119, 102, 70, 118, 68, 136, 104, 102, 68, 104, 104, 53, 102, 103, 134, 70, 120, 103, 119, 102, 136, 101, 120, 135
        .byte   136, 87, 88, 135, 136, 119, 102, 120, 119, 119, 103, 120, 103, 119, 103, 103, 133, 135, 102, 119, 120, 119, 135, 119, 134, 103, 118, 103, 119, 102, 118, 117
        .byte   118, 102, 135, 103, 102, 117, 102, 103, 102, 132, 133, 119, 119, 103, 85, 118, 85, 120, 117, 119, 119, 102, 118, 134, 117, 133, 85, 134, 117, 103, 118, 100
        .byte   103, 104, 103, 103, 103, 103, 118, 117, 103, 102, 103, 103, 135, 120, 102, 102, 118, 119, 117, 119, 103, 118, 101, 119, 118, 104, 118, 103, 119, 134, 102, 134
        .byte   118, 118, 135, 119, 119, 119, 103, 103, 134, 120, 135, 119, 103, 120, 120, 119, 104, 103, 102, 119, 119, 103, 119, 101, 104, 120, 118, 103, 119, 102, 87, 104
        .byte   135, 134, 118, 101, 134, 86, 103, 118, 136, 102, 101, 136, 102, 88, 104, 118, 104, 135, 135, 119, 88, 119, 119, 103, 103, 103, 120, 104, 119, 103, 87, 119
        .byte   87, 118, 117, 117, 117, 70, 87, 120, 86, 103, 101, 136, 120, 70, 71, 103, 135, 71, 117, 119, 134, 88, 120, 99, 104, 102, 88, 120, 100, 71, 119, 134
        .byte   71, 87, 119, 55, 118, 104, 103, 101, 102, 117, 120, 118, 119, 135, 118, 102, 135, 120, 88, 117, 120, 86, 134, 118, 119, 119, 118, 119, 119, 118, 120, 103
        .byte   118, 85, 120, 133, 120, 102, 120, 118, 118, 119, 120, 102, 118, 118, 103, 119, 119, 119, 119, 117, 119, 119, 120, 120, 101, 104, 118, 135, 102, 103, 119, 134
        .byte   119, 120, 117, 119, 120, 119, 103, 135, 119, 117, 135, 120, 117, 134, 118, 102, 134, 120, 135, 118, 118, 103, 120, 119, 118, 103, 87, 119, 136, 120, 119, 119
        .byte   119, 102, 119, 103, 135, 134, 104, 103, 104, 119, 103, 135, 101, 102, 87, 119, 104, 104, 119, 119, 135, 120, 103, 118, 119, 120, 133, 135, 118, 103, 118, 120
        .byte   120, 134, 104, 119, 119, 135, 120, 119, 119, 117, 119, 118, 119, 134, 136, 119, 134, 119, 135, 135, 118, 119, 119, 119, 119, 118, 118, 119, 119, 120, 104, 134
        .byte   135, 102, 117, 135, 88, 118, 119, 135, 102, 119, 119, 102, 120, 120, 103, 104, 120, 135, 136, 119, 119, 134, 136, 103, 134, 119, 119, 120, 104, 135, 87, 118
        .byte   136, 120, 102, 87, 117, 102, 86, 118, 134, 119, 103, 120, 118, 84, 119, 134, 84, 102, 119, 133, 117, 103, 101, 85, 119, 86, 101, 119, 150, 119, 135, 118
        .byte   87, 135, 103, 119, 134, 102, 103, 118, 120, 119, 134, 119, 102, 120, 118, 118, 103, 118, 102, 134, 119, 119, 117, 102, 135, 104, 119, 134, 136, 104, 120, 119
        .byte   102, 103, 119, 103, 119, 119, 119, 104, 120, 120, 135, 118, 88, 103, 118, 86, 120, 71, 86, 87, 118, 135, 119, 101, 119, 135, 134, 117, 103, 118, 117, 119
        .byte   103, 102, 103, 118, 135, 118, 117, 87, 134, 134, 103, 119, 102, 103, 101, 119, 120, 118, 119, 135, 102, 103, 101, 119, 118, 118, 71, 103, 117, 103, 117, 103
        .byte   101, 118, 118, 87, 87, 135, 103, 136, 119, 85, 119, 102, 135, 102, 104, 103, 118, 102, 103, 119, 118, 119, 118, 120, 119, 119, 118, 119, 119, 119, 135, 118
        .byte   119, 103, 119, 119, 104, 102, 136, 102, 134, 134, 134, 102, 135, 103, 102, 133, 88, 85, 104, 120, 134, 118, 119, 103, 118, 102, 103, 103, 104, 102, 118, 119
        .byte   87, 120, 102, 136, 117, 118, 102, 134, 102, 118, 104, 103, 117, 103, 134, 104, 119, 134, 120, 119, 103, 135, 119, 135, 118, 103, 120, 120, 120, 119, 136, 119
        .byte   119, 120, 135, 133, 135, 119, 134, 120, 103, 104, 103, 135, 134, 120, 136, 120, 136, 119, 103, 136, 119, 120, 104, 120, 121, 119, 119, 134, 135, 119, 120, 120
        .byte   135, 103, 136, 134, 136, 119, 119, 136, 120, 104, 119, 120, 120, 103, 103, 120, 135, 102, 118, 136, 118, 134, 120, 119, 101, 102, 120, 119, 119, 120, 103, 120
        .byte   118, 119, 118, 120, 119, 104, 119, 118, 118, 120, 120, 118, 134, 103, 136, 118, 119, 135, 120, 87, 103, 134, 135, 120, 88, 88, 120, 87, 119, 119, 135, 71
        .byte   119, 102, 135, 88, 118, 118, 135, 134, 120, 136, 85, 135, 120, 120, 118, 119, 119, 103, 88, 118, 136, 120, 72, 119, 119, 119, 135, 118, 135, 119, 118, 135
        .byte   135, 103, 119, 136, 103, 103, 119, 103, 119, 119, 134, 119, 119, 135, 120, 118, 119, 119, 119, 103, 136, 103, 136, 120, 134, 136, 120, 103, 119, 135, 119, 119
        .byte   119, 119, 135, 120, 119, 136, 135, 118, 136, 120, 119, 103, 135, 119, 118, 120, 119, 102, 120, 103, 136, 118, 119, 119, 135, 135, 104, 104, 120, 119, 120, 119
        .byte   120, 135, 103, 119, 119, 119, 103, 134, 134, 104, 135, 134, 133, 135, 103, 119, 120, 117, 103, 135, 118, 119, 134, 134, 103, 135, 119, 119, 120, 119, 120, 135
        .byte   135, 119, 136, 118, 119, 119, 119, 103, 135, 119, 103, 119, 120, 119, 136, 103, 120, 135, 104, 119, 103, 119, 135, 103, 118, 118, 117, 120, 119, 120, 87, 120
        .byte   135, 103, 134, 87, 102, 102, 118, 120, 120, 133, 118, 102, 119, 103, 119, 136, 120, 119, 104, 119, 119, 103, 119, 119, 118, 120, 103, 118, 103, 120, 119, 103
        .byte   120, 103, 119, 119, 103, 119, 103, 134, 119, 119, 103, 135, 119, 135, 119, 135, 135, 136, 136, 118, 136, 135, 120, 118, 119, 119, 117, 103, 119, 87, 102, 86
        .byte   135, 103, 119, 104, 103, 134, 120, 120, 102, 135, 135, 135, 103, 135, 119, 120, 118, 118, 118, 120, 119, 119, 119, 120, 120, 136, 136, 120, 119, 135, 119, 134
        .byte   135, 120, 120, 135, 135, 103, 134, 120, 120, 135, 119, 119, 103, 103, 103, 119, 103, 135, 118, 120, 119, 135, 118, 87, 118, 103, 118, 118, 119, 102, 120, 117
        .byte   103, 117, 118, 102, 136, 135, 136, 118, 121, 135, 119, 119, 119, 104, 118, 119, 119, 120, 119, 135, 119, 103, 120, 120, 119, 103, 136, 136, 119, 134, 135, 136
        .byte   119, 120, 136, 118, 118, 120, 118, 118, 118, 103, 120, 118, 120, 135, 103, 103, 118, 136, 120, 136, 119, 119, 119, 119, 135, 119, 136, 118, 119, 119, 136, 118
        .byte   103, 120, 120, 152, 103, 135, 120, 103, 103, 119, 136, 119, 120, 119, 136, 119, 135, 86, 120, 103, 103, 118, 120, 102, 103, 135, 104, 118, 103, 120, 118, 120
        .byte   88, 135, 120, 104, 119, 134, 104, 120, 120, 103, 134, 103, 104, 119, 120, 120, 120, 119, 103, 134, 104, 135, 136, 103, 120, 135, 136, 119, 119, 134, 102, 132
        .byte   84, 103, 116, 134, 120, 103, 117, 102, 134, 117, 99, 118, 117, 83, 117, 115, 55, 115, 119, 101, 82, 87, 85, 53, 120, 87, 55, 103, 117, 118, 117, 87
        .byte   135, 71, 135, 116, 119, 119, 86, 70, 119, 119, 120, 102, 119, 119, 86, 86, 104, 102, 87, 87, 120, 101, 102, 102, 116, 117, 118, 119, 87, 88, 118, 103
        .byte   87, 103, 71, 87, 119, 118, 104, 84, 102, 101, 102, 70, 118, 117, 86, 116, 56, 102, 133, 102, 118, 132, 104, 103, 102, 103, 87, 103, 86, 103, 118, 86
        .byte   116, 118, 85, 102, 120, 102, 134, 119, 118, 119, 119, 119, 135, 119, 119, 135, 120, 119, 103, 135, 136, 135, 119, 119, 103, 120, 119, 120, 135, 119, 119, 120
        .byte   136, 102, 103, 134, 119, 136, 120, 103, 134, 136, 136, 119, 119, 135, 136, 119, 135, 119, 134, 102, 134, 119, 118, 135, 119, 119, 118, 119, 118, 119, 136, 151
        .byte   103, 118, 119, 87, 136, 103, 135, 101, 136, 120, 120, 103, 119, 136, 133, 70, 119, 103, 87, 134, 84, 119, 101, 119, 102, 102, 119, 87, 103, 119, 118, 134
        .byte   135, 103, 102, 120, 135, 119, 117, 102, 119, 135, 119, 135, 118, 103, 119, 135, 102, 135, 134, 120, 118, 118, 120, 102, 134, 87, 87, 119, 135, 119, 117, 118
        .byte   135, 71, 118, 85, 118, 119, 88, 117, 103, 103, 101, 117, 119, 119, 136, 118, 101, 102, 103, 103, 119, 104, 118, 118, 118, 134, 134, 117, 120, 119, 135, 134
        .byte   119, 119, 118, 136, 119, 103, 119, 118, 118, 119, 118, 103, 103, 117, 118, 87, 103, 85, 87, 135, 103, 86, 104, 119, 71, 119, 119, 120, 120, 119, 135, 136
        .byte   119, 135, 104, 104, 119, 119, 119, 120, 135, 136, 119, 119, 104, 134, 135, 104, 118, 119, 101, 136, 85, 118, 102, 134, 118, 117, 135, 119, 101, 119, 118, 119
        .byte   116, 118, 117, 120, 103, 104, 119, 102, 118, 116, 71, 132, 102, 104, 132, 71, 118, 116, 103, 104, 131, 102, 120, 119, 118, 104, 134, 136, 119, 86, 119, 120
        .byte   136, 133, 135, 133, 119, 119, 102, 118, 134, 117, 133, 101, 134, 133, 120, 119, 116, 103, 120, 103, 103, 120, 119, 119, 118, 103, 119, 119, 120, 119, 119, 118
        .byte   117, 103, 103, 136, 119, 135, 120, 118, 103, 119, 135, 103, 119, 118, 119, 117, 103, 103, 118, 119, 119, 119, 86, 118, 103, 120, 118, 135, 119, 103, 101, 104
        .byte   88, 136, 120, 85, 135, 119, 119, 134, 118, 133, 118, 120, 134, 136, 119, 116, 119, 88, 87, 119, 119, 118, 103, 136, 117, 103, 119, 71, 135, 103, 120, 119
        .byte   120, 103, 119, 119, 120, 135, 120, 134, 136, 120, 103, 134, 120, 103, 120, 120, 136, 134, 136, 120, 134, 135, 103, 119, 119, 119, 120, 135, 119, 102, 119, 119
        .byte   119, 104, 119, 103, 86, 119, 135, 104, 102, 104, 136, 118, 103, 120, 103, 135, 119, 135, 119, 103, 135, 120, 119, 119, 120, 104, 135, 103, 104, 119, 119, 135
        .byte   118, 104, 119, 119, 119, 119, 119, 119, 103, 120, 103, 87, 136, 102, 87, 134, 118, 119, 119, 118, 72, 119, 86, 119, 135, 70, 102, 103, 119, 68, 53, 104
        .byte   102, 70, 103, 119, 71, 70, 120, 103, 104, 120, 135, 119, 102, 88, 103, 135, 104, 118, 117, 134, 136, 136, 133, 118, 119, 118, 119, 86, 118, 119, 119, 102
        .byte   118, 134, 102, 101, 103, 88, 119, 85, 118, 117, 87, 116, 86, 102, 104, 87, 87, 103, 104, 71, 119, 120, 119, 119, 120, 103, 103, 119, 119, 104, 103, 119
        .byte   103, 119, 103, 117, 120, 118, 136, 104, 102, 103, 104, 119, 104, 86, 120, 102, 86, 118, 117, 120, 117, 88, 119, 136, 119, 104, 120, 120, 71, 119, 104, 135
        .byte   101, 135, 87, 135, 88, 103, 120, 119, 119, 116, 103, 134, 103, 118, 134, 117, 118, 120, 103, 104, 103, 119, 136, 102, 134, 104, 119, 119, 119, 118, 133, 136
        .byte   118, 120, 119, 119, 119, 119, 135, 119, 104, 135, 119, 136, 136, 119, 135, 119, 135, 118, 135, 119, 119, 134, 118, 104, 119, 119, 134, 119, 119, 102, 103, 135
        .byte   120, 118, 135, 120, 120, 118, 120, 136, 103, 136, 135, 119, 119, 103, 118, 120, 135, 135, 119, 119, 135, 102, 120, 118, 120, 103, 135, 135, 102, 120, 136, 119
        .byte   119, 118, 120, 104, 119, 136, 119, 119, 135, 120, 135, 120, 119, 118, 119, 135, 102, 101, 103, 120, 119, 119, 135, 119, 102, 136, 119, 135, 135, 120, 103, 136
        .byte   103, 136, 119, 135, 120, 104, 119, 120, 120, 135, 120, 102, 136, 119, 135, 118, 119, 119, 136, 119, 135, 119, 103, 119, 103, 102, 119, 133, 119, 119, 103, 136
        .byte   119, 119, 135, 119, 118, 118, 136, 135, 120, 117, 119, 134, 101, 136, 119, 70, 119, 119, 103, 135, 135, 117, 86, 102, 117, 100, 102, 101, 102, 118, 119, 118
        .byte   102, 119, 119, 117, 87, 136, 119, 118, 120, 119, 135, 135, 136, 134, 119, 135, 119, 134, 118, 118, 119, 120, 120, 133, 119, 104, 119, 118, 102, 119, 118, 104
        .byte   135, 119, 118, 119, 136, 136, 103, 119, 120, 135, 119, 134, 119, 119, 119, 119, 136, 103, 120, 103, 135, 134, 119, 119, 103, 119, 119, 135, 118, 119, 134, 118
        .byte   118, 120, 103, 135, 136, 134, 135, 135, 136, 120, 103, 136, 87, 120, 118, 135, 120, 119, 136, 136, 135, 135, 135, 135, 136, 103, 135, 118, 136, 119, 135, 120
        .byte   135, 119, 135, 119, 119, 118, 134, 135, 118, 118, 135, 136, 103, 135, 134, 133, 135, 118, 103, 136, 118, 88, 118, 136, 135, 120, 103, 136, 120, 119, 134, 134
        .byte   119, 118, 119, 134, 87, 135, 86, 119, 103, 120, 102, 135, 136, 103, 119, 133, 120, 119, 134, 120, 136, 87, 120, 120, 120, 134, 119, 103, 118, 116, 99, 118
        .byte   84, 117, 118, 119, 117, 86, 134, 118, 100, 102, 118, 134, 87, 135, 103, 135, 103, 119, 103, 103, 119, 118, 119, 118, 135, 87, 120, 101, 134, 103, 103, 104
        .byte   103, 119, 120, 120, 103, 103, 104, 119, 134, 116, 119, 119, 88, 84, 119, 120, 118, 116, 87, 115, 104, 104, 86, 133, 103, 120, 103, 102, 135, 135, 135, 119
        .byte   119, 118, 136, 119, 136, 104, 119, 102, 120, 118, 119, 119, 118, 119, 135, 117, 102, 118, 102, 135, 120, 135, 120, 119, 103, 120, 120, 136, 119, 136, 119, 136
        .byte   118, 135, 119, 119, 119, 133, 119, 119, 103, 101, 135, 119, 119, 117, 103, 100, 119, 119, 86, 103, 117, 119, 116, 103, 101, 103, 135, 117, 103, 120, 136, 118
        .byte   118, 135, 119, 103, 104, 119, 119, 118, 119, 102, 119, 118, 119, 101, 103, 119, 119, 103, 118, 119, 118, 135, 120, 119, 118, 104, 103, 119, 135, 135, 119, 119
        .byte   119, 120, 136, 119, 135, 120, 135, 120, 120, 103, 103, 135, 120, 136, 120, 136, 120, 118, 120, 104, 103, 135, 119, 120, 135, 135, 135, 134, 118, 119, 120, 136
        .byte   134, 101, 119, 86, 120, 136, 135, 104, 119, 103, 136, 102, 136, 120, 118, 119, 103, 137, 135, 136, 134, 135, 103, 120, 119, 118, 119, 104, 120, 135, 118, 120
        .byte   136, 136, 120, 120, 119, 119, 120, 119, 135, 136, 119, 119, 135, 119, 136, 136, 119, 104, 119, 119, 135, 120, 135, 135, 135, 134, 103, 120, 134, 119, 134, 135
        .byte   119, 102, 119, 135, 135, 118, 118, 133, 117, 119, 119, 135, 119, 135, 136, 118, 120, 119, 119, 118, 136, 136, 134, 119, 85, 119, 119, 102, 103, 102, 103, 103
        .byte   119, 103, 102, 120, 102, 118, 134, 135, 120, 135, 135, 120, 120, 119, 119, 119, 135, 119, 103, 136, 119, 120, 135, 118, 102, 118, 118, 102, 119, 119, 85, 135
        .byte   151, 102, 118, 103, 134, 119, 118, 119, 120, 119, 118, 120, 119, 119, 135, 119, 102, 103, 120, 120, 104, 119, 136, 120, 135, 119, 103, 120, 119, 136, 120, 134
        .byte   135, 136, 120, 121, 135, 136, 118, 119, 103, 118, 120, 103, 120, 119, 135, 120, 135, 119, 103, 117, 86, 104, 103, 118, 134, 135, 118, 102, 103, 119, 135, 87
        .byte   103, 101, 119, 86, 103, 102, 119, 103, 135, 118, 118, 102, 119, 136, 118, 134, 119, 135, 119, 120, 103, 120, 136, 135, 119, 120, 136, 119, 120, 118, 119, 87
        .byte   103, 135, 103, 117, 118, 100, 118, 85, 87, 119, 101, 87, 118, 120, 87, 119, 87, 119, 120, 119, 132, 103, 117, 87, 119, 117, 119, 118, 87, 103, 118, 135
        .byte   87, 104, 134, 103, 133, 102, 104, 102, 119, 103, 86, 87, 103, 119, 102, 134, 136, 120, 119, 117, 103, 135, 119, 103, 118, 118, 103, 118, 118, 119, 119, 119
        .byte   119, 119, 103, 119, 118, 118, 118, 119, 136, 119, 103, 119, 101, 120, 119, 103, 119, 103, 104, 119, 103, 103, 120, 104, 104, 120, 136, 135, 136, 119, 119, 120
        .byte   136, 136, 120, 119, 134, 118, 104, 120, 118, 135, 120, 104, 103, 120, 118, 119, 103, 102, 119, 119, 119, 120, 119, 120, 118, 134, 119, 135, 135, 135, 103, 118
        .byte   103, 120, 135, 119, 135, 119, 135, 119, 135, 120, 120, 120, 135, 104, 103, 119, 135, 119, 136, 135, 102, 103, 119, 118, 88, 103, 88, 120, 103, 103, 103, 103
        .byte   118, 119, 102, 104, 119, 119, 102, 119, 119, 120, 119, 120, 120, 119, 119, 119, 103, 119, 136, 135, 136, 118, 120, 118, 120, 119, 120, 120, 103, 119, 119, 119
        .byte   119, 136, 120, 134, 120, 133, 119, 118, 135, 119, 134, 119, 120, 136, 134, 120, 120, 136, 103, 119, 134, 119, 120, 120, 119, 118, 136, 134, 120, 135, 120, 134
        .byte   87, 135, 119, 120, 101, 120, 119, 85, 101, 119, 135, 119, 101, 135, 116, 119, 133, 135, 120, 134, 119, 136, 119, 118, 119, 134, 135, 103, 120, 136, 118, 120
        .byte   104, 120, 119, 120, 119, 135, 104, 119, 119, 118, 135, 120, 119, 119, 119, 118, 135, 119, 119, 117, 136, 103, 103, 135, 118, 103, 118, 103, 103, 119, 117, 102
        .byte   135, 104, 103, 103, 120, 119, 134, 119, 117, 102, 135, 120, 120, 135, 135, 120, 118, 120, 119, 119, 119, 104, 119, 135, 120, 134, 119, 134, 135, 103, 120, 102
        .byte   120, 119, 134, 87, 135, 119, 152, 104, 119, 120, 118, 135, 103, 119, 104, 119, 104, 118, 87, 118, 103, 103, 104, 134, 104, 120, 119, 135, 117, 104, 86, 118
        .byte   102, 119, 134, 119, 102, 119, 134, 103, 120, 135, 120, 118, 120, 119, 136, 120, 119, 136, 104, 120, 135, 135, 103, 118, 103, 120, 118, 118, 86, 135, 119, 103
        .byte   103, 102, 119, 104, 136, 103, 84, 88, 119, 104, 118, 120, 117, 88, 133, 88, 103, 87, 135, 118, 136, 118, 135, 118, 120, 120, 85, 119, 103, 134, 102, 135
        .byte   137, 120, 135, 118, 102, 118, 135, 134, 135, 103, 119, 119, 119, 118, 119, 119, 135, 119, 86, 119, 103, 104, 132, 87, 118, 119, 103, 87, 117, 87, 118, 101
        .byte   119, 119, 119, 134, 120, 117, 104, 135, 103, 103, 119, 118, 104, 135, 118, 103, 120, 103, 117, 119, 103, 119, 136, 134, 118, 118, 118, 103, 118, 118, 86, 87
        .byte   118, 102, 135, 135, 102, 104, 118, 88, 136, 135, 103, 135, 118, 102, 119, 119, 119, 104, 135, 118, 135, 119, 119, 102, 136, 119, 135, 102, 104, 120, 104, 136
        .byte   104, 121, 119, 120, 118, 119, 103, 136, 117, 104, 120, 119, 104, 136, 120, 135, 136, 135, 120, 119, 136, 136, 119, 119, 135, 119, 118, 120, 136, 135, 119, 120
        .byte   120, 120, 119, 136, 120, 136, 103, 119, 120, 119, 120, 119, 135, 136, 120, 135, 134, 136, 119, 104, 136, 119, 119, 119, 136, 120, 120, 135, 103, 120, 136, 118
        .byte   120, 119, 135, 120, 136, 120, 119, 120, 72, 119, 102, 119, 119, 102, 86, 120, 118, 135, 135, 117, 85, 120, 103, 103, 101, 103, 86, 119, 87, 103, 119, 86
        .byte   116, 119, 117, 85, 119, 118, 120, 119, 119, 120, 103, 103, 119, 119, 134, 118, 120, 118, 119, 104, 87, 119, 119, 104, 120, 104, 119, 120, 135, 135, 103, 119
        .byte   135, 119, 119, 134, 119, 135, 135, 119, 118, 104, 120, 135, 119, 103, 119, 135, 102, 118, 134, 87, 118, 120, 102, 102, 87, 101, 103, 118, 102, 102, 86, 104
        .byte   102, 136, 103, 88, 103, 102, 103, 103, 101, 119, 86, 85, 118, 69, 86, 118, 102, 104, 102, 101, 103, 103, 119, 102, 103, 119, 118, 103, 119, 118, 87, 103
        .byte   119, 103, 119, 120, 119, 135, 119, 104, 135, 119, 119, 134, 119, 136, 118, 119, 135, 136, 136, 136, 135, 119, 118, 103, 136, 134, 120, 120, 120, 119, 120, 102
        .byte   120, 135, 103, 119, 120, 118, 104, 135, 104, 119, 86, 120, 134, 135, 119, 102, 104, 119, 102, 118, 104, 120, 117, 118, 134, 134, 119, 118, 135, 134, 119, 104
        .byte   135, 102, 120, 119, 135, 117, 118, 134, 102, 120, 119, 136, 119, 120, 119, 119, 119, 119, 118, 120, 119, 120, 135, 102, 120, 118, 120, 135, 135, 135, 120, 103
        .byte   119, 135, 119, 118, 135, 119, 119, 103, 135, 87, 103, 119, 119, 118, 119, 118, 119, 102, 103, 118, 118, 103, 103, 119, 119, 136, 135, 119, 119, 119, 119, 120
        .byte   119, 120, 136, 118, 136, 119, 120, 103, 136, 119, 136, 119, 120, 136, 136, 135, 135, 136, 119, 119, 136, 135, 119, 120, 136, 135, 135, 119, 135, 136, 119, 119
        .byte   119, 103, 120, 136, 120, 120, 87, 135, 120, 103, 103, 135, 119, 87, 119, 103, 103, 104, 135, 118, 88, 119, 135, 119, 104, 104, 119, 118, 120, 133, 103, 134
        .byte   104, 136, 117, 119, 118, 119, 103, 136, 120, 120, 118, 103, 119, 134, 103, 136, 136, 119, 119, 119, 118, 120, 103, 88, 118, 119, 104, 119, 135, 119, 119, 120
        .byte   102, 119, 119, 119, 135, 135, 119, 104, 134, 119, 119, 135, 103, 136, 119, 134, 136, 136, 119, 119, 136, 136, 135, 120, 120, 136, 119, 136, 119, 136, 120, 87
        .byte   119, 104, 119, 119, 119, 135, 134, 136, 103, 135, 119, 104, 118, 136, 104, 135, 120, 103, 119, 119, 119, 119, 136, 103, 120, 136, 135, 104, 119, 136, 119, 136
        .byte   120, 120, 136, 120, 120, 120, 135, 104, 120, 136, 136, 136, 119, 118, 120, 136, 134, 135, 135, 119, 136, 135, 136, 119, 119, 119, 120, 120, 134, 136, 118, 120
        .byte   119, 104, 119, 135, 135, 120, 119, 119, 120, 119, 136, 120, 134, 120, 117, 119, 134, 136, 104, 135, 134, 119, 135, 118, 135, 136, 88, 135, 136, 103, 119, 135
        .byte   120, 104, 136, 103, 119, 103, 136, 135, 118, 135, 103, 120, 136, 136, 103, 135, 120, 120, 120, 135, 119, 119, 135, 120, 118, 120, 118, 135, 135, 104, 120, 135
        .byte   134, 136, 136, 101, 118, 135, 87, 103, 120, 87, 134, 104, 87, 103, 120, 117, 119, 120, 84, 101, 134, 136, 118, 119, 120, 120, 119, 118, 119, 135, 118, 135
        .byte   135, 120, 120, 119, 120, 104, 119, 88, 135, 135, 119, 102, 104, 119, 103, 136, 134, 118, 134, 120, 119, 120, 135, 103, 119, 134, 135, 136, 133, 120, 120, 118
        .byte   104, 136, 103, 120, 136, 103, 117, 104, 103, 120, 136, 118, 103, 103, 101, 102, 135, 136, 135, 134, 120, 119, 120, 104, 120, 119, 119, 119, 135, 119, 119, 134
        .byte   135, 134, 119, 119, 135, 119, 120, 135, 119, 118, 119, 118, 119, 120, 136, 135, 104, 119, 135, 103, 119, 136, 119, 135, 136, 119, 120, 119, 135, 134, 119, 135
        .byte   119, 118, 120, 119, 120, 119, 136, 119, 120, 104, 119, 136, 119, 118, 119, 118, 119, 118, 134, 118, 103, 135, 119, 120, 85, 119, 121, 103, 118, 136, 120, 135
        .byte   103, 120, 136, 103, 136, 119, 120, 119, 120, 120, 117, 120, 119, 119, 119, 136, 103, 119, 136, 135, 104, 119, 119, 135, 119, 118, 120, 103, 136, 103, 119, 118
        .byte   120, 136, 136, 103, 87, 118, 119, 119, 103, 135, 119, 136, 135, 119, 136, 119, 135, 136, 134, 119, 135, 119, 120, 135, 102, 119, 119, 104, 118, 88, 120, 102
        .byte   136, 118, 103, 86, 103, 119, 135, 119, 120, 119, 120, 120, 120, 120, 103, 136, 119, 103, 119, 136, 103, 119, 119, 87, 119, 119, 119, 119, 120, 103, 104, 102
        .byte   118, 135, 134, 118, 102, 119, 118, 135, 135, 120, 119, 104, 118, 119, 120, 119, 119, 120, 135, 119, 136, 119, 134, 119, 104, 120, 135, 120, 119, 103, 135, 118
        .byte   119, 119, 103, 103, 120, 136, 103, 134, 120, 118, 119, 120, 117, 119, 118, 118, 102, 136, 103, 136, 135, 120, 119, 120, 135, 136, 136, 119, 135, 120, 135, 135
        .byte   135, 136, 119, 135, 120, 120, 119, 135, 119, 135, 104, 136, 136, 136, 119, 136, 119, 103, 103, 119, 134, 119, 135, 120, 119, 120, 135, 120, 119, 135, 120, 119
        .byte   102, 103, 103, 119, 117, 120, 119, 103, 103, 118, 119, 119, 103, 119, 136, 119, 135, 119, 120, 135, 136, 120, 103, 120, 135, 135, 120, 135, 103, 119, 135, 119
        .byte   120, 119, 120, 135, 104, 135, 118, 120, 104, 135, 103, 119, 119, 134, 119, 118, 118, 104, 118, 103, 118, 103, 135, 119, 119, 119, 135, 119, 120, 119, 119, 120
        .byte   136, 136, 119, 119, 119, 119, 119, 104, 135, 135, 103, 103, 135, 103, 103, 104, 118, 117, 103, 120, 102, 135, 87, 118, 103, 119, 135, 120, 136, 104, 120, 135
        .byte   136, 120, 119, 119, 120, 136, 152, 120, 135, 119, 118, 120, 103, 119, 135, 135, 102, 103, 135, 118, 120, 120, 104, 119, 120, 135, 119, 103, 135, 120, 120, 103
        .byte   136, 120, 102, 120, 120, 120, 104, 133, 120, 103, 118, 119, 119, 119, 118, 103, 118, 119, 119, 136, 119, 135, 135, 135, 118, 135, 119, 118, 119, 135, 135, 135
        .byte   119, 118, 119, 134, 119, 103, 135, 103, 119, 103, 87, 119, 103, 104, 103, 135, 118, 119, 135, 120, 120, 136, 119, 135, 119, 136, 136, 136, 120, 136, 135, 135
        .byte   119, 119, 136, 103, 119, 136, 135, 135, 136, 135, 119, 120, 119, 103, 120, 136, 104, 120, 120, 120, 135, 120, 136, 119, 135, 118, 135, 135, 120, 136, 120, 119
        .byte   119, 136, 136, 137, 120, 136, 104, 120, 120, 119, 136, 119, 136, 136, 119, 136, 136, 136, 135, 136, 136, 120, 136, 119, 136, 120, 120, 135, 136, 136, 120, 136
        .byte   120, 136, 135, 137, 120, 136, 136, 119, 135, 135, 136, 136, 136, 104, 136, 120, 136, 136, 135, 135, 120, 135, 136, 136, 120, 135, 136, 120, 120, 136, 135, 136
        .byte   135, 135, 120, 136, 120, 119, 119, 120, 136, 120, 136, 119, 134, 119, 120, 119, 119, 119, 120, 120, 119, 118, 104, 119, 120, 120, 103, 120, 119, 136, 88, 103
        .byte   135, 135, 134, 120, 135, 103, 104, 120, 103, 135, 120, 136, 102, 136, 135, 119, 119, 136, 119, 119, 120, 119, 103, 135, 135, 119, 120, 119, 135, 120, 135, 135
        .byte   119, 119, 119, 135, 118, 120, 104, 120, 119, 102, 119, 135, 120, 119, 135, 120, 118, 119, 135, 120, 119, 119, 104, 135, 120, 104, 104, 119, 118, 120, 135, 117
        .byte   102, 135, 119, 119, 134, 135, 104, 136, 136, 119, 119, 135, 120, 120, 135, 120, 134, 119, 136, 135, 119, 119, 118, 135, 120, 135, 135, 88, 118, 103, 135, 103
        .byte   135, 119, 103, 135, 87, 101, 119, 118, 118, 120, 103, 102, 120, 135, 103, 118, 102, 102, 120, 120, 120, 119, 134, 135, 104, 135, 118, 102, 136, 119, 117, 135
        .byte   118, 119, 120, 134, 103, 104, 135, 120, 135, 118, 118, 119, 103, 118, 117, 87, 118, 119, 118, 136, 119, 120, 136, 119, 136, 120, 119, 120, 119, 103, 120, 87
        .byte   119, 120, 120, 85, 72, 119, 119, 86, 119, 119, 86, 87, 119, 103, 119, 119, 136, 119, 103, 120, 119, 136, 119, 103, 103, 102, 119, 119, 120, 120, 119, 102
        .byte   119, 120, 135, 120, 134, 103, 120, 103, 103, 120, 135, 87, 119, 135, 120, 103, 119, 119, 119, 120, 103, 102, 87, 119, 119, 136, 104, 135, 135, 135, 135, 119
        .byte   119, 120, 119, 135, 104, 119, 118, 136, 136, 104, 119, 135, 135, 120, 135, 119, 104, 119, 120, 118, 134, 119, 136, 136, 119, 119, 120, 136, 136, 135, 120, 119
        .byte   119, 136, 135, 135, 134, 136, 135, 120, 119, 120, 119, 136, 119, 136, 119, 119, 119, 120, 120, 104, 104, 104, 120, 88, 120, 103, 120, 136, 119, 104, 119, 135
        .byte   135, 103, 135, 136, 136, 119, 135, 120, 136, 104, 136, 135, 135, 120, 119, 136, 120, 119, 135, 120, 120, 119, 135, 135, 120, 120, 135, 120, 119, 104, 135, 119
        .byte   136, 119, 135, 102, 135, 120, 137, 119, 120, 136, 104, 135, 136, 136, 135, 120, 136, 120, 120, 119, 104, 135, 120, 103, 104, 119, 118, 135, 135, 120, 103, 120
        .byte   119, 135, 119, 135, 118, 134, 134, 119, 119, 120, 135, 103, 136, 119, 135, 119, 119, 119, 136, 118, 119, 119, 135, 136, 119, 136, 120, 136, 120, 135, 118, 120
        .byte   136, 120, 136, 135, 120, 136, 120, 119, 120, 135, 136, 135, 134, 135, 135, 120, 103, 119, 119, 120, 135, 119, 103, 119, 120, 118, 103, 119, 136, 119, 103, 103
        .byte   119, 102, 119, 103, 119, 87, 103, 119, 119, 119, 102, 119, 118, 104, 119, 135, 120, 119, 119, 104, 102, 119, 119, 102, 87, 119, 136, 119, 103, 120, 134, 86
        .byte   102, 88, 135, 102, 104, 119, 118, 119, 102, 101, 103, 120, 104, 135, 119, 119, 135, 136, 136, 120, 119, 119, 119, 119, 119, 119, 102, 119, 120, 119, 102, 88
        .byte   103, 119, 103, 135, 102, 103, 103, 120, 136, 136, 119, 119, 120, 119, 136, 120, 104, 134, 119, 104, 119, 119, 119, 119, 119, 87, 120, 120, 135, 135, 102, 103
        .byte   120, 119, 103, 133, 103, 135, 119, 119, 104, 101, 119, 86, 119, 85, 86, 119, 119, 87, 119, 119, 71, 103, 120, 119, 118, 103, 120, 136, 103, 119, 87, 118
        .byte   103, 120, 120, 119, 135, 104, 120, 103, 102, 103, 88, 103, 102, 102, 136, 118, 102, 119, 118, 88, 120, 136, 102, 119, 135, 103, 104, 103, 119, 103, 120, 102
        .byte   118, 88, 86, 119, 135, 118, 136, 117, 120, 104, 120, 119, 134, 102, 119, 134, 134, 119, 103, 119, 134, 119, 118, 120, 102, 119, 103, 133, 117, 135, 118, 118
        .byte   102, 134, 135, 134, 135, 117, 135, 135, 103, 120, 120, 120, 103, 136, 135, 135, 102, 119, 120, 134, 119, 120, 87, 101, 120, 119, 119, 103, 102, 104, 135, 134
        .byte   120, 136, 103, 135, 136, 119, 119, 103, 87, 119, 120, 104, 119, 135, 136, 103, 135, 118, 136, 136, 103, 102, 103, 135, 120, 120, 133, 134, 118, 119, 135, 135
        .byte   119, 119, 103, 134, 119, 119, 135, 119, 135, 135, 119, 104, 103, 119, 135, 135, 119, 118, 136, 119, 119, 134, 120, 119, 135, 135, 119, 120, 134, 119, 119, 118
        .byte   135, 134, 135, 118, 119, 119, 119, 135, 135, 118, 119, 103, 101, 119, 103, 103, 119, 134, 103, 101, 133, 119, 118, 117, 116, 70, 134, 102, 100, 118, 103, 99
        .byte   134, 119, 68, 132, 135, 134, 100, 103, 119, 103, 118, 103, 133, 118, 103, 119, 104, 87, 120, 71, 103, 117, 136, 118, 119, 119, 120, 102, 104, 119, 119, 120
        .byte   118, 118, 120, 133, 102, 87, 103, 118, 118, 117, 102, 104, 118, 118, 117, 103, 103, 133, 88, 119, 103, 104, 117, 87, 119, 103, 88, 118, 117, 71, 85, 102
        .byte   87, 119, 103, 85, 119, 103, 119, 104, 103, 119, 135, 135, 119, 102, 103, 135, 119, 135, 117, 136, 102, 119, 118, 151, 134, 119, 120, 117, 135, 119, 136, 134
        .byte   136, 119, 136, 102, 119, 118, 119, 134, 118, 119, 135, 119, 87, 119, 103, 136, 103, 120, 119, 119, 136, 136, 120, 135, 120, 136, 120, 103, 134, 136, 136, 119
        .byte   104, 119, 119, 104, 104, 103, 119, 102, 119, 134, 119, 117, 119, 136, 102, 88, 120, 120, 105, 119, 103, 120, 104, 136, 118, 136, 119, 119, 136, 120, 135, 135
        .byte   135, 136, 119, 119, 136, 135, 135, 136, 136, 119, 119, 135, 104, 120, 136, 118, 103, 120, 120, 135, 120, 118, 119, 135, 134, 119, 135, 104, 118, 119, 118, 120
        .byte   135, 135, 120, 135, 119, 120, 118, 135, 103, 119, 118, 86, 134, 103, 134, 135, 118, 134, 118, 118, 119, 118, 119, 119, 134, 103, 120, 119, 119, 119, 119, 119
        .byte   118, 119, 135, 104, 136, 119, 120, 103, 118, 103, 120, 118, 88, 103, 88, 103, 103, 102, 103, 102, 102, 118, 87, 104, 103, 119, 120, 103, 134, 119, 103, 104
        .byte   119, 103, 119, 86, 119, 118, 119, 135, 103, 135, 136, 119, 120, 120, 121, 120, 119, 103, 104, 119, 119, 134, 135, 119, 135, 135, 119, 136, 120, 120, 136, 119
        .byte   135, 135, 136, 135, 136, 120, 117, 120, 119, 136, 134, 135, 119, 134, 87, 119, 120, 120, 104, 118, 119, 87, 103, 119, 117, 133, 119, 136, 117, 119, 102, 103
        .byte   132, 88, 117, 120, 119, 136, 134, 104, 119, 135, 117, 134, 136, 119, 119, 119, 136, 118, 103, 103, 104, 103, 120, 104, 102, 135, 103, 102, 135, 85, 101, 134
        .byte   103, 120, 119, 118, 103, 119, 103, 135, 103, 119, 134, 119, 120, 103, 119, 134, 119, 120, 120, 120, 119, 120, 119, 103, 119, 134, 120, 103, 135, 119, 134, 104
        .byte   119, 119, 118, 119, 103, 103, 119, 103, 136, 118, 119, 119, 118, 103, 103, 118, 118, 133, 134, 133, 103, 119, 134, 119, 118, 119, 119, 119, 135, 87, 103, 135
        .byte   134, 119, 117, 103, 102, 135, 120, 102, 103, 120, 119, 119, 71, 56, 135, 70, 87, 87, 104, 69, 103, 102, 71, 101, 87, 118, 102, 101, 119, 103, 118, 119
        .byte   119, 118, 104, 103, 118, 119, 119, 118, 136, 135, 135, 104, 101, 100, 135, 118, 116, 103, 102, 99, 69, 87, 119, 102, 101, 86, 136, 119, 118, 103, 119, 118
        .byte   118, 135, 117, 118, 119, 119, 103, 135, 136, 103, 120, 117, 88, 103, 119, 101, 101, 103, 103, 102, 102, 119, 116, 119, 119, 118, 103, 103, 119, 119, 104, 119
        .byte   118, 117, 119, 135, 103, 118, 102, 118, 102, 102, 120, 135, 117, 102, 135, 118, 101, 118, 136, 102, 102, 118, 118, 119, 119, 118, 119, 120, 119, 119, 103, 118
        .byte   103, 118, 117, 118, 135, 119, 136, 120, 119, 136, 119, 135, 119, 119, 119, 119, 102, 135, 104, 119, 117, 119, 119, 85, 119, 133, 103, 132, 119, 134, 117, 87
        .byte   135, 119, 120, 135, 135, 119, 119, 135, 135, 136, 118, 120, 135, 136, 135, 135, 118, 135, 135, 136, 135, 119, 102, 119, 119, 135, 119, 135, 120, 119, 119, 102
        .byte   119, 119, 103, 120, 119, 119, 120, 120, 136, 103, 103, 136, 120, 135, 120, 136, 103, 119, 120, 119, 135, 135, 118, 135, 118, 119, 119, 118, 119, 119, 102, 119
        .byte   119, 119, 87, 103, 102, 104, 103, 135, 118, 135, 119, 135, 102, 135, 120, 136, 135, 136, 136, 119, 119, 104, 136, 120, 136, 102, 135, 119, 136, 119, 136, 103
        .byte   135, 135, 119, 119, 102, 120, 119, 120, 135, 135, 103, 119, 104, 135, 101, 135, 103, 135, 101, 119, 119, 72, 120, 135, 119, 87, 118, 118, 119, 117, 134, 136
        .byte   104, 117, 116, 119, 118, 119, 119, 135, 117, 103, 135, 86, 134, 120, 119, 117, 117, 134, 118, 119, 135, 120, 119, 118, 119, 118, 85, 103, 120, 103, 86, 119
        .byte   85, 87, 118, 119, 133, 103, 100, 119, 103, 118, 119, 86, 102, 119, 102, 87, 103, 104, 103, 101, 103, 118, 119, 119, 118, 119, 134, 119, 135, 118, 119, 103
        .byte   119, 119, 135, 103, 119, 119, 103, 117, 85, 119, 136, 87, 87, 119, 103, 119, 119, 117, 116, 119, 104, 103, 136, 86, 119, 104, 87, 101, 117, 119, 135, 102
        .byte   101, 135, 134, 118, 118, 119, 118, 104, 119, 134, 117, 103, 118, 119, 118, 103, 119, 118, 103, 119, 120, 134, 120, 135, 118, 119, 135, 119, 120, 136, 119, 102
        .byte   136, 118, 120, 135, 119, 120, 104, 119, 120, 119, 119, 103, 119, 120, 136, 134, 102, 102, 119, 118, 118, 103, 135, 118, 88, 103, 120, 87, 104, 119, 135, 136
        .byte   119, 119, 135, 136, 136, 135, 135, 119, 136, 119, 120, 136, 120, 120, 118, 104, 134, 119, 118, 119, 118, 102, 134, 134, 136, 117, 120, 118, 135, 120, 135, 136
        .byte   135, 135, 136, 120, 119, 118, 120, 135, 103, 136, 136, 134, 136, 120, 134, 135, 119, 137, 118, 119, 118, 119, 119, 103, 120, 120, 120, 135, 103, 136, 119, 103
        .byte   136, 120, 134, 135, 135, 119, 119, 119, 119, 120, 135, 119, 135, 119, 118, 120, 136, 119, 119, 119, 135, 103, 134, 135, 118, 119, 116, 104, 103, 119, 104, 136
        .byte   118, 104, 87, 117, 119, 103, 120, 87, 135, 136, 134, 136, 119, 135, 119, 136, 136, 120, 135, 103, 120, 120, 136, 103, 134, 119, 102, 120, 104, 119, 119, 135
        .byte   86, 102, 120, 120, 103, 103, 118, 135, 119, 103, 119, 119, 133, 119, 103, 132, 134, 119, 117, 87, 120, 120, 118, 135, 120, 135, 119, 135, 102, 136, 134, 136
        .byte   119, 119, 134, 119, 120, 102, 87, 136, 135, 120, 119, 120, 119, 119, 120, 104, 117, 118, 135, 119, 117, 87, 120, 119, 103, 117, 135, 119, 71, 118, 117, 119
        .byte   117, 86, 119, 119, 135, 102, 103, 119, 134, 119, 118, 118, 119, 87, 119, 135, 103, 120, 119, 135, 118, 118, 120, 118, 117, 135, 135, 87, 119, 104, 120, 102
        .byte   119, 120, 119, 119, 119, 135, 102, 119, 135, 119, 119, 118, 119, 120, 120, 119, 119, 119, 119, 120, 120, 104, 135, 119, 119, 120, 118, 135, 103, 119, 119, 86
        .byte   119, 117, 87, 119, 117, 118, 119, 117, 71, 119, 86, 119, 120, 119, 119, 119, 102, 119, 135, 119, 103, 134, 135, 102, 136, 103, 120, 135, 118, 86, 103, 118
        .byte   118, 120, 119, 118, 104, 134, 103, 118, 86, 118, 119, 119, 119, 135, 118, 119, 103, 87, 103, 103, 120, 119, 135, 102, 118, 118, 135, 135, 119, 135, 136, 118
        .byte   120, 119, 119, 120, 136, 136, 104, 136, 119, 119, 119, 136, 119, 135, 136, 119, 119, 119, 119, 120, 136, 135, 136, 119, 119, 102, 119, 103, 103, 119, 104, 104
        .byte   119, 102, 86, 120, 120, 103, 134, 135, 135, 136, 134, 135, 136, 119, 120, 119, 119, 120, 119, 136, 135, 135, 120, 134, 88, 119, 136, 119, 119, 135, 104, 133
        .byte   104, 135, 135, 119, 135, 86, 119, 86, 118, 135, 120, 71, 119, 103, 87, 86, 86, 118, 87, 118, 102, 119, 135, 118, 103, 119, 117, 119, 102, 118, 118, 103
        .byte   120, 103, 104, 135, 119, 135, 119, 119, 135, 134, 118, 104, 119, 120, 119, 119, 135, 119, 135, 102, 103, 119, 119, 103, 102, 119, 87, 119, 120, 119, 134, 134
        .byte   118, 119, 101, 103, 117, 101, 136, 118, 133, 116, 119, 117, 103, 120, 103, 117, 120, 119, 135, 118, 134, 120, 134, 117, 120, 135, 87, 120, 119, 120, 102, 119
        .byte   118, 119, 103, 119, 118, 135, 103, 120, 102, 120, 119, 119, 119, 120, 102, 103, 118, 134, 103, 118, 118, 87, 102, 104, 119, 86, 134, 104, 87, 119, 103, 119
        .byte   102, 119, 118, 103, 103, 119, 103, 87, 102, 120, 135, 103, 120, 119, 118, 103, 118, 120, 120, 118, 103, 119, 118, 120, 103, 133, 103, 120, 104, 135, 119, 104
        .byte   135, 120, 119, 136, 119, 104, 135, 118, 119, 135, 120, 136, 134, 119, 135, 118, 102, 119, 120, 119, 119, 119, 119, 118, 119, 136, 119, 136, 103, 103, 120, 119
        .byte   136, 134, 134, 135, 119, 119, 135, 120, 136, 119, 103, 120, 135, 104, 136, 119, 135, 136, 120, 135, 119, 120, 119, 136, 119, 103, 136, 119, 120, 134, 120, 135
        .byte   136, 136, 119, 120, 119, 135, 104, 119, 135, 119, 135, 103, 135, 103, 135, 120, 118, 135, 119, 120, 118, 137, 136, 135, 119, 136, 119, 120, 136, 135, 135, 135
        .byte   119, 136, 135, 136, 120, 120, 119, 120, 135, 120, 136, 119, 120, 135, 118, 135, 119, 134, 135, 119, 120, 137, 135, 136, 136, 136, 136, 136, 135, 136, 136, 135
        .byte   136, 120, 135, 135, 103, 102, 135, 120, 119, 119, 119, 135, 135, 135, 118, 118, 120, 119, 119, 104, 104, 135, 104, 136, 135, 120, 118, 135, 135, 118, 117, 136
        .byte   120, 119, 104, 135, 135, 119, 136, 119, 119, 135, 134, 136, 135, 119, 135, 119, 102, 134, 118, 135, 133, 119, 104, 134, 104, 135, 119, 118, 103, 120, 136, 136
        .byte   136, 135, 135, 136, 119, 120, 119, 135, 119, 121, 136, 120, 136, 120, 136, 135, 119, 120, 120, 120, 120, 136, 135, 135, 103, 135, 119, 136, 118, 119, 103, 117
        .byte   103, 120, 103, 103, 119, 135, 118, 103, 136, 119, 135, 120, 120, 119, 136, 135, 119, 119, 136, 136, 119, 134, 134, 136, 119, 120, 136, 87, 104, 120, 119, 135
        .byte   135, 136, 134, 135, 135, 103, 102, 119, 135, 135, 119, 136, 119, 119, 120, 120, 119, 135, 103, 103, 119, 120, 136, 119, 102, 103, 133, 117, 119, 119, 119, 85
        .byte   119, 119, 88, 87, 103, 135, 70, 119, 119, 135, 118, 136, 136, 118, 119, 119, 133, 102, 120, 119, 136, 103, 135, 135, 119, 119, 103, 120, 119, 120, 120, 119
        .byte   119, 119, 119, 134, 104, 136, 120, 103, 135, 136, 120, 120, 136, 119, 119, 120, 103, 136, 104, 120, 119, 102, 135, 103, 118, 119, 103, 118, 88, 120, 103, 135
        .byte   102, 118, 119, 104, 118, 87, 135, 136, 136, 103, 119, 119, 103, 104, 120, 135, 134, 136, 103, 118, 87, 104, 136, 135, 135, 118, 120, 118, 104, 136, 135, 134
        .byte   136, 119, 103, 136, 135, 119, 118, 119, 119, 119, 119, 120, 119, 102, 120, 135, 136, 136, 136, 119, 136, 135, 119, 136, 119, 120, 120, 135, 136, 136, 135, 135
        .byte   119, 104, 134, 134, 120, 135, 119, 118, 120, 135, 119, 119, 119, 119, 120, 120, 136, 120, 120, 119, 134, 104, 119, 135, 103, 136, 136, 120, 119, 119, 119, 120
        .byte   120, 119, 120, 120, 104, 134, 135, 118, 120, 135, 136, 135, 119, 119, 119, 103, 118, 119, 119, 119, 119, 119, 135, 119, 119, 118, 135, 119, 117, 119, 102, 118
        .byte   118, 118, 119, 118, 101, 102, 119, 102, 103, 119, 103, 118, 117, 134, 102, 118, 119, 118, 135, 134, 118, 119, 104, 118, 118, 135, 119, 118, 102, 120, 119, 102
        .byte   119, 135, 103, 136, 103, 102, 117, 103, 135, 135, 120, 118, 88, 119, 103, 119, 133, 119, 103, 104, 120, 103, 119, 117, 119, 117, 118, 104, 119, 102, 103, 135
        .byte   103, 118, 103, 102, 101, 102, 120, 135, 119, 120, 119, 119, 118, 135, 119, 119, 135, 119, 119, 118, 119, 118, 103, 135, 103, 103, 117, 119, 119, 103, 119, 103
        .byte   119, 86, 103, 119, 101, 87, 118, 119, 87, 116, 104, 119, 87, 119, 119, 88, 102, 87, 119, 119, 102, 134, 118, 118, 117, 119, 103, 101, 104, 102, 118, 119
        .byte   120, 118, 120, 135, 136, 135, 135, 136, 104, 135, 119, 135, 120, 118, 135, 119, 120, 136, 103, 119, 118, 136, 117, 119, 119, 136, 119, 102, 136, 135, 120, 119
        .byte   135, 136, 136, 119, 119, 135, 134, 119, 120, 135, 119, 120, 119, 118, 119, 103, 119, 102, 104, 102, 103, 136, 118, 104, 119, 134, 120, 87, 117, 119, 102, 87
        .byte   135, 103, 103, 118, 119, 104, 120, 119, 103, 136, 102, 104, 119, 119, 118, 118, 120, 120, 135, 136, 103, 119, 120, 119, 136, 104, 135, 119, 136, 132, 116, 117
        .byte   117, 117, 119, 134, 101, 104, 101, 119, 119, 117, 102, 120, 103, 119, 117, 103, 119, 104, 101, 117, 103, 119, 119, 118, 103, 116, 102, 104, 119, 103, 102, 103
        .byte   119, 118, 119, 134, 119, 133, 103, 119, 102, 120, 134, 119, 117, 118, 119, 87, 104, 119, 118, 119, 119, 100, 117, 104, 102, 135, 120, 103, 119, 120, 119, 119
        .byte   104, 135, 135, 119, 118, 135, 135, 120, 135, 135, 134, 104, 120, 135, 135, 119, 119, 120, 135, 119, 136, 120, 118, 119, 136, 134, 103, 119, 119, 135, 119, 135
        .byte   119, 120, 119, 104, 103, 120, 88, 119, 120, 135, 119, 120, 118, 119, 135, 120, 118, 103, 120, 134, 120, 119, 119, 120, 119, 103, 136, 119, 136, 134, 136, 135
        .byte   135, 119, 136, 134, 119, 136, 103, 120, 119, 120, 119, 136, 119, 119, 135, 119, 104, 119, 120, 102, 103, 118, 134, 104, 104, 104, 104, 103, 120, 88, 102, 133
        .byte   119, 119, 119, 120, 119, 118, 102, 103, 135, 103, 119, 103, 119, 117, 103, 118, 120, 136, 135, 103, 135, 136, 136, 135, 120, 151, 136, 119, 136, 135, 135, 135
        .byte   135, 135, 118, 120, 135, 118, 134, 119, 120, 120, 120, 120, 119, 120, 136, 136, 117, 120, 120, 134, 120, 120, 104, 120, 120, 120, 135, 120, 118, 135, 104, 119
        .byte   134, 119, 119, 104, 119, 102, 120, 120, 135, 117, 120, 134, 104, 119, 135, 119, 134, 119, 135, 119, 119, 136, 119, 120, 118, 119, 135, 135, 120, 135, 120, 119
        .byte   120, 118, 120, 104, 119, 120, 136, 136, 120, 135, 120, 119, 118, 135, 103, 104, 135, 103, 134, 104, 135, 102, 119, 134, 87, 120, 103, 103, 120, 120, 120, 119
        .byte   136, 134, 120, 120, 135, 136, 119, 119, 120, 104, 103, 119, 136, 135, 135, 135, 119, 135, 120, 136, 137, 136, 119, 119, 133, 134, 120, 103, 118, 119, 118, 103
        .byte   134, 134, 118, 87, 119, 119, 134, 118, 86, 86, 135, 103, 136, 119, 104, 134, 119, 118, 119, 135, 119, 120, 134, 135, 120, 119, 103, 120, 135, 119, 119, 136
        .byte   120, 118, 119, 135, 135, 120, 120, 120, 135, 136, 136, 120, 135, 136, 151, 119, 120, 135, 136, 136, 120, 136, 136, 119, 120, 119, 136, 120, 119, 120, 136, 135
        .byte   136, 120, 119, 119, 118, 120, 104, 119, 103, 120, 119, 118, 88, 119, 119, 88, 119, 119, 119, 119, 119, 118, 120, 119, 118, 119, 104, 136, 117, 119, 133, 118
        .byte   102, 117, 119, 87, 119, 119, 87, 117, 71, 119, 117, 119, 135, 117, 103, 119, 101, 119, 87, 119, 119, 86, 117, 71, 119, 88, 119, 87, 134, 119, 120, 119
        .byte   118, 118, 119, 120, 104, 119, 119, 119, 119, 135, 101, 118, 103, 120, 103, 119, 119, 135, 120, 119, 119, 119, 120, 118, 119, 135, 119, 104, 119, 119, 119, 119
        .byte   120, 120, 135, 135, 120, 119, 104, 119, 119, 136, 104, 120, 118, 119, 103, 136, 119, 119, 136, 119, 119, 119, 134, 120, 119, 119, 103, 119, 136, 118, 120, 103
        .byte   118, 119, 119, 118, 134, 119, 103, 119, 135, 103, 103, 119, 103, 119, 118, 118, 104, 119, 119, 118, 134, 118, 135, 120, 135, 119, 135, 118, 118, 118, 118, 135
        .byte   135, 103, 134, 103, 119, 133, 119, 134, 104, 136, 134, 119, 136, 134, 119, 135, 118, 87, 119, 119, 135, 120, 136, 136, 136, 135, 120, 136, 120, 135, 136, 135
        .byte   119, 136, 135, 104, 136, 136, 120, 135, 119, 120, 136, 119, 119, 135, 120, 135, 120, 119, 118, 119, 135, 135, 135, 103, 117, 104, 120, 120, 103, 135, 120, 104
        .byte   119, 135, 119, 103, 103, 120, 86, 118, 102, 118, 102, 88, 101, 103, 103, 119, 118, 104, 87, 120, 119, 135, 135, 119, 103, 103, 136, 104, 135, 103, 120, 119
        .byte   119, 119, 119, 117, 119, 86, 87, 135, 87, 118, 103, 135, 85, 118, 119, 70, 135, 120, 135, 103, 119, 119, 136, 118, 120, 118, 120, 118, 120, 119, 117, 119
        .byte   103, 118, 136, 103, 118, 120, 119, 103, 118, 104, 136, 119, 119, 117, 119, 119, 135, 120, 119, 120, 104, 119, 120, 135, 135, 118, 136, 136, 136, 120, 135, 136
        .byte   103, 103, 120, 120, 135, 103, 135, 104, 119, 136, 118, 120, 136, 136, 136, 135, 135, 119, 135, 136, 135, 136, 120, 136, 136, 120, 135, 104, 119, 119, 120, 119
        .byte   118, 102, 104, 135, 118, 118, 119, 86, 104, 119, 118, 119, 120, 86, 104, 120, 119, 118, 103, 118, 134, 135, 103, 118, 103, 135, 136, 119, 119, 134, 135, 119
        .byte   104, 135, 103, 136, 119, 119, 120, 135, 134, 118, 103, 135, 86, 119, 103, 104, 104, 135, 101, 120, 135, 103, 134, 119, 119, 120, 103, 103, 119, 119, 135, 119
        .byte   119, 135, 118, 103, 135, 103, 119, 103, 69, 135, 119, 87, 103, 119, 118, 103, 103, 103, 135, 71, 103, 103, 70, 70, 135, 103, 71, 103, 100, 102, 116, 104
        .byte   115, 118, 118, 116, 103, 103, 119, 118, 102, 103, 119, 118, 118, 118, 102, 118, 118, 119, 87, 102, 70, 119, 116, 70, 120, 116, 102, 118, 100, 55, 118, 70
        .byte   104, 119, 103, 119, 118, 117, 102, 120, 100, 119, 119, 86, 118, 135, 118, 116, 104, 118, 134, 119, 134, 103, 118, 103, 117, 104, 103, 103, 103, 103, 87, 103
        .byte   118, 119, 119, 102, 119, 119, 119, 117, 102, 119, 119, 103, 119, 102, 102, 120, 104, 102, 135, 120, 120, 136, 136, 135, 120, 120, 135, 120, 119, 136, 104, 119
        .byte   118, 135, 119, 119, 103, 120, 120, 135, 103, 136, 103, 103, 119, 119, 102, 118, 118, 118, 118, 119, 119, 119, 86, 118, 103, 120, 102, 151, 134, 118, 120, 118
        .byte   118, 119, 119, 118, 117, 102, 119, 119, 120, 118, 118, 136, 136, 136, 120, 136, 120, 119, 119, 135, 118, 120, 135, 136, 136, 135, 136, 119, 136, 135, 119, 136
        .byte   135, 119, 120, 103, 103, 119, 136, 151, 120, 119, 135, 118, 134, 102, 119, 118, 119, 119, 104, 119, 118, 134, 117, 134, 136, 134, 120, 120, 136, 103, 119, 120
        .byte   120, 134, 119, 119, 136, 120, 120, 103, 134, 119, 135, 118, 119, 103, 120, 118, 119, 119, 118, 135, 134, 102, 101, 103, 118, 118, 102, 102, 103, 119, 86, 118
        .byte   118, 86, 120, 118, 87, 119, 119, 135, 136, 135, 136, 119, 119, 119, 120, 120, 120, 120, 119, 103, 135, 102, 119, 118, 136, 120, 118, 119, 119, 119, 119, 119
        .byte   135, 118, 104, 103, 117, 118, 102, 103, 118, 102, 119, 102, 119, 86, 119, 119, 87, 104, 136, 120, 120, 119, 136, 136, 135, 136, 119, 118, 119, 120, 136, 136
        .byte   120
# END GENERATED TABLES

# ---------------------------------------------------------------------------
# scratch memory no heap
# ---------------------------------------------------------------------------
        .align  2
root_st:  .zero 16                     # p0..6, pad, o0..6, pad
cur_st:   .zero 16
new_st:   .zero 16
path:     .zero 16
frames:   .zero 256                    # 16 frames x 16 bytes
loc_buf:  .zero 8                      # root slot of each cubie
num_buf:  .zero 4
in_buf:   .zero 16                      # CLI state string
