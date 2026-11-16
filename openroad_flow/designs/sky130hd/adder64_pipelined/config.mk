export DESIGN_NAME = adder64_pipelined
export PLATFORM    = sky130hd

export VERILOG_FILES = $(DESIGN_HOME)/src/$(DESIGN_NICKNAME)/adder64_pipelined.v
export SDC_FILE      = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

# Adders degrade GCD
export ADDER_MAP_FILE :=

# The die is sized from the synthesized cell area, so every STAGES / CHUNK
# setting in adder64_pipelined.v gets its own square die: core area =
# cell area / 0.43, plus a 5 um margin. For STAGES = 64, CHUNK = 1 (6,370 flops,
# ~176,000 um^2 after synthesis) that is a 640 x 640 um core in a 650 x 650 um
# die, ~50% utilized at the end. io_constraints.tcl places the I/O pins up to
# 120 um along each edge, which fits the smallest die (STAGES = 2, ~180 um).
export CORE_UTILIZATION  = 43
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN       = 5
export TNS_END_PERCENT = 100
export EQUIVALENCE_CHECK   ?=   0
export REMOVE_CELLS_FOR_EQY = sky130_fd_sc_hd__tapvpwrvgnd*

export IO_CONSTRAINTS = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/io_constraints.tcl
