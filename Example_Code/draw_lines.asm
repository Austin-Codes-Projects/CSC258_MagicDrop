.data
displayaddress:   .word 0x10008000

# ...
.text
# ...

li $t1, 0xff0000    # red colour
li $t2, 0x00ff00    # green colour
li $t3, 0x0000ff    # blue colour




add $t4, $t1, $t3  # t4 = magenta 
add $t5, $t2, $t3  # t5 = cyan
add $t6, $t1, $t2  # t6 = yellow
add $t7, $t6, $t3  # t7 = white

lw $t0, displayaddress   # $t0 = base address for display
sw $t1, 0($t0)          # paint first unit (top-left) red
sw $t2, 4($t0)          # paint second unit on the first row green
sw $t4, 8($t0)          # paint shows magenta
sw $t5, 12($t0)          # paint shows blue
sw $t6, 16($t0)          # paint shows yellow
sw $t3, 128($t0)        # paint the first unit on the second row blue


#HOW WE DRAW THE BOARD QUICKLY
# infinite loop that fills board with white 

add $t8, $t0 ,$zero    #copy $t0 into $t8
addi $t9, $zero, 5

target:     #start of loop
sw $t7, 256($t8)          # paint shows yellow
addi $t8, $t8, 4         #move $to to the next pixel location of memory
addi $t9,$t9, -1         #decrement $t9 by 1
beq $t9, $zero, end     #break out of loop
j target                # jump to start of loop

end:




draw_line:
# The Line drawing code
# $t0 The location in memory of the top-left corner of the bitmap
# $t1 The x coordinate of the start of the line
# $t2 The y coordinate of the start of the line
# $t3 The length of the line
# $t5 The Colour of the line


# Calculate Horizontal offset from the leftmost column

sll $t1,$t1, 2 #multiplying $t1 by 4 to get the offset in bytes
#calculate the vertical offset from the first row
sll $t2,$t2, 7 # add the horizontal offset to $t0, store in $t8

add $t8, $t0, $t1 # addthe horisontal offset to $t0, store in $t8
add $t8, $t8, $t2 # add the vertical offset to $t8

line_loop_start:
beq $t3, $zero, line_loop_end # checking if we reached the end of the line
addi $t3, $t3, -1  #decrement the loop var(length of the line)
sw $t5, 0($t8)      #store a pixel in the current location in memory
add $t8 $t8, 4   # move to next pixel line
j line_loop_start

line_loop_end:

