;;  This is my second rendition of JCGOL in ARM assembly for Komodo
;;  
;;  This will attempt to follow the ARM 32bit calling convention 
;;      R0-3 are argument registers, scratch
;;      R4-10 are local variable registers and should be saved before use in a function
;;      R11 - FP
;;      R12 - IPC
;;      R13 - SP
;;      R14 - LR
;;      R15 - PC
;;
;;  The plan
;;  - Create a simple `heap` allocator for the grid and input
;;  - Ask the user
;;      |-Use default? Y - skip below
;;      |-dims of the grid
;;      |   `-Will need a way to get a string input and convert to an integer (make sure to catch -ve)
;;      |-slow mode
;;      `-erase mode
;;  - ask for generation mode
;;      |-If random ask for seed
;;      |   `-For generation roll the seed to create a pseudorandom value for each `pixel`
;;      `-If draw then get them to draw the grid one `pixel` at a time
;;  - Allocate two grids, the pointers to which will swap after a frame. One is used to count the neighbours the other for the new cell value.
;;  - loop
;;      |-count neighbours
;;      |-update inactive grid
;;      |-swap grids
;;      |-draw active grid
;;      `-goto loop


;;SINGLE STEP mode allows you to save the current state of the board into a list, also give it a name
;;At the main menu you can load a saved grid

;;Save info struct
;;  -address of grid [4 BYTES]
;;  -char* to the name [4 BYTES]


;;  CURRENT ISSUES/TODOS
;;  |-More testing of malloc & free need to be done
;;  |-Think about minimising the fragmentation of the heap - find the best free block instead of the first
;;  |
;;  |-Need to add the saveGrid and LoadGrids methods
;;  |-Need to restructure the gridInfo struct - it needs the ptr to arr, maxsize, and current index - this will shift the sp offset to not n + m + 4 % 8 == 0
;;  |-Need to copy the grid when saving to allow the current grid to be used again
;;  `-When we're in the menu should the current grids be freed?
max_addr    EQU  0x100000
stack_size  EQU  0x10000
nlchar      EQU  10
backspace   EQU  8
minBuffSize EQU  8
enter       EQU  nlchar
minSaveSize EQU  8
sizeofSaveI EQU  8

_start
    ;;prepare the stack
    ldr R13, =max_addr
    mov R14, #0 ;; allow for `returning` from _start
    push {R14}

    ;;[[temp]] clean the heap
    bl heapclean

    ;;setup heap
    adrl R0, heapstart
    str R0, heaphead
    bl setupHeap

    mov R0, #14
    bl malloc

    bl main

    pop {R14}
    swi 2
    mov R15, R14

