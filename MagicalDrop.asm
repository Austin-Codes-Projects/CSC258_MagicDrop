
################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Austin Sunesh, 1011054001
# Student 2: Anita Navid,   1011321240
#
# We assert that the code submitted here is entirely our own
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################
.data

##############################################################################
# Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!

# Memory-mapped addresses for the bitmap display and keyboard input
ADDR_DSPL: .word 0x10008000
ADDR_KBRD: .word 0xffff0000

# 7 columns x 14 rows = 98 cells, each stored as a 4-byte word
# Keep grid and mark next to each other; the mark for each cell is 392 bytes after it.
grid: .space 392
mark: .space 392    # 0 = unmarked, 1 = remove the bubble
player_col: .word 3    # Player starts in the middle column (0-6)

# Gameplay variables
hold_colour: .word 0    # var of the colour the player is currently holding. 0 = none, no colours held.
hold_count: .word 0    # The number of bubbles the player is holding.
last_row_time: .word 0    # var for time when the last row was added, measured in milliseconds. 
row_interval: .word 5000    # Time between new rows in milliseconds. We have set it currently as 5 seconds.
speed_increment: .word 250    # The var, which is reduces the row interval by 250 ms each time. Part of 
min_interval: .word 1500    # Fastest allowed row advancement (1.5 seconds)
game_over: .word 0    # Flag indicating whether the game has ended

# Each grid cell stores a colour index rather than the full RGB value
# 0 = empty, 1 = red, 2 = green, 3 = blue, 4 = yellow
colours: .word 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00

lcg_seed: .word 0    # Current seed for the random colour generator


.text
.globl main

main:
    # Use the current system time as our random seed so each restart
    # generates a different arrangement of bubbles
    li $v0, 30      # 30 is the syscall instruction for time 
    syscall         # now we are doing system call to get time.
    sw $a0, lcg_seed    # Save the time value returned in $a0

    jal init_grid    # Initialize all 98 grid cells, so making the column space 0,
                    # so we can updated it later
    jal draw_scene    # Draw the starting board

    # Wait for the player to activate the keyboard and press a key
wait_start:
    li $v0, 32      # 32 is the syscall number for sleep
    li $a0, 16      # Sleep is applied for 16 milliseconds, $a0 is the first register for arguments.
    syscall

    jal read_keyboard # code for user input 
    beq $v0, $zero, wait_start  # added by Anita, to fix rapid row incrmentation, since we are not good at this game.

    # Save the first key so we can still perform its action
    move $t9, $v0

    # Start the timer once the player is ready
    li $v0, 30  # starting timer
    syscall
    sw $a0, last_row_time # timer of prevrow is taken

    move $v0, $t9
    j check_keys # jump to used input 


# keyboard_loop: check the timer and handle input
# redraw the screen whenever the game state changes
keyboard_loop:
    # wait 16 ms between keyboard and timer checks
    li $v0, 32    # sleep
    li $a0, 16    # duration
    syscall

    # get the current system time
    li $v0, 30    # system time
    syscall

    # E1: Calculate how much time has passed since the last new row
    lw $t0, last_row_time
    subu $t1, $a0, $t0    # curr time - last row time, a0 is the curr time, t0 is the last row time
    lw $t2, row_interval    # required time between rows

    # not enough time passed, continue to keyboard input
    bltu $t1, $t2, poll_keyboard    # branch if less than unsigned

    # enough time has passed, so reset the timer and add a row
    sw $a0, last_row_time
    jal advance_rows

    # E2: gradually speed up row advancement as the game progresses
    lw $t0, row_interval    # current time between rows
    lw $t1, speed_increment    # amount to decrease the interval by, saved above
    subu $t0, $t0, $t1

    # prevent the interval from dropping below the minimum speed limit
    lw $t2, min_interval 
    bge $t0, $t2, save_interval
    move $t0, $t2    # Enforce the minimum interval

save_interval:
    sw $t0, row_interval    # Save the new interval for the next row
    jal draw_scene

poll_keyboard:
    jal read_keyboard    # returns the pressed key in $v0
    beq $v0, $zero, keyboard_loop

# Check which key was pressed
check_keys:
    li $t0, 97    # ASCII 97 = 'a'
    beq $v0, $t0, move_left

    li $t0, 100    # ASCII 100 = 'd'
    beq $v0, $t0, move_right

    li $t0, 115    # ASCII 115 represents 's'
    beq $v0, $t0, grab_bubble    # Jump to grab_bubble when S is pressed

    li $t0, 119    # ASCII 119 = 'w'
    beq $v0, $t0, throw_bubbles    # Jump to throw_bubbles when W is pressed

    li $t0, 113    # ASCII for 'q'
    beq $v0, $t0, quit_game    # Exit when Q is pressed

    j keyboard_loop    # Ignore other keys for now

