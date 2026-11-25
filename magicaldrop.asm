################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Austin Sunesh, 1011054001
# Student 2: Name, Student Number (if applicable)
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
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL:
    .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:
    .word 0xffff0000

##############################################################################
# Mutable Data
##############################################################################
    grid: .space 392
    player_col: .word 3
    hold_colour: .word 0
    hold_count: .word 0
    key_count: .word 0
    game_over: .word 0
    score: .word 0
    chain_depth: .word 0
    colours: .word 0x000000, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00   # empty, red, green, blue, yellow
    
    
    #Randomizer 
    lcg_seed:   .word 0


##############################################################################
# Code
##############################################################################
	.text
	.globl main

    # Run the game.
    
    
main:
    # Initialize random seed
    li $v0, 30   # We are loading the current system call into register $v0, 30 is the system call to get the current system time
    syscall     # This does the service of getting the current system time.
    sw $a0, lcg_seed # Now we are saving the current system time int $a0
    
    #init grid
    jal init_grid # jump to were grid is intialized 
    
    #init screen 
    jal game_loop # jump to were the game is starting
    
    
game_loop:


    # 1a. Check if key has been pressed
    # 1b. Check which key has been pressed
    # 2a. Check for collisions
	# 2b. Update locations (capsules)
	
	
	# 3. Draw the screen
	jal draw_scene  # Drawing the scene 
	
	# 4. Sleep
	li $v0, 32  # selects the syscall 32 which is sleeping in MARS
	li $a0, 16  # Is setting the sleeping to 16 milliseconds, we do this so we can control the amount of updates the game does
	syscall

    # 5. Go back to Step 1
    j game_loop # Repeating the game 



    
# FUNCTIONS 
#draw rec for bitmap display
draw_rect:
    # $a0 is x position, $a1 is y position, $a2 is width, $a3 is height, $v1 is the colour
    # now we can draw the full rectangle in bitmap
        
    lw      $t0, ADDR_DSPL  # loading the display address into a temp register 
    
    
    
    
    
    
    
    
    jr $ra
    
        
        
        
        
        
    # draw game field and background
draw_field:
    jr $ra
random_colour:
    jr $ra
        
init_grid:
    jr $ra
    
draw_bubble:
    jr $ra
    
draw_player:
    jr $ra
    
draw_scene: 
    jr $ra
        