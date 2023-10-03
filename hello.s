start
    
    adr R0, hello 
    swi 3

    adr R0, ask
    swi 3

    bl getname

    bl sayname

    adrl r0, name
    adrl r1, sudoname
    bl rstreq

    bl outputres

    adr R0, goodbye
    swi 3

    swi 2

outputres
    ;;now that we have compared the strings we can output if they are the same or not
    ;; only input is in r0 and it is 1 for eq and 0 for neq
    cmp r0, #0
    beq outfail
outsucc
    adrl r0, success
    swi 3
    b outend
outfail
    adrl r0, fail
    swi 3
outend
    mov r15, r14

rstreq
    ;;adr of first string is in R0
    ;;adr of second string is in R1
    ;;The result (0 for neq and 1 for eq) will be stored in R0

    ;;while not the end of either string
    ;;  cmp the string at that position
    ;;  if not eq then return 0 else continue
    ;;cmp if the strings are of the same length i.e. if one has stopped by the other has not
    mov r4, #0
rstreqloop
    ;r4 stores the index offset
    ldrb r5, [r0, r4]
    ldrb r6, [r1, r4]

    cmp r5, #0
    beq endstra
    cmp r6, #0
    beq endstrb

    add r4, r4, #1

    cmp r5, r6
    bne rstrneq
    b rstreqloop

rstrneq
    mov r0, #0
    mov r15, r14;;ret

endstra
    ;;we have reached the end of string a and should return True if str b is also ended
    ldrb r6, [r0, r4]
    mov r0, #0
    cmp r6, #0
    moveq r0, #1
    b rstreqend

endstrb
    ;;we have reached the end of string b and so should return 1 if str a has also ended
    ldrb r5, [r1, r4]
    mov r0, #0
    cmp r5, #0
    moveq r0, #1
    b rstreqend

rstreqend
    mov r15, r14

sayname
    adr r0, respond
    swi 3
    adr r0, name
    swi 3
    adr r0, newline
    swi 3
    mov r15, r14
    

getname
    adr r8, name 
getnameloop
    swi 1
    cmp r0, #33 
    beq getnameend

    strb r0, [R8], #1

    b getnameloop
getnameend
    mov r0, #0
    strb r0, [R8], #1
    mov r15, r14

hello defb "Hello world!\n", 0
goodbye defb "Goodbye cruel world!\n", 0
ask defb "Please enter your name:\n", 0
respond defb "Your name is: ", 0
newline defb "\n", 0
sudoname defb "james", 0
success defb "Congrats you are the correct user!\n", 0
fail defb "Unfortunately you are not the correct user :(\n", 0
name defs 30