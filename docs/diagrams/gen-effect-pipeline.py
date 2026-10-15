#!/usr/bin/env python3
"""Generates docs/effect-pipeline.svg — every effect as an input->output node.

Companion to docs/effect-pipeline-model.md. Shows the whole compositor as an
ordered chain of effects, each declared as (input image, params, aux) -> output
image, and how the renderer realizes that chain (fused transforms + real passes).
"""

import math

W = 1660
H = 2760

BG = "#0f141b"
PANEL = "#161d27"
PANEL2 = "#1b2431"
STROKE = "#2c3a4b"
TEXT = "#dbe6f2"
MUTED = "#89a7ad"
SUB = "#6f8794"

SEED = "#54d17a"       # green  - seed composite
TRANS = "#4aa3ff"      # blue   - transform (fusable)
COMP = "#8f7dff"       # violet - composite (geometry)
FB = "#ffb02e"         # amber  - feedback (history)
GATHER = "#3fd0c9"     # teal   - gather (resample)
WARM = FB

out = []
def add(s): out.append(s)
def esc(t): return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def rect(x, y, w, h, fill=PANEL, stroke=STROKE, rx=10, sw=1.4, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

def text(x, y, s, size=14, fill=TEXT, weight="400", anchor="start", opacity=1, mono_f=False):
    fam = "SF Mono, Menlo, Consolas, monospace" if mono_f else \
          "Helvetica Neue, Helvetica, Arial, sans-serif"
    add(f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" '
        f'fill="{fill}" font-weight="{weight}" text-anchor="{anchor}" '
        f'opacity="{opacity}">{esc(s)}</text>')

def mono(x, y, s, size=12.5, fill=TEXT, anchor="start", weight="400", opacity=1):
    text(x, y, s, size=size, fill=fill, anchor=anchor, weight=weight, opacity=opacity, mono_f=True)

def center(x, y, s, **kw):
    kw.setdefault("anchor", "middle"); text(x, y, s, **kw)

def arrow(x1, y1, x2, y2, color=STROKE, sw=2.0, dash=None, marker="arrow"):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
        f'stroke-width="{sw}"{d} marker-end="url(#{marker})"/>')

def pill(x, y, s, col, size=10.5):
    w = len(s) * size * 0.62 + 18
    add(f'<rect x="{x}" y="{y}" width="{w}" height="20" rx="10" '
        f'fill="{col}" opacity="0.18"/>')
    text(x + w / 2, y + 14, s, size=size, fill=col, anchor="middle", weight="600")
    return x + w

# ---------------------------------------------------------------- defs
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
add('<defs>')
for name, col in [("arrow", STROKE), ("arrowSeed", SEED), ("arrowT", TRANS),
                  ("arrowV", COMP), ("arrowF", FB), ("arrowK", GATHER)]:
    add(f'<marker id="{name}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
        f'markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="{col}"/></marker>')
add('<linearGradient id="hdr" x1="0" y1="0" x2="1" y2="0">'
    f'<stop offset="0" stop-color="{GATHER}" stop-opacity="0.22"/>'
    f'<stop offset="1" stop-color="{GATHER}" stop-opacity="0.02"/></linearGradient>')
add('</defs>')
add(f'<rect width="{W}" height="{H}" fill="{BG}"/>')

# ---------------------------------------------------------------- header
add(f'<rect x="0" y="0" width="{W}" height="96" fill="url(#hdr)"/>')
text(48, 46, "Kinetic Canvas — the effect pipeline", size=28, weight="700")
text(48, 74, "Every effect is one function:  (input image, params, aux) → output image.  "
             "Order = position in the FX stack.", size=15, fill=MUTED)

x0 = 48

# ================================================================ 1. THE MODEL
y = 122
rect(x0, y, 1564, 148, rx=14)
text(x0 + 22, y + 32, "1 · The contract", size=16, weight="700", fill=GATHER)

# schematic chain
sx = x0 + 40
sy = y + 92
bw, bh = 118, 52
def chip(x, label, col, sub=None, w=bw):
    rect(x, sy - bh / 2, w, bh, fill=PANEL2, stroke=col, sw=1.6)
    center(x + w / 2, sy - 2, label, size=12.5, weight="600", fill=col)
    if sub:
        center(x + w / 2, sy + 15, sub, size=9.5, fill=SUB)

