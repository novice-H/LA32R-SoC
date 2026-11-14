/* 最小启动代码：设置栈、清零 .bss、调用 ai_bench_main */
    .section .text.entry, "ax"
    .globl _start
_start:
    li.w    $sp, 0x1C3FF000          /* BaseRAM 顶端作栈 */
    la.local $r4, __bss_start
    la.local $r5, __bss_end
1:  bgeu    $r4, $r5, 2f
    st.w    $r0, $r4, 0
    addi.w  $r4, $r4, 4
    b       1b
2:  bl      ai_bench_main
3:  b       3b