move_left:
    lw $t0, player_col    # Get the player's current column
    beq $t0, $zero, keyboard_loop    # Don't move beyond column 0

    addiu $t0, $t0, -1    # Move one column left
    sw $t0, player_col    # Save the updated position
    jal draw_scene    # Redraw the player in the new position
    j keyboard_loop

move_right:
    lw $t0, player_col
    li $t1, 6    # Rightmost valid column
    beq $t0, $t1, keyboard_loop    # Don't move beyond column 6

    addiu $t0, $t0, 1    # Move one column right
    sw $t0, player_col
    jal draw_scene
    j keyboard_loop


# Grab the lowest bubble in the column and any matching ones above it
grab_bubble:
    lw $t0, player_col    # $t0 stores the column the player is under
    li $t1, 13    # $t1 starts at the bottom row of the grid
    la $t2, grid    # $t2 holds the starting address of the grid

grab_search:
    bltz $t1, grab_done    # Stop if we searched past the top row

    # Find the current cell's address using (row * 7 + column) * 4.
    # There are 7 cells per row, and each cell takes 4 bytes.
    li $t3, 7
    mul $t4, $t1, $t3    # Multiply the current row by 7
    addu $t4, $t4, $t0    # Add the player's column to get the cell index
    sll $t4, $t4, 2    # Convert the cell index into a byte offset
    addu $t5, $t2, $t4    # $t5 now points to the actual cell in memory

    lw $t6, 0($t5)    # Read the bubble's colour index (0 means empty)
    bne $t6, $zero, grab_found

    addiu $t1, $t1, -1    # Empty cell, so move up one row and search again
    j grab_search

grab_found:
    # Can't grab a different colour while already holding bubbles
    lw $t7, hold_colour
    beq $t7, $zero, grab_start
    bne $t7, $t6, grab_done

grab_start:
    sw $t6, hold_colour    # Save the colour of the bubbles being collected
    move $t8, $t6    # Keep the target colour in $t8 for comparison
    lw $t7, hold_count    # Load how many bubbles the player already holds

grab_chain:
    # Keep grabbing until we reach a different colour or an empty cell
    bltz $t1, grab_finish    # Stop if we've moved above the top of the grid
    lw $t6, 0($t5)
    bne $t6, $t8, grab_finish

    sw $zero, 0($t5)    # Remove the matching bubble by clearing its cell
    addiu $t7, $t7, 1    # Add the bubble to the player's held count
    addiu $t5, $t5, -28    # Move up one row (7 cells * 4 bytes = 28)
    addiu $t1, $t1, -1    # Update the row counter to match the new position
    j grab_chain

grab_finish:
    sw $t7, hold_count    # Save the total number of bubbles now being held
    jal draw_scene    # Redraw the board to remove the collected bubbles

grab_done:
    j keyboard_loop    # Return to checking keyboard input

# Throw the held bubbles into the column above the player
throw_bubbles:
    lw $t0, hold_count # count of how much is held by player
    beq $t0, $zero, keyboard_loop    # Nothing to throw

    # search the player's column from the bottom up to find
    # where the thrown bubbles should attach.
    lw $t1, player_col    # player's current column (0-6)
    li $t2, 13    # start at the bottom row
    la $t3, grid    # base address of the grid

throw_search:
    bltz $t2, throw_landing    # reached the top without finding a bubble

    # calculate the cell's memory address:
    # grid + (row * 7 + column) * 4
    # each row contains 7 cells, and each cell occupies 4 bytes.
    li $t4, 7
    mul $t5, $t2, $t4    # find the start of the current row
    addu $t5, $t5, $t1    # add the column to get the cell index
    sll $t5, $t5, 2    # multiply by 4 to get the byte offset
    addu $t6, $t3, $t5    # address of the current cell in memory

    # Stop searching once we find the lowest occupied cell
    lw $t7, 0($t6)    # Read the colour index (0 means empty)
    bne $t7, $zero, throw_landing

    # If the cell is empty, move up one row and continue searching
    addiu $t2, $t2, -1
    j throw_search

