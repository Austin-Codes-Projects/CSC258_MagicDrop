
# Magical Drop - Milestone 2
#
# We assert that the code submitted here is entirely our own creation,
# and will indicate otherwise when it is not.
#
# Bitmap Display Configuration
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000

.data

# Memory-mapped addresses for the bitmap display and keyboard input
ADDR_DSPL:       .word 0x10008000
ADDR_KBRD:       .word 0xffff0000

# 7 columns x 14 rows = 98 cells, each stored as a 4-byte word
grid:            .space 392

player_col:      .word 3            # Player starts in the middle column (0-6)

# Gameplay variables (score and chain depth are for later milestones).
hold_colour:     .word 0           # Colour currently held by the player (0 = none)
hold_count:      .word 0           # Number of bubbles being held
key_count:       .word 0           # Keypress counter used to advance the board
game_over:       .word 0           # Flag indicating whether the game has ended
score:           .word 0           # Player's score
chain_depth:     .word 0           # Tracks consecutive matches for chain reactions

# Each grid cell stores a colour index rather than the full RGB value
# 0 = empty, 1 = red, 2 = green, 3 = blue, 4 = yellow
colours:         .word 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00

lcg_seed:        .word 0           # Current seed for the random colour generator


.text
.globl main

main:

    # Use the current system time as our random seed so each restart
    # generates a different arrangement of bubbles
    li      $v0, 30
    syscall
    sw      $a0, lcg_seed           # Save the time value returned in $a0

    jal     init_grid               # Initialize all 98 grid cells
    j       game_loop               # Start the game after the board is ready


# Main loop: refresh the screen, check input and update the game
game_loop:
keyboard_loop:
    # Redraw the current game state even when no key is pressed
    jal     draw_scene

    # Pause for 16 milliseconds between frames to target roughly 60 FPS
    li      $v0, 32
    li      $a0, 16
    syscall

    # Check for keyboard input after refreshing the display
    jal     read_keyboard           # Get the pressed key's ASCII code in $v0
    beq     $v0, $zero, keyboard_loop  # Don't count when no key was pressed

    # Count each keypress so we can advance the board after 10
    lw      $t1, key_count          # Load the current number of keypresses
    addiu   $t1, $t1, 1            # Increase the counter by one
    sw      $t1, key_count          # Save the updated count in memory
    
    # Check whether the counter has reached 10
    li      $t2, 10
    bne     $t1, $t2, check_keys

    # Save the pressed key on the stack because function calls can overwrite $v0
    addiu   $sp, $sp, -4
    sw      $v0, 0($sp)

    sw      $zero, key_count       # Start counting the next set of 10 keypresses
    jal     advance_rows           # Move the bubbles down and generate a new row
    jal     draw_scene             # Update the display

    lw      $v0, 0($sp)            # Restore the original key's ASCII code
    addiu   $sp, $sp, 4            # Release the temporary stack space

check_keys:
    li      $t0, 97                 # ASCII 97 = 'a'
    beq     $v0, $t0, move_left

    li      $t0, 100                # ASCII 100 = 'd'
    beq     $v0, $t0, move_right

    li      $t0, 115                # ASCII 115 represents 's'
    beq     $v0, $t0, grab_bubble   # Jump to grab_bubble when S is pressed

    li      $t0, 113                # ASCII for 'q'
    beq     $v0, $t0, quit_game     # Exit when Q is pressed
    
    j       keyboard_loop           # Ignore other keys for now

move_left:
    lw      $t0, player_col         # Get the player's current column
    beq     $t0, $zero, keyboard_loop # Don't move beyond column 0

    addiu   $t0, $t0, -1            # Move one column left
    sw      $t0, player_col         # Save the updated position
    jal     draw_scene              # Redraw the player in the new position
    j       keyboard_loop

move_right:
    lw      $t0, player_col
    li      $t1, 6                  # Rightmost valid column
    beq     $t0, $t1, keyboard_loop # Don't move beyond column 6

    addiu   $t0, $t0, 1             # Move one column right
    sw      $t0, player_col
    jal     draw_scene
    j       keyboard_loop
    