main
    push {fp, R14, R4-R10} ;;8 registers saved

    add fp, sp, #28 ;;(r - 1) * 4
    sub sp, sp, #8 ;;reserve 8bytes on the stack for the pointer to the list of saved grids + the maxSize of the array

    ldr R0, =minSaveSize
    str R0, [sp, #0]

    ;;minsize * sizeof(SaveInfo)
    ldr R1, =sizeofSaveI
    mul R0, R0, R1
    bl malloc ;;allocate the array on the heap

    str R0, [sp, #4] ;;store the address

    adrl R0, welcomemsg
    swi 3

    adrl R0, welcome2msg
    swi 3

mainchoice
    swi 1
    orr R0, R0, #32
    cmp R0, #'n' ;;new board generation
    beq newboard

    cmp R0, #'l' ;;load a saved board
    beq loadboard

    cmp R0, #'q' ;;quit
    beq mainEnd

    adrl R0, mainchoicefail
    swi 3

    b mainchoice

    ;;R4 will hold the active grid, R5 will hold the passive grid
    ;;Active is used to count neighbours, passive is used to place updated values in 
    ;;either can be drawn, just drawn in a different position

newboard
    mov R0, #1;;should get dims
    bl setupOptions

    bl setupGrid
    
    ldr R4, gridA
    ldr R5, gridB

    cmp R4, #0
    beq gridFail
    cmp R5, #0
    beq gridFail

    b mainloopstart

loadboard
;;display the saved grids
;;ask for the index
;;load the grids with the saved info
;;ask the user for the settings
;;b to mainloopstart

;;update loop
;;    - loop
;;      |-count neighbours
;;      |-update inactive grid
;;      |-swap grids
;;      |-draw grid
;;      |-[slow?] - slow() - loops for some time to increase waiting time
;;      |-[step?] - step() - waits for input, s and q will have effects
;;      |-[erase?] - erase() - \b until grid is gone
;;      `-goto loop
mainloopstart
    ;;load the slow, step, and erase booleans
    ldrb R6, slow_b
    ldrb R7, erase_b
    ldrb R8, step_b

    ;;(width * height) * 2 + 1 + height
    ldrb R0, width
    ldrb R1, height
    mul R0, R0, R1
    mov R0, R0, lsl #1
    add R0, R0, #1
    add R0, R0, R1
    mov R9, R0      ;;R9 holds the itterations for erase, so it doesn't have to calc it every time

mainloop
    mov R0, R4
    mov R1, R5
    bl updategrid

    mov R0, R4
    bl drawgrid

    cmp R8, #1
    bleq step

    cmp R6, #1
    bleq slow

    cmp R7, #1
    moveq R0, R9
    bleq erase

    mov R0, R4
    mov R4, R5
    mov R5, R0 ;;SWAP the active and passive

    b mainloop

gridFail
    adrl R0, gridfailmsg
    swi 3

mainEnd
    ;;need to free all of the memory, saved grids (grids + names) + current grids

    sub sp, fp, #24 ;;???
    pop {R14, R4-R10}
    mov R15, R14

newline
    ldr R0, =nlchar
    swi 0

    mov R15, R14

step
;;INP --
;;OUT in R0 is 1 if should return to main menu, else 0

;;get user input
;;if q -> jump to main menu
;;if s -> ask for name, bl saveGrid with name
    push {R14, R4-R8}

    swi 1

    cmp R0, #'q'
    beq stependfail ;;bad name, shame I can't change it eh

    cmp R0, #'s'
    bne stependsucc

    adrl R0, askname
    swi 3

    ldr R0, =enter
    mov R1, #-1
    mov R2, #1
    bl getstring

    bl saveGrid

    adrl R0, savedchoice
    swi 3

    cmp R0, #'Y'
    beq stependfail
    b stependsucc

stependfail
    mov R0, #1
    b stepend

stependsucc
    mov R0, #0

stepend
    pop {R14, R4-R8}
    mov R15, R14

saveGrid
;;INP in R0 is the ptr gridInfo struct (in the main's stackframe)
;;INP in R1 is the char* to the name
;;RET --

;;if reachedCap -> realloc + inc maxsize
;;copy the current grid to another loc and place info in gridArr
;;inc current index

erase
;;INP in R0 is the itters
;;for (width * height + 1) * 2 + 1
;;      print('\b')
    mov R1, R0

eraseloop
    cmp R1, #0
    beq eraseend

    ldr R0, =backspace
    swi 0

    sub R1, R1, #1
    b eraseloop

eraseend
    mov R15, R14

slow
    mov R1, #0xFF
    mov R1, R1, lsl #1

slowloop
    cmp R1, #0
    beq slowend

    mov R0, #' '
    swi 0
    ldr R0, =backspace
    swi 0

    sub R1, R1, #1
    b slowloop

slowend
    mov R15, R14

heapclean
;;zero out all memory in the heap (debugging uses)
    adrl R0, heapstart
    ldr R1, =max_addr ;;stores the end of the heap
    ldr R2, =stack_size
    sub R1, R1, R2 ;; R1 = max_addr - stack_size which should be the heap end
    and R1, R1, #-4 ;;align to 4 byte boundry just in case
    mov R3, #0
heapcleanloop ;;starting at heapstart
    cmp R0, R1
    beq heapcleanend
    str R3, [R0] ;;store 0 in loc
    add R0, R0, #4 ;;inc by a word
    b heapcleanloop
heapcleanend
    mov R15, R14


strlen
;;INP in R0 is the address of the string
;;OUT in R0 is the length of the null terminated string

;;len = 0
;;while(inp[len] != \0) {len++;}
;;return len

    mov R1, #0 ;;len
    cmp R0, #0
    beq strlenend

strlenloop
    ldrb R2, [R0, R1]
    cmp R2, #0
    beq strlenend
    add R1, R1, #1
    b strlenloop

strlenend
    mov R0, R1
    mov R15, R14

strtoi
;;INP in R0 is the address of the string
;;OUT in R0 is the value created
;;OUT in R1 is the err code
;;
;;ERR codes
;;  0 is success
;;  1 is attempted -ve
;;  2 is use of non-numeric characters
;;  3 is value out of range of integer
;;  4 is null string given

;;  example inp
;;  12234       len = 5
;;      ^-find end
;;  tot = 0
;;  for i from end to 0:
;;      tot += inp[i] * (10 ** (len(inp) - i - 1))
;;  +some checks for valid input

;;This will take in an address to the start of a string and attempt to convert it into an integer
;;String is only valid when all characters are numerical
;;For now it does not accept -ve numbers

    push {R14, R4-R8}
    mov R4, R0  ;;R4 holds the addr

    cmp R0, #0
    moveq R1, #4
    beq strtoiendfail ;;null given so err code = 4 and end

    bl strlen
    mov R5, R0  ;;R5 holds the len of the string

    cmp R5, #0
    beq strtoiendsucc ;;if len(string) == 0 then return 0

    ldrb R6, [R4, #0]
    cmp R6, #45
    beq strtoifailminus

    mov R6, #0  ;;R6 holds the total
    mov R7, #1  ;;R7 holds the **
    sub R8, R5, #1  ;;R8 is i which starts at end (len - 1)
    mov R3, #10 ;;mul to **

strtoiloop
    cmp R8, #0
    blt strtoilend

    ldrb R2, [R4, R8]
    sub R2, R2, #48

    cmp R2, #0
    blt strtoifailnonnum
    cmp R2, #9
    bgt strtoifailnonnum

    mla R6, R2, R7, R6 ;;total = (inp[i] * (**)) + total -> total += inp[i] * (**)
    bvs strtoifailoutrange
    mul R7, R7, R3

    sub R8, R8, #1

    b strtoiloop


;;branches are expensive - should this just be rep RET? probably doesn't matter at this scale
strtoilend
    mov R0, R6
    b strtoiendsucc

strtoifailminus
    mov R1, #1
    b strtoiendfail

strtoifailoutrange
    mov R1, #3
    b strtoiendfail

strtoifailnonnum
    mov R1, #2

strtoiendfail
    mov R0, #0
    b strtoiend

strtoiendsucc
    mov R1, #0

strtoiend
    pop {R14, R4-R8}
    mov R15, R14

memcpy
;;INP in R0 is the addr of src
;;INP in R1 is the addr of dst
;;INP in R2 is the number of bytes to copy

;;check if src and dst are alliged
;;If different then write bytes
;;If same then go to 4byte boundry
;;  Write words of bytes2copy / 4
;;  Write remaining bytes
    push {R14, R4-R8}

    and R4, R0, #0b11
    and R5, R1, #0b11

    cmp R4, R5
    bne memcpyallbytes

    ;;If they are the same then cpy R4 bytes and then do words
    sub R2, R2, R4;; bytes2cpy -= bytes we are about to write
    mov R3, R4
    bl memcpybytes

    ;;Now find the number of words that can be written i.e. bytes2cpy / 4 (bytes2cpy >> 2)
    and R3, R2, #-4 ;;the number of bytes to write that make up the words
    mov R4, #0 ;;i
memcpywordsloop
    cmp R4, R3
    beq memcpywordslend

    ldr R6, [R0, R4]
    str R6, [R1, R4]
    
    add R4, R4, #4

    b memcpywordsloop
    
memcpywordslend
;;Now copy the remaining bytes
    and R2, R2, #0b11
    mov R3, R2
    bl memcpybytes
    b memcpyend

memcpyallbytes
    mov R3, R2
    bl memcpybytes
    b memcpyend

memcpybytes
;;This is an internal function to memcpy and so doesn't follow the calling convention, it also assumes values are in place from memcpy
;;for (int i = 0; i < byte2cpy; i++) {
;;      *(dst + i) = *(src + i)
;;INP in R3 is the number of bytes to copy
    mov R5, #0 ;;i
memcpybytesloop
    cmp R5, R3
    beq memcpybyteslend ;;i < bytes2cpy

    ldrb R4, [R0, R5]
    strb R4, [R1, R5] ;;dst[i] = src[i]

    add R5, R5, #1 ;;i++

    b memcpybytesloop

memcpybyteslend
    mov R15, R14

memcpyend
    pop {R14, R4-R8}
    mov R15, R14

getstring
;;INP in R0 the terminator character
;;INP in R1 the max number of characters or -1 for no max
;;INP in R2 boolean (non-0/0) for if letters should be printed out as well
;;RET in R0 a ptr to the memory address
;;
;;Dynamically allocate memory to support large string

;;buff = malloc(minBytes)
;;while (input != terminator && pos < maxchars) 
;;  buff[pos] = input
;;  putchar(input)
;;  if (pos > buffSize)
;;      nBuff = malloc(buffSize << 1)
;;      memcpy from buff to nBuff
;;      free buff
;;      buff = nBuff

    push {R14, R4-R10}

    mov R8, R0 ;;now holds terminator
    mov R9, R1 ;;nax chars
    cmp R9, #0
    beq getstringEnd
    ;sub R9, R9, #1 ;;reduce by 1 to use later
    mov R10, R2 ;;print bool

    ldr R6, =minBuffSize ;;R6 will hold the current size of the buffer
    mov R0, R6
    bl malloc
    mov R4, R0 ;;R4 is the address of the buffer

    mov R5, #0 ;;R5 is the loop counter/index into buffer
getstringloop
    cmp R5, R9 ;;position - maxsize
                      ;;pos 2 means 3 characters written
    bge getstringlend ;;if position >= maxsize

    swi 1 ;;get input
    cmp R0, R8 ;;is input == terminator character
    beq getstringlend

    cmp R9, #-1
    beq skipMax
    
skipMax
    cmp R5, R6
    push {R0}
    bge getstringresize

getstringlcont
    pop {R0}
    strb R0, [R4, R5] ;;buff[pos] = input

    cmp R10, #0
    swine 0 ;;output the character to the screen if R10 is not 0

    add R5, R5, #1

    b getstringloop

getstringresize
    ;;r6 will hold new buffer
    mov R0, R6, lsl #1
    bl malloc
    mov R7, R0

    mov R0, R4 ;;old buff
    mov R1, R7 ;;newBuff
    mov R2, R5 ;;bytes to write
    bl memcpy

    mov R0, R4
    bl free
    mov R4, R7

    mov R6, R6, lsl #1

    b getstringlcont

getstringlend
    ;;need to add a \0
    ;;need to check if the buffer is completely full -> resize buffer to +1? (will be aligned to 8 in malloc!) then copy
    ;;I could have the buffers always leave a space open for the \0? but this is kind of an edge case?
    cmp R5, R6 ;;position to size of buffer
    beq getstringResizeEnd

    b getstringEnd

getstringResizeEnd
    add R0, R6, #1
    bl malloc
    mov R7, R0

    mov R0, R4;;old buff
    mov R1, R7;;new buff
    mov R2, R5;;bytes2write
    bl memcpy

    mov R0, R4
    bl free
    mov R4, R7

    add R6, R6, #1 ;;not needed

getstringEnd
    mov R0, #0
    strb R0, [R4, R5]

    mov R0, R4

    pop {R14, R4-R10}
    mov R15, R14

tolower
;;INP in R0 is a character
;;OUT in R0 is the character.lower()
    orr R0, R0, #32
    mov R15, R14

setupGrid
;;INP --
;;RET --
;;The values addresses of the grids will now be set, can still be 0
;; ask for generation mode
;;      |-If random ask for seed
;;      |   `-For generation roll the seed to create a pseudorandom value for each `pixel`
;;      `-If draw then get them to draw the grid one `pixel` at a time
    push {R14, R4-R10}

    ;;generate the main grid
    ldrb R6, width
    ldrb R7, height

    mul R0, R6, R7 ;;width * height = num of bytes to malloc

    mov R5, R0
    bl malloc
    mov R4, R0
    str R4, gridA

    mov R0, R5
    bl malloc
    str R0, gridB

    cmp R5, #0
    beq setupGridFail
    cmp R4, #0
    beq setupGridFail

    ;;R4 holds the gridA addr
    ;;R6 holds the width
    ;;R7 holds the height

    adrl R0, askgenoption
    swi 3
setupGridAsk
    swi 1
    orr R0, R0, #32

    mov R1, R0
    bl newline

    cmp R1, #'d'
    beq setupdrawing

    cmp R1, #'r'
    beq setuprandom

    adrl R0, setupGrdFailmsg
    swi 3
    b setupGridAsk

setupdrawing
    mov R9, #0
    b setupstart

setuprandom
    mov R0, #0
    mov R1, #4
    mov R2, #1
    bl getstring

    mov R8, R0

    bl newline

    mov R9, #1

setupstart
;;This is probably not a good way to do it as there is more branching in the middle of a loop that is executed alot
;;I'm doing it this way `not because it is easy, but because I though it would be easy`
;;Reduces the need for writing another loop :)
;;R9 holds the mode (1 for random, 0 for draw)
;;R8 will hold the seed for random
;;for row from 0 to height - 1
;;  for col from 0 to width - 1
;;      if (random)
;;          grid[row][col] = ((seed rol 1) || row) && 1
;;      else
;;          grid[row][col] = input() == 1
    mov R5, #0 ;; row
setuprowloop
    cmp R5, R7
    beq setuprowlend

    mov R10, #0 ;;col
setupcolloop
    cmp R10, R6
    beq setupcollend

    cmp R9, #1
    beq dorandom
    b dodraw

;;dorandom and dodraw will get their value for this position and then place it in R2
;;R3 is free at this point
dorandom
    ;;seed in R8
    mov R8, R8, ror #1
    and R3, R10, R5
    eor R8, R8, R3
    and R2, R8, #1
    b setupcollcont
dodraw
    ;;get input, validate 1 or 0
    ;;if invalid print error loop back
    ;;-_- I've just realised I want to print the grid each time as well R0-R3 are scratch
    swi 1

    cmp R0, #'1'
    beq dodrawsucc
    cmp R0, #'0'
    beq dodrawsucc

    adrl R0, drawfailmsg
    swi 3

    b dodraw

dodrawsucc
    sub R2, R0, #48 ;;could be xor?

setupcollcont
    ;;place the value in R2 into the grid[row][col]
    ;;row * width + col

    mla R3, R5, R6, R10 ;;R3 = row * width + col
    strb R2, [R4, R3] ;;grid offset by R3

    cmp R9, #0
    moveq R0, R4
    bleq drawgrid ;;print the new state of the grid if this is drawing mode

    add R10, R10, #1
    b setupcolloop
setupcollend
    add R5, R5, #1
    b setuprowloop
setuprowlend
    ;;grid has been setup

setupGridFail
setupGridEnd
    pop {R14, R4-R10}
    mov R15, R14


;;[[TODO]] the heap may not be blank (when heapclean is removed) and so need to 0 the mem. Maybe add option to malloc or add calloc (not the same)
drawgrid
;;INP in R0 is the grid address to draw

;;for row from 0 to height - 1
;;  for col from 0 to width - 1
;;      print('X' if grid[row][col] else '_')
;;  print(newline)
;;print(newline)
    push {R4-R8}

    mov R6, R0

    ldrb R4, width
    ldrb R5, height

    mov R2, #0 ;;row
drawgridrowloop
    cmp R2, R5
    beq drawgridrowlend

    mov R1, #0 ;;col
drawgridcolloop
    cmp R1, R4
    beq drawgridcollend

    mla R3, R2, R4, R1 ;;R3 = row * width + col
    ldrb R3, [R6, R3]

    cmp R3, #1
    moveq R0, #'X'
    movne R0, #'-'

    swi 0

    mov R0, #' '
    swi 0

    add R1, R1, #1
    b drawgridcolloop

drawgridcollend
    mov R1, #0
    add R2, R2, #1
    mov R0, #10
    swi 0
    b drawgridrowloop

drawgridrowlend
    mov R0, #10
    swi 0
drawgridend
    pop {R4-R8}
    mov R15, R14


setupOptions
;;INP in R0 is 1 if should ask for dims 0 for skip
    push {R14, R4}
    mov R4, R0

    adrl R0, askdefaults ;;ask q
    swi 3
    swi 1   ;;get character answer
    swi 0
    cmp R0, #'Y'
    ldr R0, =nlchar
    swi 0

    bne setupCustom

    adrl R0, usingDefault
    swi 3

    mov R0, #0
    strb R0, erase_b
    strb R0, slow_b
    mov R0, #18
    strb R0, width
    strb R0, height

    pop {R14, R4}
    mov R15, R14 ;;RET

setupCustom
;;ask for erase, slow, step, and conditionally dims

;;ask step
;;ask erase
;;if (!step)
;;  if erase
;;      print(recommend slow)
;;  ask slow

    mov R1, #1

    adrl R0, askstep
    swi 3
    swi 1
    swi 0 
    cmp R0, #'Y' 
    ldr R0, =nlchar
    swi 0
    movne R1, #0
    strb R1, step_b

    mov R1, #1

    adrl R0, askerase
    swi 3
    swi 1
    swi 0
    cmp R0, #'Y'
    ldr R0, =nlchar
    swi 0
    movne R1, #0
    strb R1, erase_b

    ldrb R0, step_b
    cmp R0, #1
    beq setupCustomskipslow

    cmp R1, #1 ;;if erase is on
    adrl R0, warneraseslow
    swieq 3

    mov R1, #1
 
    adrl R0, askslow
    swi 3
    swi 1
    swi 0 
    cmp R0, #'Y' 
    ldr R0, =nlchar
    swi 0
    movne R1, #0
    strb R1, slow_b

    b setupCustomDimsCheck

setupCustomskipslow
    mov R0, #0
    strb R0, slow_b

setupCustomDimsCheck
    cmp R4, #0
    beq customend

    adrl R0, askwid
    swi 3
    
getwid
    ldr R0, =enter
    mov R1, #2
    mov R2, #1
    bl getstring

    bl strtoi

    mov R1, R0

    bl newline

    cmp R1, #30
    bgt getwidFail
    cmp R1, #0
    ble getwidFail

    strb R1, width

    b getheisetup

getwidFail
    adrl R0, getwidfailmsg
    swi 3

    b getwid

getheisetup
    adrl R0, askhei
    swi 3

gethei
    ldr R0, =enter
    mov R1, #2
    mov R2, #1
    bl getstring

    bl strtoi

    mov R1, R0

    bl newline

    cmp R1, #30
    bgt getheiFail
    cmp R1, #0
    ble getheiFail

    strb R1, height

    b customend

getheiFail
    adrl R0, getheifailmsg
    swi 3

    b gethei

customend
    pop {R14, R4}
    mov R15, R14 ;;RET


updategrid
;;INP in R0 is the active grid
;;INP in R1 is the passive grid
;;passive grid is the one being updated based on the value in the activeGrid
;;RET --
;;for row from 0 to height - 1
;;  for col from 0 to width - 1
;;      int n = countNeighbours(activeGrid, row, col)
;;      int s = activeGrid[row][col]
;;      
;;      if (s == alive)
;;          passiveGrid[row][col] = n == 3 or n == 2
;;      else
;;          passiveGrid[row][col] = n == 3

;;  R4 holds the row
;;  R5 holds the col
;;  R6 holds the width
;;  R7 holds the height
;;  R8 holds the active grid
;;  R9 holds the passive grid

    push {R14, R4-R10}

    ldrb R6, width
    ldrb R7, height

    mov R8, R0
    mov R9, R1

    mov R4, #0 ;;row
updategridrowloop
    cmp R4, R7
    beq updategridrowlend

    mov R5, #0 ;;col
updategridcolloop
    cmp R5, R6
    beq updategridccollend

    mov R0, R8
    mov R1, R4
    mov R2, R5
    bl countneighbours

    mla R1, R4, R6, R5 ;;R1 = row * width + col
    ldrb R2, [R8, R1] ;;grid[R1]
    ;;R0 holds the n count
    cmp R2, #0
    beq updatedead

updatealive
    mov R3, #0
    cmp R0, #3
    moveq R3, #1
    cmp R0, #2
    moveq R3, #1
    strb R3, [R9, R1]
    b updatelcont

updatedead
    mov R3, #1
    cmp R0, #3
    movne R3, #0
    strb R3, [R9, R1]

updatelcont
    add R5, R5, #1
    b updategridcolloop

updategridccollend
    mov R5, #0
    add R4, R4, #1
    b updategridrowloop

updategridrowlend
updategridend
    pop {R14, R4-R10}
    mov R15, R14


countneighbours
;;INP in R0 is the activeGrid
;;INP in R1 is the row
;;INP in R2 is the col
;;OUT in R0 is the number of neighbours

;;offsets = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]]
;;tot = 0
;;for offset in offsets
;;  if (isinrange(row + offset[0], col + offset[1]))
;;      tot += grid[row + offset[0]][col + offset[1]]
;;return tot
    push {R14, R4-R11} ;;I used the fp before I knew it wasn't a general purpose one, its fine in this context anyway

    adrl R4, offsets ;;holds the offset

    mov R7, R0
    mov R8, R1
    mov R9, R2
    mov R10, #0 ;;R10 holds the total
    ldrb R11, width;;R11 holds the width of the grid

    mov R3, #0

countneighboursloop
    cmp R3, #8 ;;change this ccheck to be for R4
    beq countneighbourslend

    ldr R5, [R4], #4
    ldr R6, [R4], #4

    add R0, R8, R5
    add R1, R9, R6

    add R3, R3, #1

    push {R3} ;;I should probably be using a local var on the stack, but I don't yet know how to setup a stack frame properly
    bl isinrange
    pop {R3}

    cmp R0, #0
    beq countneighboursskipadd

    add R0, R8, R5 ;;new row
    add R1, R9, R6 ;;new col ;;can assume that R0, R1 haven't changed as isinrange doesn't edit them, but I'm going to for now

    mla R0, R0, R11, R1 ;;find offset
    ldrb R0, [R7, R0]
    add R10, R10, R0 ;;tot += grid[newrow][newcol]

countneighboursskipadd
    b countneighboursloop

countneighbourslend
countneighboursend
    mov R0, R10
    pop {R14, R4-R11}
    mov R15, R14


isinrange
;;INP in R0 is the row
;;INP in R1 is the col
;;Uses defined width and height
;;RET in R0 is 1 if is in range else 0
    mov R2, #1 ;;is valid unless...

    cmp R0, #0
    blt isinrangefail

    cmp R1, #0
    blt isinrangefail

    ldrb R3, width
    cmp R1, R3
    bge isinrangefail

    ldrb R3, height
    cmp R0, R3
    bge isinrangefail

    mov R0, #1
    b isinrangeend

isinrangefail
    mov R0, #0

isinrangeend
    mov R15, R14


;; The heap will be a linked list of free blocks - unlike the Comodo version which stores both free & taken blocks 
;; This is an idea I'm stealing from the C programming book
;; Crate structure
;;  |-ptr to next crate (1 word)
;;  |-ptr to prev crate (1 word)
;;  `-Size (bytes)      (1 word)
;; 

;;  Traversal of the heap
;;  Unlink in my Comodo implimentation the heap is not a linked list of all Crates (free or not)
;;  That made traversing the heap for debugging purposes very easy, in this case taken crates do not point to the next
;;  Instead could start at head and then just go to addr + sizeof(Crate) + size. This should take us to the next crate, free or not
;;  
setupHeap
;;NO INP
;;NO OUT
    ;;we have the heapstart
    ;;the end of the heap will be 0x100000 (it will overlap with the stack :) )
    ldr R0, heaphead ;;stores the mem addr of the start of the heap
    ldr R1, =max_addr ;;stores the end of the heap
    ldr R2, =stack_size
    sub R1, R1, R2

    sub R1, R1, R0  ;;HEAPEND - HEAPSTART = TOTAL STORAGE (bytes)
    sub R1, R1, #12 ;;SIZE -= SIZEOF(CRATE) (12 bytes)
    str R1, [R0, #8] ;;set the size of the crate
    mov R1, #0
    str R1, [R0, #4] ;;set the prev ptr
    str R1, [R0, #0] ;;set the next ptr

    mov R15, R14

;; The heap is a linked list of free Crates and so find the header and then go though until one satifies the size requirement
;;  end if next is 0
;;  once found either take over the crate or split it into two new crates
;;  align the bytes amount to 8 byte boundry
malloc
;;INP into R0 bytes to allocate
;;OUT into R0 the ptr to the memory or 0 for no memory allocated
    ;;step 1 align the bytes
    ;;1001010 & 0111 = 0000010 ;2
    ;;if 0 goto alignend
    ;;1001010 + (8 - 2)
    push {R4}

    and R1, R0, #0b0111
    cmp R1, #0
    beq mallignend
    mov R3, #0b1000
    sub R2, R3, R1
    add R0, R0, R2

mallignend
    ldr R1, heaphead ;;stores a ptr to the first block
    
checkcrate
    ldr R2, [R1, #8] ;;Size of the crate
    cmp R0, R2 ;;bytes needed - bytes in crate
    ble foundcrate
    ldr R2, [R1, #0] ;;get the next ptr
    cmp R2, #0
    beq nocrates
    mov R1, R2 ;;swap the current crate with the next crate
    b checkcrate
nocrates
    mov R0, #0
    b mallocEnd

foundcrate
    ;;Once a crate that we can use has been found we need to either split the crate or use the crate
    ;;We should use the whole crate only when its size < bytesneeded + CrateHeader + 8
    ;;This would give the edge case crate 8 bytes
    
    ;;R1 holds the found crate ptr
    ;;R0 is the bytes requested and aligned
    add R2, R0, #20 ;;A crate header is 12 bytes + the extra 8 bytes minimum
    ldr R3, [R1, #8]
    cmp R3, R2
    blt usecrate
splitcrate
    ;;In this case we have a large crate that should be split up.
    ;;ATM the crate will just be split up to where the requested memory is at the end of the free Crate.

    ldr R3, [R1, #8] ;;The size of the toSplit Crate
    sub R3, R3, R0 ;; size - bytesRequested
    sub R3, R3, #12 ;; size - bytesRequested - sizeof(Crate)
    str R3, [R1, #8] ;;toSplit->size = newSize

    add R3, R3, R1 ;; newSize + toSplit.addr
    add R4, R3, #12 ;; newSize + toSplit.addr + sizeof(Crate) = position of new Crate

    ;;Setup the header for the newCrate
    mov R2, #0
    str R2, [R4, #0] ;;next = 0
    str R2, [R4, #4] ;;prev = 0
    str R0, [R4, #8] ;;size = requested and aligned

    ;;MAYBE: can the crates that are taken have a smaller header than those that are free. Taken crates need not store the next, prev free nodes
    ;;This may complicate things as size would need to be moved around and the size from taken to free would be different. 

    add R4, R4, #12

    mov R0, R4

    b mallocEnd

usecrate
    ;; Simplest option as we can just remove it from the list
    ;; c1 <-> c2 <-> c3 ==> c1 <-> c3
    ldr R2, [R1, #0] ;;next ptr
    ldr R3, [R1, #4] ;;prev ptr
    str R3, [R2, #4] ;;Store c1 into c3's previous
    str R2, [R3, #0] ;;Store c3 into c1's next

    mov R0, R1 ;;move the found crate's address into the return register ;;The crate header is no longer needed

mallocEnd
    pop {R4}
    mov R15, R14

free
;;INP in R0 is the mem addr of the data to be freed
;;OUT in R0 is the success code - 0 for mem freed, ¬0 for error ;;probably won't be currently used `=(- -)=' 
    ;;In order to free memory we need to add it back to the linked list
    ;;Following K&R's version the linked list will be ordered by address this will make finding consecutive memory locations that should be combined easier

    ;;The inputted address of the crate is the address given in malloc and so the start of the crate is that addr - sizeof(Crate) (#12)

    ;;heapHead = first Crate
    ;;current = heapHead
    ;;while (toFree.addr > current.addr)
    ;;  current = current.next
    ;;
    ;;//Add the toFree Crate inbetween the current and its previous i.e.  A<->B<->C, toFree = D (addr < C, addr > B) ==> A<->B<->D<->C
    ;;current->prev->next = toFree
    ;;toFree->prev = current.prev
    ;;current->prev = toFree
    ;;toFree->next = current

    ;; Crate structure
    ;;  |-ptr to next crate (1 word)
    ;;  |-ptr to prev crate (1 word)
    ;;  `-Size (bytes)      (1 word)

    push {R4-R8}

    ldr R1, heaphead ;;R1 will hold the current
    sub R0, R0, #12 ;;subtract sizeof(Crate) to get header pointer
freeloop
    ldr R2, [R1, #0] ;;load the ptr to the next
    cmp R2, R0 ;;compare the address of the toFree to the address of current->next

    bge freelend ;;current->next.addr >= toFree.addr

    cmp R2, #0 ;;If there are no more Crates to the right then this could be a new Crate at the end or |F|T| it should merge left 
    beq freelendEnd

    mov R1, R2 ;;current = current.next

    b freeloop

freelend
    ;; R1 holds the current (left)
    ;; R2 holds the c->next (right)
    ldr R2, [R1, #0]

    ;;Setup the ptrs for the crates this will help later on   left<->toFree<->right ;;left,right can be 0
    ;;We're just adding the new crate to the linked list
    ;;current->next->prev = toFree
    ;;toFree->next = current->next
    ;;current->next = toFree
    ;;toFree->prev = current

    ldr R3, [R1, #0] ;;holds current->next
    cmp R3, #0
    strne R0, [R3, #4] ;;current->next->prev = toFree
    str R3, [R0, #0] ;;toFree->next = current->next
    str R0, [R1, #0] ;;current->next = toFree
    str R1, [R0, #4] ;;toFree->prev = current

    b freeMergeCheck

freelendEnd
;;If there are no more Crates to the right then this could be a new Crate at the end or |F|T| it should merge left 
;;Found a crate (current) that is to the left of the crate as we ran out of ->next ptrs
;;Need to set current->next = toFree
;;            toFree->prev = current
    str R1, [R0, #4] ;;toFree->prev = current
    str R0, [R1, #0] ;;current->next = toFree

freeMergeCheck
    ;;We have a ptr to current. This should be the closest Crate to the left of toFree
    ;;We also have the next Crate (null or not) which is to the right of toFree
    ;;Both of these crates MAY need to be merged but could also have taken crates in between
    ;;First is to check if the crates are adjacent
    ;;  If they are NOT then create a newCrate
    ;;  If they are     then merge both
    ;;  If only one     then merge either left or right

    ;;R1 will be left
    ;;R2 will be right

    cmp R1, #0
    moveq R1, R0 ;;If there is no left crate then left=toFree
    cmp R2, #0
    moveq R2, R0 ;;If there is no right crate (more likely) then right=toFree

verifyLeft
    ;;Check if the left is adjacent
    ;;It will be if (left.addr + sizeof(Crate) + left.size == toFree.addr)

    ldr R3, [R1, #8]
    add R3, R3, #12 ;;12 is sizeof(Crate) + toFree.size
    add R3, R3, R1 ;;left.addr + left->size ??

    cmp R3, R0
    movne R1, R0

verifyRight
    ;;Going from toFree to Right
    ldr R3, [R0, #8] ;;get size of toFree
    add R3, R3, #12 ;;12 is sizeof(Crate) + toFree.size
    add R3, R3, R0 ;; + toFree.addr

    cmp R3, R2
    movne R2, R0

merge
    ;;Merge the two Crates given in R1 and R2
    ;;left can be (left) or (toFree)
    ;;right can be (right) or (toFree)
    ;;If left == right: don't merge; create new Crate
    ;;If left != right: then add to left's size

    cmp R1, R2
    beq mergeNew

    ;;The new size is right.addr - left.addr + right->size    from right.addr - left.addr - sizeof(Crate) + sizeof(Crate) + right->size
    ;;                                                               |left      |right
    ;;                                                               |<12>|size||<12>|size|
    ;;
    ;;                                                               |left      
    ;;                                                               |<12>|size           |
    ;;
    ;;I'm doing it this way as the left and right may not be contiguous i.e. if toFree has a free crate on either side

    sub R3, R2, R1
    ldr R4, [R2, #8]
    add R3, R3, R4
    str R3, [R1, #8]

    ;;Time to switch some ptrs
    ;;Current state left.prev<->left<->right<->right.next (with left or right = toFree) or left.prev<->left<->toFree<->right<->right.next
    ;;New state would be left.prev<->left<->right.next (with left or right = toFree) or left.prev<->left<->right.next
    ;;Both cases end the same, so get right.next. These could be 0 but it doesn't matter
    ;;Next need to change the prev and next ptrs for adjacent Crates
    ;;i.e. right->next->prev = left

    ldr R4, [R2, #0] ;;right->next
    cmp R4, R1
    strne R4, [R1, #0] ;;left->next = right->next
    movne R4, #0
    strne R4, [R1, #0]

    cmp R4, #0
    strne R1, [R4, #4] ;;right->next->prev = left

mergeNew
    ;;The crate has already been setup with its ptrs and had its size as well so don't need to do anything

freeEnd
    pop {R4-R8}
    mov R15, R14

align
;;Integer defs
heaphead        defw 0x10000 ;;default start changed to addr of heapstart
offsets         defw -1,-1,-1,0,-1,1,0,-1,0,1,1,-1,1,0,1,1 ;;[[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]]

;;Grid addresses
gridA           defw 0
gridB           defw 0

;;options
erase_b         defb 0
slow_b          defb 0
step_b          defb 0
width           defb 18
height          defb 18

;;String defs
welcomemsg      defb "-----------Welcome to JCGOL in ARM32-----------\n", 0
welcome2msg     defb "To start a new board press n\nTo load a saved board press l\nTo quit press q\n", 0
mainchoicefail  defb "Invalid choice please enter 'n' for new board or 'l' for load a board or 'q' to close. Not cases sensative\n", 0
helpmsg         defb "Slow mode will create a pause between each grid print to make it more readable - can't use with step mode\nErase mode will erase the previous board before printing the next - [is 2x slower]\n", 0
help2msg        defb "Single step mode will prompt for input each time a grid is drawn, you can (s)ave the current state or (q)uit to menu", 0
askdefaults     defb "Would you like to use the default settings? Y/n: ", 0
askerase        defb "Enable erase mode? Y/n: ", 0
askslow         defb "Enable slow mode? Y/n: ", 0
askstep         defb "Enable step mode? Y/n: ", 0
stepslowwarning defb "Cannot have slow and step mode active at the same time, disabling slow mode\n", 0
savedchoice     defb "Return to menu? (n for continue sim) Y/n: ", 0
askname         defb "Please enter a name for the grid: ", 0
warneraseslow   defb "Erase mode is active it is recommended to also use slow mode\n", 0
askwid          defb "Please enter a width (1-30): ", 0
askhei          defb "Please enter a height (1-30): ", 0
getwidfailmsg   defb "Invalid width please enter a value between 1-30 inclusive: ", 0
getheifailmsg   defb "Invalid height please enter a value between 1-30 inclusive: ", 0
usingDefault    defb "Using default values: dims=(18, 18) slowMode=Off eraseMode=Off stepMode=Off", nlchar, 0
askgenoption    defb "Choose between (R)andom generation or (D)rawing the grid", 0
setupGrdFailmsg defb "Invalid choice, use `R` for random generation and `d` for drawing the grid. Not case sensative: ", 0
askseed         defb "Enter 4 characters to be used as the seed: ", 0
drawfailmsg     defb "Invalid input please enter 1 or 0: ", nlchar, 0
gridfailmsg     defb "Grid was not properly initialised, consider smaller dims", nlchar, 0


align
heapstart       defw 0 ;;points to the end of the data this is where the heap can then begin