throw_landing:
    # Start placing bubbles directly below the lowest existing bubble.
    # If the column is empty, -1 becomes 0 (the top row).
    addiu $t2, $t2, 1

    # Make sure the entire held stack fits before writing to memory.
    # Otherwise, we could accidentally write outside the grid.
    addu $t4, $t2, $t0    # Landing row + held count
    li $t5, 14    # Total number of rows
    bgt $t4, $t5, end_game

    lw $t7, hold_colour    # Colour of the bubbles being thrown
    li $t8, 0    # Number of bubbles placed so far

throw_place:
    beq $t8, $t0, throw_done    # Stop once all held bubbles are placed

    # Find the address of the next cell in the player's column.
    li $t4, 7
    mul $t5, $t2, $t4    # Find the start of the current row
    addu $t5, $t5, $t1    # Add the player's column
    sll $t5, $t5, 2    # Convert the cell index to a byte offset
    addu $t6, $t3, $t5    # Address of the destination cell

    sw $t7, 0($t6)    # Place the bubble in the grid

    addiu $t2, $t2, 1    # Move down one row
    addiu $t8, $t8, 1    # Increase the number of bubbles placed
    j throw_place

throw_done:
    # The bubbles are now on the board, so empty the player's hands
    sw $zero, hold_count
    sw $zero, hold_colour

    jal set_board    # matching and gravity combined, repeating until stable

    # Check for game over AFTER removing matches, since a successful
    # match could clear bubbles that reached the bottom row.
    la $t0, grid
    addiu $t0, $t0, 364    # Bottom row begins at cell 91 (91 * 4)
    li $t1, 0    # Number of cells checked

throw_check_bottom:
    li $t2, 7
    beq $t1, $t2, throw_safe    # All seven cells are empty

    lw $t3, 0($t0)    # Read the current cell
    bne $t3, $zero, end_game    # Any remaining bubble ends the game

    addiu $t0, $t0, 4    # Move to the next column in memory
    addiu $t1, $t1, 1
    j throw_check_bottom

throw_safe:
    # Update the board and continue playing
    jal draw_scene
    j keyboard_loop

# Q exits the game
quit_game:
    li $v0, 10    # Load Immediate: syscall 10 = exit program
    syscall    # Execute the exit syscall

# Draw a filled rectangle by writing RGB values directly to display memory
# Inputs: $a0 = x, $a1 = y, $a2 = width, $a3 = height, $v1 = colour
draw_rect:
    lw $t0, ADDR_DSPL    # $t0 holds the base address of the bitmap display

    # Copy the arguments into temporary registers for use throughout the loops
    move $t1, $a0    # rect starting x value
    move $t2, $a1    # rect starting y value
    move $t3, $a2    # width of rect
    move $t4, $a3    # height of rect
    move $t5, $v1    # RGB colour written to each display unit

    li $t6, 0    # Row counter, starting from the top

draw_rect_row:
    beq $t6, $t4, draw_rect_done    # finish when drawn all request rows

    li $t7, 0    # Reset the col counter for each new row

    # calculate the display address of the first unit in the curr row
    # The display is 32 units wide, and every unit occupies 4 bytes
    move $t8, $t2    # start with the rect y
    add $t8, $t8, $t6    # add the curr row offset
    sll $t8, $t8, 5    # multiply y by 32 to get the row's unit offset

    add $t8, $t8, $t1    # add x to find the correct position in row
    sll $t8, $t8, 2    # convert the unit offset to bytes by multiplying by 4
    add $t8, $t8, $t0    # add the display base address to get the loc in memory

draw_rect_col:
    beq $t7, $t3, draw_rect_next_row    # move down row after drawing full width
    sw $t5, 0($t8)    # write the rect colour to the curr display unit

    addiu $t8, $t8, 4    # go to next display unit (4 bytes)
    addiu $t7, $t7, 1    # count the unit we just drew

    j draw_rect_col    # continue across the row

draw_rect_next_row:
    addiu $t6, $t6, 1    # increment to next row 
    j draw_rect_row

draw_rect_done:
    jr $ra    # full rectangle is done colouring now we return


