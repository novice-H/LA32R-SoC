/* 全系统冒烟测试 v2：整屏填充 + 边框
 *
 *   背景：深蓝 0x03（RGB332）
 *   顶边：粉   0xEF（第 0 行整行）
 *   底边：白   0xFF（第 599 行整行）
 *   左右：白   0xFF（第 0 列、第 796..799 列）
 *   结束后写 STATUS[13]=1，死循环
 */
    .text
    .globl _start
_start:
    li.w    $r4, 0xbfd00000      /* confreg */
    li.w    $r6, 1234
    st.w    $r6, $r4, 0          /* STEP = 1234 */

    /* 1) 整屏填充深蓝 0x03（120000 字） */
    li.w    $r5, 0x1c400000
    li.w    $r7, 0x03030303
    li.w    $r8, 120000
1:  st.w    $r7, $r5, 0
    addi.w  $r5, $r5, 4
    addi.w  $r8, $r8, -1
    bne     $r8, $r0, 1b

    /* 2) 顶边粉色（第 0 行，200 字） */
    li.w    $r5, 0x1c400000
    li.w    $r7, 0xefefefef
    li.w    $r8, 200
2:  st.w    $r7, $r5, 0
    addi.w  $r5, $r5, 4
    addi.w  $r8, $r8, -1
    bne     $r8, $r0, 2b

    /* 3) 底边白色（第 599 行，偏移 599*800 = 0x74FE0，200 字） */
    li.w    $r5, 0x1c400000
    li.w    $r9, 0x74fe0
    add.w   $r5, $r5, $r9
    li.w    $r7, 0xffffffff
    li.w    $r8, 200
3:  st.w    $r7, $r5, 0
    addi.w  $r5, $r5, 4
    addi.w  $r8, $r8, -1
    bne     $r8, $r0, 3b

    /* 4) 左右两列白色（600 行，每行 x=0 与 x=796 两个点） */
    li.w    $r5, 0x1c400000
    li.w    $r7, 0xffffffff
    li.w    $r8, 600
4:  st.w    $r7, $r5, 0
    st.w    $r7, $r5, 796
    addi.w  $r5, $r5, 800
    addi.w  $r8, $r8, -1
    bne     $r8, $r0, 4b

    /* 5) 完成标志 */
    li.w    $r6, 0x2000
    st.w    $r6, $r4, 4

5:  b 5b