chip(sx, "I₀  input", SEED, "prev output")
mono(sx + bw + 26, sy + 5, "→", size=22, fill=SUB)
gx = sx + bw + 62
rect(gx, sy - bh / 2, 150, bh, fill="#0e1f20", stroke=GATHER, sw=2.0)
center(gx + 75, sy - 4, "FXᵢ", size=15, weight="700", fill=GATHER)
center(gx + 75, sy + 15, "reads in · writes out", size=9.5, fill=SUB)
mono(gx + 176, sy + 5, "→", size=22, fill=SUB)
chip(gx + 212, "Iᵢ₊₁  output", SEED, "next input")

text(gx + 360, sy - 2, "The same texture flows through; each stage owns one transform.", size=12, fill=MUTED)
text(gx + 360, sy + 18, "Reorder the stack  →  reorder the functions. No hidden state between FX.", size=12, fill=MUTED)

# ================================================================ 2. CHAIN
y = 300
CHAIN_H = 1180
rect(x0, y, 1564, CHAIN_H, rx=14)
text(x0 + 22, y + 32, "2 · The full pipeline — every effect as an input → output node",
     size=16, weight="700", fill=TEXT)
text(x0 + 22, y + 54, "Default order shown. Each node names the image it consumes (IN) and the image it "
     "produces (OUT); the renderer decides which nodes share a GPU pass.", size=12, fill=MUTED)

spine = x0 + 70
nx0, nw = x0 + 120, 940
nh, ngap = 74, 14
cy = y + 96

def node(i, name, cat, catcol, in_img, out_img, cost, detail, fused=False):
    global cy
    rect(nx0, cy, nw, nh, fill=PANEL2 if not fused else "#121a24",
         stroke=catcol, sw=1.7)
    # index
    add(f'<circle cx="{nx0+30}" cy="{cy+nh/2}" r="16" fill="{catcol}" opacity="0.16"/>')
    center(nx0 + 30, cy + nh / 2 + 5, str(i), size=13, weight="700", fill=catcol)
    # title + badge
    text(nx0 + 58, cy + 28, name, size=14.5, weight="600")
    px = nx0 + 58 + len(name) * 8.0 + 14
    pill(px, cy + 14, cat, catcol)
    # in/out
    mono(nx0 + 58, cy + 54, f"IN  {in_img}", size=11.5, fill=SUB)
    mono(nx0 + 250, cy + 54, f"OUT {out_img}", size=11.5, fill=SUB)
    mono(nx0 + 470, cy + 54, detail, size=11, fill=SUB)
    # cost badge
    text(nx0 + nw - 16, cy + 30, cost, size=11, fill=catcol, anchor="end", weight="600")
    # spine tick + label
    add(f'<circle cx="{spine}" cy="{cy+nh/2}" r="4" fill="{catcol}"/>')
    text(spine - 14, cy + nh / 2 + 4, in_img, size=10.5, fill=SUB, anchor="end")
    cy += nh
    if i is not None and name != "Line Sampler":
        arrow(spine, cy + 1, spine, cy + ngap - 1, color=catcol, sw=1.8)
    cy += ngap

# seed
node(0, "Composite subject over background", "seed", SEED, "I0  camera+alpha", "I1",
     "1 fused pass", "foreground × matte over background", fused=True)
# transforms (fused together)
node(1, "Gradient Overlay", "transform", TRANS, "I1", "I2", "fused", "tint by gradient ramp")
node(2, "Video Fill", "transform", TRANS, "I2", "I3", "fused", "blend video texture")
node(3, "Liquid Distortion", "transform", TRANS, "I3", "I4", "fused", "warp sampling UV")
# feedback
node(4, "Historical Trail", "feedback", FB, "I4", "I5", "N passes", "ring of past snapshots")
# composites
node(5, "Skeleton", "composite", COMP, "I5", "I6", "1 pass", "bone quads")
node(6, "Lines", "composite", COMP, "I6", "I7", "1 pass", "nearest-neighbour mesh")
node(7, "Particles", "composite", COMP, "I7", "I8", "1 pass", "point sprites")

# ── image / post boundary ──────────────────────────────────────────────
add(f'<line x1="{nx0-16}" y1="{cy-7}" x2="{nx0+nw+16}" y2="{cy-7}" stroke="{FB}" '
    f'stroke-width="1.5" stroke-dasharray="6 5"/>')