# Draw the playing field using two overlapping rectangles
# A grey 9x16 rectangle forms the border around the black 7x14 area
draw_field:
    # Save $ra since calling draw_rect with jal will overwrite it
    addiu $sp, $sp, -4
    sw $ra, 0($sp)

    # Outer grey rectangle begins at (3,2)
    # The extra unit on every side creates the border
    li $a0, 3   #loading x value
    li $a1, 2   #loading y value
    li $a2, 9   # loading width
    li $a3, 16  # loading height
    li $v1, 0x808080    #loading colour, which is grey for the border
    jal draw_rect

    # Draw the black playing area inside the border, starting at (4,3)
    # same idea as before just inside now
    li $a0, 4   
    li $a1, 3
    li $a2, 7
    li $a3, 14
    li $v1, 0x000000
    jal draw_rect

    # Restore the return address and release our stack space
    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra


# Generate a random bubble colour using a linear congruential generator (LCG)
# Returns an index from 1 to 4 in $v0, leaving 0 reserved for empty cells
random_colour:  
    lw $t0, lcg_seed    # Load the previous seed from memory

    # updated seed with formula, seed = seed * 1103515245 + 12345
    # keep lower 32 bitsas our new seed value
    li $t1, 1103515245
    multu $t0, $t1 #multiply unsigned
    mflo $t2    # Move the lower half result into t2, mflo - move from Lo, which is lower bits 

    li $t1, 12345
    addu $t2, $t2, $t1    # Add the constant without trapping on overflow

    sw $t2, lcg_seed    # Save the updated seed for the next random number

    # Extract two bits from the middle of the seed to produce a value from 0 to 3
    srl $t2, $t2, 16    # Shift right by 16 bits
    andi $t2, $t2, 3    # Keep only the lowest two bits

    addiu $v0, $t2, 1    # Convert 0-3 into the four colour indices, 1-4

    jr $ra


# Initialize the entire 7x14 game board
# The first 35 cells represent the top five rows and receive random colours
# The remaining 63 cells are cleared so they begin empty
init_grid:
    # Save the registers we modify, including $ra, retur address, for calling random_colour
    # $s0 tracks the current grid address, $s1 the cell index, and $s2 the total number of cells
    addiu $sp, $sp, -16 # 16 bytes are saved onto stack, 4 registers.
    sw $ra, 12($sp) # save return address
    sw $s0, 8($sp) # save curr gird address
    sw $s1, 4($sp)  # cell index
    sw $s2, 0($sp)  # total number of cells

    la $s0, grid    # Point $s0 to the first grid cell in memory
    li $s1, 0    # Start at cell index 0
    li $s2, 98    # Total number of cells (7 x 14)

init_grid_loop:
    beq $s1, $s2, init_grid_done    # Stop once all 98 cells have been initialized

    # Check whether the current cell is part of the first five rows/ 35 means the first five rows
    slti $t0, $s1, 35    # Set $t0 to 1 if the index is below 35, slti - set less than immediate
    beq $t0, $zero, init_grid_empty    # Otherwise, store 0 for an empty cell. branch when 35 reg has been init

    # H4: Avoid creating a vertical match while filling the starting board

# if it is less than 35, so first five has not been init
init_pick:
    jal random_colour    # Get a random colour index in $v0
    slti $t0, $s1, 14    # first two rows can't form a run, slti - set less than immediate,
                        #so make it 1 if it is less than, 0 otherwise
    bne $t0, $zero, init_store  # branch not equal, if t0 is true we store it with init_store
    lw $t1, -28($s0)    # cell one row above, 7 x 4(1 + 0) = 28 
    lw $t2, -56($s0)    # cell two rows above, 7 x 8(1 + 0) = 56
    bne $t1, $t2, init_store    # they differ, so no run is possible
    beq $v0, $t1, init_pick    # new colour would complete a run, so re-roll


init_store:
    sw $v0, 0($s0)  # storing the colour in the 0 offset of of s0

    j init_grid_next    # now we will go to init next grid 

init_grid_empty:
    sw $zero, 0($s0)    # Empty cells are represented by 0. s0 is the curr grid addres

init_grid_next:
    sw $zero, 392($s0)    # Initialize the corresponding mark to 0
    addiu $s0, $s0, 4    # Move forward one word to the next grid cell
    addiu $s1, $s1, 1    # Increase the cell counter

    j init_grid_loop

init_grid_done:
    # Restore the original saved registers before returning
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)

    addiu $sp, $sp, 16    # Release the stack space used by this function
    jr $ra


# Draw every non-empty bubble using the grid's stored colour indices
# Convert grid positions into screen positions with:
# screen x = column + 4, screen y = row + 3
draw_bubbles:
    # Save the registers used to track positions and bubble colours
    # $s0 = current grid address, $s1 = row, $s2 = column
    # $s3 = colour index, $s4 = address of the corresponding RGB entry
    addiu $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)
    sw $s1, 12($sp)
    sw $s2, 8($sp)
    sw $s3, 4($sp)
    sw $s4, 0($sp)

    la $s0, grid    # Begin at the first grid cell
    li $s1, 0    # Start with the top row

