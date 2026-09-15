![SystemVerilog](https://img.shields.io/badge/SystemVerilog-RTL-0175)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=FFD43B)
![Xilinx Vivado](https://img.shields.io/badge/Xilinx-Vivado-E01F27)
![FPGA](https://img.shields.io/badge/FPGA-Hardware-6C757D)

# fpga-cnn-accelerator
FPGA-based Edge AI CNN convolution accelerator with SystemVerilog RTL, verification, FPGA implementation, and Python golden reference.

## Repository layout

| Folder | Content |
|---|---|
| `hw/` | RTL: `hw/ip/*` building blocks, `hw/system/conv_system` top level and testbenches |
| `sw/` | `conv_lab`: Python golden model, image/kernel tools, QuestaSim hardware regression |
| `fpga/` | Vivado flow (`synth/`, `impl/`, `reports/` with power and FoM), PYNQ-Z2 board demo (`bitstream/`, `board/`) - see [fpga/README.md](fpga/README.md) |
| `experiments/` | the three MAC architectures as standalone designs |
| `docs/` | report, diagrams, competition specification |

## Verification quick start

```bash
python common/script/vrun.py list                   # simulatable IPs and systems
python common/script/vrun.py sim conv_system        # self-checking system testbench (QuestaSim)
python common/script/vrun.py sim line_buffer        # IP unit tests: line_buffer, output_fifo, kernel_register
cd sw && python -m pytest -m "not hardware"         # golden model and contract unit tests
cd sw && python -m pytest -m hardware tests         # hardware regression against the golden model
python -m pytest fpga/board/tests                   # PYNQ driver against a model of the AXI wrapper
```

`conv_system` streams frames back to back without a reset: `o_frame_done` marks the last
feature of every frame (see `hw/system/conv_system/src/rtl/conv_system.sv`).

## FPGA quick start

```powershell
.\fpga\run.ps1                          # synth, impl, benchmark power + FoM, PYNQ-Z2 bitstream
.\fpga\run.ps1 -Steps synth,impl,power  # FoM only -> fpga/reports/default/summary.md
```
