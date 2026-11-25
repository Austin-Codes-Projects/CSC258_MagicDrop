
# Magical Drop - Milestone 1
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

# Memory-mapped addresses used to communicate with the display and keyboard
ADDR_DSPL:       .word 0x10008000
ADDR_KBRD:       .word 0xffff0000

# The board has 7 columns and 14 rows, with each cell stored as a 4-byte word
# 7 * 14 * 4 = 392 bytes of memory
grid:            .space 392

player_col:      .word 3            # Player starts in the middle column (0-6)

# These variables will be used as we add gameplay in later milestones
hold_colour:     .word 0           # Colour of the currently held bubble (0 means none)
hold_count:      .word 0           # Number of bubbles being held
key_count:       .word 0           # Tracks keypresses for advancing the rows
game_over:       .word 0           # Will indicate when the game has ended
score:           .word 0           # Current score
chain_depth:     .word 0           # Number of consecutive matches in a chain reaction

# Each grid cell stores a colour index rather than the full RGB value
# Index 0 is empty, followed by red, green, blue, and yellow
colours:         .word 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00

lcg_seed:        .word 0           # Stores the current state of our random generator


.text
.globl main

main:

    # Use the current system time as the starting seed so that restarting
    # the program produces a different arrangement of bubbles
    li      $v0, 30
    syscall
    sw      $a0, lcg_seed           # Save the time value returned in $a0

    jal     init_grid               # Fill the grid before drawing anything
    j       game_loop


# Milestone 1 only needs a static scene, so we draw it once
# and keep the program running afterward to inspect the bitmap and memory
game_loop:
    jal     draw_scene

# Waiting in memory closed loop will change in M2
memory_wait:
    j       memory_wait             # Stay here instead of continuously redrawing the same scene


# Draw a filled rectangle by writing its RGB colour directly into display memory
# Inputs: $a0 = x, $a1 = y, $a2 = width, $a3 = height, $v1 = colour
draw_rect:

    lw      $t0, ADDR_DSPL          # $t0 holds the starting bitmap display, base memory address

    # Copy the arguments into temporary registers so the rectangle's
    # position, size, and colour are available throughout both loops
    move    $t1, $a0                # Starting x coordinate
    move    $t2, $a1                # Starting y coordinate
    move    $t3, $a2                # Rectangle width
    move    $t4, $a3                # Rectangle height
    move    $t5, $v1                # RGB colour to draw

    li      $t6, 0                  # $t6 counts the rows that have been drawn

draw_rect_row:

    beq     $t6, $t4, draw_rect_done # Stop once we've reached the requested height/ Checking if all rows are drawn 

    li      $t7, 0                  # Reset the column counter for each new row

    # Calculate the memory address of the first unit in the current row
    # Each display row contains 32 units, and each unit occupies 4 bytes
    move    $t8, $t2                # Begin with the rectangle's starting y coordinate
    add     $t8, $t8, $t6           # Add the current row offset
    sll     $t8, $t8, 5             # Multiply y by 32 to get the row's starting unit index

    add     $t8, $t8, $t1           # Add x to find the correct unit within that row
    sll     $t8, $t8, 2             # Multiply the unit index by 4 to convert it to bytes
    add     $t8, $t8, $t0           # Add the display base address to get the actual memory location

draw_rect_col:

    beq     $t7, $t3, draw_rect_next_row # Once the width is reached, start the next row

    sw      $t5, 0($t8)             # Write the colour to the current display unit

    addiu   $t8, $t8, 4             # Move the address to the next unit (4 bytes later)
    addiu   $t7, $t7, 1             # Count the unit we just drew

    j       draw_rect_col           # Continue across the current row

draw_rect_next_row:

    addiu   $t6, $t6, 1             # Move down one row in the rectangle
    j       draw_rect_row

draw_rect_done:

    jr      $ra                     # Return to the function that requested the rectangle


# Draw the playing field using two rectangles:
# a larger grey rectangle for the border and a smaller black one inside it
draw_field:

    # Save $ra because calling draw_rect with jal replaces our return address
    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    # Draw the 9x16 grey outer rectangle at (3,2)
    # It extends one unit beyond the playable area on every side
    li      $a0, 3
    li      $a1, 2
    li      $a2, 9
    li      $a3, 16
    li      $v1, 0x808080
    jal     draw_rect

    # Draw the 7x14 black playable area at (4,3)
    # Drawing it over the grey rectangle leaves a one-unit border
    li      $a0, 4
    li      $a1, 3
    li      $a2, 7
    li      $a3, 14
    li      $v1, 0x000000
    jal     draw_rect

    # Restore the original return address and release the stack space
    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra


# Generate a random bubble colour using a linear congruential generator (LCG)
# We return an index from 1 to 4, since 0 is reserved for empty cells
random_colour:

    lw      $t0, lcg_seed           # Load the previous seed into $t0

    # Generate the next seed using: seed = seed * 1103515245 + 12345
    # We only need the lower 32 bits of the multiplication result
    li      $t1, 1103515245
    multu   $t0, $t1
    mflo    $t2                     # Copy the low 32 bits of the product into $t2

    li      $t1, 12345
    addu    $t2, $t2, $t1           # Add the constant without trapping on overflow

    sw      $t2, lcg_seed           # Save the new seed for the next call

    # Use two bits from the updated seed to get a number between 0 and 3
    # Shifting by 16 avoids relying only on the seed's lowest bits
    srl     $t2, $t2, 16
    andi    $t2, $t2, 3

    addiu   $v0, $t2, 1             # Convert 0-3 into the four valid colour indices, 1-4

    jr      $ra                     # Return the generated index through $v0


