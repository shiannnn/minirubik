# Small program for the Ripes datapath walkthrough, note.md section 4.8.
# Run it on RV32_5S, not RV32_ISS, and press Step once per clock cycle.
# Each block uses an instruction pattern that stage5_led.s relies on.
        .text
        .globl  _start
_start:
        la      s0, tbl
        la      s1, fb
        li      t0, 5
        # 1 shift and add replaces a multiply, as in the idx = o*210 + l code
        slli    t1, t0, 1               # t1 = 2 * 5
        add     t1, t1, t0              # t1 = 3 * 5 = 15, forwarded from slli
        # 2 table load followed by its use, a load-use hazard like onext and lnext
        add     t2, s0, t0              # address of tbl at 5
        lbu     t3, 0(t2)               # t3 = 40
        add     t4, t3, t1              # needs t3 right away: one stall, 55
        # 3 stores like the frame buffer writes of render
        sw      t4, 0(s1)               # word 55 at fb
        sb      t3, 4(s1)               # byte 40 at fb + 4
        # 4 backward branch, taken twice and then not taken, like the search loops
        li      t5, 3
loop:
        addi    t5, t5, -1
        bnez    t5, loop
        # 5 read the stored word back
        lw      a0, 0(s1)
        li      a7, 93
        nop
        nop
        nop
        ecall
        .data
tbl:    .byte   10, 15, 20, 25, 30, 40, 50, 60
        .align  2
fb:     .zero   8
