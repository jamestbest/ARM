
strings:
stra: defw "This is a sentence"
strb: defb 'h', 'i'

start:
	mov R0, #1
	mov R1, #2
	add R3, R1, R2

	mov r0, 'a'
	swi 0
	ret

