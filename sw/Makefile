CXX ?= g++
CROSS ?= loongarch32r-linux-gnusf-
BUILD ?= $(if $(LA32R_BUILD),$(LA32R_BUILD)/sw,$(HOME)/build/la32r/sw)
CXXFLAGS ?= -std=c++11 -O2 -Wall -Wextra -Werror -pedantic
CORE := app/game.cpp
AI_CORE := app/ai.cpp
HEADERS := app/game.h hal/platform.h
LA32R_BUILD_DIR := $(BUILD)/la32r
LA32R_FLAGS := $(CXXFLAGS) -march=loongarch32r -mabi=ilp32s -ffreestanding -fno-exceptions -fno-rtti -fno-pic -fno-pie -fno-stack-protector
SMOKE_DIR := $(BUILD)/board-smoke
SMOKE_FLAGS := $(LA32R_FLAGS) -fno-unwind-tables -fno-asynchronous-unwind-tables
INPUT_DIR := $(BUILD)/input-soc
FRAMEBUFFER_DIR := $(BUILD)/framebuffer-soc

.PHONY: all play test cross-check cross-artifacts board-smoke board-smoke-test board-smoke-wave input-soc input-soc-test framebuffer-test framebuffer-soc framebuffer-soc-test
all: $(BUILD)/2048

$(BUILD):
	mkdir -p "$@"

$(BUILD)/2048: $(CORE) app/main.cpp hal/platform_pc.cpp $(HEADERS) | $(BUILD)
	$(CXX) $(CXXFLAGS) $(CORE) app/main.cpp hal/platform_pc.cpp -o "$@"

$(BUILD)/game_test: $(CORE) tests/game_test.cpp app/game.h | $(BUILD)
	$(CXX) $(CXXFLAGS) $(CORE) tests/game_test.cpp -o "$@"

play: $(BUILD)/2048
	"$(BUILD)/2048"

test: $(BUILD)/game_test $(BUILD)/2048
	"$(BUILD)/game_test"
	python3 tests/pc_test.py "$(BUILD)/2048"

# Compile-only portability check; board startup/linker/drivers are separate work.
$(BUILD)/ai_test: $(AI_CORE) tests/ai_test.cpp app/ai.h | $(BUILD)
	$(CXX) $(CXXFLAGS) $(AI_CORE) tests/ai_test.cpp -o "$@"

ai-test: $(BUILD)/ai_test
	"$(BUILD)/ai_test"

cross-check: | $(BUILD)
	$(CROSS)g++ $(CXXFLAGS) -ffreestanding -fno-exceptions -fno-rtti -c $(CORE) -o "$(BUILD)/game.la32r.o"
	$(CROSS)g++ $(CXXFLAGS) -ffreestanding -fno-exceptions -fno-rtti -c app/main.cpp -o "$(BUILD)/main.la32r.o"

# Current game sources compiled for mycpu; complete firmware requires a board backend.
cross-artifacts: | $(BUILD)
	mkdir -p "$(LA32R_BUILD_DIR)"
	$(CROSS)g++ $(LA32R_FLAGS) -c $(CORE) -o "$(LA32R_BUILD_DIR)/game.o"
	$(CROSS)g++ $(LA32R_FLAGS) -c app/main.cpp -o "$(LA32R_BUILD_DIR)/main.o"
	$(CROSS)g++ $(LA32R_FLAGS) -S $(CORE) -o "$(LA32R_BUILD_DIR)/game.s"
	$(CROSS)g++ $(LA32R_FLAGS) -S app/main.cpp -o "$(LA32R_BUILD_DIR)/main.s"
	$(CROSS)objdump -d -C "$(LA32R_BUILD_DIR)/game.o" > "$(LA32R_BUILD_DIR)/game.dis"
	$(CROSS)objdump -d -C "$(LA32R_BUILD_DIR)/main.o" > "$(LA32R_BUILD_DIR)/main.dis"
	$(CROSS)ar rcs "$(LA32R_BUILD_DIR)/libgame2048.a" "$(LA32R_BUILD_DIR)/game.o"
	$(CROSS)readelf -h "$(LA32R_BUILD_DIR)/game.o" "$(LA32R_BUILD_DIR)/main.o" > "$(LA32R_BUILD_DIR)/elf-headers.txt"
	$(CROSS)nm -u -C "$(LA32R_BUILD_DIR)/game.o" "$(LA32R_BUILD_DIR)/main.o" > "$(LA32R_BUILD_DIR)/undefined-symbols.txt"

$(SMOKE_DIR):
	mkdir -p "$@"

