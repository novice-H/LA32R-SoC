# ---------------------------------------------------------------------------
# config_vtg.xdc —— 全局配置属性（与引脚无关，故不放进 gen_xdc.py 的自动生成区）
#
# 为什么单独一个文件：
#   constraints/thinpad_top.xdc 由 tools/gen_xdc.py 从引脚对照表自动生成、
#   标注了"请勿手改"，重新生成会覆盖手工添加的内容。这两个属性是设计级
#   （不是引脚级）的，放在独立文件里更安全。
#
# 作用：
#   缺这两条时 write_bitstream 会因 CFGBVS / CONFIG_VOLTAGE 未指定而报
#   DRC/关键告警。薄板 BANK0 配置口按 VCCO 判定，电压 3.3V。
# ---------------------------------------------------------------------------

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
