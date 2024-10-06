dd if=firmware_1.bin of=part_1.bin bs=1 skip=$((0x000000)) count=$((0x200000))
dd if=firmware_1.bin of=part_2.bin bs=1 skip=$((0x200000)) count=$((0x400000))
dd if=firmware_1.bin of=part_3.bin bs=1 skip=$((0x600000)) count=$((0x200000))
dd if=firmware_1.bin of=part_4.bin bs=1 skip=$((0x800000)) count=$((0xc00000))