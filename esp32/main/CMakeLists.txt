idf_component_register(
    SRCS "main.c" "stream.c" "stream_frame.c" "envelope.c" "fpga_link.c" "afe.c"
         "cmd_parse.c" "cmd.c" "live_cfg.c"
    INCLUDE_DIRS "."
    REQUIRES lmh6518 mcp4726 driver
)
