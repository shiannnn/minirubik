# Host test shim for stage3.s (qemu-riscv32, Linux ABI). Not part of the
# Ripes deliverable: replaces _start and put_str of stage3.s so that every
# argv[1..] state is solved and printed on stderr by the same solve_case.
        .text
        .globl  _start
        .globl  put_str
_start:
        lw      s0, 0(sp)               # argc
        addi    s1, sp, 4               # argv
        li      s2, 1
        li      s3, 0                   # failures
arg_loop:
        bge     s2, s0, arg_done
        slli    t0, s2, 2
        add     t0, t0, s1
        lw      a0, 0(t0)
        li      a1, -1                  # no expected distance
        call    solve_case
        xori    a0, a0, 1
        add     s3, s3, a0
        addi    s2, s2, 1
        j       arg_loop
arg_done:
        mv      a0, s3
        li      a7, 93
        ecall

put_str:                                # a0 = NUL-terminated string
        mv      a1, a0
        li      a2, 0
ps_len:
        add     t0, a1, a2
        lbu     t0, 0(t0)
        beqz    t0, ps_go
        addi    a2, a2, 1
        j       ps_len
ps_go:
        li      a0, 2
        li      a7, 64
        ecall
        ret
