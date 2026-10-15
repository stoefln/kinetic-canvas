#!/usr/bin/env python3
"""Generates docs/kaleidoscope-processing.svg.

Documents one change: the Kaleidoscope effect added to the Metal compositor in
Sources/KineticCanvas/Rendering/MetalRenderer.swift. It is a gather pass over
the composited drawable, inserted into the per-frame pass chain at a slot chosen
from the FX-stack order.
"""

import math

W = 1660
H = 2660

BG = "#0f141b"
PANEL = "#161d27"
PANEL2 = "#1b2431"
STROKE = "#2c3a4b"
TEXT = "#dbe6f2"
MUTED = "#89a7ad"
ACCENT = "#3fd0c9"      # teal   - kaleidoscope
WARM = "#ffb02e"        # amber  - pose / joints
VIOLET = "#8f7dff"      # violet - pass machinery
BLUE = "#4aa3ff"
GREEN = "#54d17a"

out = []
def add(s): out.append(s)

def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def rect(x, y, w, h, fill=PANEL, stroke=STROKE, rx=10, sw=1.4, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

def text(x, y, s, size=14, fill=TEXT, weight="400", anchor="start",
         family="Helvetica Neue, Helvetica, Arial, sans-serif", opacity=1):
    add(f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" '
        f'fill="{fill}" font-weight="{weight}" text-anchor="{anchor}" '
        f'opacity="{opacity}">{esc(s)}</text>')

def mono(x, y, s, size=13, fill=TEXT, anchor="start", weight="400", opacity=1):
    text(x, y, s, size=size, fill=fill, anchor=anchor, weight=weight,
         family="SF Mono, Menlo, Consolas, monospace", opacity=opacity)

def arrow(x1, y1, x2, y2, color=STROKE, sw=2.0, dash=None, marker="arrow"):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
        f'stroke-width="{sw}"{d} marker-end="url(#{marker})"/>')

def center_text(x, y, s, **kw):
    kw.setdefault("anchor", "middle")
    text(x, y, s, **kw)

def section(x, y, w, h, num, title, color, subtitle=None):
    rect(x, y, w, h, fill=PANEL, rx=14)
    text(x + 22, y + 32, f"{num} · {title}", size=16, weight="700", fill=color)
    if subtitle:
        text(x + 22, y + 54, subtitle, size=12, fill=MUTED)

# ---------------------------------------------------------------- defs
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
    f'viewBox="0 0 {W} {H}">')
add('<defs>')
for name, col in [("arrow", STROKE), ("arrowA", ACCENT), ("arrowW", WARM),
                  ("arrowV", VIOLET), ("arrowB", BLUE)]:
    add(f'<marker id="{name}" viewBox="0 0 10 10" refX="9" refY="5" '
        f'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{col}"/></marker>')
add('<linearGradient id="hdr" x1="0" y1="0" x2="1" y2="0">'
    f'<stop offset="0" stop-color="{ACCENT}" stop-opacity="0.22"/>'
    f'<stop offset="1" stop-color="{ACCENT}" stop-opacity="0.02"/></linearGradient>')
add('</defs>')
add(f'<rect width="{W}" height="{H}" fill="{BG}"/>')

# ---------------------------------------------------------------- header
add(f'<rect x="0" y="0" width="{W}" height="96" fill="url(#hdr)"/>')
text(48, 46, "Kaleidoscope — processing change", size=28, weight="700")
text(48, 74, "MetalRenderer.swift  ·  a gather pass over the composited drawable, "
             "slotted by FX-stack order", size=15, fill=MUTED)

# ================================================================ 1. ACQUISITION
x0 = 48
y = 130
rect(x0, y, 1564, 188, rx=14)
text(x0 + 22, y + 32, "1 · Acquisition  (per frame)", size=16, weight="700", fill=BLUE)

rect(x0 + 24, y + 52, 200, 54, fill=PANEL2, stroke=BLUE)
center_text(x0 + 124, y + 78, "Camera frame", size=14, weight="600")
center_text(x0 + 124, y + 96, "CVPixelBuffer", size=11, fill=MUTED)
arrow(x0 + 228, y + 79, x0 + 300, y + 79, color=BLUE, marker="arrowB", sw=2.2)

