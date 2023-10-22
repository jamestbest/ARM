	b main

labela defb "This is a string of length 30", 0
labelb defb "This string is not aligned at addr 0x22 of len 50", 0
labelc defb "This string is aligned at addr 0x54 of len 44", 0

	align

;;aligned labels have a range of 1020 bytes from ADR instruction
;;non-aligned labels have a range of 255 bytes from ADR instruction

main
	;;all labels are within 255 bytes and so adr should work
	;;address 0x84

	adr R0, labela
	adr R1, labelb
	adr R2, labelc

	defs  0xF8
	;;This should place all of the labels at least 255 bytes away from the current instruction
	;;address 0x188

	adr R0, labela
	;;adr R1, labelb   ;;because labelb is the only non-aligned string it will fail here with out of range, the others however are still within 1020 bytes.
	adrl R1, labelb    ;;adrl is turned into two offsets i.e. SUB R1, PC, #0x72 and SUB R1, R1, #0x100
	adr R2, labelc
	adrl R2, labelc    ;;even given adrl here the assembler has only turned it into one offset i.e. SUB R2, PC, #0x14C

	defs  0x2E8

	;;This should place all of the labels at least 1020 bytes away from the labels, making all adr's out of range
	;;address 0x484

	;;adr R0, labela
	;;adr R1, labelb
	;;adr R2, labelc

	adrl R0, labela
	adrl R1, labelb
	adrl R2, labelc

	defs 0xFA000

	;;This should place non-aligned addresses out of range according to the [ARM page](https://developer.arm.com/documentation/dui0068/b/ARM-Instruction-Reference/ARM-pseudo-instructions/ADRL-ARM-pseudo-instruction)
	;;However aasm seems to just generate more offsets and so it will continue to work until the max kmd mem. addr. (0x100000)
	;;address 0xFA498
	adrl R0, labela
	adrl R1, labelb
	adrl R2, labelc
