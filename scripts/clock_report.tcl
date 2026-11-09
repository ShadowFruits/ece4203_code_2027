# Clock tree numbers for a finished ORFS run, to compare CTS variants.
#
#   make clock_report                  (from openroad_flow/, after a run)
#   make CTS=small clock_report        (same knobs as the run)
#
# Reads 6_final.odb (with 6_final.spef when there is one) and writes
#   reports/.../clock_report.txt   report_clock_latency, report_clock_skew,
#                                  report_power and the tree summary below
#   logs/.../clock_report.json     the same numbers, picked up by make metrics
#
# The flow's own metrics only have the skew. This adds the clock tree cells,
# sinks, depth, latency, routed clock wirelength and clock power.

source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
set spef $::env(RESULTS_DIR)/6_final.spef
if { [file exists $spef] } {
  read_spef $spef
} else {
  estimate_parasitics -placement
}

set block [ord::get_db_block]

# Clock nets, and the instance driving each one (none for the net from the port)
set clock_nets {}
set driver_of [dict create]
foreach net [$block getNets] {
  if { [$net getSigType] != "CLOCK" } {
    continue
  }
  lappend clock_nets $net
  foreach iterm [$net getITerms] {
    if { [$iterm isOutputSignal] } {
      dict set driver_of [$net getName] [$iterm getInst]
    }
  }
}

# Tree cells drive a clock net (buffers, inverters, clock gates). Any other
# load on a clock net is a sink (a flop), or a dummy load if its output is
# unconnected: a buffer or inverter CTS added to even out a cluster's load.
set tree_cells [dict create]
dict for {name inst} $driver_of {
  dict set tree_cells [$inst getName] $inst
}
set sinks 0
set dummies 0
foreach net $clock_nets {
  foreach iterm [$net getITerms] {
    if { ![$iterm isInputSignal] } {
      continue
    }
    set inst [$iterm getInst]
    if { [dict exists $tree_cells [$inst getName]] } {
      continue
    }
    set drives 0
    foreach out [$inst getITerms] {
      if { [$out isOutputSignal] && [$out getNet] != "NULL" } {
        set drives 1
      }
    }
    if { $drives } {
      incr sinks
    } else {
      incr dummies
    }
  }
}

# Depth: the most tree cells between the clock port and any sink
proc clock_depth { net tree_cells } {
  set depth 0
  foreach iterm [$net getITerms] {
    set inst [$iterm getInst]
    if { ![$iterm isInputSignal] || ![dict exists $tree_cells [$inst getName]] } {
      continue
    }
    foreach out [$inst getITerms] {
      set out_net [$out getNet]
      if { [$out isOutputSignal] && $out_net != "NULL" } {
        set depth [expr { max($depth, 1 + [clock_depth $out_net $tree_cells]) }]
      }
    }
  }
  return $depth
}
set levels 0
foreach net $clock_nets {
  if { ![dict exists $driver_of [$net getName]] } {
    set levels [expr { max($levels, [clock_depth $net $tree_cells]) }]
  }
}

# Cell types in the tree, e.g. "17 clkbuf_16"
set cell_types [dict create]
dict for {name inst} $tree_cells {
  regsub {^sky130_fd_sc_hd__} [[$inst getMaster] getName] {} master
  dict incr cell_types $master
}

# Routed wirelength of the clock nets, from report_wire_length's log lines
set names {}
foreach net $clock_nets {
  lappend names [$net getName]
}
utl::redirectStringBegin
report_wire_length -net $names -detailed_route
set wl_text [utl::redirectStringEnd]
set wirelength 0.0
foreach {- um} [regexp -all -inline {wire length: ([0-9.]+)um} $wl_text] {
  set wirelength [expr { $wirelength + $um }]
}

# Latency, skew and power, from the STA reports
sta::with_output_to_variable latency_text { report_clock_latency -digits 3 }
sta::with_output_to_variable skew_text { report_clock_skew -setup -digits 3 }
sta::with_output_to_variable power_text { report_power }
# rise -> rise block: "   0.430   0.441 latency" then "   0.011 skew"
regexp {([0-9.]+)\s+([0-9.]+)\s+latency} $latency_text - lat_min lat_max
regexp {([0-9.-]+)\s+setup skew} $skew_text - skew
regexp {\nClock\s+\S+\s+\S+\s+\S+\s+(\S+)\s+([0-9.]+)%} $power_text - clk_power clk_pct
regexp {\nTotal\s+\S+\s+\S+\s+\S+\s+(\S+)} $power_text - total_power

set summary [format \
  "Clock tree: %d tree cells, %d sinks, %d dummy loads, %d levels, %d nets\n\
   Cells: %s\n\
   Latency %.3f - %.3f ns, setup skew %.3f ns\n\
   Clock wirelength %.1f um\n\
   Clock power %.3f mW of %.3f mW (%s%%)" \
  [dict size $tree_cells] $sinks $dummies $levels [llength $clock_nets] \
  [join [lmap {k v} $cell_types { list $v $k }] ", "] \
  $lat_min $lat_max $skew $wirelength \
  [expr { $clk_power * 1e3 }] [expr { $total_power * 1e3 }] $clk_pct]
puts $summary

set fh [open $::env(REPORTS_DIR)/clock_report.txt w]
puts $fh "$summary\n\n$latency_text\n$skew_text\n$power_text"
close $fh

set fh [open $::env(LOG_DIR)/clock_report.json w]
puts $fh [format {{
  "clock__tree__cells": %d,
  "clock__tree__sinks": %d,
  "clock__tree__dummy_loads": %d,
  "clock__tree__levels": %d,
  "clock__latency__min": %s,
  "clock__latency__max": %s,
  "clock__skew__setup": %s,
  "clock__wirelength": %s,
  "clock__power": %s
}} [dict size $tree_cells] $sinks $dummies $levels $lat_min $lat_max $skew $wirelength $clk_power]
close $fh
puts "Wrote $::env(REPORTS_DIR)/clock_report.txt and $::env(LOG_DIR)/clock_report.json"
