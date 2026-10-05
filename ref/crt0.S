# Minimal start-up for the GCC reference build: call main, exit with its
# return value (Ripes/MARS ecall 93). No stack setup: Ripes initialises sp.
        .globl  _start
        .text
_start:
        call    main
        li      a7, 93
        ecall