# Grab the lowest bubble in the column and any matching ones above it
grab_bubble:
    lw      $t0, player_col     # $t0 stores the column the player is under
    li      $t1, 13             # $t1 starts at the bottom row of the grid
    la      $t2, grid           # $t2 holds the starting address of the grid

grab_search:
    bltz    $t1, grab_done      # Stop if we searched past the top row

    # Find the current cell's address using (row * 7 + column) * 4.
    # There are 7 cells per row, and each cell takes 4 bytes.
    li      $t3, 7
    mul     $t4, $t1, $t3       # Multiply the current row by 7
    addu    $t4, $t4, $t0       # Add the player's column to get the cell index
    sll     $t4, $t4, 2         # Convert the cell index into a byte offset
    addu    $t5, $t2, $t4       # $t5 now points to the actual cell in memory

    lw      $t6, 0($t5)         # Read the bubble's colour index (0 means empty)
    bne     $t6, $zero, grab_found

    addiu   $t1, $t1, -1        # Empty cell, so move up one row and search again
    j       grab_search

grab_found:
    # Can't grab a different colour while already holding bubbles
    lw      $t7, hold_colour
    beq     $t7, $zero, grab_start
    bne     $t7, $t6, grab_done

grab_start:
    sw      $t6, hold_colour   # Save the colour of the bubbles being collected
    move    $t8, $t6           # Keep the target colour in $t8 for comparison
    lw      $t7, hold_count    # Load how many bubbles the player already holds

grab_chain:
    # Keep grabbing until we reach a different colour or an empty cell
    bltz    $t1, grab_finish   # Stop if we've moved above the top of the grid
    lw      $t6, 0($t5)
    bne     $t6, $t8, grab_finish

    sw      $zero, 0($t5)      # Remove the matching bubble by clearing its cell
    addiu   $t7, $t7, 1        # Add the bubble to the player's held count
    addiu   $t5, $t5, -28      # Move up one row (7 cells * 4 bytes = 28)
    addiu   $t1, $t1, -1       # Update the row counter to match the new position
    j       grab_chain

grab_finish:
    sw      $t7, hold_count    # Save the total number of bubbles now being held
    jal     draw_scene         # Redraw the board to remove the collected bubbles

grab_done:
    j       keyboard_loop      # Return to checking keyboard input    

# Q exits the game
quit_game:
    li      $v0, 10             # Load Immediate: syscall 10 = exit program
    syscall                     # Execute the exit syscall

# Draw a filled rectangle by writing RGB values directly to display memory
# Inputs: $a0 = x, $a1 = y, $a2 = width, $a3 = height, $v1 = colour
draw_rect:

    lw      $t0, ADDR_DSPL          # $t0 holds the base address of the bitmap display

    # Copy the arguments into temporary registers for use throughout the loops
    move    $t1, $a0                # Rectangle's starting x coordinate
    move    $t2, $a1                # Rectangle's starting y coordinate
    move    $t3, $a2                # Width of the rectangle
    move    $t4, $a3                # Height of the rectangle
    move    $t5, $v1                # RGB colour written to each display unit

    li      $t6, 0                  # Row counter, starting from the top

draw_rect_row:

    beq     $t6, $t4, draw_rect_done # Finish when we've drawn the requested number of rows

    li      $t7, 0                  # Reset the column counter for each new row

    # Calculate the display address of the first unit in the current row
    # The display is 32 units wide, and every unit occupies 4 bytes
    move    $t8, $t2                # Start with the rectangle's y coordinate
    add     $t8, $t8, $t6           # Add the current row offset
    sll     $t8, $t8, 5             # Multiply y by 32 to get the row's unit offset

    add     $t8, $t8, $t1           # Add x to find the correct position within that row
    sll     $t8, $t8, 2             # Convert the unit offset to bytes by multiplying by 4
    add     $t8, $t8, $t0           # Add the display base address to get the location in memory

draw_rect_col:

    beq     $t7, $t3, draw_rect_next_row # Move down a row after drawing the full width

    sw      $t5, 0($t8)             # Write the rectangle's colour to the current display unit

    addiu   $t8, $t8, 4             # Advance to the next display unit (4 bytes)
    addiu   $t7, $t7, 1             # Count the unit we just drew

    j       draw_rect_col           # Continue across the row

