# Host-side tests for the firmware logic that has no ESP-IDF dependencies:
# the column reduction and the wire-format packer. Run with `make -C esp32/test`.

CC     ?= gcc
CFLAGS := -std=c11 -Wall -Wextra -Werror -O2 -I../main

BUILD := build
TESTS := test_envelope test_stream_frame test_cmd_parse

.PHONY: all clean $(TESTS)

all: $(TESTS)
	@echo "---- all host tests run ----"

test_envelope: $(BUILD)/test_envelope
	@./$<

test_stream_frame: $(BUILD)/test_stream_frame
	@./$<

test_cmd_parse: $(BUILD)/test_cmd_parse
	@./$<

$(BUILD)/test_envelope: test_envelope.c ../main/envelope.c ../main/envelope.h
	@mkdir -p $(BUILD)
	@$(CC) $(CFLAGS) -o $@ test_envelope.c ../main/envelope.c

$(BUILD)/test_stream_frame: test_stream_frame.c ../main/stream_frame.c ../main/stream_frame.h
	@mkdir -p $(BUILD)
	@$(CC) $(CFLAGS) -o $@ test_stream_frame.c ../main/stream_frame.c

$(BUILD)/test_cmd_parse: test_cmd_parse.c ../main/cmd_parse.c ../main/cmd_parse.h
	@mkdir -p $(BUILD)
	@$(CC) $(CFLAGS) -o $@ test_cmd_parse.c ../main/cmd_parse.c

clean:
	rm -rf $(BUILD)
