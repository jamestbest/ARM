;;  This is my second rendition of JCGOL in ARM assembly for Komodo
;;  
;;  This will attempt to follow the ARM 32bit calling convention 
;;      R0-3 are argument registers, scratch
;;      R4-11 are local variable registers and should be saved before use in a function
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
;;      |-slow mode
;;      `-erase mode
;;  - ask for generation mode
;;      |-If random ask for seed
;;      `-If draw then get them to draw the grid
;;  - Allocate two grids, the pointers to which will swap after a frame
;;  - loop
;;      |-count neighbours
;;      |-update inactive grid
;;      |-swap grids
;;      |-draw active grid
;;      `-goto loop

max_addr EQU 0x100000
nlchar EQU 10

_start
    ;;prepare the stack
    ldr R13, =max_addr 
    ;;setup heap
    push {R14}

    adr R0, heapstart
    str R0, heaphead
    bl setupHeap

    mov R0, #14
    bl malloc

    bl main

    pop {R14}
    swi 2
    mov r15, #0

main
    bl setupOptions

newline
    ldr R0, =nlchar
    swi 0

    mov R15, R14

getstring
;;INP in R0 the terminator character
;;INP in R1 the max number of characters or -1 for no max
;;RET in R0 a ptr to the memory address
;;
;;Dynamically allocate memory to support large string

setupOptions
    adrl R0, askdefaults ;;ask q
    swi 3
    swi 1   ;;get character answer
    swi 0
    cmp R0, #'Y'
    ldr R0, =nlchar
    swi 0

    bne setupCustom

    mov R15, R14 ;;RET

setupCustom
;;ask for erase, slow, dims
    mov R1, #1

    adrl R0, askerase
    swi 3
    swi 1
    swi 0
    cmp R0, #'Y'
    ldr R0, =nlchar
    swi 0
    streqb R1, erase_b
 
    adrl R0, askslow
    swi 3
    swi 1
    swi 0 
    cmp R0, #'Y' 
    ldr R0, =nlchar
    swi 0
    streqb R1, slow_b

;; The heap will be a linked list of free blocks - unlike the Comodo version which stores both free & taken blocks 
;; This is an idea I'm stealing from the C programming book
;; Crate structure
;;  |-ptr to next crate (1 word)
;;  |-ptr to prev crate (1 word)
;;  `-Size (bytes)      (1 word)
;; 
setupHeap
;;NO INP
;;NO OUT
    ;;we have the heapstart
    ;;the end of the heap will be 0x100000 (it will overlap with the stack :) )
    ldr R0, heaphead ;;stores the mem addr of the start of the heap
    ldr R1, =max_addr ;;stores the end of the heap

    sub R1, R1, R0  ;;HEAPEND - HEAPSTART = TOTAL STORAGE (bytes)
    sub R1, R1, #12 ;;SIZE -= SIZEOF(CRATE) (12 bytes)
    str R1, [R0, #8] ;;set the size of the crate
    mov R1, #0
    str R1, [R0, #4] ;;set the prev ptr
    str R1, [R0, #0] ;;set the next ptr

    mov r15, r14

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
    and R1, R0, #0b0111
    cmp R1, #0
    bleq mallignend
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
    mov R15, R14 ;;RET

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
    ;;Change the current crates size and give the mem addr for the end of the crates block?
    ldr R2, [R1, #8] ;;get size
    sub R2, R2, R0
    str R2, [R1, #8] ;;store back size - bytesRequested
    mov R0, R1
    add R0, R0, #12         ;; address of crate + sizeof(Crate) + size
    ldr R3, [R1, #8]        ;;
    add R0, R0, R3          ;;

    mov R15, R14 ;;RET

usecrate
    ;; Simplest option as we can just remove it from the list
    ;; c1 <-> c2 <-> c3 ==> c1 <-> c3
    ldr R2, [R1, #0] ;;next ptr
    ldr R3, [R1, #4] ;;prev ptr
    str R3, [R2, #4] ;;Store c1 into c3's previous
    str R2, [R3, #0] ;;Store c3 into c1's next

    mov R0, R1 ;;move the found crate's address into the return register ;;The crate header is no longer needed
    mov R15, r14 ;;RET


;;String defs
askdefaults defb "Would you like to use the default settings? Y/n: ", 0
askerase    defb "Enable erase mode? Y/n: ", 0
askslow     defb "Enable slow mode? Y/n: ", 0
askwid      defb "Please enter a width (1-30): ", 0
askhei      defb "Please enter a height (1-30): ", 0

align
;;Integer defs
heaphead defw 0x10000 ;;default start

;;options
erase_b defb 0
slow_b  defb 0
width   defb 18
height  defb 18

align
heapstart ;;points to the end of the data this is where the heap can then begin