rect(x0 + 304, y + 52, 240, 54, fill=PANEL2, stroke=BLUE)
center_text(x0 + 424, y + 78, "RVM matting (Core ML)", size=13.5, weight="600")
center_text(x0 + 424, y + 96, "recurrent single pass", size=11, fill=MUTED)
arrow(x0 + 548, y + 79, x0 + 620, y + 79, color=BLUE, marker="arrowB", sw=2.2)

rect(x0 + 624, y + 44, 210, 76, fill=PANEL2, stroke=BLUE)
mono(x0 + 640, y + 70, "source  (color)", size=12)
mono(x0 + 640, y + 92, "alpha   (matte)", size=12)
center_text(x0 + 729, y + 132, "Metal textures", size=10.5, fill=MUTED)

rect(x0 + 900, y + 52, 250, 54, fill=PANEL2, stroke=WARM)
center_text(x0 + 1025, y + 78, "BodyPoseDetector.detect", size=13, weight="600", fill=WARM)
center_text(x0 + 1025, y + 96, "every 2nd frame · Vision", size=10.5, fill=MUTED)
arrow(x0 + 1154, y + 79, x0 + 1226, y + 79, color=WARM, marker="arrowW", sw=2.2)

rect(x0 + 1230, y + 44, 306, 76, fill=PANEL2, stroke=WARM)
mono(x0 + 1246, y + 70, "updatePose(_:)  →  latestPoses", size=12, fill=WARM)
mono(x0 + 1246, y + 92, "joints + confidence + track id", size=11.5, fill=MUTED)
center_text(x0 + 1383, y + 132, "fresh while ≤ 0.6 s old", size=10.5, fill=MUTED)

text(x0 + 24, y + 168,
     "Both feed the same draw(): matting textures become the base image; latestPoses "
     "are read only when the anchor is a joint.", size=12, fill=MUTED)

# ================================================================ 2. CHAIN
y = 348
rect(x0, y, 1030, 1120, rx=14)
text(x0 + 22, y + 32, "2 · Per-frame pass chain  →  one drawable texture",
     size=16, weight="700", fill=VIOLET)
text(x0 + 22, y + 54,
     "Every pass reads and writes the same drawable. The Kaleidoscope (teal) can be "
     "placed at slot A, B or C.", size=12, fill=MUTED)

cx, cw = x0 + 60, 600

def step(yy, num, name, detail, col=STROKE, h=62):
    rect(cx, yy, cw, h, fill=PANEL2, stroke=col, sw=1.6)
    add(f'<circle cx="{cx+26}" cy="{yy+h/2}" r="15" fill="{col}" opacity="0.16"/>')
    center_text(cx + 26, yy + h/2 + 5, str(num), size=14, weight="700", fill=col)
    text(cx + 54, yy + 25, name, size=14, weight="600")
    text(cx + 54, yy + 45, detail, size=11.5, fill=MUTED)
    return yy + h

def slot(yy, letter, when, h=58):
    rect(cx - 14, yy, cw + 28, h, fill="#0e1f20", stroke=ACCENT, sw=2.2, dash="7 5")
    add(f'<circle cx="{cx+26}" cy="{yy+h/2}" r="15" fill="{ACCENT}" opacity="0.20"/>')
    center_text(cx + 26, yy + h/2 + 5, letter, size=14, weight="700", fill=ACCENT)
    text(cx + 54, yy + 24, "KALEIDOSCOPE  (gather pass)", size=13.5, weight="700", fill=ACCENT)
    text(cx + 54, yy + 44, when, size=11, fill=MUTED)
    return yy + h

GAP = 30
cy = y + 82
for i, (nm, dt) in enumerate([
    ("basePass", "fills background into drawable  (mode 0/1 = original / matte)"),
    ("signal snapshot", "if trails on: half-res snapshot capture"),
    ("trailPass  × cloneCount", "historical clone layers composited onto drawable"),
    ("subjectPass", "composites subject; folds gradient / video / liquid by order"),
    ("encodePoseOverlays", "skeleton · lines · particles (vertex + fragment)"),
]):
    cy = step(cy, i + 1, nm, dt)
    arrow(cx + 26, cy + 1, cx + 26, cy + GAP - 1, sw=1.8)
    cy += GAP

