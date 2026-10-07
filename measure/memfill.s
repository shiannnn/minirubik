# memfill.s - touch N distinct guest bytes, one sb per byte, for the
# host-bytes-per-guest-byte measurement.
# N is substituted by measure.ps1 (placeholder @N@). N = 0 gives the baseline run.
.text
    li   a0, 0x20000000      # far from .text/.data/stack
    li   a1, @N@
    add  a1, a0, a1          # end pointer
    beq  a0, a1, done        # N = 0: write nothing
    li   t0, 0x5a
loop:
    sb   t0, 0(a0)
    addi a0, a0, 1
    bne  a0, a1, loop
done:
    li   a7, 10
    ecall
