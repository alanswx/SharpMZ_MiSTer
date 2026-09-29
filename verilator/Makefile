#============================================================================
#  SharpMZ Verilator simulation
#
#    make            # headless sim            -> ./obj_dir_headless/Vtop
#    make netlist    # VHDL -> Verilog only    -> gen/sharpmz.v
#    make test       # smoke tests (run_tests.sh)
#    make test-clkgen  # GHDL testbench for the clock enable generator
#    make clean
#
#  The RTL is VHDL and Verilator reads only Verilog, so every build starts by
#  running the core through "ghdl synth", which emits a Verilog netlist. Module,
#  instance and register names survive; combinational nodes become nNNNN.
#
#  dpram/dprom (Altera altsyncram wrappers) are not analysed: ghdl leaves them
#  as black boxes and rtl_v/dpram.v, rtl_v/dprom.v supply the memories. Their
#  .mif init files are converted to software/mif/<name>.mif.hex.
#
#  Requires: ghdl (5.x), verilator (5.x), python3.
#============================================================================

V      = verilator
GHDL   = ghdl
RTL    = ../rtl
GEN    = gen
WORK   = ghdl_work

GHDL_FLAGS = --std=08 -fsynopsys -fexplicit -frelaxed -Wno-hide -Wno-shared -Wno-binding \
	--workdir=$(WORK) --work=pkgs

# Analysis order: packages first, then leaves, then the assembly.
VHD_SRC = \
	$(RTL)/config_pkg.vhd \
	$(RTL)/clkgen_pkg.vhd \
	$(RTL)/mctrl_pkg.vhd \
	$(RTL)/functions.vhd \
	$(RTL)/clkgen.vhd \
	$(RTL)/mctrl.vhd \
	$(RTL)/T80/T80_Pack.vhd \
	$(RTL)/T80/T80_ALU.vhd \
	$(RTL)/T80/T80_Reg.vhd \
	$(RTL)/T80/T80_MCode.vhd \
	$(RTL)/T80/T80.vhd \
	$(RTL)/T80/T80se.vhd \
	$(RTL)/i8254/i8254_counter.vhd \
	$(RTL)/i8254/i8254.vhd \
	$(RTL)/i8255/i8255.vhd \
	$(RTL)/z8420/Interrupt.vhd \
	$(RTL)/z8420/z8420.vhd \
	$(RTL)/clk_div.vhd \
	$(RTL)/keymatrix.vhd \
	$(RTL)/video.vhd \
	$(RTL)/cmt.vhd \
	$(RTL)/mz80c/mz80c.vhd \
	$(RTL)/mz80b/mz80b.vhd \
	$(RTL)/vc/vc_mctrl_pkg.vhd \
	$(RTL)/vc/VideoController_pkg.vhd \
	$(RTL)/vc/vc_rams.vhd \
	$(RTL)/vc/VideoController.vhd \
	$(RTL)/vc/video_vc.vhd \
	$(RTL)/sharpmz.vhd

GEN_V = $(GEN)/sharpmz.v
V_SRC = sim.v $(GEN_V) rtl_v/dpram.v rtl_v/dprom.v $(RTL)/tape_image.sv

MIFS    = $(wildcard $(RTL)/software/mif/*.mif)
MIF_HEX = $(patsubst $(RTL)/software/mif/%.mif,software/mif/%.mif.hex,$(MIFS))

V_OPT = -O3 --x-assign fast --x-initial fast --noassert \
	-Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
	-Wno-UNSIGNED -Wno-CMPCONST -Wno-DECLFILENAME -Wno-MULTIDRIVEN -Wno-LATCH \
	-Wno-TIMESCALEMOD -Wno-COMBDLY

CXXFLAGS = -O3 -std=c++17
HL_DIR   = obj_dir_headless
HL_EXE   = ./$(HL_DIR)/Vtop

all: headless

headless: $(HL_EXE) $(MIF_HEX)

# ---------------------------------------------------------------------------
# VHDL -> Verilog netlist
# ---------------------------------------------------------------------------
$(GEN_V): $(VHD_SRC) fix_port_aliases.py Makefile
	@mkdir -p $(GEN) $(WORK)
	$(GHDL) -a $(GHDL_FLAGS) $(VHD_SRC)
	$(GHDL) synth $(GHDL_FLAGS) --out=verilog sharpmz > $@.tmp
	$(GHDL) synth $(GHDL_FLAGS) --out=vhdl sharpmz > $(GEN)/sharpmz_netlist.vhd
	python3 fix_port_aliases.py $@.tmp $(GEN)/sharpmz_netlist.vhd
	@# VHDL names that are (System)Verilog keywords.
	perl -pi -e 's/\b(do|config)\b/$${1}_v/g' $@.tmp
	@mv $@.tmp $@

netlist: $(GEN_V)

software/mif/%.mif.hex: $(RTL)/software/mif/%.mif mif2hex.py
	@mkdir -p software/mif
	python3 mif2hex.py $< $@

# ---------------------------------------------------------------------------
# Headless: no SDL. Screenshots, frame logs and state dumps for regressions.
# ---------------------------------------------------------------------------
$(HL_EXE): $(V_SRC) sim_headless.cpp ps2_keys.h sharp_vcode.h Makefile
	$V -cc $(V_OPT) --exe --build -j 0 --Mdir $(HL_DIR) --top-module top \
		-CFLAGS "$(CXXFLAGS)" $(V_SRC) sim_headless.cpp -o Vtop

test: headless
	./run_tests.sh

# ---------------------------------------------------------------------------
# GHDL unit testbenches.
# ---------------------------------------------------------------------------
test-clkgen: $(GEN_V)
	$(GHDL) -a $(GHDL_FLAGS) tests/tb_clkgen.vhd
	$(GHDL) -e $(GHDL_FLAGS) -o $(WORK)/tb_clkgen tb_clkgen
	cd $(WORK) && ./tb_clkgen --assert-level=error

clean:
	rm -rf $(HL_DIR) $(GEN) $(WORK) software out

.PHONY: all headless netlist test test-clkgen clean