cy = slot(cy, "A", "runs when: explosions enabled AND  i < index(.clapExplosions)")
arrow(cx + 26, cy + 1, cx + 26, cy + GAP - 1, sw=1.8)
cy += GAP

cy = step(cy, 6, "encodeClapExplosions", "per-clap video sprite composited")
arrow(cx + 26, cy + 1, cx + 26, cy + GAP - 1, sw=1.8)
cy += GAP

cy = slot(cy, "B", "runs when: NOT before-explosions AND  i < index(.lineSampler)")
arrow(cx + 26, cy + 1, cx + 26, cy + GAP - 1, sw=1.8)
cy += GAP

cy = step(cy, 7, "encodeLineSampler", "blit + per-line strip composite + occupancy read")
arrow(cx + 26, cy + 1, cx + 26, cy + GAP - 1, sw=1.8)
cy += GAP

cy = slot(cy, "C", "runs when: NOT before-explosions AND NOT before-sampler (fallthrough)")
arrow(cx + 26, cy + 1, cx + 26, cy + GAP - 1, sw=1.8)
cy += GAP

cy = step(cy, 8, "thumbnail capture  →  present(drawable)",
          "optional 640×360 CGImage; then swapchain")

text(cx - 14, cy + 30,
     "Guard on every slot:  kaleidoscopeEnabled  AND  displayMode ≥ Foreground  "
     "(Original / Alpha Matte stay clean).", size=11.5, fill=ACCENT, opacity=0.95)

# ---------------------------------------------------------------- 3. ORDERING
px, pw = x0 + 1080, 484
rect(px, y, pw, 620, rx=14)
text(px + 20, y + 32, "3 · Ordering decision", size=16, weight="700", fill=GREEN)
text(px + 20, y + 54, "effectOrder = enabled effects, in stack order", size=11.5, fill=MUTED)

mono(px + 20, y + 90, "let kaleidoOrder  = index(.kaleidoscope)", size=12, fill=ACCENT)
mono(px + 20, y + 114, "let kaleidoActive = enabled && mode ≥ fg", size=12, fill=TEXT)
add(f'<line x1="{px+20}" y1="{y+134}" x2="{px+pw-20}" y2="{y+134}" stroke="{STROKE}" stroke-width="1"/>')

mono(px + 20, y + 164, "runBeforeExplosions =", size=12, fill=GREEN)
mono(px + 40, y + 184, "explosionsOn && kaleidoOrder", size=11.5, fill=MUTED)
mono(px + 40, y + 202, "             < index(.clapExplosions)", size=11.5, fill=MUTED)

mono(px + 20, y + 234, "runBeforeSampler =", size=12, fill=GREEN)
mono(px + 40, y + 254, "samplerOn && kaleidoOrder", size=11.5, fill=MUTED)
mono(px + 40, y + 272, "          < index(.lineSampler)", size=11.5, fill=MUTED)

rect(px + 20, y + 294, pw - 40, 116, fill=PANEL2, rx=8)
mono(px + 36, y + 320, "slot = before-explosions ? A", size=12, fill=ACCENT)
mono(px + 36, y + 344, "     : before-sampler      ? B", size=12, fill=ACCENT)
mono(px + 36, y + 368, "     :                      C", size=12, fill=ACCENT)
text(px + 36, y + 394, "disabled stages are skipped, not sentinels", size=10.5, fill=MUTED)

text(px + 20, y + 440, "Why it matters", size=13, weight="700", fill=GREEN)
text(px + 20, y + 464, "Slot A / B → the Line Sampler captures", size=11.5)
text(px + 20, y + 482, "unfolded pixels.", size=11.5)
text(px + 20, y + 506, "Slot C     → the sampler captures the", size=11.5)
text(px + 20, y + 524, "folded image (lines feed on the fold).", size=11.5)
text(px + 20, y + 556, "The fold always covers subject, trails", size=11.5, fill=WARM)
text(px + 20, y + 574, "and overlays — it cannot run beneath them.", size=11.5, fill=WARM)