# Set up the 7x14 board in memory
# The top 5 rows (35 cells) contain random bubbles, while the remaining 63 are empty
init_grid:

    # Save the return address and $s registers because we'll modify them
    # $s0 tracks the current grid address, $s1 the cell index, and $s2 the total
    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    sw      $s0, 8($sp)
    sw      $s1, 4($sp)
    sw      $s2, 0($sp)

    la      $s0, grid               # Point $s0 to the beginning of the grid in memory
    li      $s1, 0                  # Start at cell index 0
    li      $s2, 98                 # 7 columns * 14 rows = 98 cells

init_grid_loop:

    beq     $s1, $s2, init_grid_done # Finish after all 98 cells have been initialized

    # Check whether the current cell belongs to the first five rows
    slti    $t0, $s1, 35            # $t0 becomes 1 if the cell index is less than 35
    beq     $t0, $zero, init_grid_empty # Otherwise, leave the cell empty

    jal     random_colour           # Generate a colour index in $v0
    sw      $v0, 0($s0)             # Store that index in the current grid cell

    j       init_grid_next          # Skip the empty-cell case

init_grid_empty:

    sw      $zero, 0($s0)           # Store 0 to represent an empty cell

init_grid_next:

    addiu   $s0, $s0, 4             # Advance to the next word in grid memory
    addiu   $s1, $s1, 1             # Increase the cell counter

    j       init_grid_loop          # Continue until the entire board has been initialized

init_grid_done:

    # Restore the registers to their values before init_grid was called
    # The saved registers must be preserved for whichever function called us
    lw      $s2, 0($sp)
    lw      $s1, 4($sp)
    lw      $s0, 8($sp)
    lw      $ra, 12($sp)

    addiu   $sp, $sp, 16            # Release the 16 bytes reserved on the stack
    jr      $ra


# Draw every occupied cell of the grid onto the bitmap display
# Grid coordinates are converted using x = column + 4 and y = row + 3
# The offsets account for the playing field's position inside the border
draw_bubbles:

    # Save registers used to track the grid and colour information
    # $s0 = grid address, $s1 = row, $s2 = column, $s3 = colour index
    # $s4 = address of the matching colour in the RGB lookup table
    addiu   $sp, $sp, -24
    sw      $ra, 20($sp)
    sw      $s0, 16($sp)
    sw      $s1, 12($sp)
    sw      $s2, 8($sp)
    sw      $s3, 4($sp)
    sw      $s4, 0($sp)

    la      $s0, grid               # Start reading from the first grid cell
    li      $s1, 0                  # Begin with row 0

draw_bubbles_row:

    li      $t0, 14
    beq     $s1, $t0, draw_bubbles_done # Stop after drawing all 14 rows

    li      $s2, 0                  # Start at column 0 for each new row

draw_bubbles_col:

    li      $t0, 7
    beq     $s2, $t0, draw_bubbles_next_row # Move to the next row after 7 columns

    lw      $s3, 0($s0)             # Load the current cell's colour index
    beq     $s3, $zero, draw_bubbles_skip # Don't draw anything if the cell is empty

    # Look up the RGB value that corresponds to the stored colour index
    # Each colour entry takes 4 bytes, so the index must first be multiplied by 4
    la      $s4, colours            # Start at the address of the colour lookup table
    sll     $t0, $s3, 2             # Multiply the index by 4 to get its byte offset
    add     $s4, $s4, $t0           # Move to the correct entry in the table
    lw      $v1, 0($s4)             # Load the RGB value for draw_rect to use

    # Translate the grid position into display coordinates
    # The playable area starts at (4,3), not at the display's origin
    addiu   $a0, $s2, 4             # Screen x = column + 4
    addiu   $a1, $s1, 3             # Screen y = row + 3

    # Each bubble is represented by a single 8x8-pixel display unit
    li      $a2, 1
    li      $a3, 1

    jal     draw_rect               # Draw this bubble using its position and RGB colour

draw_bubbles_skip:

    # Whether the cell was empty or drawn, advance to the next grid position
    addiu   $s0, $s0, 4             # Move forward one 4-byte grid cell
    addiu   $s2, $s2, 1             # Move to the next column

    j       draw_bubbles_col

draw_bubbles_next_row:

    addiu   $s1, $s1, 1             # Increase the row counter
    j       draw_bubbles_row        # Start the next row, resetting its column counter

draw_bubbles_done:

    # Restore all saved registers before leaving this function
    lw      $s4, 0($sp)
    lw      $s3, 4($sp)
    lw      $s2, 8($sp)
    lw      $s1, 12($sp)
    lw      $s0, 16($sp)
    lw      $ra, 20($sp)

    addiu   $sp, $sp, 24
    jr      $ra


# Draw the player below the board as a white head and green body
# The sprite is fixed at the centre for this Milestone 1 version
draw_player:

    # Save $ra since draw_rect will be called twice
    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    # Draw the white head at (7,18), directly below the playing field
    li      $a0, 7
    li      $a1, 18
    li      $a2, 1
    li      $a3, 1
    li      $v1, 0xffffff
    jal     draw_rect

    # Draw the green body starting one unit below the head
    # It uses the same x coordinate so the two rectangles line up
    li      $a0, 7
    li      $a1, 19
    li      $a2, 1
    li      $a3, 2
    li      $v1, 0x00ff00
    jal     draw_rect

    # Restore the return address so we can return to draw_scene
    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra


# Draw the complete game scene in the correct order
# The field goes first, then its bubbles, followed by the player below it
draw_scene:

    # Save $ra because this function makes several nested function calls
    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    jal     draw_field              # Draw the border and black playing area
    jal     draw_bubbles            # Draw all non-empty cells using the grid data
    jal     draw_player             # Draw the player at the bottom of the board

    # Restore the original return address and finish drawing
    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra
