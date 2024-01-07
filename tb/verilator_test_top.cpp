// Verilated -*- C++ -*-
// DESCRIPTION: main() calling loop, created with Verilator --main

#include "Vverilator_test_top.h"
#include "verilated.h"
#include <iostream>

//======================

int main(int argc, char **argv, char **) {
  // Setup context, defaults, and parse command line
  Verilated::debug(0);
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
  contextp->commandArgs(argc, argv);

  // Construct the Verilated model, from Vtop.h generated from Verilating
  const std::unique_ptr<Vverilator_test_top> topp{
      new Vverilator_test_top{contextp.get()}};

#if VM_TRACE==1
  contextp->traceEverOn(true);
#endif

  topp->rst_ni = 0;
  topp->clk_i = 0;

  // Simulate until $finish
  while (!contextp->gotFinish()) {
    // Evaluate model
    topp->eval();
    // Advance time
    contextp->timeInc(1);

    topp->clk_i = !topp->clk_i;
    if (contextp->time() >= 10) {
      topp->rst_ni = 1;
    }
    if (contextp->time() >= 1000) {
      break;
    }
  }

  if (!contextp->gotFinish()) {
    std::cerr << "Simulation ran out of timesteps\n";
    VL_DEBUG_IF(VL_PRINTF("+ Exiting without $finish; no events left\n"););
  }

  // Final model cleanup
  topp->final();
  return 0;
}