# ---------------------------------------------------------------- 4. PRESET STATE
pty = 990
rect(px, pty, pw, 488, rx=14)
text(px + 20, pty + 32, "4 · Persisted state", size=16, weight="700", fill=VIOLET)
text(px + 20, pty + 54, "EffectPreset fields — all optional, older presets decode cleanly",
     size=11, fill=MUTED)

fields = [
    "kaleidoscopeSegments: Int?",
    "kaleidoscopeRotationDegrees: Double?",
    "kaleidoscopeSpeed: Double?",
    "kaleidoscopeZoom: Double?",
    "kaleidoscopeOpacity: Double?",
    "kaleidoscopeJoint: String?   // rawValue",
    "kaleidoscopePersonIndex: Int?",
    "kaleidoscopeOffsetX: Double?",
    "kaleidoscopeOffsetY: Double?",
]
fy2 = pty + 86
for s in fields:
    mono(px + 22, fy2, s, size=11.5, fill=TEXT)
    fy2 += 25

add(f'<line x1="{px+20}" y1="{fy2-4}" x2="{px+pw-20}" y2="{fy2-4}" stroke="{STROKE}" stroke-width="1"/>')
text(px + 20, fy2 + 24, "AppController @Published mirrors every field and", size=11, fill=MUTED)
text(px + 20, fy2 + 42, "pushes them to the renderer via syncEffects().", size=11, fill=MUTED)
text(px + 20, fy2 + 72, "effectBlendModes[.kaleidoscope] round-trips the", size=11, fill=MUTED)
text(px + 20, fy2 + 90, "card's blend mode, layered over the Mix slider.", size=11, fill=MUTED)

rect(px + 20, fy2 + 108, pw - 40, 62, fill="#2a1f0e", stroke=WARM, rx=8, sw=1.2)
text(px + 36, fy2 + 132, "An unknown joint from a newer build", size=11, fill=WARM)
text(px + 36, fy2 + 150, "degrades to the frame center rather than", size=11, fill=WARM)
text(px + 36, fy2 + 166, "failing to decode the whole preset.", size=11, fill=WARM)

# ================================================================ 5. PASS INTERNALS
py = 1502
rect(x0, py, 1564, 300, rx=14)
text(x0 + 22, py + 32, "5 · Inside encodeKaleidoscope  (MetalRenderer.swift)",
     size=16, weight="700", fill=ACCENT)

bx, by = x0 + 40, py + 70
rect(bx, by, 300, 118, fill=PANEL2, stroke=VIOLET, rx=10)
text(bx + 18, by + 32, "① blit", size=14, weight="700", fill=VIOLET)
mono(bx + 18, by + 58, "drawable  →  scratch", size=12.5)
mono(bx + 18, by + 80, "bgra8Unorm · private", size=11, fill=MUTED)
mono(bx + 18, by + 100, "snapshot of everything so far", size=10.5, fill=MUTED)

arrow(bx + 312, by + 59, bx + 392, by + 59, color=ACCENT, marker="arrowA", sw=2.4)

kx = bx + 396
rect(kx, by, 512, 118, fill="#0e1f20", stroke=ACCENT, rx=10, sw=2.0)
text(kx + 18, by + 32, "② compute  kaleidoscopePass", size=14, weight="700", fill=ACCENT)
mono(kx + 18, by + 58, "in  scratch (texture 0)   out  drawable (texture 1)", size=11.5)
mono(kx + 18, by + 80, "params: kaleidoSegments/Rotation/Speed/", size=11, fill=MUTED)
mono(kx + 18, by + 98, "        Zoom/Opacity/Blend/CenterX/Y", size=11, fill=MUTED)

arrow(kx + 524, by + 59, kx + 604, by + 59, color=ACCENT, marker="arrowA", sw=2.4)

rx2 = kx + 608
rect(rx2, by, 500, 118, fill=PANEL2, rx=10)
text(rx2 + 18, by + 32, "③ result written back to drawable", size=13.5, weight="600")
mono(rx2 + 18, by + 60, "folded = scratch.sample( kaleidoUV(uv) )", size=11.5)
mono(rx2 + 18, by + 80, "base   = scratch.sample( uv )", size=11.5)
mono(rx2 + 18, by + 100, "out    = trailBlend(base, folded,", size=11.5, fill=ACCENT)
mono(rx2 + 296, by + 100, "opacity, blend)", size=11.5, fill=ACCENT)

