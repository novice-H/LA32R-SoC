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
                # 不要在这里调 generate_target：
                #   openLA500 的 IP 是 .xcix 容器，generate_target 会把产物
                #   回写进 .xcix 本体（跟踪文件，会被改动成脏状态）。
                #   下面用 launch_runs 的工程运行流，Vivado 会在
                #   runs 目录里自行生成输出产物并做 OOC 综合。
            }
        }
    }

    # ------------------------------------------------------------ 约束
    add_files -fileset constrs_1 -norecurse $ROOT/constraints/thinpad_top.xdc
    add_files -fileset constrs_1 -norecurse $ROOT/constraints/config_vtg.xdc
    set_property top $TOP [current_fileset]

    file mkdir [file join $PROJ_DIR reports]

    # ------------------------------------------------------------ 综合/实现（工程运行流）
    # 必须用 launch_runs，不能直接调用 synth_design：
    #   openLA500 的 cache SRAM 是 .xcix 容器形式提供的，只有 Vivado 的
    #   run 管理会去解包容器、生成输出产物并做 OOC 综合。直接 synth_design
    #   时容器里的模块不可见，会报：
    #     ERROR: [Synth 8-439] module 'data_bank_sram' not found
    #   而 dcache.v 里同名模块只是 `ifdef SIMU 下的行为兜底，综合时不存在。
    puts "==> launch_runs synth_1"
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "synth_1 失败（status=[get_property STATUS [get_runs synth_1]]），见 $PROJ_DIR/thinpad.runs/synth_1/runme.log"
    }

    puts "==> launch_runs impl_1 -to_step write_bitstream"
    # 实现策略：默认策略在 openLA500 的 TLB 匹配路径上有约 -0.5ns 违例
    # （该路径布线延迟占 72%，且东向拥塞达 97%，属布局/拥塞问题而非逻辑深度）。
    # Performance_ExplorePostRoutePhysOpt 会在布线后追加物理优化，
    # 对"布线占比高"的违例最有效，且不需要改动任何 RTL。
    catch { set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1] }
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "impl_1 失败（status=[get_property STATUS [get_runs impl_1]]），见 $PROJ_DIR/thinpad.runs/impl_1/runme.log"
    }

    # ------------------------------------------------------------ 报告
    open_run impl_1 -quiet
    report_utilization    -file [file join $PROJ_DIR reports utilization.rpt]
    report_timing_summary -file [file join $PROJ_DIR reports timing_summary.rpt]
    report_drc            -file [file join $PROJ_DIR reports drc.rpt]
    report_power          -file [file join $PROJ_DIR reports power.rpt]

    # ------------------------------------------------------------ bit
    # impl_1 生成的 bit 名字取自顶层模块，再复制到约定的 $BIT 路径
    set impl_bit [file join $PROJ_DIR thinpad.runs impl_1 ${TOP}.bit]
    if {![file exists $impl_bit]} {
        error "impl_1 已跑完但找不到 bit：$impl_bit"
    }
    file copy -force $impl_bit $BIT

    # 再放一份到入库的交付目录：
    #   vivado/build/  整个构建目录被 .gitignore 忽略（本地产物，不入库）
    #   vivado/artifacts/ 是交付目录，.gitignore 里对 *.bit 做了例外，会入版本库
    # 这样构建完成后 git status 能直接看到需要提交的新 bit。
    set ART_DIR [file join $ROOT vivado artifacts]
    file mkdir $ART_DIR
    file copy -force $impl_bit [file join $ART_DIR ${TOP}.bit]
    puts " 交付副本 : [file join $ART_DIR ${TOP}.bit]"

    # ------------------------------------------------------------ 时序检查
    # 把时序结果显式打到控制台：Vivado 即使时序不收敛也会照常生成 bit，
    # 不主动检查就很容易带着违例的 bit 去上板。
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
    puts "============================================================"
    puts " WNS (setup) : $wns ns"
    puts " WHS (hold)  : $whs ns"
    if {$wns < 0} {
        puts " WARNING: 时序未收敛！bit 已生成但可能不可靠。"
        puts "          详见 [file join $PROJ_DIR reports timing_summary.rpt]"
    } else {
        puts " 时序已收敛"
    }
    puts "============================================================"

    puts "============================================================"
    puts " BITSTREAM : $BIT"
    puts "============================================================"

} err]} {
    puts "ERROR: $err"
    exit 1
}
