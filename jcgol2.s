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

;;buff = malloc(minBytes)
;;while (input != terminator) 
;;  buff[pos] = input
;;  if (pos > buffSize)
;;      nBuff = malloc(buffSize << 1)
;;      memcpy from buff to nBuff
;;      free buff

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


free
;;INP in R0 is the mem addr of the data to be freed
;;OUT in R0 is the success code - 0 for mem freed, ¬0 for error ;;probably won't be currently used `=(- -)=' 
    ;;In order to free memory we need to add it back to the linked list
    ;;Following K&R's version the linked list will be ordered by address this will make finding consecutive memory locations that should be combined easier

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

    ldr R1, [heapHead] ;;R1 will hold the current
freeloop
    cmp R0, R1 ;;compare the address of the toFree to the address of current
    ble freelend ;;toFree.addr <= current.addr
    ldr R2, [R1, #0] ;;load the ptr to the next

    cmp R2, #0 ;;If we are at the end of the list then it should just be added to the end
    b freeAddEnd

    mov R1, R2 ;;current = current.next

    b freeloop
freelend
    ;;should have the addr of current in R1 this
    ldr R3, [R1, #4] ;; R4 holds current->prev
    str R0, [R3, #0] ;; current->prev->next = toFree
    str R4, [R0, #4] ;; toFree->prev = current->prev
    str R0, [R4]     ;; current->prev = toFree
    str R1, [R0, #0] ;; toFree->next = current

    b freeMergeCheck

freeAddEnd
    ;;Append to the end of the linked list, addr of the current is in R1
    str R0, [R1, #0] ;;current.next = toFree
    str R1, [R0, #4] ;;toFree.prev = current

freeMergeCheck
    ;;Now need to check if the crate can be merged with either the prev or the next, or both!
    ;; prev = (toFree, prev2, size) ;;prev is an address
    ;; toFree = (next, prev, size) toFree is an address
    ;; next = (next2, toFree, size) next is an address

    ;; We should merge toFree and prev when prev + prev.size + sizeof(Crate) = toFree
    ;;  |toFree prev2 size||data of size size bytes||next prev size||data of size size bytes||next2 toFree size||data of size size bytes|
    ;;  ^-prev             ^-prev + sizeof(Crate)   ^-prev + sizeof(Crate) + size bytes = toFree
    ;;  When this is met we can just change prev size to size += toFree->size + sizeof(Crate)
    ;;  Also need to change the next ptr of prev i.e. prev.next = toFree.next
    ;;  and toFree.next.prev = toFree.prev

    ;;In order to check both the left and the right crates we can find the left most and right most crates that can be merged
    ;;e.g. If prev can be merged then left = prev else left = current. If next can be merged then right = next else right = current. If left == right then we don't need to merge else merge

    ;;STEP 1
    ;;Find left and right crates
    ;;R0 is toFree
    ;;R1 is current (crate with a higher addr)

    ldr R2, [R0, #4] ;;toFree->prev
    ldr R3, [R0, #8] ;;toFree->size
    add R2, R2, R3   ;;add address of prev to size of prev
    add R2, R2, #12  ;;add size of a Crate

    cmp R2, R0
    moveq R4, R2
    movne R4, R0

    ;;toFree.addr + toFree.size + sizeof(Crate) == toFree.next Then right = toFree->next else right = toFree
    ldr R2, [R0, #0] ;;toFree->next
    ldr R3, [R0, #8] ;;toFree->size
    add R3, R3, R0   ;;toFree.addr + toFree.size
    add R3, R3, #12  ;;add sizeof(Crate)

    cmp R3, R2 ;;does that == toFree->next
    moveq R5, R2
    movne R5, R0
    
    ;;R4 contains the left crate
    ;;R5 contains the right crate

    cmp R4, R5 ;;if equal then don't merge the crates
    beq freeEnd


mergeCrates
;;PSEUDOFUNC
;;INP in R4 is the address of the left crate to merge
;;INP in R5 is the address of the right crate to merge
    ldr R2, [R5, #8] ;;right->size in R2
    mov R3, #12      ;;sizeof(Crate) = 12 bytes
    add R2, R2, R3
    str R2, [R4, #8] ;;left->size = R2 (right->size + sizeof(Crate))

    ;;left->next = right->next
    ;;if (left->next != 0)
    ;;  left->next->prev = left

    ldr R3, [R5, #0] ;;right->next
    str R3, [R4, #0] ;;left->next = right->next
    cmp R3, #0
    beq freeEnd
    str R4, [R3, #4] ;;left->next->prev = left

freeEnd
    pop {R4-R8}
    mov R15, R14

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