text(x0 + 40, by + 152,
     "One full-resolution compute pass (single sample per pixel) + one blit, only while "
     "enabled. Wedge count is free; cost scales with output resolution.", size=12, fill=MUTED)

# ================================================================ 6. FOLD MATH
fy = 1836
rect(x0, fy, 950, 560, rx=14)
text(x0 + 22, fy + 32, "6 · The fold  —  kaleidoUV(uv, params)",
     size=16, weight="700", fill=ACCENT)
text(x0 + 22, fy + 54, "maps an output coordinate to the source pixel it reads",
     size=11.5, fill=MUTED)

code_x, code_y = x0 + 26, fy + 84
lines = [
    ("float segments = max(2, kaleidoSegments);", TEXT),
    ("float2 p = uv - center;", TEXT),
    ("p.x *= viewAspect;                 // aspect-correct", MUTED),
    ("float r = length(p);", TEXT),
    ("float wedge = TWO_PI / segments;   // one wedge's angle", MUTED),
    ("", TEXT),
    ("float a = atan2(p.y, p.x)", TEXT),
    ("        + rotation + time*speed;   // base angle + spin", MUTED),
    ("", TEXT),
    ("a = fmod(a, wedge);                // fold into one wedge", ACCENT),
    ("if (a < 0) a += wedge;", TEXT),
    ("a = a > wedge*0.5 ? wedge - a : a; // mirror  ← symmetry", ACCENT),
    ("", TEXT),
    ("r *= max(0.05, zoom);              // radial scale", TEXT),
    ("float2 folded = float2(cos(a), sin(a)) * r;", ACCENT),
    ("folded.x /= viewAspect;", MUTED),
    ("return folded + center;", ACCENT),
]
yy = code_y
for s, col in lines:
    if s:
        mono(code_x, yy, s, size=12.5, fill=col)
    yy += 24

# polar illustration (inside panel 6)
pcx, pcy, R, N = x0 + 790, fy + 320, 96, 6
center_text(pcx, pcy - R - 22, "one wedge, mirrored", size=12.5, weight="700", fill=ACCENT)
add(f'<circle cx="{pcx}" cy="{pcy}" r="{R}" fill="#0e1f20" stroke="{STROKE}" stroke-width="1.6"/>')
for i in range(N):
    a = (2 * math.pi / N) * i - math.pi / 2
    add(f'<line x1="{pcx}" y1="{pcy}" x2="{pcx + R*math.cos(a)}" '
        f'y2="{pcy + R*math.sin(a)}" stroke="{STROKE}" stroke-width="1.2"/>')
a0 = -math.pi / 2
a1 = a0 + 2 * math.pi / N
px1, py1 = pcx + R * math.cos(a0), pcy + R * math.sin(a0)
px2, py2 = pcx + R * math.cos(a1), pcy + R * math.sin(a1)
add(f'<path d="M {pcx} {pcy} L {px1} {py1} A {R} {R} 0 0 1 {px2} {py2} Z" '
    f'fill="{ACCENT}" opacity="0.16" stroke="{ACCENT}" stroke-width="1.6"/>')
am = a0 + math.pi / N
add(f'<line x1="{pcx}" y1="{pcy}" x2="{pcx + R*math.cos(am)}" '
    f'y2="{pcy + R*math.sin(am)}" stroke="{ACCENT}" stroke-width="1.4" stroke-dasharray="5 4"/>')
add(f'<circle cx="{pcx}" cy="{pcy}" r="4" fill="{ACCENT}"/>')
center_text(pcx, pcy - 7, "center", size=10, fill=ACCENT)
center_text(pcx, pcy + R + 26, "segments = 6 → wedge = 60°", size=11, fill=MUTED)
center_text(pcx, pcy + R + 44, "dashed line = mirror axis", size=10.5, fill=ACCENT)

