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


#HOW WE DRAW THE BOARD QUICKLY
target:     #start of loop
sw $t7, 28($t0)          # paint shows yellow
addi $t0, $t0, 4         #move $to to the next pixel location of memory

j target                # jump to start of loop


sw $t3, 128($t0)        # paint the first unit on the second row blue