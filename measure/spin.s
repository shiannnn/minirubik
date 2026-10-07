# spin.s - fixed-length loop for the retired-instructions-per-second measurement.
# ITER is substituted by measure.ps1 (placeholder @ITER@). Roughly 2*ITER instructions.
.text
    li   t0, @ITER@
loop:
    addi t0, t0, -1
    bnez t0, loop
    li   a7, 10
    ecall