# ================================================================ 7. ANCHOR
ax, aw = x0 + 974, 590
rect(ax, fy, aw, 560, rx=14)
text(ax + 20, fy + 32, "7 · Joint anchor  →  kaleidoCenter",
     size=16, weight="700", fill=WARM)

mono(ax + 20, fy + 70, "kaleidoscopeCenter(poses, viewAspect)", size=12.5, fill=WARM)
for i, (s, c) in enumerate([
    ("joint == nil             → (0.5, 0.5)", MUTED),
    ("personIndex out of range → (0.5, 0.5)", MUTED),
    ("confidence < 0.25        → (0.5, 0.5)", MUTED),
    ("else  viewPosition(point)", WARM),
    ("      → mirror + aspect-fill to view UV", MUTED),
    ("+ kaleidoscopeCenterOffset", TEXT),
    ("→ params.kaleidoCenterX / Y", ACCENT),
]):
    mono(ax + 32, fy + 100 + i * 24, s, size=11.5, fill=c)

add(f'<line x1="{ax+20}" y1="{fy+282}" x2="{ax+aw-20}" y2="{fy+282}" stroke="{STROKE}" stroke-width="1"/>')

text(ax + 20, fy + 310, "Controls that drive it", size=13, weight="700", fill=WARM)
for i, (k, v) in enumerate([
    ("Anchor", "frame center | any PoseJoint"),
    ("Body", "1 … Max people"),
    ("Offset X / Y", "±50 % of view"),
    ("Confidence gate", "0.25 (fixed)"),
    ("Pose cadence", "every 2nd frame, ≤ 0.6 s old"),
]):
    mono(ax + 32, fy + 336 + i * 26, k, size=11.5, fill=TEXT)
    text(ax + 190, fy + 336 + i * 26, v, size=11.5, fill=MUTED)

add(f'<line x1="{ax+20}" y1="{fy+474}" x2="{ax+aw-20}" y2="{fy+474}" stroke="{STROKE}" stroke-width="1"/>')
text(ax + 20, fy + 500, "poseEffectsEnabled now includes the kaleidoscope", size=11.5, fill=WARM)
text(ax + 20, fy + 518, "when a joint is chosen, so tracking runs even", size=11.5, fill=WARM)
text(ax + 20, fy + 536, "with no other pose effect active.", size=11.5, fill=WARM)

# ================================================================ 8. PARAMS
gy = 2430
rect(x0, gy, 1564, 150, rx=14)
text(x0 + 22, gy + 32, "8 · Params appended to ShaderParams  "
     "(Swift struct ↔ MSL struct, identical field order)", size=15, weight="700", fill=VIOLET)
cols = [
    ("kaleidoEnabled", "UInt32"), ("kaleidoBlendMode", "UInt32"),
    ("kaleidoSegments", "UInt32"), ("kaleidoRotation", "Float"),
    ("kaleidoSpeed", "Float"), ("kaleidoZoom", "Float"),
    ("kaleidoOpacity", "Float"), ("kaleidoCenterX", "Float"),
    ("kaleidoCenterY", "Float"),
]
for i, (n, t) in enumerate(cols):
    cx2 = x0 + 34 + (i % 5) * 300
    cy2 = gy + 82 + (i // 5) * 30
    mono(cx2, cy2, n, size=12, fill=TEXT)
    text(cx2 + 172, cy2, t, size=11, fill=MUTED)

# ---------------------------------------------------------------- legend
ly = gy + 182
legend = [
    (BLUE, "capture / Core ML"),
    (VIOLET, "existing Metal pass"),
    (ACCENT, "new: kaleidoscope + fold"),
    (WARM, "pose / joint anchor"),
    (GREEN, "ordering decision"),
]
lx = x0 + 6
for col, lbl in legend:
    add(f'<rect x="{lx}" y="{ly-12}" width="16" height="16" rx="4" fill="{col}" opacity="0.85"/>')
    text(lx + 26, ly + 2, lbl, size=12, fill=MUTED)
    lx += 74 + len(lbl) * 6.4

add('</svg>')

with open("docs/kaleidoscope-processing.svg", "w") as f:
    f.write("\n".join(out))
print("wrote docs/kaleidoscope-processing.svg")