draw_rect_next_row:

    addiu   $t6, $t6, 1             # Move to the next row
    j       draw_rect_row

draw_rect_done:

    jr      $ra                     # Return to the function that called draw_rect


# Draw the playing field using two overlapping rectangles
# A grey 9x16 rectangle forms the border around the black 7x14 area
draw_field:

    # Save $ra since calling draw_rect with jal will overwrite it
    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    # Outer grey rectangle begins at (3,2)
    # The extra unit on every side creates the border
    li      $a0, 3
    li      $a1, 2
    li      $a2, 9
    li      $a3, 16
    li      $v1, 0x808080
    jal     draw_rect

    # Draw the black playing area inside the border, starting at (4,3)
    li      $a0, 4
    li      $a1, 3
    li      $a2, 7
    li      $a3, 14
    li      $v1, 0x000000
    jal     draw_rect

    # Restore the return address and release our stack space
    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra


# Generate a random bubble colour using a linear congruential generator (LCG)
# Returns an index from 1 to 4 in $v0, leaving 0 reserved for empty cells
random_colour:

    lw      $t0, lcg_seed           # Load the previous seed from memory

    # Update the seed using: seed = seed * 1103515245 + 12345
    # We keep the lower 32 bits of the product as our new seed value
    li      $t1, 1103515245
    multu   $t0, $t1
    mflo    $t2                     # Move the lower half of the multiplication result into $t2

    li      $t1, 12345
    addu    $t2, $t2, $t1           # Add the constant without trapping on overflow

    sw      $t2, lcg_seed           # Save the updated seed for the next random number

    # Extract two bits from the middle of the seed to produce a value from 0 to 3
    srl     $t2, $t2, 16            # Shift right by 16 bits
    andi    $t2, $t2, 3             # Keep only the lowest two bits

    addiu   $v0, $t2, 1             # Convert 0-3 into the four colour indices, 1-4

    jr      $ra


# Initialize the entire 7x14 game board
# The first 35 cells represent the top five rows and receive random colours
# The remaining 63 cells are cleared so they begin empty
init_grid:

    # Save the registers we'll modify, including $ra for calling random_colour
    # $s0 tracks the current grid address, $s1 the cell index, and $s2 the total
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    sw      $s0, 8($sp)
    sw      $s1, 4($sp)
    sw      $s2, 0($sp)

    la      $s0, grid               # Point $s0 to the first grid cell in memory
    li      $s1, 0                  # Start at cell index 0
    li      $s2, 98                 # Total number of cells (7 x 14)

init_grid_loop:

    beq     $s1, $s2, init_grid_done # Stop once all 98 cells have been initialized

    # Check whether the current cell is part of the first five rows
    slti    $t0, $s1, 35            # Set $t0 to 1 if the index is below 35
    beq     $t0, $zero, init_grid_empty # Otherwise, store 0 for an empty cell

    jal     random_colour           # Get a random colour index in $v0
    sw      $v0, 0($s0)             # Store the colour index in the current cell

    j       init_grid_next          # Skip the empty-cell case

init_grid_empty:

    sw      $zero, 0($s0)           # Empty cells are represented by 0

init_grid_next:

    addiu   $s0, $s0, 4             # Move forward one word to the next grid cell
    addiu   $s1, $s1, 1             # Increase the cell counter

    j       init_grid_loop

init_grid_done:

    # Restore the original saved registers before returning
    lw      $s2, 0($sp)
    lw      $s1, 4($sp)
    lw      $s0, 8($sp)
    lw      $ra, 12($sp)

    addiu   $sp, $sp, 16            # Release the stack space used by this function
    jr      $ra


# Draw every non-empty bubble using the grid's stored colour indices
# Convert grid positions into screen positions with:
# screen x = column + 4, screen y = row + 3
draw_bubbles:

    # Save the registers used to track positions and bubble colours
    # $s0 = current grid address, $s1 = row, $s2 = column
    # $s3 = colour index, $s4 = address of the corresponding RGB entry
    addiu   $sp, $sp, -24
    sw      $ra, 20($sp)
    sw      $s0, 16($sp)
    sw      $s1, 12($sp)
    sw      $s2, 8($sp)
    sw      $s3, 4($sp)
    sw      $s4, 0($sp)

    la      $s0, grid               # Begin at the first grid cell
    li      $s1, 0                  # Start with the top row