$(SMOKE_DIR)/crt0.o: boot/crt0.S Makefile | $(SMOKE_DIR)
	$(CROSS)gcc -march=loongarch32r -mabi=ilp32s -fno-pic -fno-pie -c $< -o "$@"

$(SMOKE_DIR)/board_smoke.o: tests/board_smoke.cpp Makefile | $(SMOKE_DIR)
	$(CROSS)g++ $(SMOKE_FLAGS) -c $< -o "$@"

$(SMOKE_DIR)/smoke.elf: $(SMOKE_DIR)/crt0.o $(SMOKE_DIR)/board_smoke.o boot/link.ld Makefile
	$(CROSS)g++ -march=loongarch32r -mabi=ilp32s -static -no-pie -nostdlib -nostartfiles \
	    -Wl,--build-id=none,-Map,$(SMOKE_DIR)/smoke.map -T boot/link.ld \
	    $(SMOKE_DIR)/crt0.o $(SMOKE_DIR)/board_smoke.o -lgcc -o "$@"
	test -z "$$($(CROSS)nm -u "$@")"

$(SMOKE_DIR)/smoke.bin: $(SMOKE_DIR)/smoke.elf
	$(CROSS)objcopy -O binary $< "$@"

$(SMOKE_DIR)/smoke.hex: $(SMOKE_DIR)/smoke.bin ../sim/soc/bin2hex.py
	python3 ../sim/soc/bin2hex.py $< "$@"

board-smoke: $(SMOKE_DIR)/smoke.hex
	$(CROSS)objdump -d -C "$(SMOKE_DIR)/smoke.elf" > "$(SMOKE_DIR)/smoke.dis"
	$(CROSS)readelf -h -l -S "$(SMOKE_DIR)/smoke.elf" > "$(SMOKE_DIR)/smoke.elf-info.txt"
	$(CROSS)nm -n "$(SMOKE_DIR)/smoke.elf" > "$(SMOKE_DIR)/smoke.nm"

board-smoke-test: board-smoke
	$(MAKE) -C ../sim/soc BUILD="$(abspath $(SMOKE_DIR)/soc)" CROSS="$(CROSS)" \
	    PROGRAM_HEX="$(abspath $(SMOKE_DIR)/smoke.hex)" \
	    SMOKE_SYMBOLS="$(abspath $(SMOKE_DIR)/smoke.nm)" RUN_ARGS=+cpp-smoke run

board-smoke-wave: board-smoke
	$(MAKE) -C ../sim/soc BUILD="$(abspath $(SMOKE_DIR)/soc)" CROSS="$(CROSS)" \
	    PROGRAM_HEX="$(abspath $(SMOKE_DIR)/smoke.hex)" \
	    SMOKE_SYMBOLS="$(abspath $(SMOKE_DIR)/smoke.nm)" RUN_ARGS=+cpp-smoke wave

$(INPUT_DIR):
	mkdir -p "$@"

$(INPUT_DIR)/input.o: drv/input.cpp drv/input.h drv/confreg.h Makefile | $(INPUT_DIR)
	$(CROSS)g++ $(SMOKE_FLAGS) -c $< -o "$@"

$(INPUT_DIR)/input_soc.o: tests/input_soc.cpp drv/input.h drv/confreg.h Makefile | $(INPUT_DIR)
	$(CROSS)g++ $(SMOKE_FLAGS) -c $< -o "$@"

$(INPUT_DIR)/input.elf: $(SMOKE_DIR)/crt0.o $(INPUT_DIR)/input.o $(INPUT_DIR)/input_soc.o boot/link.ld Makefile
	$(CROSS)g++ -march=loongarch32r -mabi=ilp32s -static -no-pie -nostdlib -nostartfiles \
	    -Wl,--build-id=none,-Map,$(INPUT_DIR)/input.map -T boot/link.ld \
	    $(SMOKE_DIR)/crt0.o $(INPUT_DIR)/input.o $(INPUT_DIR)/input_soc.o -lgcc -o "$@"
	test -z "$$($(CROSS)nm -u "$@")"

$(INPUT_DIR)/input.bin: $(INPUT_DIR)/input.elf
	$(CROSS)objcopy -O binary $< "$@"

$(INPUT_DIR)/input.hex: $(INPUT_DIR)/input.bin ../sim/soc/bin2hex.py
	python3 ../sim/soc/bin2hex.py $< "$@"

input-soc: $(INPUT_DIR)/input.hex
	$(CROSS)objdump -d -C "$(INPUT_DIR)/input.elf" > "$(INPUT_DIR)/input.dis"
	$(CROSS)readelf -h -l -S "$(INPUT_DIR)/input.elf" > "$(INPUT_DIR)/input.elf-info.txt"
	$(CROSS)nm -n "$(INPUT_DIR)/input.elf" > "$(INPUT_DIR)/input.nm"

