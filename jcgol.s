;;This is an attempt at JCGOL in ARM assembly for the Komodo emulator
;;
;; Two buffers with the map switch between them and use the other to count the neighbours
;; 
;;[!!] I am not going to use the ARM 32 calling convention - [NOTE] THIS WAS A MISTAKE

;;[NOTE] non-leaf functions have to save the stack pointer as it is not pushed to the stack

w EQU 20
h EQU 20
b start
temp defb 14332 
align
start
    mov r13, #0x10000 ;;WHAT ARE THE RULES?!?!?! Is some memory at the top ROM

    mov r0, #0
    strb r0, slowmode

    adrl r10, grida ;;R10 Will store the pointer to the active grid
    adrl r11, gridb ;;R11 will store the pointer to the grid to update ;;THESE (r10,r11) ARE NOT USED ELSEWHERE

    ;; bl clearinput

    bl gengrid

    bl drawgrid

loop
    bl updategrid

    ldrb r0, slowmode
    cmp r0, #1
    bne loopcont

    bl slow

loopcont
    mov r9, r10
    mov r10, r11
    mov r11, r9 ;;swap grids
    bl drawgrid
    b loop
    swi 2

slow
    mov r1, #255
slowouterloop
    cmp r1, #0
    beq slowlend 
    mov r2, #255
slinnerloop
    cmp r2, #0
    beq slowinnerlend
    sub r2, r2, #1
    b slinnerloop
slowinnerlend
    mov r2, #255
    sub r1, r1, #1
    b slowouterloop
slowlend
    mov r15, r14

clearinput
    mov r1, #255
ciloop
    cmp r1, #0
    beq ciend
    swi 1
    cmp r0, #0x58
    beq ciend
    sub r1, r1, #1
    b ciloop
ciend
    mov r15, r14

updategrid
;;go through the current grid and count the neighbours for that position
;;set alive/dead in the OTHER grid
;;swap the active grid
    push {r14}
    mov r0, #0 ;;row
ugouterloop
    ldrb r5, height
    cmp r0, r5
    bge updategridend
    mov r1, #0 ;;col
uginnerloop
    ldrb r5, width
    cmp r1, r5
    bge uginnerloopend
    push {r0, r1}
    bl getneighbourcount
    mov r2, r0 ;;n count
    pop {r0, r1}
    push {r0, r1, r2} ;;this is bad; I am tired
    bl gett
    mov r3, r0 ;;value grid[row][col]
    pop {r0, r1, r2}

    cmp r3, #0
    mov r4, #0 ;;r4 holds the new value
    bne updatealive
updatedead
    cmp r2, #3
    moveq r4, #1
    b endupdate
updatealive
    cmp r2, #2
    moveq r4, #1
    cmp r2, #3
    moveq r4, #1
endupdate
    ;;calculate new offset
    ;;r11 holds the newgrid to update
    mov r2, r4
    mov r9, r11
    bl sett

    add r1, r1, #1
    b uginnerloop

uginnerloopend
    add r0, r0, #1
    mov r1, #0
    b ugouterloop

updategridend
    pop {r14}
    mov r15, r14
    


getneighbourcount
;;INP row in R0, col in R1
;;8 neighbours
;;[x-1,y-1] [x  , y-1] [x+1,y-1]
;;[x-1,y  ] [x  , y  ] [x+1,y  ]
;;[x-1,y+1] [x  , y+1] [x+1,y+1]
;;OUT no. neighbours in R0
    mov r5, r0 ;;row
    mov r6, r1 ;;col
    mov r7, #0 ;;count

    push {r14} ;;save return

    adrl r8, offsets
    mov r9, #0
gncloop ;;go through every offset
    cmp r9, #16
    beq gncend
    mov r0, r5
    ldrsb r2, [r8, r9]
    add r0, r0, r2 ;;offsets
    mov r1, r6
    add r9, r9, #1
    ldrsb r3, [r8, r9]
    add r9, r9, #1
    add r1, r1, r3
    push {r0, r1}
    bl isvalidindex
    cmp r0, #0
    pop {r0, r1}
    beq gncloop
    bl gett
    cmp r0, #1
    addeq r7, r7, #1
    b gncloop

gncend
    mov r0, r7
    pop {r14}
    mov r15, r14

isvalidindex
;;INP   r0 = row
;;      r1 = col
;;returns 1 in R0 if valid else 0
    mov r2, #1 ;;isvalid
    cmp r0, #0
    movlt r2, #0
    ldrb r3, height
    cmp r0, r3
    movge r2, #0
    cmp r1, #0
    movlt r2, #0
    ldrb r3, width 
    cmp r1, r3
    movge r2, #0
    mov r0, r2
    mov r15, r14


init
;;initialise the grids settings all values to 0
;;for i from 0 to w * h - 1:
;;  grid offset i = 0
    mov r6, #0 ;;i = 0
    mov r7, #0

    ldrb r8, width
    ldrb r9, height
    mul r8, r8, r9
    mov r9, r10 ;;mov into r9 the active grids addr