draw_bubbles_row:

    li      $t0, 14
    beq     $s1, $t0, draw_bubbles_done # Stop after processing all 14 rows

    li      $s2, 0                  # Reset to the first column of this row

draw_bubbles_col:

    li      $t0, 7
    beq     $s2, $t0, draw_bubbles_next_row # Move down after checking all 7 columns

    lw      $s3, 0($s0)             # Read the colour index stored in the current grid cell
    beq     $s3, $zero, draw_bubbles_skip # Skip cells containing 0 because they're empty

    # Look up the actual RGB value using the cell's colour index
    # Each entry occupies 4 bytes, so multiply the index by 4 for the offset
    la      $s4, colours            # Address of the colour lookup table
    sll     $t0, $s3, 2             # Multiply the colour index by 4
    add     $s4, $s4, $t0           # Find the address of the selected RGB value
    lw      $v1, 0($s4)             # Load that colour for draw_rect

    # Convert the current grid column and row into display coordinates
    # The playable area begins at (4,3), rather than the top-left of the display
    addiu   $a0, $s2, 4             # Screen x coordinate
    addiu   $a1, $s1, 3             # Screen y coordinate

    # Each bubble is drawn as one 8x8-pixel display unit
    li      $a2, 1
    li      $a3, 1

    jal     draw_rect               # Draw this bubble using the selected colour and position

draw_bubbles_skip:

    # Advance to the next grid cell whether or not we drew a bubble
    addiu   $s0, $s0, 4             # Next word in grid memory
    addiu   $s2, $s2, 1             # Next column

    j       draw_bubbles_col

draw_bubbles_next_row:

    addiu   $s1, $s1, 1             # Advance to the next row
    j       draw_bubbles_row        # Restart the column loop at column 0

draw_bubbles_done:

    # Restore the saved registers before leaving draw_bubbles
    lw      $s4, 0($sp)
    lw      $s3, 4($sp)
    lw      $s2, 8($sp)
    lw      $s1, 12($sp)
    lw      $s0, 16($sp)
    lw      $ra, 20($sp)

    addiu   $sp, $sp, 24
    jr      $ra


# Draw the player below the field using a white head and green body
# Both parts use player_col so they stay aligned when the player moves
draw_player:
    # Save the return address and registers used for drawing the held stack
    addiu   $sp, $sp, -12
    sw      $ra, 8($sp)
    sw      $s0, 4($sp)
    sw      $s1, 0($sp)

    # Draw the white head at y = 18
    # The grid begins at x = 4, so we add 4 to player_col to get screen x
    lw      $t0, player_col         # Load the player's current column (0-6)
    addiu   $a0, $t0, 4             # Convert that column into its screen x coordinate
    li      $a1, 18
    li      $a2, 1
    li      $a3, 1
    li      $v1, 0xffffff
    jal     draw_rect

    # Draw the green body directly beneath the head
    lw      $t0, player_col
    addiu   $a0, $t0, 4
    li      $a1, 19
    li      $a2, 1
    li      $a3, 2
    li      $v1, 0x00ff00
    jal     draw_rect

    # Check how many bubbles are currently held
    lw      $t0, hold_count
    beq     $t0, $zero, player_done

    # Convert the held colour index into its RGB value
    lw      $t0, hold_colour
    la      $t1, colours
    sll     $t0, $t0, 2
    addu    $t1, $t1, $t0
    lw      $s1, 0($t1)       # Keep the colour safe across draw_rect calls

    li      $s0, 0            # Count how many held bubbles we've drawn

draw_held_loop:
    # Display up to 11 held bubbles to stay within the bitmap boundaries
    # This limits only the drawing, not the number of bubbles held
    lw      $t0, hold_count
    beq     $s0, $t0, player_done
    li      $t0, 11
    beq     $s0, $t0, player_done

    # Draw each bubble below the player, one unit apart
    lw      $t0, player_col
    addiu   $a0, $t0, 4
    addiu   $a1, $s0, 21
    li      $a2, 1
    li      $a3, 1
    move    $v1, $s1
    jal     draw_rect

    addiu   $s0, $s0, 1
    j       draw_held_loop

