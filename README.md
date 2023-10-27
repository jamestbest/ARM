# ARM

Collection of Projects for KMD

## JCGOL 2
This is my second rendition of John Conway's Game of life.

### Key elements
  - Dynamic memory allocation on the heap with malloc & free
  - Get string input from the user - grows buffer to get large strings
  - Strtoi, get the integer value of the given string, with some error codes if fails
  - Settings menu to change default values / bounds
  - Drawing mode where the user can enter the value for each cell in the grid
  - Random mode where the user enters a 4 character seed that is used to populate the grid
  - Saving & loading of the grids
  - Simulation of the grid i.e. counting neighbours and updating new alt grid
  - Helper memory functions such as memset & memcpy

### BTS
#### Malloc & Free
The heap is a contiguous area in memory from the end of the code section to the MAX_ADDR (0x100000) - STACK_SIZE (0x10000) (0xF0000), it's ~960KB in size (varies based as there is metadata for the memory attatched)  
There is a free list of memory locations on the heap stored as a linked list, unlike in Comodo this linked list does not store both the free and claimed memory in the heap, just the free. This makes it more efficient in terms of finding free blocks, but harder to debug.  
Malloc will attempt to find the 'best' free Crate i.e. the smallest crate in the free list where crate.size is >= requested bytes. This helps to reduce the heap fragmentation.

#### Saving & loading
In main there is a local variable we'll call SaveOverviewStruct, this holds the gridInfoStruct* array, the current position in that array that new grids should be added to and a max size.
When saving a grid it just malloc's a new grid memcpy's the values, this allows the user to continue the simulation and have the saved grid stay the same. The new grid* along with the width, height, and name inputted by the user (char*) are stored in a gridInfoStruct
which is added to the SaveOverviewStruct's array. If when adding another grid it exceeds the size it will Realloc with double capacity.

When loading all of the available GridInfoStructs are printing with their corresponding information.

When the user selects a grid all of the information is loaded i.e. width, height and if the dims of the toLoad grid are the same as the old grid then the values are just copied over, otherwise the old grid is freed and another grid of correct dims is allocated and 
then the values are copied over.

### What went well
  - There was a point before adding all the un-thought-out features where the code was fairly well structured
  - Generally followed the ARM32 calling convention
  - Lots of error checking and input validation, more than in some of my HL code which probably says more about those projects than this project.
  - Lots of comments! This was imperative to debugging code I'd written days before and made me think things through a lot more before implimentation.

### What went wrong
  - The naming scheme got progressively worse, to a detrimental effect. Things like messages need a prefix or suffix or something like that to distinguish from labels.
  - Didn't make use of local variables on the stack. Attempted to do this is main but I wasn't sure enough to try it in other areas.
  - Didn't fully follow the ARM32 calling convention. For example calls to newline assume only R0 is clobbered, which is true but not a good idea.
  - Some branches should be functions. Within the main choice's there are branches to new grid, load grid, settings, ect. These should have been bls. I might change this at some point.
  - newline should not be a function, it's just convenient, if only there were assembly macros or something.
  - The code grew large enough that ldr failed with pc relative label offsets - had to adrl and then ldr. Str failing was even worse as I couldn't use the same register.
  - After adding the main game that was basically a better version of JCGOL.s I decided to add saving & loading and later settings. This wasn't in the original scope at all and made refactoring much harder

### Todo
  - Could strtoi also take into account the \b's? Would also have to change the max length on some of the inputs

### Maybe
The main thing I've been thinking about adding is to designate an area of memory as 'non-volatile' this is of course only non-volatile between runs of the program not of KMD. This could then store the saved grids.  
It'd need someway to keep track of the stored information, a function to save to that area, one to read from it ect.  
It's not imperative and wouldn't really add anything to the game, but it would be cool to try and add.

## JCGOL
Unlike its sequel JCGOL.s in old/ is a static implementation of JCGOL, it has two grids stored as defs of maxwidth * maxheight