text(nx0 + nw + 30, cy + 12, "↑ IMAGE pipeline", size=11.5, fill=SUB, weight="600")
text(nx0 + nw + 30, cy + 30, "the frame is composited here;", size=10.5, fill=SUB)
text(nx0 + nw + 30, cy + 45, "reorder freely inside the stage", size=10.5, fill=SUB)
text(nx0 + nw + 30, cy + 75, "↓ POST", size=11.5, fill=FB, weight="600")
text(nx0 + nw + 30, cy + 93, "sees the finished frame; always", size=10.5, fill=SUB)
text(nx0 + nw + 30, cy + 108, "runs last — the boundary is fixed", size=10.5, fill=SUB)

node(8, "Clap Explosions", "composite", COMP, "I8", "I9", "1 pass", "video sprite")
# gather
node(9, "Kaleidoscope", "gather", GATHER, "I9", "I10", "blit + 1 pass", "fold output of I9")
# feedback
node(10, "Line Sampler", "feedback", FB, "I10", "I11", "1 pass × lines", "strip history")
node(11, "present(drawable)", "seed", SEED, "I11", "—", "swapchain", "screen", fused=True)

# fusion bracket around seed..liquid
b_top = y + 96
b_bot = y + 96 + 4 * (nh + ngap) - ngap
bx = nx0 - 20
add(f'<path d="M {bx} {b_top} h -12 v {b_bot-b_top} h 12" fill="none" stroke="{TRANS}" '
    f'stroke-width="2" stroke-dasharray="6 4"/>')
mono(bx - 18, (b_top + b_bot) / 2, "fused into one kernel", size=10.5, fill=TRANS,
     anchor="middle")

# ================================================================ 3. REALIZATION
y = 1510
rect(x0, y, 1564, 430, rx=14)
text(x0 + 22, y + 32, "3 · How the renderer realizes the chain", size=16, weight="700", fill=GATHER)
text(x0 + 22, y + 54, "Adjacent transforms share a pass (fusion). Every other category "
     "owns a real pass. Textures ping-pong so a pass never reads what it writes.",
     size=12, fill=MUTED)

# fusion lane
fy = y + 92
rect(x0 + 30, fy, 860, 120, fill=PANEL2, rx=10)
text(x0 + 48, fy + 28, "segments the scheduler can fuse", size=12.5, weight="600", fill=TRANS)
for i, (nm, col) in enumerate([("Gradient", TRANS), ("Video", TRANS), ("Liquid", TRANS)]):
    bx2 = x0 + 56 + i * 150
    rect(bx2, fy + 42, 130, 56, fill="#0e1f20", stroke=col, sw=1.4)
    center(bx2 + 65, fy + 68, nm, size=12, weight="600", fill=col)
    center(bx2 + 65, fy + 86, "transform", size=9.5, fill=SUB)
    if i < 2:
        mono(bx2 + 137, fy + 76, "→", size=16, fill=SUB)
mono(x0 + 508, fy + 76, "⟶  executed as ONE compute dispatch", size=12, fill=TRANS)

# pass lane
px2 = x0 + 910
rect(px2, fy, 624, 120, fill=PANEL2, rx=10)
text(px2 + 18, fy + 28, "categories that need their own pass", size=12.5, weight="600", fill=MUTED)
for i, (nm, col) in enumerate([("composite", COMP), ("feedback", FB), ("gather", GATHER)]):
    bx3 = px2 + 20 + i * 196
    rect(bx3, fy + 42, 176, 56, fill="#0e1f20", stroke=col, sw=1.4)
    center(bx3 + 88, fy + 68, nm, size=12, weight="600", fill=col)
    center(bx3 + 88, fy + 86, "geometry / history / resample", size=9, fill=SUB)

# buffers
by3 = fy + 158
text(x0 + 30, by3, "buffers", size=12.5, weight="600", fill=GATHER)
bufs = [("A / B", "ping-pong colour", GATHER), ("ring", "trail + strip history", FB),
        ("aux", "camera · alpha · video", TRANS)]
for i, (nm, dt, col) in enumerate(bufs):
    bx4 = x0 + 120 + i * 300
    rect(bx4, by3 - 18, 280, 44, fill=PANEL2, stroke=col, sw=1.2)
    mono(bx4 + 16, by3 + 6, nm, size=12, fill=col)
    text(bx4 + 70, by3 + 6, dt, size=11, fill=SUB)

text(x0 + 30, by3 + 78,
     "Cost rule:  bandwidth = passes × resolution.  Fusion is not an optimisation bolted on — "
     "it is how the model stays affordable.", size=12, fill=WARM)

