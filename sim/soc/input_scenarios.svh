// Included inside tb_soc_top. CPU firmware announces phases through STEP;
// physical button/DIP pins are the stimulus, and all BTN reads go through CPU.
integer input_reads = 0;
integer input_nonzero_reads = 0;
reg [31:0] input_last_nonzero = 0;
reg input_button_response = 0;
reg [31:0] input_symbols [0:2];

always @(posedge clk) begin
    if (reset_btn) begin
        input_reads <= 0;
        input_nonzero_reads <= 0;
        input_last_nonzero <= 0;
        input_button_response <= 0;
    end else begin
        input_button_response <= dut.u_soc.c_req && dut.u_soc.c_ready &&
                                 !dut.u_soc.c_we && dut.u_soc.c_addr == 8'h08;
        if (input_button_response && dut.u_soc.c_rsp_valid) begin
            input_reads <= input_reads + 1;
            if (dut.u_soc.c_rsp_rdata != 0) begin
                input_nonzero_reads <= input_nonzero_reads + 1;
                input_last_nonzero <= dut.u_soc.c_rsp_rdata;
            end
        end
    end
end

task automatic input_wait_step(input integer expected);
    integer cycles;
    bit found;
    begin
        cycles = 0;
        found = 0;
        while (!found && cycles < 100000) begin
            @(negedge clk);
            if (leds[14])
                $fatal(1, "CPU input firmware failed; waiting STEP=%0d, WB PC=%h", expected, dbg_wb_pc);
            found = dut.u_soc.c_req && dut.u_soc.c_ready && dut.u_soc.c_we &&
                    dut.u_soc.c_addr == 8'h00 && dut.u_soc.c_wdata == 32'(expected);
            cycles++;
        end
        if (!found) $fatal(1, "CPU input phase timeout STEP=%0d, WB PC=%h", expected, dbg_wb_pc);
    end
endtask

task automatic run_input_scenarios;
    integer phase, reads_before, nonzero_before, expected_reads, cycles;
    reg [31:0] expected_mask;
    begin
        $readmemh("input-symbols.hex", input_symbols);
        for (phase = 1; phase <= 12; phase++) begin
            input_wait_step(phase);
            reads_before = input_reads;
            nonzero_before = input_nonzero_reads;
            expected_mask = 0;
            case (phase)
                1: begin touch_btn = 4'h1; expected_mask = 1; expected_reads = 11; end
                2: begin touch_btn = 4'h4; expected_mask = 4; expected_reads = 3; end
                3: begin touch_btn = 4'h2; expected_mask = 2; expected_reads = 3; end
                4: begin touch_btn = 4'h8; expected_mask = 8; expected_reads = 3; end
                5: begin touch_btn = 4'hf; expected_mask = 15; expected_reads = 4; end
                6: begin
                    touch_btn = 1; repeat (8) @(negedge clk);
                    touch_btn = 0; repeat (8) @(negedge clk);
                    touch_btn = 2; repeat (8) @(negedge clk);
                    touch_btn = 0;
                    expected_mask = 3; expected_reads = 4;
                end
                7: begin
                    touch_btn = 1; repeat (8) @(negedge clk);
                    touch_btn = 0; repeat (8) @(negedge clk);
                    touch_btn = 1; repeat (8) @(negedge clk);
                    touch_btn = 0;
                    expected_mask = 1; expected_reads = 3;
                end
                8: begin touch_btn = 1; expected_mask = 1; expected_reads = 3; end
                9: begin touch_btn = 15; expected_mask = 15; expected_reads = 4; end
                10: begin touch_btn = 15; expected_mask = 15; expected_reads = 3; end
                11, 12: begin touch_btn = 0; expected_reads = 2; end
                default: $fatal(1, "unexpected input phase");
            endcase
            // CPU waits on KEY until the synchronized edges have accumulated.
            repeat (8) @(negedge clk);
            dip_sw = phase == 11 ? 32'hffff_fffd :
                     phase == 12 ? 32'hffff_fffe : 32'hffff_ffff;
            input_wait_step(100 + phase);
            check32(32'(input_reads - reads_before), 32'(expected_reads),
                    $sformatf("input phase %0d CPU BTN read count", phase));
            check32(32'(input_nonzero_reads - nonzero_before), phase <= 10 ? 32'd1 : 32'd0,
                    $sformatf("input phase %0d one accumulated event snapshot", phase));
            if (phase <= 10)
                check32(input_last_nonzero, expected_mask,
                        $sformatf("input phase %0d raw BTN bits before read-clear", phase));
            $display("INPUT_PHASE: %0d completed by CPU", phase);
            touch_btn = 0;
            repeat (8) @(negedge clk);
            dip_sw = 0;
        end
        input_wait_step(1234);
        cycles = 0;
        while ((!leds[13] || dbg_wb_pc != input_symbols[2]) && cycles < 10000) begin
            @(negedge clk);
            cycles++;
        end
        check32({31'd0, leds[13]}, 1, "input firmware completion status");
        check32(dbg_wb_pc, input_symbols[2], "input main returned to boot halt");
        check32(u_base_ram.mem[(input_symbols[0] - 'h1c000000) >> 2],
                32'h600d1a00, "CPU input firmware result");
        check32(u_base_ram.mem[(input_symbols[1] - 'h1c000000) >> 2],
                49, "CPU input assertions completed");
        check32({27'd0, leds[4:0]}, 12, "input test STEP LED output");
        check32({24'd0, dpy1}, 32'hb6, "input test seven-segment tens");
        check32({24'd0, dpy0}, 32'hd2, "input test seven-segment units");
    end
endtask
