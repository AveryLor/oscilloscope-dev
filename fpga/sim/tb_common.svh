/*
 * File: tb_common.svh
 * Description: Shared testbench helpers for the Icarus Verilog benches: pass/fail
 *              tracking macros, a VCD dump guard, and a mode-0 SPI master task.
 *              Include this once per bench after the module imports.
 * Author: Avery Lor
 * Date: Aug 30 2026
 */

`ifndef TB_COMMON_SVH
`define TB_COMMON_SVH

integer tb_errors = 0;
integer tb_checks = 0;

`define EXPECT(cond, msg) do begin \
    tb_checks = tb_checks + 1; \
    if (!(cond)) begin \
        tb_errors = tb_errors + 1; \
        $display("  FAIL [%0t] %s", $time, msg); \
    end \
end while (0)

`define EXPECT_EQ(got, exp, msg) do begin \
    tb_checks = tb_checks + 1; \
    if ((got) !== (exp)) begin \
        tb_errors = tb_errors + 1; \
        $display("  FAIL [%0t] %s : got=%0d exp=%0d", $time, msg, (got), (exp)); \
    end \
end while (0)

`define TB_FINISH(name) do begin \
    if (tb_errors == 0) \
        $display("PASS %s (%0d checks)", name, tb_checks); \
    else \
        $display("FAIL %s (%0d/%0d checks failed)", name, tb_errors, tb_checks); \
    $finish; \
end while (0)

`ifdef DUMP_VCD
  `define TB_DUMP(fname) initial begin $dumpfile(fname); $dumpvars(0); end
`else
  `define TB_DUMP(fname)
`endif

`endif
