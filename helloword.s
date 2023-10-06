start
	mov R0, #1
	mov R1, #2
	add R3, R1, R2

	mov r0, 'a'
	swi 0
	adr r0, stra
	swi 3

	b start
	ret


stra defb "Hello world!",0
