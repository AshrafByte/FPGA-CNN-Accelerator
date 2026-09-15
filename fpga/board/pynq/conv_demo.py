"""PYNQ-Z2 driver and demo for the conv_system accelerator overlay.

Copy this file together with fpga/bitstream/conv_demo.bit and conv_demo.hwh to
the board (for example /home/xilinx/jupyter_notebooks/conv_demo/) and run:

    sudo python3 conv_demo.py                        # patterns x demo kernels
    sudo python3 conv_demo.py --image photo.jpg      # any picture, resized to the overlay
    sudo python3 conv_demo.py --kernels sobel_x sobel_y --save edges.png
    python3 conv_demo.py --model-only                # anywhere, no board: golden model only

Every hardware frame is compared feature by feature with the bit-accurate
golden model below (valid correlation, round half up, 16-bit saturation, the
same rule as sw/conv_lab/core/reference.py). The exit code is 1 on any mismatch.

The accelerator is reset once, when the overlay is opened. Every frame after
that streams without a reset: the driver writes a kernel only when it changes,
sends the pixels and waits for the frame-done flag that conv_system's
o_frame_done sets; FRAME_COUNT counts the completed frames.

Register map and protocol: fpga/board/rtl/conv_axi_lite.sv.
"""

import argparse
import os
import sys
import time

import numpy as np

BASE_ADDR = 0x43C00000
ADDR_RANGE = 0x100000
FEATURE_BASE = 0x10000
CORE_ID = 0x434E5631

REG = {
    "ID": 0x000, "GEOMETRY": 0x004, "FORMAT": 0x008, "CTRL": 0x00C, "STATUS": 0x010,
    "KERNEL_SEL": 0x014, "WEIGHT": 0x018, "PIXEL": 0x01C, "PIXELS4": 0x020,
    "WEIGHT_COUNT": 0x024, "PIXEL_COUNT": 0x028, "OUT_COUNT": 0x02C,
    "LATENCY": 0x030, "FRAME_CYCLES": 0x034, "FRAME_COUNT": 0x038,
}

HERE = os.path.dirname(os.path.abspath(__file__))

# 3x3 demo kernels. The datapath divides every window sum by 16 (drop of 4
# bits at 3x3), so smoothing and sharpening kernels are scaled by 16.
DEMO_KERNELS = {
    "identity":  [[0, 0, 0], [0, 16, 0], [0, 0, 0]],
    "sobel_x":   [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]],
    "sobel_y":   [[-1, -2, -1], [0, 0, 0], [1, 2, 1]],
    "laplacian": [[-1, -1, -1], [-1, 8, -1], [-1, -1, -1]],
    "gaussian":  [[1, 2, 1], [2, 4, 2], [1, 2, 1]],
    "sharpen":   [[0, -16, 0], [-16, 80, -16], [0, -16, 0]],
    "emboss":    [[-32, -16, 0], [-16, 16, 16], [0, 16, 32]],
}

PATTERNS = ("bars", "checker", "circle", "ramp", "noise")


# ----------------------------------------------------------------------------- golden model
def drop_bits(window):
    """Low bits round_saturate discards: ACCUM_WIDTH - 16 = $clog2(N*N) for 8-bit data."""
    return (window * window - 1).bit_length()


def reference(image, kernel, relu=False):
    """What conv_system must produce: int32 array (W-N+1, W-N+1)."""
    kernel = np.asarray(kernel, dtype=np.int64)
    n = kernel.shape[0]
    size = image.shape[0] - n + 1
    src = image.astype(np.int64)
    acc = np.zeros((size, size), dtype=np.int64)
    for i in range(n):
        for j in range(n):
            acc += src[i:i + size, j:j + size] * kernel[i, j]
    drop = drop_bits(n)
    if drop:
        acc = (acc + (1 << (drop - 1))) >> drop          # round half up, floor shift
    acc = np.clip(acc, -32768, 32767)
    if relu:
        acc = np.maximum(acc, 0)
    return acc.astype(np.int32)


