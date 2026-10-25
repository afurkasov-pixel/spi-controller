# Запуск тестов SPI controller: Verilator и Icarus, покрытие
# Файл использует ">" вместо табуляции в командах (так проще копировать)
.RECIPEPREFIX = >
.DEFAULT_GOAL := help

RTL   := RTL/spi_fifo.sv RTL/spi_protocol_engine.sv RTL/spi_controller.sv
TB    ?= tb/sv_tb/tb_spi_v2.sv
TOP   ?= tb_spi_v2
BUILD := build
SEED  ?= 1
TEST  ?= all

.PHONY: help verilator icarus regress coverage clean

help:
> @echo "make verilator  - собрать и запустить в Verilator"
> @echo "make icarus     - собрать и запустить в Icarus Verilog"
> @echo "make regress    - запустить оба и показать итоги"
> @echo "make coverage   - Verilator + отчёт покрытия RTL (build/cov_html)"
> @echo "make clean      - удалить папку build"
> @echo "Параметры: SEED=число TEST=имя_теста (пример: make verilator SEED=5)"

verilator:
> @mkdir -p $(BUILD)/vl
> verilator --binary --timing --coverage --trace -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD --top-module $(TOP) -Mdir $(BUILD)/vl $(RTL) $(TB)
> cd $(BUILD)/vl && ./V$(TOP) +seed=$(SEED) +TEST=$(TEST) | tee run.log

icarus:
> @mkdir -p $(BUILD)/icarus
> iverilog -g2012 -o $(BUILD)/icarus/sim $(RTL) $(TB)
> cd $(BUILD)/icarus && vvp sim +seed=$(SEED) +TEST=$(TEST) | tee run.log

regress: verilator icarus
> @echo "=== ИТОГИ ==="
> @echo "--- Verilator ---"
> @grep -E "Total tests|Passed|Failed" $(BUILD)/vl/run.log
> @echo "--- Icarus ---"
> @grep -E "Total tests|Passed|Failed" $(BUILD)/icarus/run.log

coverage: verilator
> verilator_coverage --write-info $(BUILD)/coverage.info $(BUILD)/vl/coverage.dat
> lcov --extract $(BUILD)/coverage.info '*RTL/*' -o $(BUILD)/rtl.info
> genhtml $(BUILD)/rtl.info -o $(BUILD)/cov_html
> lcov --summary $(BUILD)/rtl.info

clean:
> rm -rf $(BUILD)
