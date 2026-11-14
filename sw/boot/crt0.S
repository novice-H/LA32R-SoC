    .section .text.boot,"ax",@progbits
    .align 2
    .globl _start
    .type _start, @function
_start:
    /* r3 is the stack pointer. Match link.ld's fixed BaseRAM upper bound.
       LA32 v2.0 la.local uses PC-relative relocation for section symbols;
       use an immediate for this absolute top-of-memory constant. */
    li.w      $r3, 0x1c400000

    /* Copy initialized data from its ROM/image LMA to its RAM VMA. */
    la.local  $r4, __data_load
    la.local  $r5, __data_start
    la.local  $r6, __data_end
1:
    bgeu      $r5, $r6, 2f
    ld.w      $r7, $r4, 0
    st.w      $r7, $r5, 0
    addi.w    $r4, $r4, 4
    addi.w    $r5, $r5, 4
    b         1b
2:
    /* Clear BSS in 32-bit words, matching the aligned linker boundaries. */
    la.local  $r4, __bss_start
    la.local  $r5, __bss_end
3:
    bgeu      $r4, $r5, 4f
    st.w      $r0, $r4, 0
    addi.w    $r4, $r4, 4
    b         3b
4:
    bl        main

    /* A returned main is a stable, externally observable halt point. */
    .globl _boot_halt
    .type _boot_halt, @function
_boot_halt:
    b         _boot_halt
    .size _boot_halt, .-_boot_halt
    .size _start, .-_start