initloop
    cmp r6, r8
    beq initend
    strb r7, [r9, r6]
    add r6, r6, #1
    b initloop
initend
    mov r15, r14;;ret

getseed
;;get 4 characters of input from the user
;;store them in the seed
    adrl r0, getseedmsg
    swi 3

    adrl r1, seed
    swi 1
    strb r0, [r1, #0]
    swi 1
    strb r0, [r1, #1]
    swi 1
    strb r0, [r1, #2]
    swi 1
    strb r0, [r1, #2]

    mov r15, r14

gengrid
;;two options
;;1. you can give it a keyword that will be used to generate a screen
;;2. you can type 1 and 0 or maybe anything/space to set each pixel
    push {r14}

    bl getdims

    adrl r0, slowmodemsg
    swi 3

    mov r0, #10
    swi 0

    swi 1
    cmp r0, #89
    mov r1, #1
    streqb r1, slowmode

    bl init

    adrl r0, getchoicemsg
    swi 3

    swi 1
    cmp r0, #115
    beq gengridrandom

    cmp r0, #100
    beq getdrawing

    adrl r0, failmsg
    swi 3
ggend
    pop {r14}
    mov r15, r14

getdims
    push {r14}
    adrl r0, getwidthmsg
    swi 3

    adrl r0, widthinp
    mov r1, #2
    bl getinpntbt

    adrl r0, widthinp
    bl str2int
    ;;get input()
    ;;unfortunately we must convert this input into a decimal value from the string

    swi 4
    strb r0, width

    mov r0, #10
    swi 0

    adrl r0, getheightmsg
    swi 3

    adrl r0, heightinp
    mov r1, #2
    bl getinpntbt

    adrl r0, heightinp
    bl str2int
    ;;get input()
    ;;unfortunately we must convert this input into a decimal value from the string

    swi 4
    strb r0, height

    mov r0, #10
    swi 0

    pop {r14}
    mov r15, r14

getinpntbt ;;get input null terminated or bang terminated
;;in R0 have a ptr to the mem adr to store to
;;in R1 have the max number of characters to read in
    mov r2, #0 ;;i
    mov r3, r0 ;;r3 holds the mem addr
gintloop
    cmp r2, r1
    bge gintend

    swi 1
    cmp r0, #33

    beq gintend

    strb r0, [r3, r2]
    add r2, r2, #1

    b gintloop
    
gintend
    mov r0, #0
    strb r0, [r3, r2]
    mov r15, r14

getdrawing
;;for i from 0 to rows - 1
;;  for j from 0 to cols - 1
;;      getinput()
;;      write to location
;;      print grid
    adrl r0, getdrawingmsg
    swi 3

    swi 1

    mov r3, #0 ;;i
    mov r1, #0
gdouterloop
    ldrb r2, width
    cmp r3, r2
    beq gdend

gdinnerloop
    ldrb r2, height
    cmp r1, r2
    beq gdinnerlend
gdinp
    swi 1 ;;get input
    cmp r0, #48 ;;0
    beq gdwrite
    cmp r0, #49 ;;1
    beq gdwrite

    adrl r0, gderrormsg
    swi 3
    b gdinp

gdwrite
    sub r0, r0, #48
    mov r2, r0 ;;store the value in r2 i.e. 1 or 0
    mov r0, r3
    mov r9, r10
    push {r1, r3}
    bl sett

    bl drawgrid
    pop {r1, r3}

    add r1, r1, #1
    b gdinnerloop

gdinnerlend
    mov r1, #0
    add r3, r3, #1
    b gdouterloop

gdend
    adrl r0, drawingcmplmsg
    swi 3
    swi 1
    b ggend

gengridrandom
;;if it is to be random then prompt for a 4 character seed
    bl getseed

    adrl r9, seed
    ldr r6, [r9] ;;r6 holds the random seed
    ;;for i from 0 to w * h - 1
    mov r7, #0 ;;i
ggrloop
    push {r5, r6}
    ldrb r5, width
    ldrb r6, height
    mul r5, r5, r6
    cmp r7, r5
    pop {r5, r6}
    beq ggrlend
    and r8, r6, #1
    add r7, r7, #1
    mov r9, r10;;mov active grid into r9
    strb r8, [r9, r7]
    mov	r6, r6, ror #1 ;;funky
    eor r6, r6, r7 ;;attempt to reduce repetition??
    b ggrloop
ggrlend
    b ggend

gett ;;get is a keyword?
;;just requires the x,y in R0, R1
;;this function is not generic and will just work with this atm

;;[[1,2,3][4,5,6]] width = 3, height = 2
;;position of 6 = [1,2]
;;  1 * width + 2 = 4
    push {r5, r6, r10}
    ldrb r5, width
    mul r6, r0, r5 ;;r6 = width * x
    add r6, r6, r1 ;;r6 = r6 + y
    ;;r6 holds the position in the array as an offset
    mov r2, r10;;move active grid into r2
    ldrb r0, [r2, r6] ;;r0 = [grid + offset]
    pop {r5, r6, r10}
    mov r15, r14;;ret

sett
;;x,y,value in R0, R1, R2 + addr of grid in R9 ;;late edition -_-
    push {r3, r4, r5}
    ldrb r3, width
    mul r4, r0, r3
    add r4, r4, r1

    mov r5, r9
    strb r2, [r5, r4]

    pop {r3, r4, r5}
    mov r15, r14

drawgrid
;;draw each line
;;for row from 0 to h - 1
;;  for col from 0 to w - 1
;;      if value(row,col) == 1:
;;          output 'X'
;;      else:
;;          output '~'

    mov r5, #0 ;;row
outerloop
    ldrb r6, height
    cmp r5, r6
    beq outerlend
    mov r6, #0 ;;col
innerloop
    ldrb r7, width
    cmp r6, r7
    beq innerlend

    mov r0, r5
    mov r1, r6

    push {r14, r5, r6}
    bl gett
    pop {r14, r5, r6}

    cmp r0, #0
    moveq r0, #46
    movne r0, #88

    swi 0

    mov r0, #32
    swi 0
    add r6, r6, #1
    b innerloop
innerlend
    mov r0, #10
    swi 0
    add r5, r5, #1
    b outerloop
outerlend
    ;;draw ----------------------------
    mov r5, #0
    mov r0, #45
endloop
    cmp r5, #22
    beq endlend
    swi 0
    add r5, r5, #1
    b endloop
endlend
    mov r0, #10
    swi 0
    mov r15, r14


str2int
;;this takes in a str buffer adr in R0 which points to a null terminated string to be converted
;;returns the int value in R0, R1 will be 1 if there was an error?
    push {r14, r0}

    bl s2icount
    ;;r0 holds the number of characters
    ;;pop to get adr of string 
    mov r8, r0 ;;r8 holds count
    mov r9, r8
    pop {r0}
    ;;e.g. if count == 3 then first int would be x * (10 ** 2) or x * (10 ** (count -= 1))
    mov r2, #0 ;;offset
    mov r7, #0 ;;r6 holds the total value
s2iloop
    cmp r2, r9 ;;have we done all of the numbers
    beq s2iend
    mov r4, #1 ;;r4 will hold the temp add value
    ldrb r3, [r0, r2]
    ;;r3 holds the value
    sub r3, r3, #48 ;;remove ascii
    mov r5, #1 ;;i for inner loop ;;its 1 to account for count - 1
    cmp r8, #0 ;;if count == 0 then a) something is wrong with my input, and b) see a
    beq s2iinnerlend
s2iinnerloop ;;used to get 10 ** (count - 1)
    cmp r5, r8 ;; cmp i to count
    bge s2iinnerlend
    mov r6, #10
    mul r4, r4, r6
    add r5, r5, #1
    b s2iinnerloop
s2iinnerlend
    ;;we now have 10 ** correctly so * x
    mul r4, r4, r3
    add r7, r7, r4
    add r2, r2, #1
    sub r8, r8, #1
    b s2iloop
s2iend
    pop {r14}
    mov r0, r7
    mov r15, r14

s2icount
;;counts the number of characters stored in a buffer (adr in R0) does NOT include the null terminator
    mov r2, #0 ;;offset
s2icloop
    ldrb r3, [r0, r2] ;;adr + offset
    cmp r3, #0
    beq s2iclend ;;naming is hard

    add r2, r2, #1
    b s2icloop
s2iclend
    mov r0, r2
    mov r15, r14

getchoicemsg defb "Please enter (s) to input a seed or (d) to draw the grid with inputs\n", 0
getseedmsg defb "Please enter 4 characters as the seed\n", 0
getwidthmsg defb "Please enter width (a +ve int between 1-30) (use ! at end if its only 1 digit): ", 0
getheightmsg defb "Please enter height (a +ve int between 1-30) (use ! at end if its only 1 digit): ", 0
getdrawingmsg defb "You must enter a 1 or 0 for each pixel in the grid, after each input the grid will be drawn. Press any key to continue.\n", 0
drawingcmplmsg defb "Drawing complete! press any key to begin simulation\n",0
slowmodemsg defb "Do you want to active slowmode? (Y/n): ", 0

failmsg defb "You dun messed it all up\n", 0
gderrormsg defb "Please enter either 0 or 1\n", 0

ALIGN

widthinp defs 3;;2 bytes for the width input i.e. the characters as max should be `30` + \0 for end
heightinp defs 3;;same for the height

seed defw 0

width defb 10
height defb 10

slowmode defb 0

offsets defb -1,-1,-1,0,1,0,0,1,0,-1,1,1,-1,1,1,-1

;;the grids are 20 * 20 pixels
;;grida defs w * h
;;gridb defs w * h
grida defs 30 * 30 
gridb defs 30 * 30

;;this is the max size that the grids can be under the current I cannot reserve dynamicaly?
