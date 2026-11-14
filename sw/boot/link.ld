OUTPUT_ARCH(loongarch)
ENTRY(_start)

MEMORY
{
    baseram (rwx) : ORIGIN = 0x1c000000, LENGTH = 4M
}

SECTIONS
{
    . = ORIGIN(baseram);
    .text : ALIGN(4)
    {
        KEEP(*(.text.boot))
        *(.text .text.*)
    } > baseram

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
    } > baseram

    /* The data image follows rodata in the load image. The output section
       below has a page-aligned RAM VMA and this compact LMA for startup copy. */
    __data_load = ALIGN(., 4);
    .data ALIGN(4096) : AT(__data_load)
    {
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        *(.got .got.*)
        . = ALIGN(4);
        __data_end = .;
    } > baseram

    .bss ALIGN(4) (NOLOAD) :
    {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > baseram

    .init_array :
    {
        KEEP(*(.init_array .init_array.*))
    } > baseram

    __stack_top = 0x1c400000;
    __stack_reserve = 16K;

    ASSERT(__data_start % 4096 == 0, ".data VMA must be 4 KiB aligned")
    ASSERT(__data_load % 4 == 0, ".data LMA must be word aligned")
    ASSERT(__data_start % 4 == 0 && __data_end % 4 == 0,
           ".data bounds must be word aligned")
    ASSERT(__bss_start % 4 == 0 && __bss_end % 4 == 0,
           ".bss bounds must be word aligned")
    ASSERT(SIZEOF(.init_array) == 0, "dynamic C++ initialization is unsupported")
    ASSERT(__stack_top == ORIGIN(baseram) + LENGTH(baseram),
           "stack top must match the 4 MiB BaseRAM boundary")
    ASSERT(__bss_end <= __stack_top - __stack_reserve,
           "BaseRAM image overlaps the reserved 16 KiB stack")
    ASSERT(__data_load + SIZEOF(.data) <= __data_start,
           ".data load image overlaps its RAM VMA")

    /DISCARD/ :
    {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
        *(.gcc_except_table .gcc_except_table.*)
    }
}
