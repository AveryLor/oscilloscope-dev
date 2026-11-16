idf_component_register(
    SRCS "main.c" "stream.c" "stream_frame.c" "envelope.c" "fpga_link.c" "afe.c"
         "cmd_parse.c" "cmd.c" "live_cfg.c" "or_protect.c" "vscale.c" "vknob.c"
    INCLUDE_DIRS "."
    REQUIRES lmh6518 mcp4726 driver
)
