"""Render pages of a draw.io file to cropped PNGs (headless Chrome + viewer.diagrams.net).

usage: export_diagrams.py <file.drawio> <out_dir> [page names ...]
Each PNG is named after its page. The viewer URL can exceed the Windows
command-line limit, so Chrome opens a local page that redirects to it.
Needs Google Chrome, Pillow and network access to viewer.diagrams.net.
"""
import base64
import json
import subprocess
import sys
import urllib.parse
import xml.dom.minidom as md
import zlib
from pathlib import Path

from PIL import Image, ImageChops

SRC = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
ONLY = set(sys.argv[3:])
OUT.mkdir(parents=True, exist_ok=True)
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
WORK = Path(__file__).resolve().parent / ".diagram_build"
WORK.mkdir(exist_ok=True)
PROFILE = WORK / "chrome_headless_profile"


def pack(xml):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return base64.b64encode(c.compress(urllib.parse.quote(xml, safe="~()*!.'").encode()) + c.flush()).decode()


def bbox(model):
    xs, ys = [], []
    for c in md.parseString(model).getElementsByTagName("mxCell"):
        if c.getAttribute("vertex") != "1":
            continue
        g = c.getElementsByTagName("mxGeometry")[0]
        x, y = float(g.getAttribute("x") or 0), float(g.getAttribute("y") or 0)
        w, h = float(g.getAttribute("width") or 0), float(g.getAttribute("height") or 0)
        xs += [x, x + w]
        ys += [y, y + h]
    return min(xs), min(ys), max(xs), max(ys)


doc = md.parse(str(SRC))
for d in doc.getElementsByTagName("diagram"):
    name = d.getAttribute("name")
    if ONLY and name not in ONLY:
        continue
    model = d.getElementsByTagName("mxGraphModel")[0].toxml()
    x0, y0, x1, y1 = bbox(model)
    win_w = 1800
    win_h = int(win_w * (y1 - y0 + 80) / (x1 - x0 + 80)) + 200
    page = f'<mxfile><diagram id="p" name="p">{model}</diagram></mxfile>'
    url = "https://viewer.diagrams.net/?lightbox=1&highlight=0000ff&nav=0&toolbar=0#R" + pack(page)
    redirect = WORK / f"redirect_{name}.html"
    redirect.write_text(f"<meta charset='utf-8'><script>location.replace({json.dumps(url)})</script>", encoding="utf-8")
    raw = OUT / f"{name}_raw.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={PROFILE}",
                    f"--window-size={win_w},{win_h}", "--force-device-scale-factor=2",
                    "--virtual-time-budget=25000", f"--screenshot={raw}", redirect.as_uri()],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    img = Image.open(raw).convert("RGB")
    box = ImageChops.difference(img, Image.new("RGB", img.size, (255, 255, 255))).point(
        lambda v: 255 if v > 12 else 0).getbbox()
    if box:
        pad = 24
        img = img.crop((max(box[0] - pad, 0), max(box[1] - pad, 0),
                        min(box[2] + pad, img.width), min(box[3] + pad, img.height)))
    img.save(OUT / f"{name}.png", optimize=True)
    raw.unlink()
    print(f"{name:20s} {img.size}")
