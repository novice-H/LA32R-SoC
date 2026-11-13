ENTRY(_start)
SECTIONS {
  . = 0x1C000000;
  .text   : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }
  .bss    : { *(.bss*) }
}
