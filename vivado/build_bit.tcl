# -----------------------------------------------------------------------------
# build_bit.tcl —— 从零创建 Vivado 工程并生成 bit
#
# 用法（Windows / Linux 均可，在仓库根目录或任意目录执行）：
#   vivado -mode batch -source vivado/build_bit.tcl -notrace
#
# 产物：
#   vivado/build/thinpad/thinpad_top.bit
#   vivado/build/thinpad/reports/*.rpt
# -----------------------------------------------------------------------------

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR ..]]
set PROJ_DIR   [file join $ROOT vivado build thinpad]
set PART       "xc7a200tfbg676-2"
set TOP        "thinpad_top"
set BIT        [file join $PROJ_DIR ${TOP}.bit]

# 是否强制使用行为 SRAM（跳过 CPU 的 cache IP）。
#   0 = 优先用 soc/cpu/open-la500/IP/*.xcix（正式）
#   1 = 定义 SIMU，用可推断 BRAM（仅功能兜底，时序/面积不同）
set USE_INFERRED_SRAM 0

puts "============================================================"
puts " ROOT     : $ROOT"
puts " PROJ_DIR : $PROJ_DIR"
puts " PART     : $PART"
puts " TOP      : $TOP"
puts "============================================================"

file mkdir $PROJ_DIR

if {[catch {

    # ------------------------------------------------------------ 建工程
    create_project -force thinpad $PROJ_DIR -part $PART

    # ------------------------------------------------------------ RTL
    add_files -norecurse [list \
        $ROOT/soc/thinpad_top.v \
        $ROOT/soc/soc_top.v \
        $ROOT/soc/confreg.v \
        $ROOT/soc/vga_fb.v \
    ]

    add_files -norecurse [glob -nocomplain $ROOT/soc/bus/*.v]
    add_files -norecurse [glob -nocomplain $ROOT/soc/mem/*.v]
    add_files -norecurse [glob -nocomplain $ROOT/soc/cpu/open-la500/*.v]

    set_property include_dirs [list $ROOT/soc/cpu/open-la500] [get_filesets sources_1]

    # ------------------------------------------------------------ CPU cache IP
    set ip_files [glob -nocomplain $ROOT/soc/cpu/open-la500/IP/*.xcix]
    if {$USE_INFERRED_SRAM} {
        puts "NOTE: USE_INFERRED_SRAM=1，使用行为 SRAM（SIMU）"
        set_property verilog_define {SIMU} [get_filesets sources_1]
    } elseif {[llength $ip_files] == 0} {
        puts "WARNING: 找不到 .xcix，回退到行为 SRAM（SIMU）"
        set_property verilog_define {SIMU} [get_filesets sources_1]
    } else {
        if {[catch {add_files -norecurse $ip_files} err]} {
            puts "WARNING: 添加 IP 失败：$err"
            puts "WARNING: 回退到行为 SRAM（SIMU）"
            set_property verilog_define {SIMU} [get_filesets sources_1]
        } else {
            # IP 可能来自旧版本 Vivado，尝试升级到当前版本
            set ip_count 0
            catch {set ip_count [llength [get_ips]]}
            if {$ip_count == 0} {
                puts "WARNING: .xcix 未被识别为 IP，回退到行为 SRAM（SIMU）"
                set_property verilog_define {SIMU} [get_filesets sources_1]
            } else {
                catch {upgrade_ip -quiet [get_ips]}
                puts "IP: $ip_count 个"
            }
        }
    }

    # ------------------------------------------------------------ 约束
    add_files -fileset constrs_1 -norecurse $ROOT/constraints/thinpad_top.xdc
    set_property top $TOP [current_fileset]

    # ------------------------------------------------------------ 综合/实现
    synth_design -top $TOP -part $PART

    # 配置电压属性（避免 write_bitstream 的 CFGBVS 检查告警）
    catch { set_property CFGBVS VCCO       [current_design] }
    catch { set_property CONFIG_VOLTAGE 3.3 [current_design] }

    opt_design
    place_design
    route_design

    # ------------------------------------------------------------ 报告
    file mkdir [file join $PROJ_DIR reports]
    report_utilization    -file [file join $PROJ_DIR reports utilization.rpt]
    report_timing_summary -file [file join $PROJ_DIR reports timing_summary.rpt]
    report_drc            -file [file join $PROJ_DIR reports drc.rpt]
    report_power          -file [file join $PROJ_DIR reports power.rpt]

    # ------------------------------------------------------------ bit
    write_bitstream -force $BIT

    puts "============================================================"
    puts " BITSTREAM : $BIT"
    puts "============================================================"

} err]} {
    puts "ERROR: $err"
    exit 1
}
