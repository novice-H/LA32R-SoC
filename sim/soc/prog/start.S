/* 全系统仿真的最小裸机程序（openLA500，DA=1 直接地址） */
    .text
    .globl _start
_start:
    li.w    $r4, 0xbfd00000      /* confreg 基址 */
    li.w    $r5, 0x1c400000      /* FB0 基址 */

    /* STEP = 1234 -> LED[4:0]=12，数码管 34 */
    li.w    $r6, 1234
    st.w    $r6, $r4, 0

    /* FB0 第 0 行（200 字 = 800 像素）填 0xEFEFEFEF */
    li.w    $r7, 0xefefefef
    li.w    $r8, 200
1:  st.w    $r7, $r5, 0
    addi.w  $r5, $r5, 4
    addi.w  $r8, $r8, -1
    bne     $r8, $r0, 1b

    /* FB0 第 200 字（第 1 行前 4 像素）= 0xE0E0E0E0（红） */
    li.w    $r5, 0x1c400000
    addi.w  $r5, $r5, 800
    li.w    $r7, 0xe0e0e0e0
    st.w    $r7, $r5, 0

    /* STATUS[13] = 1（WIN 标志，供仿真判定程序跑完） */
    li.w    $r6, 0x2000
    st.w    $r6, $r4, 4

2:  b 2b
