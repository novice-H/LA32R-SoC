// End-to-end CPU 2048 replay. The host replay uses the same game core and
// renderer to create the snapshot and full-frame reference data.
reg [31:0] game_symbols [0:0];
reg [31:0] game_expected [0:99];
reg [31:0] game_frame_expected [0:119999];

function automatic [31:0] game_word(input integer index);
    integer word_address;
    begin
        word_address = (int'(game_symbols[0]) - 'h1c000000) / 4 + index;
        game_word = u_base_ram.mem[word_address];
    end
endfunction

task automatic game_wait_serial(input integer wanted);
    integer cycles;
    begin
        cycles = 0;
        while (game_word(20) < 32'(wanted) && cycles < 60000000) begin
            @(negedge clk);
            cycles++;
            if (leds[14]) $fatal(1, "game firmware error, WB PC=%h", dbg_wb_pc);
        end
        if (game_word(20) != 32'(wanted))
            $fatal(1, "game render timeout serial=%0d wanted=%0d WB PC=%h",
                   game_word(20), wanted, dbg_wb_pc);
    end
endtask

// Fast full-frame recheck for changes confined to the renderer's glyph data.
task automatic run_game_image_scenarios;
    begin
        $readmemh("game-symbols.hex", game_symbols);
        $readmemh("game-expected.hex", game_expected);
        $readmemh("game-frame.hex", game_frame_expected);
        framebuffer_monitor = 1;
        dip_sw = 0;
        repeat (1000) @(negedge clk);
        dip_sw = 1;
        game_wait_serial(1);
        game_compare(0);
        game_capture_frame();
    end
endtask

task automatic game_compare(input integer frame_index);
    integer word_index;
    begin
        for (word_index = 0; word_index < 20; word_index++) begin
            if (game_word(word_index) !== game_expected[frame_index * 20 + word_index]) begin
                $display("GAME FAIL frame=%0d word=%0d got=%08x expected=%08x",
                         frame_index, word_index, game_word(word_index),
                         game_expected[frame_index * 20 + word_index]);
                errors++;
            end
        end
        if (dut.u_soc.u_conf.step !==
                (game_word(17) > 3199 ? 12'd3199 : 12'(game_word(17)))) begin
            $display("GAME FAIL confreg STEP=%0d expected moves=%0d",
                     dut.u_soc.u_conf.step, game_word(17));
            errors++;
        end
        if (game_word(18) == 0 && game_word(19) == 0 && leds[15:13] !== 3'b000) begin
            $display("GAME FAIL normal state STATUS LEDs=%b", leds[15:13]);
            errors++;
        end
        $display("GAME: snapshot %0d compared (serial=%0d)", frame_index, game_word(20));
        $fflush();
    end
endtask

task automatic game_press(input [3:0] key, input integer serial);
    begin
        touch_btn = key;
        repeat (100) @(negedge clk);
        touch_btn = 0;
        repeat (100) @(negedge clk);
        game_wait_serial(serial);
        game_compare(serial - 1);
    end
endtask

task automatic game_capture_frame;
    integer pixels, cycles, file_handle, mismatches, word_index;
    reg [31:0] expected_word, actual_words [0:119999];
    reg [7:0] expected_pixel;
    begin
        while (video_vsync) @(negedge clk);
        while (!video_vsync) @(negedge clk);
        pixels = 0;
        cycles = 0;
        mismatches = 0;
        file_handle = $fopen("game-actual.hex", "w");
        if (file_handle == 0) $fatal(1, "cannot write game framebuffer dump");
        while (pixels < 480000 && cycles < 1500000) begin
            @(negedge clk);
            cycles++;
            if (video_de) begin
                expected_word = game_frame_expected[pixels / 4];
                expected_pixel = 8'(expected_word >> ((pixels % 4) * 8));
                if ({video_red, video_green, video_blue} !== expected_pixel) begin
                    if (mismatches < 8)
                        $display("GAME PIXEL FAIL x=%0d y=%0d got=%h expected=%h",
                                 pixels % 800, pixels / 800,
                                 {video_red, video_green, video_blue}, expected_pixel);
                    mismatches++;
                end
                actual_words[pixels / 4][(pixels % 4) * 8 +: 8] =
                    {video_red, video_green, video_blue};
                pixels++;
            end
        end
        for (word_index = 0; word_index < 120000; word_index++)
            $fdisplay(file_handle, "%08x", actual_words[word_index]);
        $fclose(file_handle);
        check32(32'(pixels), 480000, "game complete VGA frame");
        check32(32'(mismatches), 0, "game initial board RGB332 frame");
        $display("GAME: dumped game-actual.hex (%0d RGB332 pixels)", pixels);
    end
endtask

task automatic run_game_scenarios;
    integer serial_before, moves_before, cycles;
    begin
        $readmemh("game-symbols.hex", game_symbols);
        $readmemh("game-expected.hex", game_expected);
        $readmemh("game-frame.hex", game_frame_expected);
        framebuffer_monitor = 1;
        dip_sw = 0;
        cycles = 0;
        while (game_word(21) != 0 && cycles < 20000000) begin
            @(negedge clk);
            cycles++;
        end
        repeat (1000) @(negedge clk);
        check32(game_word(21), 0, "game standby while DIP0");

        dip_sw = 1;
        game_wait_serial(1);
        check32(game_word(21), 1, "game active after DIP1");
        game_compare(0);

        // KEY1 is optional AI enable; the manual firmware keeps AI disabled.
        dip_sw = 3;

        game_press(4'h1, 2);
        game_press(4'h4, 3);
        game_press(4'h2, 4);
        game_press(4'h8, 5);

        serial_before = game_word(20);
        moves_before = game_word(17);
        touch_btn = 4'h1;
        game_wait_serial(serial_before + 1);
        repeat (200000) @(negedge clk);
        check32(game_word(20), 32'(serial_before + 1), "held key creates one render event");
        if (game_word(17) < 32'(moves_before) || game_word(17) > 32'(moves_before + 1)) begin
            $display("GAME FAIL held key changed move count from %0d to %0d",
                     moves_before, game_word(17));
            errors++;
        end
        touch_btn = 0;

        dip_sw = 0;
        cycles = 0;
        while (game_word(21) != 0 && cycles < 20000000) begin
            @(negedge clk);
            cycles++;
        end
        check32(game_word(21), 0, "game returns to standby after DIP0");
        serial_before = game_word(20);
        // Events generated while disabled must be discarded before a new game.
        touch_btn = 4'h8;
        repeat (1000) @(negedge clk);
        touch_btn = 0;
        repeat (1000) @(negedge clk);
        dip_sw = 1;
        game_wait_serial(serial_before + 1);
        repeat (200000) @(negedge clk);
        check32(game_word(20), 32'(serial_before + 1), "standby events discarded at restart");
        game_compare(0);
        game_capture_frame();
        check32(game_word(21), 1, "game active after restart");
    end
endtask

task automatic game_live_check(input integer stage);
    integer tile_index, occupied;
    reg [31:0] value;
    begin
        occupied = 0;
        for (tile_index = 0; tile_index < 16; tile_index++) begin
            value = game_word(tile_index);
            if (value != 0) begin
                occupied++;
                if (value != 2 && value != 4 && !(stage != 0 && value == 8)) begin
                    $display("GAME LIVE FAIL stage=%0d tile[%0d]=%0d",
                             stage, tile_index, value);
                    errors++;
                end
            end
        end
        if (stage == 0) begin
            check32(32'(occupied), 2, "live initial board has two tiles");
            check32(game_word(16), 0, "live initial score");
            check32(game_word(17), 0, "live initial moves");
            check32(game_word(18), 0, "live initial won flag");
            check32(game_word(19), 0, "live initial over flag");
        end else begin
            if (occupied != 2 && occupied != 3) begin
                $display("GAME LIVE FAIL post-Left tile count=%0d", occupied);
                errors++;
            end
            if (game_word(17) > 1) begin
                $display("GAME LIVE FAIL post-Left moves=%0d", game_word(17));
                errors++;
            end
            check32(game_word(18), 0, "live post-Left won flag");
            check32(game_word(19), 0, "live post-Left over flag");
        end
        check32(game_word(21), 1, "live snapshot active");
        check32({29'd0, leds[15:13]}, 0, "live STATUS LEDs clear");
        check32({20'd0, dut.u_soc.u_conf.step}, game_word(17) > 3199 ? 3199 : game_word(17),
                "live confreg STEP follows moves");
        $display("GAME LIVE: stage=%0d serial=%0d tiles=%0d moves=%0d score=%0d",
                 stage, game_word(20), occupied, game_word(17), game_word(16));
        $fflush();
    end
endtask

task automatic run_game_live_scenarios;
    begin
        $readmemh("game-symbols.hex", game_symbols);
        framebuffer_monitor = 1;
        dip_sw = 0;
        repeat (1000) @(negedge clk);
        check32(game_word(21), 0, "live game standby while DIP0");

        dip_sw = 1;
        game_wait_serial(1);
        game_live_check(0);

        touch_btn = 4'h4;
        repeat (100) @(negedge clk);
        touch_btn = 0;
        game_wait_serial(2);
        game_live_check(1);
        $display("GAME LIVE: initial board and Left input checked with production seed");
        $fflush();
    end
endtask
