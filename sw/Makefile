CXX ?= g++
CROSS ?= loongarch32r-linux-gnusf-
BUILD ?= $(if $(LA32R_BUILD),$(LA32R_BUILD)/sw,$(HOME)/build/la32r/sw)
CXXFLAGS ?= -std=c++11 -O2 -Wall -Wextra -Werror -pedantic
CORE := app/game.cpp
AI_CORE := app/ai.cpp
HEADERS := app/game.h hal/platform.h

.PHONY: all play test cross-check ai-test
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
