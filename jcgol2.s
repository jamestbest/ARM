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


;;  CURRENT ISSUES/TODOS
;;      |-Free is looping crates, making them point at themselves
;;      |-Have not tested getstring due to ^, prob doesn't word
;;      `-haven't tested memcpy             --^

max_addr    EQU  0x100000
stack_size  EQU  0x10000
nlchar      EQU  10
minBuffSize EQU  8
enter       EQU  nlchar

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
    push {R14, R4-R8}

    bl setupOptions


    ldr R0, =enter
    mov R1, #-1
    mov R2, #1
    bl getstring

    swi 3

    pop {R14, R4-R8}
    mov R15, R14

newline
    ldr R0, =nlchar
    swi 0

    mov R15, R14

heapclean
;;zero out all memory in the heap (debugging uses)
    ldr R0, =heapstart
    ldr R1, =max_addr ;;stores the end of the heap
    ldr R2, =stack_size
    sub R1, R1, R2
    and R1, R1, #-4
    mov R3, #0
heapcleanloop
    cmp R0, R1
    beq heapcleanend
    str R3, [R0]
    add R0, R0, #4
    b heapcleanloop
heapcleanend
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
    sub R9, R9, #1 ;;reduce by 1 to use later
    mov R10, R2 ;;print bool

    ldr R6, =minBuffSize ;;R6 will hold the current size of the buffer
    mov R0, R6
    bl malloc
    mov R4, R0 ;;R4 is the address of the buffer

    mov R5, #0 ;;R5 is the loop counter/index into buffer
getstringloop
    swi 1 ;;get input
    cmp R0, R8 ;;is input == terminator character
    beq getstringlend

    cmp R9, #-2
    beq skipMax

    cmp R5, R9 ;;position - maxsize
                      ;;pos 2 means 3 characters written
    bge getstringlend ;;if position >= maxsize - 1

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

    mov R15, R14 ;;RET

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
