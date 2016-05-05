# josephus.asm# based on http://rosetacode.org/wiki/Josephus_problem#C
# designed as test file

entry:          j main

# input: $a0 = m, $a1 = n, s.t. m >= 0, n > 0
# output: $a0 = m%n
mod:            slt $t0, $a0, $a1
                bne $t0, $zero, mod_ret
                sub $a0, $a0, $a1
                j mod

mod_ret:        jr $ra

# jos: given n people, kill every kth starting with person 1
# m is the index of the reverse kill list, that is at m = 0,
# jos returns the last surviver (Josephus) numbered on 0 to n - 1
# $a0 = n, $a1 = k, $a2 = m, s.t n >= 1, m < n, k > 1
jos:            addi $sp, $sp, -20
                sw   $ra, 16($sp)
                sw   $s3, 12($sp)
                sw   $s2, 8($sp)
                sw   $s1, 4($sp)
                sw   $s0, 0($sp)

                addi $s0, $a0, 0        # n = $a0
                addi $s1, $a1, 0        # k = $a1
                addi $s2, $a2, 0        # m = $a2
                addi $s3, $s2, 1        # a = m +1

jos_for:        slt  $t0, $s0, $s3       # $t0 = (n < a), eqv !(a <= n)
                bne  $t0, $zero, jos_ret # if (a <= n) goto jos_ret

                add  $a0, $s2, $s1      # $a0 = m + k
                addi $a1, $s3, 0        # $a1 = a
                jal mod
                addi $s2, $a0, 0        # m = $a0

                addi $s3, $s3, 1        # a++
                j    jos_for

jos_ret:        addi $v0, $s2, 0        # return m
                lw   $s0, 0($sp)        # restore the stack
                lw   $s1, 4($sp)
                lw   $s2, 8($sp)
                lw   $s3, 12($sp)
                lw   $ra, 16($sp)
                addi $sp, $sp, 20
                jr   $ra

error:          addi $at, $zero, 0xDEA     # use $at to mark failure
                sll  $at, $at, 12
                ori  $at, $at, 0xDBA
                sll  $at, $at, 8
                ori  $at, $at, 0xBE
                j    store_stat

main:           addi $sp, $zero, 0      # make the stack grow down from the top of memory
                addi $s0, $zero, 1      # checkpoint = 0

                # simple example
                # n = 5, k = 2, m = 0
                addi $a0, $zero, 5      # n = 5
                addi $a1, $zero, 2      # k = 2
                addi $a2, $zero, 0      # m = 0
                jal jos
                add  $s1, $zero, $v0    # store result for debugger
                addi $t0, $zero, 2
                bne  $s1, $t0, error

                addi $s0, $s0, 1        # update checkpoint

                # classic problem
                addi $a0, $zero, 41     # n = 41
                addi $a1, $zero, 3      # k = 3
                addi $a2, $zero, 0      # m = 0 (Josephus)
                jal jos
                add  $s2, $zero, $v0
                addi $t0, $zero, 30
                bne  $s2, $t0, error
                
                addi $s0, $s0, 1        # update checkpoint

                addi $a0, $zero, 41     # n = 41
                addi $a1, $zero, 3      # k = 3
                addi $a2, $zero, 1      # m = 1 (Other survivor)
                jal jos
                add  $s3, $zero, $v0
                addi $t0, $zero, 15
                bne  $s3, $t0, error

                addi $s0, $s0, 1        # update checkpoint

                ori $at, $zero, 0xCAF  #success constant for debugging
                sll  $at, $at, 8
                ori  $at, $at, 0xEB
                sll  $at, $at, 12
                ori  $at, $at, 0xABE

store_stat:     sw   $at, 4($zero)      # put notification in memory
exit:
