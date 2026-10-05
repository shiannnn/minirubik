#!/bin/sh
# Build the GCC reference for one state: sh measure/build_ref.sh 21345671111111 out.elf [-DQUICK]
# (riscv64-unknown-elf-gcc 10.2, newlib/libgcc multilib rv32i/ilp32)
set -e
riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32 -mno-relax -nostdlib -static -isystem /usr/include/newlib \
    $3 -Wall -Wextra -DSTATE="\"$1\"" -Iref -Wl,--no-relax -Wl,-Ttext=0 -Wl,-Tdata=0x10000000 \
    -o "$2" ref/crt0.S ref/stage3_ref.c -lgcc
