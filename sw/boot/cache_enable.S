/* 在 DA 模式与 PG+DMW 模式之间切换，用于打开/关闭 I/D-Cache。
 *
 * 地址映射（PG 模式）：
 *   DMW0: VSEG=0 -> PA 段 0，MAT=1（可缓存） 覆盖 0x0000_0000-0x1FFF_FFFF
 *         （代码、栈、BaseRAM、ExtRAM/FB 都在这一段）
 *   DMW1: VSEG=5 -> PA 段 5，MAT=0（不缓存） 覆盖 0xA000_0000-0xBFFF_FFFF
 *         （confreg 的 0xBFD0_0000；MMIO 不能被缓存）
 *
 * 注意：ExtRAM 里的帧缓冲也会变成可缓存，写完需要 cache 写回或切回 DA，
 * 否则 VGA 可能读到旧数据。
 */
    .section .text.cache, "ax"

    .globl boot_enable_caches
    .type  boot_enable_caches, @function
boot_enable_caches:
    li.w    $r4, 0x00000011        /* DMW0: VSEG0 PSEG0 MAT=1 PLV0 */
    csrwr   $r4, 0x180
    li.w    $r4, 0xaa000001        /* DMW1: VSEG5 PSEG5 MAT=0 PLV0 */
    csrwr   $r4, 0x181
    li.w    $r4, 0x00000010        /* CRMD: PG=1, DA=0 */
    csrwr   $r4, 0x0
    ibar 0
    jirl $r0, $r1, 0

    .globl boot_disable_caches
    .type  boot_disable_caches, @function
boot_disable_caches:
    li.w    $r4, 0x00000008        /* CRMD: DA=1, PG=0 */
    csrwr   $r4, 0x0
    ibar 0
    jirl $r0, $r1, 0

    .size boot_enable_caches, .-boot_enable_caches