draw_bubbles_row:
    li $t0, 14
    beq $s1, $t0, draw_bubbles_done    # Stop after processing all 14 rows

    li $s2, 0    # Reset to the first column of this row

draw_bubbles_col:
    li $t0, 7
    beq $s2, $t0, draw_bubbles_next_row    # Move down after checking all 7 columns

    lw $s3, 0($s0)    # Read the colour index stored in the current grid cell
    beq $s3, $zero, draw_bubbles_skip    # Skip cells containing 0 because they're empty

    # Look up the actual RGB value using the cell's colour index
    # Each entry occupies 4 bytes, so multiply the index by 4 for the offset
    la $s4, colours    # Address of the colour lookup table
    sll $t0, $s3, 2    # Multiply the colour index by 4
    add $s4, $s4, $t0    # Find the address of the selected RGB value
    lw $v1, 0($s4)    # Load that colour for draw_rect

    # Convert the current grid column and row into display coordinates
    # The playable area begins at (4,3), rather than the top-left of the display
    addiu $a0, $s2, 4    # Screen x coordinate
    addiu $a1, $s1, 3    # Screen y coordinate

    # Each bubble is drawn as one 8x8-pixel display unit
    li $a2, 1
    li $a3, 1

    jal draw_rect    # Draw this bubble using the selected colour and position

draw_bubbles_skip:
    # Advance to the next grid cell whether or not we drew a bubble
    addiu $s0, $s0, 4    # Next word in grid memory
    addiu $s2, $s2, 1    # Next column

    j draw_bubbles_col

draw_bubbles_next_row:
    addiu $s1, $s1, 1    # Advance to the next row
    j draw_bubbles_row    # Restart the column loop at column 0

draw_bubbles_done:
    # Restore the saved registers before leaving draw_bubbles
    lw $s4, 0($sp)
    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)

    addiu $sp, $sp, 24
    jr $ra


# Draw the player below the field using a white head and grey body
# Both parts use player_col so they stay aligned when the player moves
draw_player:
    # Save the return address and registers used for drawing the held stack
    addiu $sp, $sp, -12
    sw $ra, 8($sp)
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    # Draw the white head at y = 18
    # The grid begins at x = 4, so we add 4 to player_col to get screen x
    lw $t0, player_col    # Load the player's current column (0-6)
    addiu $a0, $t0, 4    # Convert that column into its screen x coordinate
    li $a1, 18
    li $a2, 1
    li $a3, 1
    li $v1, 0xffffff
    jal draw_rect

    # Draw the grey body directly beneath the head
    lw $t0, player_col
    addiu $a0, $t0, 4
    li $a1, 19
    li $a2, 1
    li $a3, 2
    li $v1, 0xc0c0c0
    jal draw_rect

    # Check how many bubbles are currently held
    lw $t0, hold_count
    beq $t0, $zero, player_done

    # Convert the held colour index into its RGB value
    lw $t0, hold_colour
    la $t1, colours
    sll $t0, $t0, 2
    addu $t1, $t1, $t0
    lw $s1, 0($t1)    # Keep the colour safe across draw_rect calls

    li $s0, 0    # Count how many held bubbles we've drawn

draw_held_loop:
    # Display up to 11 held bubbles to stay within the bitmap boundaries
    # This limits only the drawing, not the number of bubbles held
    lw $t0, hold_count
    beq $s0, $t0, player_done
    li $t0, 11
    beq $s0, $t0, player_done

    # Stack held bubbles vertically, starting at screen row 21
    lw $t0, player_col
    addiu $a0, $t0, 4
    addiu $a1, $s0, 21
    li $a2, 1
    li $a3, 1
    move $v1, $s1
    jal draw_rect

    addiu $s0, $s0, 1
    j draw_held_loop

player_done:
    # Restore saved registers and return
    lw $s1, 0($sp)    # Restore the original colour register
    lw $s0, 4($sp)    # Restore the original counter register
    lw $ra, 8($sp)    # Restore the return address
    addiu $sp, $sp, 12    # Release the 12 bytes reserved earlier
    jr $ra


