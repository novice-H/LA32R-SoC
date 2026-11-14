// Real CPU draws both complete frames. Compare sampled RGB against the host
// rasterizer; the host has separate independent per-pixel rendering tests.
reg [31:0] framebuffer_symbols [0:2];
reg [31:0] framebuffer_expected [0:119999];
reg framebuffer_monitor = 0;
reg framebuffer_previous_sel = 0;
reg framebuffer_previous_vsync = 0;
reg framebuffer_previous_request = 0;
integer framebuffer_flips = 0;
integer framebuffer_requests = 0;
integer framebuffer_writes = 0;

always @(posedge clk) begin
    if (reset_btn) begin
        framebuffer_previous_sel <= 0;
        framebuffer_previous_vsync <= 0;
        framebuffer_previous_request <= 0;
        framebuffer_flips <= 0;
        framebuffer_requests <= 0;
        framebuffer_writes <= 0;
    end else if (framebuffer_monitor) begin
        if (dut.u_soc.fb_sel != framebuffer_previous_sel) begin
            if (!framebuffer_previous_vsync || !framebuffer_previous_request)
                $fatal(1, "framebuffer selection changed outside a requested VSYNC boundary");
            framebuffer_flips <= framebuffer_flips + 1;
        end
        framebuffer_previous_sel <= dut.u_soc.fb_sel;
        framebuffer_previous_vsync <= dut.u_soc.vsync_start;
        framebuffer_previous_request <= dut.u_soc.u_conf.flip_req;
        if (dut.u_soc.c_req && dut.u_soc.c_ready && dut.u_soc.c_we &&
            dut.u_soc.c_addr == 8'h18 && dut.u_soc.c_wdata[0])
            framebuffer_requests <= framebuffer_requests + 1;
        if (dut.u_soc.e_req && dut.u_soc.e_ready && dut.u_soc.e_we) begin
            framebuffer_writes <= framebuffer_writes + 1;
            if ((!dut.u_soc.fb_sel &&
                 !(dut.u_soc.e_addr >= 131072 && dut.u_soc.e_addr < 251072)) ||
                (dut.u_soc.fb_sel && dut.u_soc.e_addr >= 120000))
                $fatal(1, "CPU framebuffer store outside back buffer: word=%h", dut.u_soc.e_addr);
            if (dut.u_soc.e_be_n != 4'h0)
                $fatal(1, "CPU framebuffer store used partial/unaligned byte lanes");
        end
    end
end

task automatic framebuffer_wait_step(input integer expected);
    integer cycles;
    bit found;
    begin
        cycles = 0;
        found = 0;
        while (!found && cycles < 20000000) begin
            @(negedge clk);
            if (leds[14]) $fatal(1, "CPU framebuffer firmware failed, WB PC=%h", dbg_wb_pc);
            found = dut.u_soc.c_req && dut.u_soc.c_ready && dut.u_soc.c_we &&
                    dut.u_soc.c_addr == 8'h00 && dut.u_soc.c_wdata == 32'(expected);
            cycles++;
        end
        if (!found) $fatal(1, "CPU framebuffer timeout STEP=%0d, WB PC=%h", expected, dbg_wb_pc);
    end
endtask

task automatic framebuffer_capture(input integer variant);
    integer pixels, cycles, mismatches, file_handle, word_index;
    reg [7:0] wanted;
    begin
        if (variant == 0) $readmemh("expected0.hex", framebuffer_expected);
        else              $readmemh("expected1.hex", framebuffer_expected);
        while (video_vsync) @(negedge clk);
        while (!video_vsync) @(negedge clk);
        pixels = 0;
        cycles = 0;
        mismatches = 0;
        while (pixels < 480000 && cycles < 1500000) begin
            @(negedge clk);
            cycles++;
            if (video_de) begin
                frame[pixels] = {video_red, video_green, video_blue};
                wanted = 8'(framebuffer_expected[pixels / 4] >> ((pixels % 4) * 8));
                if (frame[pixels] !== wanted) begin
                    if (mismatches < 8)
                        $display("PIXEL FAIL frame=%0d x=%0d y=%0d got=%h wanted=%h",
                                 variant, pixels % 800, pixels / 800, frame[pixels], wanted);
                    mismatches++;
                end
                pixels++;
            end
        end
        check32(32'(pixels), 480000, $sformatf("frame %0d complete pixel count", variant));
        check32(32'(mismatches), 0, $sformatf("frame %0d full RGB332 comparison", variant));
        file_handle = $fopen(variant == 0 ? "actual0.hex" : "actual1.hex", "w");
        if (file_handle == 0) $fatal(1, "cannot write sampled framebuffer");
        for (word_index = 0; word_index < 120000; word_index++)
            $fdisplay(file_handle, "%08x", {frame[word_index*4+3], frame[word_index*4+2],
                                           frame[word_index*4+1], frame[word_index*4]});
        $fclose(file_handle);
    end
endtask

task automatic run_framebuffer_scenarios;
    integer variant, cycles;
    begin
        $readmemh("framebuffer-symbols.hex", framebuffer_symbols);
        // Probe padding immediately beyond each valid buffer and before FB1.
        u_ext_ram.mem[120000] = 32'hdeadbeef;
        u_ext_ram.mem[131071] = 32'hdeadbeef;
        u_ext_ram.mem[251072] = 32'hdeadbeef;
        framebuffer_monitor = 1;
        for (variant = 0; variant < 2; variant++) begin
            framebuffer_wait_step(variant + 1);
            $display("FRAMEBUFFER: CPU drawing variant %0d into back buffer", variant);
            $fflush();
            framebuffer_wait_step(101 + variant);
            check32({31'd0, dut.u_soc.fb_sel}, variant == 0 ? 1 : 0,
                    $sformatf("frame %0d hardware display buffer", variant));
            framebuffer_capture(variant);
            dip_sw = 32'(variant + 1);
        end
        framebuffer_wait_step(3);
        // Keep the request far from vertical blank for deterministic zero-time
        // present/begin timeouts, then let the actual scanout finish both flips.
        while (!(dut.u_soc.u_vga.vcnt == 100 && dut.u_soc.u_vga.hcnt == 100))
            @(negedge clk);
        dip_sw = 3;
        framebuffer_wait_step(103);
        framebuffer_wait_step(1234);
        cycles = 0;
        while ((!leds[13] || dbg_wb_pc != framebuffer_symbols[2]) && cycles < 10000) begin
            @(negedge clk);
            cycles++;
        end
        check32(dbg_wb_pc, framebuffer_symbols[2], "framebuffer main returned to boot halt");
        check32(u_base_ram.mem[(framebuffer_symbols[0] - 'h1c000000) >> 2],
                32'h600dfb00, "CPU framebuffer result");
        check32(u_base_ram.mem[(framebuffer_symbols[1] - 'h1c000000) >> 2],
                22, "CPU framebuffer assertions");
        check32(32'(framebuffer_requests), 4, "exactly four accepted flip requests");
        check32(32'(framebuffer_flips), 4, "exactly four VSYNC flips");
        check32(u_ext_ram.mem[120000], 32'hdeadbeef, "FB0 upper guard");
        check32(u_ext_ram.mem[131071], 32'hdeadbeef, "FB1 lower guard");
        check32(u_ext_ram.mem[251072], 32'hdeadbeef, "FB1 upper guard");
        $display("FRAMEBUFFER: %0d aligned CPU framebuffer stores checked", framebuffer_writes);
    end
endtask