# ================================================================ 4. CATEGORIES
y = 1980
rect(x0, y, 1564, 330, rx=14)
text(x0 + 22, y + 32, "4 · Effect categories", size=16, weight="700", fill=TEXT)
cats = [
    (SEED, "seed", "produces the starting image",
     "camera × matte over background"),
    (TRANS, "transform", "pixel-local map of the image",
     "Gradient · Video · Liquid · (colour grade)"),
    (COMP, "composite", "draws new geometry on top",
     "Skeleton · Lines · Particles · Explosions"),
    (FB, "feedback", "reads past frames",
     "Historical Trail · Line Sampler"),
    (GATHER, "gather", "re-samples the image by coordinate",
     "Kaleidoscope"),
]
cy4 = y + 70
for col, name, desc, members in cats:
    rect(x0 + 30, cy4, 1500, 44, fill=PANEL2, stroke=col, sw=1.2)
    add(f'<rect x="{x0+30}" y="{cy4}" width="6" height="44" rx="3" fill="{col}"/>')
    mono(x0 + 52, cy4 + 27, name, size=13, fill=col)
    text(x0 + 210, cy4 + 27, desc, size=12, fill=TEXT)
    text(x0 + 620, cy4 + 27, members, size=12, fill=MUTED)
    cy4 += 50

# ================================================================ 5. ORDERING
y = 2350
rect(x0, y, 1564, 300, rx=14)
text(x0 + 22, y + 32, "5 · Ordering — today vs the explicit model", size=16, weight="700", fill=WARM)

# today
rect(x0 + 30, y + 56, 740, 220, fill=PANEL2, rx=10)
text(x0 + 50, y + 86, "TODAY  (implicit)", size=13, weight="700", fill=MUTED)
mono(x0 + 50, y + 118, "effectOrder: [EffectKind]   // enabled, in order", size=11.5, fill=TEXT)
mono(x0 + 50, y + 142, "gradientOrder  = index(.gradientOverlay)", size=11.5, fill=SUB)
mono(x0 + 50, y + 162, "liquidOrder    = index(.liquidDistortion)", size=11.5, fill=SUB)
mono(x0 + 50, y + 182, "videoOrder     = index(.liveVideoFill)", size=11.5, fill=SUB)
mono(x0 + 50, y + 202, "linesOrder / particleOrder / historicalOrder", size=11.5, fill=SUB)
mono(x0 + 50, y + 222, "processingLimitOrder", size=11.5, fill=SUB)
text(x0 + 50, y + 250, "Shaders compare these integers per pixel to decide", size=11.5, fill=MUTED)
text(x0 + 50, y + 268, "who has already run. Ordering lives inside kernels.", size=11.5, fill=MUTED)

# proposed
rect(x0 + 794, y + 56, 740, 220, fill="#0e1f20", rx=10)
text(x0 + 814, y + 86, "PROPOSED  (explicit)", size=13, weight="700", fill=GATHER)
mono(x0 + 814, y + 118, "protocol Effect {", size=11.5, fill=TEXT)
mono(x0 + 814, y + 138, "    var input:  TextureID", size=11.5, fill=GATHER)
mono(x0 + 814, y + 158, "    var output: TextureID", size=11.5, fill=GATHER)
mono(x0 + 814, y + 178, "    func encode(into cb: CommandBuffer)", size=11.5, fill=TEXT)
mono(x0 + 814, y + 198, "}", size=11.5, fill=TEXT)
mono(x0 + 814, y + 224, "pipeline = effects.map { $0.stage() }", size=11.5, fill=TEXT)
text(x0 + 814, y + 250, "Scheduler fuses adjacent transforms, then walks", size=11.5, fill=MUTED)
text(x0 + 814, y + 268, "the list. Order is the array; no per-pixel integers.", size=11.5, fill=MUTED)

# ---------------------------------------------------------------- legend
ly = 2680
legend = [(SEED, "seed"), (TRANS, "transform (fusable)"), (COMP, "composite"),
          (FB, "feedback"), (GATHER, "gather")]
lx = x0 + 6
for col, lbl in legend:
    add(f'<rect x="{lx}" y="{ly-12}" width="16" height="16" rx="4" fill="{col}" opacity="0.85"/>')
    text(lx + 26, ly + 2, lbl, size=12, fill=MUTED)
    lx += 70 + len(lbl) * 6.6
add('</svg>')

with open("docs/effect-pipeline.svg", "w") as f:
    f.write("\n".join(out))
print("wrote docs/effect-pipeline.svg")