# Draw the full game scene in order
# The background is drawn first, followed by the bubbles and then the player
draw_scene:
    # Save $ra because this function makes several other function calls
    addiu $sp, $sp, -4 # making room on stack for return address
    sw $ra, 0($sp) # placing return address, on offset 0 of stack

    jal draw_field    # Draw the border and black playing area
    jal draw_bubbles    # Draw the bubbles stored in the grid

    # Clear the area below the field where the player moves
    # This removes the previous player before drawing the updated position
    li $a0, 4
    li $a1, 18
    li $a2, 7
    li $a3, 14
    li $v1, 0x000000
    jal draw_rect
    jal draw_player    # Draw the player below the board

    # Restore the return address and return to the caller
    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# Check for keyboard input using Saturn's memory-mapped registers
# Returns the pressed key in $v0, or 0 if no key is available
read_keyboard:
    lw $t0, ADDR_KBRD    # Load the keyboard control address
    lw $t1, 0($t0)    # Read whether a keypress is available
    andi $t1, $t1, 1    # Check the ready bit (lowest bit)
    beq $t1, $zero, no_key    # Skip if no new key has been pressed

    lw $v0, 4($t0)    # Read the ASCII code of the pressed key, $v0 is the keyboard input 
    jr $ra

no_key:
    move $v0, $zero    # Return 0 when there's no input
    jr $ra

# Move all existing bubbles down by one row, then generate a new top row
advance_rows:
    # Save registers since we'll call random_colour inside this function
    addiu $sp, $sp, -12
    sw $ra, 8($sp)
    sw $s0, 4($sp) # init starting address
    sw $s1, 0($sp)  # init cell index

    la $s0, grid    # Starting address of the game grid
    li $s1, 97    # Start at the last cell (bottom-right)

shift_rows:
    blt $s1, 7, fill_top    # stop shifting once we reach the first row

    # work backwards, prevent overwriting bubbles before moving them.
    # each row is 28 bytes apart (7 cells * 4 bytes).
    sll $t0, $s1, 2    # current cell's byte offset = index * 4
    addu $t1, $s0, $t0    # address of the current cell
    lw $t2, -28($t1)    # read the cell one row above (7 * 4 = 28 bytes)
    sw $t2, 0($t1)    # copy its colour into the current cell

    addiu $s1, $s1, -1    # move backward to the previous cell
    j shift_rows

fill_top:
    li $s1, 0    # Begin filling the new top row

# H4: Re-roll a new bubble if it would make a vertical match
fill_top_loop:
    beq $s1, 7, advance_done

fill_pick: # picking the colours
    jal random_colour

    sll $t0, $s1, 2    # offset of this column in row 0
    addu $t1, $s0, $t0 # address for grid is offsetted with $t0
    lw $t2, 28($t1)    # row 1 of this column (old row 0)
    lw $t3, 56($t1)    # row 2 of this column (old row 1)
    bne $t2, $t3, fill_store    # they differ, so no run is possible
    beq $v0, $t2, fill_pick    # new colour would complete a run, so re-roll


# storing the fill, 
fill_store:
    sw $v0, 0($t1)

    addiu $s1, $s1, 1
    j fill_top_loop

advance_done:
    # Check the bottom row after advancing all bubbles
    la $t0, grid
    addiu $t0, $t0, 364    # Row 13 starts at cell 91 (91 * 4 bytes)
    li $t1, 0    # Number of bottom-row cells checked

check_bottom_row:
    li $t2, 7
    beq $t1, $t2, bottom_clear

    lw $t3, 0($t0)
    bne $t3, $zero, end_game

    addiu $t0, $t0, 4    # Move to the next column
    addiu $t1, $t1, 1
    j check_bottom_row

bottom_clear:
    # Restore saved registers and return if the bottom row is empty
    lw $s1, 0($sp)
    lw $s0, 4($sp)
    lw $ra, 8($sp)
    addiu $sp, $sp, 12
    jr $ra

# End the game when bubbles reach the bottom row or a throw
# would exceed the available space in the grid.
end_game:
    jal draw_scene    # Display the final board before exiting
    li $t0, 1
    sw $t0, game_over    # Record that the game has ended

    li $v0, 10    # Syscall 10: exit
    syscall

# H2: Vertical run triggers, flood fill spreads, then everything marked is cleared.
# Returns $v0 = 1 if anything was cleared.
# coordinator that calls helpers
check_matches:
    addiu $sp, $sp, -4
    sw $ra, 0($sp)
    jal mark_runs # find vertical runs of 3+
    jal expand_marks # the flood fill logic, to get horizontal matches H2
    jal clear_marked # delete all the marked matches
    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra

