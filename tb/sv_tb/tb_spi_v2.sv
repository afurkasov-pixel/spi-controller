//=============================================================================
// tb_spi_v2 : self-checking testbench for spi_controller (step 1)
//
// Run one test :  make verilator TEST=reg_rw
// Run all tests:  make verilator            (TEST=all is the default)
//
// Tests: reset_values, reset_clears_regs, reg_rw, ro_and_unmapped, irq_idle
//
// Notes
//  - Inputs are driven 1 ns AFTER the clock edge (no race with the DUT).
//  - Expected values come from the RTL as it is now (characterization).
//  - SPI slave model and reference model are added in the next steps.
//=============================================================================
`timescale 1ns/1ps

`define CHECK_EQ(GOT, EXP, MSG) \
    if ((GOT) !== (EXP)) begin \
        errors = errors + 1; \
        $display("  FAIL: %s: got 0x%08h, expected 0x%08h", MSG, (GOT), (EXP)); \
    end

`define EXPECT_REG(ADDR, EXP, MSG) \
    begin \
        apb_read(ADDR, rd); \
        `CHECK_EQ(rd, EXP, MSG) \
    end

`define RUN_TEST(NAME, TASKCALL) \
    if (run_all || test_name == NAME) begin \
        do_reset; \
        errors = 0; \
        $display("--- %s ---", NAME); \
        TASKCALL; \
        total = total + 1; \
        if (errors == 0) begin \
            passed = passed + 1; \
            $display("PASS: %s", NAME); \
        end else begin \
            failed = failed + 1; \
            $display("FAIL: %s (%0d errors)", NAME, errors); \
        end \
    end

module tb_spi_v2;

    // ------------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------------
    reg         pclk;
    reg         presetn;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [7:0]  paddr;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;
    wire        spi_clk;
    wire        spi_mosi;
    wire        spi_miso;
    wire [3:0]  spi_csn;
    wire        spi_irq;

    // Register addresses
    localparam [7:0] ADDR_CTRL   = 8'h00;
    localparam [7:0] ADDR_STAT   = 8'h04;
    localparam [7:0] ADDR_TXDATA = 8'h08;
    localparam [7:0] ADDR_RXDATA = 8'h0C;
    localparam [7:0] ADDR_BAUD   = 8'h10;
    localparam [7:0] ADDR_FIFO   = 8'h14;
    localparam [7:0] ADDR_INT    = 8'h18;
    localparam [7:0] ADDR_MODE   = 8'h1C;

    // Test bookkeeping
    integer total, passed, failed, errors;
    integer dummy;
    reg [255:0] test_name;
    reg         run_all;
    reg  [31:0] rd;

    // Data for reg_rw
    reg  [7:0]  rw_addr [0:4];
    reg  [31:0] rw_pat  [0:3];
    integer     i, j;

    // ------------------------------------------------------------------
    // Clock, DUT, watchdog
    // ------------------------------------------------------------------
    initial begin
        pclk = 1'b0;
        forever #5 pclk = ~pclk;      // 100 MHz
    end

    // SPI slave is not modelled yet: MISO is tied low
    assign spi_miso = 1'b0;

    spi_controller dut (
        .pclk_i(pclk),       .presetn_i(presetn),
        .psel_i(psel),       .penable_i(penable),
        .pwrite_i(pwrite),   .paddr_i(paddr),
        .pwdata_i(pwdata),   .prdata_o(prdata),
        .pready_o(pready),   .pslverr_o(pslverr),
        .spi_clk_o(spi_clk), .spi_mosi_o(spi_mosi),
        .spi_miso_i(spi_miso), .spi_csn_o(spi_csn),
        .spi_irq_o(spi_irq)
    );

    initial begin
        #1000000;
        $display("ERROR: watchdog timeout");
        $finish;
    end

    // ------------------------------------------------------------------
    // APB driver
    // ------------------------------------------------------------------
    task apb_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge pclk); #1;
            psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
            paddr = addr; pwdata = data;
            @(posedge pclk); #1;
            penable = 1'b1;
            @(posedge pclk); #1;
            psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
        end
    endtask

    task apb_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge pclk); #1;
            psel = 1'b1; penable = 1'b0; pwrite = 1'b0;
            paddr = addr;
            @(posedge pclk); #1;
            penable = 1'b1;
            #4;
            data = prdata;            // sampled mid-cycle, value is stable
            @(posedge pclk); #1;
            psel = 1'b0; penable = 1'b0;
        end
    endtask

    // Reset with all changes on the falling clock edge
    task do_reset;
        begin
            @(negedge pclk);
            presetn = 1'b0;
            psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
            paddr = 8'h00; pwdata = 32'h0;
            repeat (4) @(negedge pclk);
            presetn = 1'b1;
            repeat (2) @(negedge pclk);
        end
    endtask

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    task check_reset_values;
        begin
            `EXPECT_REG(ADDR_CTRL, 32'h00000000, "CTRL after reset")
            `EXPECT_REG(ADDR_STAT, 32'h00000002, "STAT after reset RX empty only")
            `EXPECT_REG(ADDR_BAUD, 32'h0000000A, "BAUD after reset")
            `EXPECT_REG(ADDR_FIFO, 32'h00000010, "FIFO after reset")
            `EXPECT_REG(ADDR_INT,  32'h00000000, "INT after reset")
            `EXPECT_REG(ADDR_MODE, 32'h00000000, "MODE after reset")
        end
    endtask

    task t_reset_values;
        begin
            check_reset_values;
        end
    endtask

    task t_reset_clears_regs;
        begin
            apb_write(ADDR_BAUD, 32'h12345678);
            apb_write(ADDR_INT,  32'h0000000F);
            apb_write(ADDR_MODE, 32'h00000A03);
            do_reset;
            check_reset_values;
        end
    endtask

    task t_reg_rw;
        begin
            rw_addr[0] = ADDR_CTRL; rw_addr[1] = ADDR_BAUD; rw_addr[2] = ADDR_FIFO;
            rw_addr[3] = ADDR_INT;  rw_addr[4] = ADDR_MODE;
            rw_pat[0] = 32'hA5A5A5A5; rw_pat[1] = 32'h5A5A5A5A;
            rw_pat[2] = 32'hFFFFFFFF; rw_pat[3] = 32'h00000000;
            for (i = 0; i < 5; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    apb_write(rw_addr[i], rw_pat[j]);
                    apb_read(rw_addr[i], rd);
                    if (rd !== rw_pat[j]) begin
                        errors = errors + 1;
                        $display("  FAIL: addr 0x%02h wrote 0x%08h read 0x%08h",
                                 rw_addr[i], rw_pat[j], rd);
                    end
                end
                // leave the register in its reset state before the next one
                apb_write(rw_addr[i], 32'h00000000);
            end
        end
    endtask

    task t_ro_and_unmapped;
        begin
            // STAT is read-only: a write must not change it
            apb_write(ADDR_STAT, 32'hFFFFFFFF);
            `EXPECT_REG(ADDR_STAT, 32'h00000002, "STAT ignores writes")
            // TXDATA is write-only: reads as 0
            `EXPECT_REG(ADDR_TXDATA, 32'h00000000, "TXDATA reads as 0")
            // unmapped addresses read as 0 and ignore writes
            apb_write(8'h20, 32'hDEADBEEF);
            `EXPECT_REG(8'h20, 32'h00000000, "unmapped 0x20 reads as 0")
            apb_write(8'hFC, 32'hDEADBEEF);
            `EXPECT_REG(8'hFC, 32'h00000000, "unmapped 0xFC reads as 0")
            // information only: the RTL never raises pslverr (plan item 27)
            $display("  INFO: pslverr=%b pready=%b (RTL: constant 0 / 1)", pslverr, pready);
        end
    endtask

    task t_irq_idle;
        begin
            // idle block: TX FIFO is empty
            `CHECK_EQ(spi_irq, 1'b0, "irq is low with INT=0")
            apb_write(ADDR_INT, 32'h00000001);        // TX FIFO empty interrupt
            repeat (3) @(posedge pclk);
            #1;
            `CHECK_EQ(spi_irq, 1'b1, "irq high: TX empty enabled and FIFO empty")
            apb_write(ADDR_INT, 32'h0000000E);        // RX full, done, error
            repeat (3) @(posedge pclk);
            #1;
            `CHECK_EQ(spi_irq, 1'b0, "irq low: RX full/done/error not active")
            apb_write(ADDR_INT, 32'h00000000);
            repeat (3) @(posedge pclk);
            #1;
            `CHECK_EQ(spi_irq, 1'b0, "irq low again with INT=0")
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_spi_v2.vcd");
        $dumpvars(0, tb_spi_v2);

        total = 0; passed = 0; failed = 0; errors = 0;
        presetn = 1'b0;
        psel = 1'b0; penable = 1'b0; pwrite = 1'b0; paddr = 8'h0; pwdata = 32'h0;

        test_name = "all";
        dummy = $value$plusargs("TEST=%s", test_name);
        run_all = (test_name == "all");

        `RUN_TEST("reset_values",      t_reset_values)
        `RUN_TEST("reset_clears_regs", t_reset_clears_regs)
        `RUN_TEST("reg_rw",            t_reg_rw)
        `RUN_TEST("ro_and_unmapped",   t_ro_and_unmapped)
        `RUN_TEST("irq_idle",          t_irq_idle)

        if (total == 0) begin
            $display("ERROR: no test matches TEST=%0s", test_name);
            failed = 1;
        end

        $display("=== Final Test Summary ===");
        $display("Total tests: %0d", total);
        $display("Passed: %0d", passed);
        $display("Failed: %0d", failed);
        if (failed == 0) $display("ALL TESTS PASSED");
        else             $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
