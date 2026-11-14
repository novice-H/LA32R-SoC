@echo off
REM 在 Windows 上一键生成 bit：双击本文件，或在 cmd 里运行
REM 需要 Vivado 已安装；若不在 PATH 中，请修改下面的 VIVADO_BIN。

setlocal
set SCRIPT_DIR=%~dp0

set VIVADO_BIN=vivado
where %VIVADO_BIN% >nul 2>nul
if errorlevel 1 (
    if exist "C:\Xilinx\Vivado\2023.2\bin\vivado.bat" (
        set VIVADO_BIN=C:\Xilinx\Vivado\2023.2\bin\vivado.bat
    ) else (
        echo [ERROR] 找不到 vivado，请把 VIVADO_BIN 改成实际安装路径
        exit /b 1
    )
)

call "%VIVADO_BIN%" -mode batch -source "%SCRIPT_DIR%build_bit.tcl" -notrace ^
    -log "%SCRIPT_DIR%build_bit.log" -journal "%SCRIPT_DIR%build_bit.jou"

if errorlevel 1 (
    echo [ERROR] 生成失败，见 vivado\build_bit.log
    exit /b 1
)

echo.
echo [OK] bit 位于 vivado\build\thinpad\thinpad_top.bit
endlocal
