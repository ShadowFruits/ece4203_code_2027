export DESIGN_NAME = adder64_pipelined
export PLATFORM    = sky130hd

export VERILOG_FILES = $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/adder64_pipelined.v
export SDC_FILE      = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

# Adders degrade GCD
export ADDER_MAP_FILE :=

# Fixed die, sized for STAGES = 64, CHUNK = 1 in adder64_pipelined.v: the input
# delay lines make it 6,370 flops, ~176,000 um^2 of cells after synthesis and
# ~200,000 um^2 at the end, so the core is 640 x 640 um (~50%). io_constraints.tcl
# places the 196 I/O pins up to 120 um along each edge, which fits any die.
# (The 8-stage version, STAGES = 8 / CHUNK = 8, fits in 0 0 200 200.)
export DIE_AREA  = 0 0 650 650
export CORE_AREA = 5 5 645 645
export TNS_END_PERCENT = 100
export EQUIVALENCE_CHECK   ?=   0
export REMOVE_CELLS_FOR_EQY = sky130_fd_sc_hd__tapvpwrvgnd*

export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/io_constraints.tcl
