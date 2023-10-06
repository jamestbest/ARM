start
	adr r1, arr
	ldr r0, [r1, #4]

	adr r8, inp
collectInp
	swi 1
	cmp R0, #0
	beq end

	ldr r0, 100

	strb R0, [r8], #1

	b collectInp
end
	swi 2


align
inp defs 12

arr defw 1,2,3,4,5 