input-soc-test: input-soc
	$(MAKE) -C ../sim/soc BUILD="$(abspath $(INPUT_DIR)/soc)" CROSS="$(CROSS)" \
	    PROGRAM_HEX="$(abspath $(INPUT_DIR)/input.hex)" \
	    INPUT_SYMBOLS="$(abspath $(INPUT_DIR)/input.nm)" RUN_ARGS=+input-test run

$(FRAMEBUFFER_DIR):
	mkdir -p "$@"

$(FRAMEBUFFER_DIR)/raster_test: tests/framebuffer_test.cpp tests/framebuffer_pattern.h drv/framebuffer.cpp drv/framebuffer.h drv/font_digits.h drv/confreg.h | $(FRAMEBUFFER_DIR)
	$(CXX) $(CXXFLAGS) tests/framebuffer_test.cpp drv/framebuffer.cpp -o "$@"

framebuffer-test: $(FRAMEBUFFER_DIR)/raster_test
	"$(FRAMEBUFFER_DIR)/raster_test" "$(FRAMEBUFFER_DIR)"

$(FRAMEBUFFER_DIR)/framebuffer.o: drv/framebuffer.cpp drv/framebuffer.h drv/font_digits.h drv/confreg.h Makefile | $(FRAMEBUFFER_DIR)
	$(CROSS)g++ $(SMOKE_FLAGS) -c $< -o "$@"

$(FRAMEBUFFER_DIR)/framebuffer_soc.o: tests/framebuffer_soc.cpp tests/framebuffer_pattern.h drv/framebuffer.h drv/confreg.h Makefile | $(FRAMEBUFFER_DIR)
	$(CROSS)g++ $(SMOKE_FLAGS) -c $< -o "$@"

$(FRAMEBUFFER_DIR)/framebuffer.elf: $(SMOKE_DIR)/crt0.o $(FRAMEBUFFER_DIR)/framebuffer.o $(FRAMEBUFFER_DIR)/framebuffer_soc.o boot/link.ld Makefile
	$(CROSS)g++ -march=loongarch32r -mabi=ilp32s -static -no-pie -nostdlib -nostartfiles \
	    -Wl,--build-id=none,-Map,$(FRAMEBUFFER_DIR)/framebuffer.map -T boot/link.ld \
	    $(SMOKE_DIR)/crt0.o $(FRAMEBUFFER_DIR)/framebuffer.o $(FRAMEBUFFER_DIR)/framebuffer_soc.o -lgcc -o "$@"
	test -z "$$($(CROSS)nm -u "$@")"

$(FRAMEBUFFER_DIR)/framebuffer.bin: $(FRAMEBUFFER_DIR)/framebuffer.elf
	$(CROSS)objcopy -O binary $< "$@"

$(FRAMEBUFFER_DIR)/framebuffer.hex: $(FRAMEBUFFER_DIR)/framebuffer.bin ../sim/soc/bin2hex.py
	python3 ../sim/soc/bin2hex.py $< "$@"

framebuffer-soc: $(FRAMEBUFFER_DIR)/framebuffer.hex
	$(CROSS)objdump -d -C "$(FRAMEBUFFER_DIR)/framebuffer.elf" > "$(FRAMEBUFFER_DIR)/framebuffer.dis"
	$(CROSS)readelf -h -l -S "$(FRAMEBUFFER_DIR)/framebuffer.elf" > "$(FRAMEBUFFER_DIR)/framebuffer.elf-info.txt"
	$(CROSS)nm -n "$(FRAMEBUFFER_DIR)/framebuffer.elf" > "$(FRAMEBUFFER_DIR)/framebuffer.nm"

framebuffer-soc-test: framebuffer-test framebuffer-soc
	$(MAKE) -C ../sim/soc BUILD="$(abspath $(FRAMEBUFFER_DIR)/soc)" CROSS="$(CROSS)" \
	    PROGRAM_HEX="$(abspath $(FRAMEBUFFER_DIR)/framebuffer.hex)" \
	    FRAMEBUFFER_SYMBOLS="$(abspath $(FRAMEBUFFER_DIR)/framebuffer.nm)" \
	    FRAMEBUFFER_GOLDEN="$(abspath $(FRAMEBUFFER_DIR))" RUN_ARGS=+framebuffer-test run
	python3 tests/framebuffer_compare.py "$(FRAMEBUFFER_DIR)" "$(FRAMEBUFFER_DIR)/soc" "$(FRAMEBUFFER_DIR)"
