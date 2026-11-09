# ORFS's aes (aes_cipher_top, 562 flops) on sky130hd, plus clock tree variants.
# Everything else comes from the ORFS config in the image; the source, SDC and
# FastRoute files stay there too.
_orfs_aes := $(FLOW_HOME)/designs/sky130hd/aes
include $(_orfs_aes)/config.mk
export VERILOG_FILES = $(sort $(wildcard $(FLOW_HOME)/designs/src/aes/*.v))
export SDC_FILE      = $(_orfs_aes)/constraint.sdc
export FASTROUTE_TCL = $(_orfs_aes)/fastroute.tcl

# ---------------------------------------------------------------------------
# Clock tree variants, like registered_adder's CTS knob:
#
#   make DESIGN=aes CTS=small            one run, in results/sky130hd/aes/cts-small/
#   make DESIGN=aes CTS=small clock_report
#   make DESIGN=aes cts_variants         every choice, clock reports, metrics
#
# registered_adder has too few flops (194) for sink clustering to run. aes has
# enough, so here the cluster settings change the tree:
#   base     ORFS's aes settings: up to 20 flops within 50 um per leaf buffer
#   small    up to 5 flops within 20 um: many leaf buffers, one more level
#   large    up to 40 flops within 150 um: few leaf buffers
#   noclust  no sink clustering; the H-tree alone picks the leaf regions
# Placement is the same for every choice; only CTS and what follows changes.
# ---------------------------------------------------------------------------
CTS ?= base
CTS_CHOICES := base small large noclust
$(if $(filter $(CTS),$(CTS_CHOICES)),,$(error CTS=$(CTS): choose one of $(CTS_CHOICES)))
export FLOW_VARIANT ?= $(if $(filter-out base,$(CTS)),cts-$(CTS),base)

ifeq ($(CTS),small)
  export CTS_CLUSTER_SIZE     = 5
  export CTS_CLUSTER_DIAMETER = 20
else ifeq ($(CTS),large)
  export CTS_CLUSTER_SIZE     = 40
  export CTS_CLUSTER_DIAMETER = 150
else ifeq ($(CTS),noclust)
  export CTS_ARGS = -repair_clock_nets
endif