# mark every cell that is part of a vertical run of 3 or more
# The mark array starts 392 bytes after the grid.
mark_runs:
    la $t0, grid  # grid address
    li $t1, 0    # col

mr_col:
    li $t2, 0    # row
    li $t3, 0    # colour of current seq
    li $t4, 0    # length of current seq

mr_row:
    li $t5, 14  # saving 14
    beq $t2, $t5, mr_next_col # if the row == 14 then we are on edge, and walked off, stop scanning
    
    # comp row and col address
    li $t5, 7   # save 7
    mul $t6, $t2, $t5   # calc index of first cell in row, t6 = row * 7
    addu $t6, $t6, $t1 # calc index in the flat array, t6 = row * 7 + col
    sll $t6, $t6, 2 # calc byte offset by 4
    addu $t7, $t0, $t6    # address of this cell
    
    # read cell and classify
    lw $t8, 0($t7) # colour index stored in cell
    beq $t8, $zero, mr_empty    # if cell is empty we reset 
    bne $t8, $t3, mr_new # if the cell colour is different from the runs colour. Run is a seq of consectuive colours
    
    # same colour as , so run seq grows.
    addiu $t4, $t4, 1   # run length is incremneted
    li $t5, 3 # min length for a clear
    blt $t4, $t5, mr_next_row # when len < 3, we do not have match so contionue
    bgt $t4, $t5, mr_extra # when len > 3, earlier seq was already marked, so we handle extra
    
    # len  is exactly 3
    li $t5, 1    # exactly 3, mark this cell form removal
    sw $t5, 392($t7) # this cell is marked
    sw $t5, 364($t7) # 392 - 28, cell one row above
    sw $t5, 336($t7)    # 392 - 56, cell two rows above
    j mr_next_row # go into next row

mr_extra:
    li $t5, 1   # marked for removal
    sw $t5, 392($t7) # we only mark this cell on the grid , since earlier ones were taken care of 
    j mr_next_row   # contionue 

mr_new:
    move $t3, $t8   # runn colour = this cell colour
    li $t4, 1   # run len is 1, marked
    j mr_next_row # contionue

mr_empty:   # empty case not marke
    li $t3, 0   
    li $t4, 0

mr_next_row: # increment to next row, then contionue mr_row loop
    addiu $t2, $t2, 1
    j mr_row

mr_next_col:
    addiu $t1, $t1, 1   # increment col
    li $t5, 7       # number of col
    blt $t1, $t5, mr_col    # if col < 7, scan next col, (reseting)
    jr $ra


#Spread marks to same-colour neighbours until nothing changes
# Only check up, down, left and right, and skip neighbours outside the grid.
expand_marks:
exp_sweep:
    li $v0, 0    # change flag = 0
    la $t0, grid # grid address
    li $t1, 0    # row = 0

exp_row:
    li $t2, 14  # rows
    beq $t1, $t2, exp_end       # row = 14 , the sweep is finished flag is changed
    li $t2, 0    # col = 0 (reset for each row)

exp_col:
    li $t3, 7 # cols
    beq $t2, $t3, exp_next_row      # col = 7, row finished, go to next row 
    
    mul $t4, $t1, $t3             # row * 7
    addu $t4, $t4, $t2            # + col = cell index
    sll $t4, $t4, 2             # * 4 offset 
    addu $t4, $t0, $t4    # address of this cell,/ + base
    lw $t5, 0($t4)    # its colour
    
    beq $t5, $zero, exp_next_col # empty cell nothing to mark
    lw $t6, 392($t4)    # cell mark
    bne $t6, $zero, exp_next_col    # already marked: skip


# up neighbour 
    beq $t1, $zero, exp_down    # up neighbour, no cell above skip
    lw $t6, -28($t4)            #colour of cell above, one row is 28 bytes
    bne $t6, $t5, exp_down     # diff colour check, try next direction
    lw $t6, 364($t4)            # mark cell above  392 -28
    bne $t6, $zero, exp_mark    # same clour and marked we mark this cell

exp_down:
    li $t6, 13
    beq $t1, $t6, exp_left    # down neighbour, no cell below, skip
    lw $t6, 28($t4)         # colour cell below
    bne $t6, $t5, exp_left # diff colour, try next direction
    lw $t6, 420($t4)    # 392 + 28, mark of cell below    
    bne $t6, $zero, exp_mark    # same colour and  marked, we mark this cell