def pattern(name, size, seed=0):
    rows, cols = np.indices((size, size))
    tile = max(size // 8, 4)
    if name == "bars":
        frame = np.where((cols // tile) % 2 == 0, 240, 15)
    elif name == "checker":
        frame = np.where((rows // tile + cols // tile) % 2 == 0, 230, 25)
    elif name == "circle":
        centre = (size - 1) / 2.0
        frame = np.where(np.hypot(rows - centre, cols - centre) <= size / 3.0, 220, 30)
    elif name == "ramp":
        frame = (rows + cols) * 255 // max(2 * (size - 1), 1)
    elif name == "noise":
        frame = np.random.RandomState(seed).randint(0, 256, size=(size, size))
    else:
        raise ValueError("unknown pattern %r, choose one of %s" % (name, ", ".join(PATTERNS)))
    return frame.astype(np.uint8)


def load_image(path, size):
    from PIL import Image
    return np.asarray(Image.open(path).convert("L").resize((size, size)), dtype=np.uint8)


# ----------------------------------------------------------------------------- hardware
class ConvAccelerator(object):
    """conv_system behind conv_axi_lite, reached through PYNQ MMIO."""

    def __init__(self, bitfile=None, download=True):
        from pynq import MMIO, Overlay

        bitfile = bitfile or os.path.join(HERE, "conv_demo.bit")
        self.overlay = Overlay(bitfile, download=download)
        self.mmio = MMIO(BASE_ADDR, ADDR_RANGE)

        core_id = self.read("ID")
        if core_id != CORE_ID:
            raise RuntimeError("no conv_axi_lite at 0x%08X (ID 0x%08X)" % (BASE_ADDR, core_id))
        geometry = self.read("GEOMETRY")
        fmt = self.read("FORMAT")
        self.input_size = geometry & 0xFFFF
        self.window = (geometry >> 16) & 0xFF
        self.num_kernels = (geometry >> 24) & 0xFF
        self.idx_bits = (fmt >> 8) & 0xFF
        self.relu = bool((fmt >> 16) & 1)
        self.output_size = self.input_size - self.window + 1
        self.reset()

    def read(self, reg):
        return self.mmio.read(REG[reg])

    def write(self, reg, value):
        self.mmio.write(REG[reg], int(value) & 0xFFFFFFFF)

    def reset(self):
        """Soft reset: clears the pipeline, the kernels and every counter."""
        self.write("CTRL", 1)
        self.write("CTRL", 0)
        self._loaded = None

    def load_kernels(self, kernels):
        """Write one N x N kernel per lane (between frames; no reset needed)."""
        for lane, kernel in enumerate(kernels):
            self.write("KERNEL_SEL", lane)
            for row in kernel:
                for weight in row[::-1]:                 # hardware tap order
                    self.write("WEIGHT", int(weight) & 0xFF)
        self._loaded = tuple(tuple(int(w) for w in k.reshape(-1)) for k in kernels)

    def run(self, image, kernels, timeout=10.0):
        """One frame, streamed after the previous one without a reset.

        image: uint8 (W, W); kernels: one N x N list per lane, written only when
        they differ from the kernels already loaded.
        Returns (features int32 (lanes, out, out), stats dict).
        """
        image = np.asarray(image, dtype=np.uint8)
        if image.shape != (self.input_size, self.input_size):
            raise ValueError("image must be %dx%d" % (self.input_size, self.input_size))
        kernels = [np.asarray(k, dtype=np.int64) for k in kernels]
        lanes = self.num_kernels
        while len(kernels) < lanes:                      # unused lanes repeat lane 0
            kernels.append(kernels[0])
        kernels = kernels[:lanes]

        t0 = time.time()
        wanted = tuple(tuple(int(w) for w in k.reshape(-1)) for k in kernels)
        if wanted != self._loaded:
            self.load_kernels(kernels)

        flat = image.reshape(-1).astype(np.uint32)
        whole = len(flat) // 4 * 4
        words = flat[:whole].reshape(-1, 4)
        words = words[:, 0] | (words[:, 1] << 8) | (words[:, 2] << 16) | (words[:, 3] << 24)
        for word in words:
            self.mmio.write(REG["PIXELS4"], int(word))
        for pixel in flat[whole:]:
            self.write("PIXEL", int(pixel))

        while not (self.read("STATUS") >> 2) & 1:
            if time.time() - t0 > timeout:
                raise RuntimeError("frame did not complete (OUT_COUNT %d)" % self.read("OUT_COUNT"))
        t1 = time.time()

        count = self.output_size ** 2
        features = np.empty((lanes, count), dtype=np.int32)
        for lane in range(lanes):
            base = FEATURE_BASE + (lane << (self.idx_bits + 2))
            raw = [self.mmio.read(base + 4 * i) for i in range(count)]
            features[lane] = np.array(raw, dtype=np.uint32).view(np.int32)
        t2 = time.time()

        stats = {
            "load_and_stream_s": t1 - t0,
            "readback_s": t2 - t1,
            "latency_cycles": self.read("LATENCY"),
            "frame_cycles": self.read("FRAME_CYCLES"),
            "frames_since_reset": self.read("FRAME_COUNT"),
        }
        return features.reshape(lanes, self.output_size, self.output_size), stats


# ----------------------------------------------------------------------------- demo
def save_grid(path, images, results):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    cols = 1 + max(len(r) for r in results)
    fig, axes = plt.subplots(len(images), cols, figsize=(2.2 * cols, 2.4 * len(images)), squeeze=False)
    for row, ((name, image), res) in enumerate(zip(images, results)):
        axes[row][0].imshow(image, cmap="gray", vmin=0, vmax=255)
        axes[row][0].set_title(name, fontsize=9)
        for col, (kname, hw, ok) in enumerate(res, start=1):
            axes[row][col].imshow(hw, cmap="gray")
            axes[row][col].set_title("%s %s" % (kname, "bit-exact" if ok else "MISMATCH"), fontsize=8)
    for ax in axes.flat:
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=120)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bit", help="overlay bitstream (default: conv_demo.bit next to this file)")
    parser.add_argument("--no-download", action="store_true", help="use the overlay already loaded")
    parser.add_argument("--image", action="append", default=[], help="picture file (repeatable)")
    parser.add_argument("--patterns", nargs="*", default=["bars", "checker", "circle"], choices=PATTERNS)
    parser.add_argument("--kernels", nargs="*", default=["sobel_x", "sobel_y", "laplacian", "gaussian", "sharpen"],
                        choices=sorted(DEMO_KERNELS))
    parser.add_argument("--model-only", action="store_true", help="no board: golden model only")
    parser.add_argument("--size", type=int, default=32, help="image size for --model-only")
    parser.add_argument("--save", default="conv_demo.png", help="result grid (needs matplotlib)")
    args = parser.parse_args(argv)

    accel = None
    size, window, lanes, relu = args.size, 3, 1, False
    if not args.model_only:
        accel = ConvAccelerator(args.bit, download=not args.no_download)
        size, window, lanes, relu = accel.input_size, accel.window, accel.num_kernels, accel.relu
        print("overlay: %dx%d image, %dx%d kernel, %d lane(s), ReLU %s"
              % (size, size, window, window, lanes, "on" if relu else "off"))
    if window != 3:
        print("demo kernels are 3x3; this overlay is %dx%d, using random kernels" % (window, window))

    images = [(p, pattern(p, size)) for p in args.patterns]
    images += [(os.path.basename(p), load_image(p, size)) for p in args.image]

    kernels = []
    for name in args.kernels:
        k = DEMO_KERNELS[name] if window == 3 else np.random.RandomState(len(kernels)).randint(-128, 128, (window, window))
        kernels.append((name, np.asarray(k)))

    failures, results = 0, []
    print("%-14s %-10s %10s %12s %10s" % ("image", "kernel", "mismatch", "stream (ms)", "latency"))
    for iname, image in images:
        row = []
        for start in range(0, len(kernels), lanes):
            batch = kernels[start:start + lanes]
            if accel is None:
                hw = np.stack([reference(image, k, relu) for _, k in batch])
                stats = {"load_and_stream_s": 0.0, "latency_cycles": "-"}
            else:
                hw, stats = accel.run(image, [k for _, k in batch])
            for lane, (kname, k) in enumerate(batch):
                ref = reference(image, k, relu)
                bad = int(np.count_nonzero(hw[lane] != ref))
                failures += bad
                row.append((kname, hw[lane], bad == 0))
                print("%-14s %-10s %10d %12.1f %10s"
                      % (iname, kname, bad, 1000 * stats["load_and_stream_s"], stats["latency_cycles"]))
        results.append(row)

    try:
        save_grid(args.save, images, results)
        print("saved %s" % args.save)
    except ImportError:
        print("matplotlib not available, no image saved")

    print("RESULT: %s" % ("all frames bit-exact" if failures == 0 else "%d mismatching features" % failures))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
