#!/bin/sh
# Assemble stage3.s for qemu-riscv32 and solve the given states (output on stderr).
#   tools/qemu_test.sh 21345671111111 [more states...]
# Needs riscv64-unknown-elf-as/ld and qemu-riscv32
# (apt: binutils-riscv64-unknown-elf qemu-user). Run from the repository root.
set -e
d=$(mktemp -d)
sed 's/^_start:/ripes_start:/; s/^put_str:/ripes_put_str:/' stage3.s > "$d/s.s"
for n in s qemu_shim; do
    src="$d/$n.s"; [ "$n" = qemu_shim ] && src=tools/qemu_shim.s
    riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -mno-relax "$src" -o "$d/$n.o"
done
riscv64-unknown-elf-ld --no-relax -m elf32lriscv "$d/s.o" "$d/qemu_shim.o" -o "$d/t.elf"
set +e
qemu-riscv32 "$d/t.elf" "$@"
rc=$?
rm -rf "$d"
exit $rc
