
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

# Memory-mapped I/O addresses
ADDR_DSPL:       .word 0x10008000
ADDR_KBRD:       .word 0xffff0000

# Game board: 7x14 cells, 4 bytes each
grid:            .space 392

player_col:      .word 3

# Gameplay variables for later milestones
hold_colour:     .word 0
hold_count:      .word 0
key_count:       .word 0
game_over:       .word 0
score:           .word 0
chain_depth:     .word 0

# Bubble colours: 0 = empty, 1 = red, 2 = green, 3 = blue, 4 = yellow
colours:         .word 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00

lcg_seed:        .word 0


.text
.globl main

main:

    # Seed the random generator using system time
    li      $v0, 30
    syscall
    sw      $a0, lcg_seed

    jal     init_grid
    j       game_loop


# Draw the scene once and stay running for memory inspection
game_loop:
    jal     draw_scene

memory_wait:
    j       memory_wait


# Draw a filled rectangle on a 32-unit-wide display
# Inputs: $a0 = x, $a1 = y, $a2 = width, $a3 = height, $v1 = colour
draw_rect:

    lw      $t0, ADDR_DSPL

    move    $t1, $a0
    move    $t2, $a1
    move    $t3, $a2
    move    $t4, $a3
    move    $t5, $v1

    li      $t6, 0            # Row counter

draw_rect_row:

    beq     $t6, $t4, draw_rect_done

    li      $t7, 0            # Column counter

    # Calculate the starting address of the current row
    move    $t8, $t2
    add     $t8, $t8, $t6
    sll     $t8, $t8, 5       # 32 display units per row

    add     $t8, $t8, $t1
    sll     $t8, $t8, 2       # 4 bytes per unit

    add     $t8, $t8, $t0

draw_rect_col:

    beq     $t7, $t3, draw_rect_next_row

    sw      $t5, 0($t8)       # Draw current unit

    addiu   $t8, $t8, 4
    addiu   $t7, $t7, 1

    j       draw_rect_col

draw_rect_next_row:

    addiu   $t6, $t6, 1
    j       draw_rect_row

draw_rect_done:

    jr      $ra


# Draw the grey border and black 7x14 playing area
draw_field:

    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    # Outer border (9x16)
    li      $a0, 3
    li      $a1, 2
    li      $a2, 9
    li      $a3, 16
    li      $v1, 0x808080
    jal     draw_rect

    # Inner playing area (7x14)
    li      $a0, 4
    li      $a1, 3
    li      $a2, 7
    li      $a3, 14
    li      $v1, 0x000000
    jal     draw_rect

    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra


# Generate a random bubble colour from 1 to 4 using an LCG
# Output: $v0 = colour
random_colour:

    lw      $t0, lcg_seed

    # Update seed: seed * 1103515245 + 12345
    li      $t1, 1103515245
    multu   $t0, $t1
    mflo    $t2

    li      $t1, 12345
    addu    $t2, $t2, $t1

    sw      $t2, lcg_seed

    # Extract two bits for a value from 0 to 3
    srl     $t2, $t2, 16
    andi    $t2, $t2, 3

    addiu   $v0, $t2, 1       # Convert to 1-4

    jr      $ra


# Fill the first 5 rows with random bubbles and clear the remaining rows
init_grid:

    addiu   $sp, $sp, -16
    sw      $ra, 12($sp)
    sw      $s0, 8($sp)
    sw      $s1, 4($sp)
    sw      $s2, 0($sp)

    la      $s0, grid
    li      $s1, 0            # Cell index
    li      $s2, 98           # Total cells

init_grid_loop:

    beq     $s1, $s2, init_grid_done

    # First 35 cells contain bubbles
    slti    $t0, $s1, 35
    beq     $t0, $zero, init_grid_empty

    jal     random_colour
    sw      $v0, 0($s0)

    j       init_grid_next

init_grid_empty:

    sw      $zero, 0($s0)

init_grid_next:

    addiu   $s0, $s0, 4
    addiu   $s1, $s1, 1

    j       init_grid_loop

init_grid_done:

    lw      $s2, 0($sp)
    lw      $s1, 4($sp)
    lw      $s0, 8($sp)
    lw      $ra, 12($sp)

    addiu   $sp, $sp, 16
    jr      $ra


# Draw non-empty bubbles using their positions and colours in the grid
# Screen coordinates: x = 4 + column, y = 3 + row
draw_bubbles:

    addiu   $sp, $sp, -24
    sw      $ra, 20($sp)
    sw      $s0, 16($sp)
    sw      $s1, 12($sp)
    sw      $s2, 8($sp)
    sw      $s3, 4($sp)
    sw      $s4, 0($sp)

    la      $s0, grid
    li      $s1, 0            # Row index

draw_bubbles_row:

    li      $t0, 14
    beq     $s1, $t0, draw_bubbles_done

    li      $s2, 0            # Column index

draw_bubbles_col:

    li      $t0, 7
    beq     $s2, $t0, draw_bubbles_next_row

    lw      $s3, 0($s0)
    beq     $s3, $zero, draw_bubbles_skip

    # Convert colour index to its RGB value
    la      $s4, colours
    sll     $t0, $s3, 2
    add     $s4, $s4, $t0
    lw      $v1, 0($s4)

    # Convert grid position to screen coordinates
    addiu   $a0, $s2, 4
    addiu   $a1, $s1, 3

    li      $a2, 1
    li      $a3, 1

    jal     draw_rect

draw_bubbles_skip:

    addiu   $s0, $s0, 4
    addiu   $s2, $s2, 1

    j       draw_bubbles_col

draw_bubbles_next_row:

    addiu   $s1, $s1, 1
    j       draw_bubbles_row

draw_bubbles_done:

    lw      $s4, 0($sp)
    lw      $s3, 4($sp)
    lw      $s2, 8($sp)
    lw      $s1, 12($sp)
    lw      $s0, 16($sp)
    lw      $ra, 20($sp)

    addiu   $sp, $sp, 24
    jr      $ra


# Draw the player at a fixed position below the field
draw_player:

    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    # White head
    li      $a0, 7
    li      $a1, 18
    li      $a2, 1
    li      $a3, 1
    li      $v1, 0xffffff

    jal     draw_rect

    # Green body
    li      $a0, 7
    li      $a1, 19
    li      $a2, 1
    li      $a3, 2
    li      $v1, 0x00ff00

    jal     draw_rect

    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra


# Draw the complete game scene
draw_scene:

    addiu   $sp, $sp, -4
    sw      $ra, 0($sp)

    jal     draw_field
    jal     draw_bubbles
    jal     draw_player

    lw      $ra, 0($sp)
    addiu   $sp, $sp, 4
    jr      $ra
