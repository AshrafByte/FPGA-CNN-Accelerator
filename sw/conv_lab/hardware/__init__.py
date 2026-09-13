"""Everything that knows about QuestaSim and conv_image_tb - and nothing else does.

    testbench.py  QuestaTestbench: a simulator session (run directory, compile once)
    contract.py   the run-directory files both sides agree on, and the tap-order flip
    questa.py     the vlib / vlog / vsim commands and the shell that runs them

This package never imports the reference model or the comparison: the hardware
side and the reference side only meet in conv_lab.harness.
"""

from .contract import TestbenchError
from .testbench import QuestaTestbench, TestbenchResult

__all__ = ["QuestaTestbench", "TestbenchError", "TestbenchResult"]
