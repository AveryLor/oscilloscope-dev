idf_component_register(
    SRCS "main.c" "stream.c" "fpga_link.c" "afe.c"
    INCLUDE_DIRS "."
    REQUIRES lmh6518 mcp4726 driver
)