player_done:
    # Restore saved registers and return
    lw      $s1, 0($sp)        # Restore the original colour register
    lw      $s0, 4($sp)        # Restore the original counter register
    lw      $ra, 8($sp)        # Restore the return address
    addiu   $sp, $sp, 12      # Release the 12 bytes reserved earlier
    jr      $ra


# Draw the full game scene in order
# The background is drawn first, followed by the bubbles and then the player
draw_scene:

    # Save $ra because this function makes several other function calls
    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    jal     draw_field              # Draw the border and black playing area
    jal     draw_bubbles            # Draw the bubbles stored in the grid
    
    # Clear the area below the field where the player moves
    # This removes the previous player before drawing the updated position
    li      $a0, 4
    li      $a1, 18
    li      $a2, 7
    li      $a3, 14
    li      $v1, 0x000000
    jal     draw_rect
    jal     draw_player             # Draw the player below the board

    # Restore the return address and return to the caller
    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra

# Check for keyboard input using Saturn's memory-mapped registers
# Returns the pressed key in $v0, or 0 if no key is available
read_keyboard:
    lw      $t0, ADDR_KBRD       # Load the keyboard control address
    lw      $t1, 0($t0)          # Read whether a keypress is available
    andi    $t1, $t1, 1         # Check the ready bit (lowest bit)
    beq     $t1, $zero, no_key  # Skip if no new key has been pressed

    lw      $v0, 4($t0)         # Read the ASCII code of the pressed key
    jr      $ra

no_key:
    move    $v0, $zero          # Return 0 when there's no input
    jr      $ra
    
# Move all existing bubbles down by one row, then generate a new top row
advance_rows:
    # Save registers since we'll call random_colour inside this function
    addiu   $sp, $sp, -12
    sw      $ra, 8($sp)
    sw      $s0, 4($sp)
    sw      $s1, 0($sp)

    la      $s0, grid           # Starting address of the game grid
    li      $s1, 97             # Start at the last cell (bottom-right)

shift_rows:
    blt     $s1, 7, fill_top    # Stop shifting once we reach the first row

    # Work backwards so we don't overwrite bubbles before moving them.
    # Each row is 28 bytes apart (7 cells * 4 bytes).
    sll     $t0, $s1, 2        # Current cell's byte offset = index * 4
    addu    $t1, $s0, $t0      # Address of the current cell
    lw      $t2, -28($t1)      # Read the cell one row above (7 * 4 = 28 bytes)
    sw      $t2, 0($t1)        # Copy its colour into the current cell

    addiu   $s1, $s1, -1       # Move backward to the previous cell
    j       shift_rows

fill_top:
    li      $s1, 0             # Begin filling the new top row

fill_top_loop:
    beq     $s1, 7, advance_done

    jal     random_colour      # Generate a colour index from 1 to 4

    sll     $t0, $s1, 2        # Find the current top-row cell's byte offset
    addu    $t1, $s0, $t0
    sw      $v0, 0($t1)        # Store the newly generated colour

    addiu   $s1, $s1, 1
    j       fill_top_loop

advance_done:
    # Check the bottom row after advancing all bubbles
    la      $t0, grid
    addiu   $t0, $t0, 364      # Row 13 starts at cell 91 (91 * 4 bytes)
    li      $t1, 0             # Number of bottom-row cells checked

check_bottom_row:
    li      $t2, 7
    beq     $t1, $t2, bottom_clear

    lw      $t3, 0($t0)
    bne     $t3, $zero, end_game

    addiu   $t0, $t0, 4        # Move to the next column
    addiu   $t1, $t1, 1
    j       check_bottom_row

bottom_clear:
    # Restore saved registers and return if the bottom row is empty
    lw      $s1, 0($sp)
    lw      $s0, 4($sp)
    lw      $ra, 8($sp)
    addiu   $sp, $sp, 12
    jr      $ra
    
# End the game as soon as a bubble reaches the bottom row.
end_game:
    jal draw_scene              # Display the final board before exiting
    li      $t0, 1
    sw      $t0, game_over     # Record that the game has ended

    li      $v0, 10           # Syscall 10: exit
    syscall