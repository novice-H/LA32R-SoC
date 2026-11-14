ENTRY(_start)
SECTIONS {
  . = 0x1C000000;
  .text : {
    *(.text.entry)
    *(.text*)
  }
  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }
  .bss : {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  }
}
