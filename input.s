start
	adr r8, inp
collectInp
	swi 1
	cmp R0, #0
	beq end

	strb R0, [r8], #1

	b collectInp
end
	swi 2


align
inp defs 12