exp_left:
    beq $t2, $zero, exp_right    # left neighbour, col 0 no left neighbour, skip
    lw $t6, -4($t4)             # colour of left cell
    bne $t6, $t5, exp_right     # diff colour try next direction
    lw $t6, 388($t4)    # 392 - 4, mark of left cell
    bne $t6, $zero, exp_mark    # same colour and marked, mark this cell

exp_right:
    li $t6, 6
    beq $t2, $t6, exp_next_col    # right neighbour, col 6 no right neighbour, skip
    lw $t6, 4($t4)                  # colour of right cell
    bne $t6, $t5, exp_next_col      # diff colour try next direction
    lw $t6, 396($t4)    # 392 + 4, mark of right cell
    beq $t6, $zero, exp_next_col    # not marked skip cell

exp_mark:
    li $t6, 1           
    sw $t6, 392($t4)   # mark this cell 
    li $v0, 1       # set changed flag, so sweep again 

exp_next_col:
    addiu $t2, $t2, 1   # col ++
    j exp_col

exp_next_row:
    addiu $t1, $t1, 1   #row ++
    j exp_row

exp_end:
    bne $v0, $zero, exp_sweep    # sweep was marked , sweep again
    jr $ra                          # no change return



# clear every marked cell and reset the marks
clear_marked:   
    la $t0, grid        # t0 pointer to curr cell,
    li $t1, 0          # t1 cell counter , starts at 0
    li $t2, 98          # t2 is total cells, loop limit
    li $v0, 0           # return value = 0, nothing cleared so far

cl_loop:            
    beq $t1, $t2, cl_done       # check if 98, finish, every cell visited
    lw $t3, 392($t0)            # this cells mark 
    beq $t3, $zero, cl_next     # mark 0, move on
    sw $zero, 0($t0)            # bubble removed
    sw $zero, 392($t0)          # reset mark for next_check_matches call
    li $v0, 1                   # something was cleared return 1

cl_next:
    addiu $t0, $t0, 4       # pointer += 4, nxt word
    addiu $t1, $t1, 1       # counter++
    j cl_loop               # back to loop test

cl_done:
    jr $ra      # return to check matches, v0 =1 if anything was cleared


# Milestone 4 (H3): move bubbles up to close gaps
apply_grav:
    la $t0, grid
    li $t1, 0    # this is the current column

grav_col:
    li $t2, 0    # read row, looks at every cell from row 0 to 13, checking holds bubble
    li $t3, 0    # write row, track next free pos where the bubble should land

grav_row:
    li $t4, 14
    beq $t2, $t4, grav_nxt_col    # checks if reading row is 14, stopping at the bottom

    li $t4, 7    # number of cells per row
    mul $t5, $t2, $t4    # get the index of the first cell in the read row
    addu $t5, $t5, $t1    # getting cell index by adding the col
    sll $t5, $t5, 2    # converting the index into a byte offset
    addu $t5, $t0, $t5    # Now $t5 points to the cell at grid base + byte offset

    lw $t6, 0($t5)    # we load the colour of $t5, to check if there is a bubble
    beq $t6, $zero, grav_skip    # zero means no bubble, so we skip gravity effect

    sw $zero, 0($t5)    # clear the old position, before we write the new position
    mul $t7, $t3, $t4    # Now we are finding the address of the destination.
    addu $t7, $t7, $t1
    sll $t7, $t7, 2
    addu $t7, $t0, $t7
    sw $t6, 0($t7)    # place the bubble in this new spot
    addiu $t3, $t3, 1    # then move the write row down by one

grav_skip:
    addiu $t2, $t2, 1    # move the read row to the next cell, even if it was empty
    j grav_row

grav_nxt_col:    # when read row hits 14
    addiu $t1, $t1, 1    # moves to next col, if col< 7, jumps back to grav_col
    li $t4, 7
    blt $t1, $t4, grav_col
    jr $ra    # when col is 7 it goes back to caller


# H5: Repeat gravity and matching until nothing is removed
# This allows new matches to form after the bubbles move up.

set_board:
    addiu $sp, $sp, -4    # making room for one word on the stack
    sw $ra, 0($sp)    # saving the return address since we will be calling a few functions

set_loop:
    jal apply_grav    # close any gaps before checking for matches
    jal check_matches    # $v0 = 1 if anything was cleared
    bne $v0, $zero, set_loop    # something was cleared, so look again

    lw $ra, 0($sp)
    addiu $sp, $sp, 4
    jr $ra
