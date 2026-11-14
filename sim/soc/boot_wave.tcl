# GTKWave startup view for tb_soc_top. API usage follows the installed
# GTKWave examples/des.tcl. Use: gtkwave soc.vcd -S boot_wave.tcl
set selected [list]
set wanted {clk reset_btn dbg_wb_pc leds dpy0 dpy1 base_ram_addr
    base_ram_data base_ram_ce_n base_ram_oe_n base_ram_we_n
    ext_ram_addr ext_ram_data ext_ram_ce_n ext_ram_oe_n ext_ram_we_n
    video_de video_vsync}
for {set i 0} {$i < [gtkwave::getNumFacs]} {incr i} {
    set name [gtkwave::getFacName $i]
    if {![regexp {(^|\.)tb_soc_top\.[^.]+$} $name]} {continue}
    set leaf [lindex [split $name .] end]
    regsub {\[.*\]$} $leaf {} leaf
    if {[lsearch -exact $wanted $leaf] >= 0} {lappend selected $name}
}
puts "CPP_BOOT_VIEW: [gtkwave::addSignalsFromList $selected] signals added"
gtkwave::/Time/Zoom/Zoom_Full
