#!/usr/bin/env python3
"""產生 art/sprites/*.svg（原創造型的占位美術，俯視奇幻 RTS 風格）。
改造型就改這支再執行：python3 tools/gen_art.py
"""
import os
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "sprites")
OL = "#1f1a12"          # 外框線
SW = 2.5

def svg(name, w, h, body):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * 2}" height="{h * 2}" viewBox="0 0 {w} {h}">'
                f'<g stroke="{OL}" stroke-width="{SW}" stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>\n')

def shadow(cx, cy, rx, ry, o=0.28):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#000" fill-opacity="{o}" stroke="none"/>'

def c(cx, cy, r, fill, extra=""):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" {extra}/>'

def e(cx, cy, rx, ry, fill, extra=""):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" {extra}/>'

def r(x, y, w, h, fill, rx=0, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" {extra}/>'

def p(d, fill, extra=""):
    return f'<path d="{d}" fill="{fill}" {extra}/>'

NS = 'stroke="none"'

# ---------- 樹 ----------
svg("tree", 80, 80,
    shadow(42, 66, 26, 9) +
    r(35, 50, 10, 16, "#6b4420", 3) +
    c(28, 40, 19, "#2f6321") + c(52, 42, 18, "#2f6321") + c(40, 28, 21, "#3f7d2c") +
    c(34, 22, 9, "#5aa03a", NS) + c(50, 34, 6, "#4b8f33", NS) + c(24, 38, 5, "#3f7d2c", NS))

svg("tree2", 80, 80,
    shadow(40, 68, 24, 8) +
    r(35, 52, 10, 16, "#5e3b1c", 3) +
    p("M40 6 L62 36 L52 36 L66 58 L14 58 L28 36 L18 36 Z", "#2b5a2a") +
    p("M40 12 L52 32 L44 32 L54 50 L34 50 Z", "#3d7a34", NS))

# ---------- 精靈（身體可染色 + 頭）----------
svg("elf_body", 64, 64,
    shadow(32, 54, 15, 5) +
    p("M32 22 C46 22 50 40 46 54 C40 58 24 58 18 54 C14 40 18 22 32 22 Z", "#ffffff") +
    p("M32 30 C40 34 42 46 40 55 C36 57 28 57 24 55 C22 46 24 34 32 30 Z", "#d2d2d2", NS) +
    p("M44 30 C54 26 58 38 52 46", "none", 'stroke="#7a5a2a" stroke-width="3"') +   # 弓
    f'<line x1="45" y1="30" x2="52" y2="46" stroke="#e9e2c8" stroke-width="1.2"/>')

svg("elf_head", 64, 64,
    p("M19 20 L6 12 L17 27 Z", "#f1c9a0") + p("M45 20 L58 12 L47 27 Z", "#f1c9a0") +
    c(32, 21, 12.5, "#f1c9a0") +
    p("M19.5 21 C18 8 46 8 44.5 21 C40 13 24 13 19.5 21 Z", "#e8dca0") +
    c(27.5, 23, 1.8, "#2a3b2a", NS) + c(36.5, 23, 1.8, "#2a3b2a", NS) +
    p("M29 28 Q32 30 35 28", "none", 'stroke-width="1.4"'))

# ---------- 靈魂 ----------
svg("soul", 64, 64,
    p("M32 8 C46 8 50 24 46 36 C44 46 38 50 36 58 C33 52 30 56 27 50 C24 54 20 46 18 36 C14 24 18 8 32 8 Z",
      "#cfefff", 'fill-opacity="0.82" stroke="#5aa6c8"') +
    p("M19 20 L8 13 L18 27 Z", "#cfefff", 'fill-opacity="0.82" stroke="#5aa6c8"') +
    p("M45 20 L56 13 L46 27 Z", "#cfefff", 'fill-opacity="0.82" stroke="#5aa6c8"') +
    c(27, 24, 2.4, "#2b5d7a", NS) + c(37, 24, 2.4, "#2b5d7a", NS) +
    c(26, 16, 4, "#ffffff", 'fill-opacity="0.7" stroke="none"'))

# ---------- 巨魔 ----------
svg("troll", 96, 96,
    shadow(48, 84, 30, 8, 0.35) +
    # 棍棒
    p("M76 30 L84 66", "none", 'stroke="#6b4420" stroke-width="7"') +
    p("M76 30 L84 66", "none", 'stroke="#8a5a2b" stroke-width="3" ') +
    e(75, 24, 10, 12, "#8d8d86") + c(72, 20, 2.5, "#b8b8b0", NS) + c(79, 27, 2, "#6f6f69", NS) +
    # 身體
    p("M48 28 C72 28 82 50 76 72 C70 86 26 86 20 72 C14 50 24 28 48 28 Z", "#5f8a4a") +
    p("M48 48 C62 48 68 60 64 74 C58 82 38 82 32 74 C28 60 34 48 48 48 Z", "#7ba562", NS) +
    r(30, 70, 36, 12, "#6b4420", 4) + p("M36 72 L36 80 M48 72 L48 80 M60 72 L60 80", "none", 'stroke-width="1.5"') +
    # 手臂
    c(18, 58, 11, "#5f8a4a") + c(78, 58, 11, "#5f8a4a") +
    # 頭
    p("M30 26 L22 8 L38 20 Z", "#e8dfc4") + p("M66 26 L74 8 L58 20 Z", "#e8dfc4") +
    e(48, 34, 20, 17, "#6a9753") +
    p("M32 30 Q40 25 46 31", "none", 'stroke-width="3"') + p("M64 30 Q56 25 50 31", "none", 'stroke-width="3"') +
    c(40, 34, 3.2, "#ffd84a") + c(56, 34, 3.2, "#ffd84a") + c(40, 34, 1.2, "#1f1a12", NS) + c(56, 34, 1.2, "#1f1a12", NS) +
    p("M36 44 Q48 50 60 44", "none", 'stroke-width="2.2"') +
    p("M39 45 L37 37 L43 45 Z", "#f4eeda") + p("M57 45 L59 37 L53 45 Z", "#f4eeda"))

# ---------- 樹屋 ----------
def roof_lines(cx, cy, rr, n, col):
    import math
    out = ""
    for i in range(n):
        a = math.pi * 2 * i / n
        out += f'<line x1="{cx}" y1="{cy}" x2="{cx + rr * math.cos(a):.1f}" y2="{cy + rr * 0.86 * math.sin(a):.1f}" stroke="{col}" stroke-width="1.6"/>'
    return out

svg("house", 128, 128,
    shadow(66, 110, 46, 12) +
    c(26, 92, 15, "#2f6321") + c(102, 94, 16, "#2f6321") + c(20, 70, 10, "#3f7d2c") + c(110, 72, 11, "#3f7d2c") +
    p("M30 62 L30 100 Q64 116 98 100 L98 62 Z", "#8a5a2b") +
    p("M30 62 L30 100 Q46 108 58 109 L58 62 Z", "#6b4420", NS) +
    p("M56 108 L56 86 Q64 76 72 86 L72 108 Z", "#3a2613") +
    r(80, 78, 11, 12, "#ffe08a", 2) + f'<line x1="85.5" y1="78" x2="85.5" y2="90" stroke-width="1.4"/>' +
    e(64, 54, 50, 34, "#c9a24a") + roof_lines(64, 54, 49, 14, "#a07f2c") +
    e(64, 46, 28, 18, "#dcb95c", NS) + roof_lines(64, 46, 27, 9, "#b8963c") +
    c(64, 40, 7, "#8a5a2b") + c(62, 38, 2.5, "#b07a3e", NS) +
    c(38, 104, 9, "#4b8f33") + c(92, 106, 8, "#4b8f33"))

# ---------- 月露林場 ----------
def sapling(x, y, s=1.0):
    return (r(x - 2.5 * s, y, 5 * s, 16 * s, "#6b4420", 2) +
            c(x, y - 4 * s, 13 * s, "#3c8f7a") + c(x - 4 * s, y - 8 * s, 5 * s, "#9ff0d8", NS) +
            c(x + 5 * s, y - 2 * s, 3 * s, "#c8fff0", NS))

def log(x, y, w=44):
    return (r(x, y, w, 12, "#8a5a2b", 6) + e(x + w - 3, y + 6, 4.5, 5.5, "#d9b77a") +
            c(x + w - 3, y + 6, 1.6, "#8a5a2b", NS))

svg("grove", 128, 128,
    e(64, 70, 58, 50, "#3f6f2f", 'stroke="#2a4d20"') +
    sapling(34, 40, 1.15) + sapling(92, 36, 1.3) + sapling(66, 56, 1.0) +
    log(22, 92) + log(40, 80, 40) + log(56, 96, 46) +
    c(100, 84, 10, "#7a5127") + c(100, 84, 5.5, "#b98a4c", NS) +
    p("M96 62 L104 80", "none", 'stroke="#6b4420" stroke-width="3.5"') + p("M90 60 L102 58 L100 68 Z", "#b8b8b0"))

# ---------- 工匠大廳 ----------
svg("hall", 128, 128,
    shadow(66, 112, 50, 10) +
    r(18, 56, 92, 52, "#8a5a2b", 3) + r(18, 56, 30, 52, "#6b4420", 3, NS) +
    p("M18 70 L110 70 M18 88 L110 88", "none", 'stroke-width="1.4"') +
    p("M54 108 L54 84 L74 84 L74 108 Z", "#3a2613") +
    r(84, 80, 14, 14, "#ffe08a", 2) + r(28, 80, 14, 14, "#ffe08a", 2) +
    p("M8 60 L64 14 L120 60 Z", "#6d5a8f") + p("M64 14 L120 60 L64 60 Z", "#8573a8", NS) +
    p("M8 60 L64 14 L120 60", "none") + p("M26 46 L102 46 M40 34 L88 34", "none", 'stroke="#55467a" stroke-width="1.6"') +
    r(88, 18, 12, 22, "#9a9a94", 2) + c(94, 14, 4, "#ff9d3a", NS) +
    c(64, 50, 11, "#d9c27a") + p("M57 48 L71 48 L68 53 L66 53 L66 56 L62 56 L62 53 L60 53 Z", "#3a3a3a", NS))

# ---------- 城牆 ----------
def stake(x):
    return p(f"M{x} 56 L{x} 20 L{x + 7} 9 L{x + 14} 20 L{x + 14} 56 Z", "#9a6a35") + \
           p(f"M{x} 56 L{x} 20 L{x + 5} 12 L{x + 5} 56 Z", "#7a5127", NS)

svg("wall_wood", 64, 64,
    shadow(32, 58, 28, 5) + stake(4) + stake(18) + stake(32) + stake(46) +
    r(3, 32, 58, 7, "#6b4420", 2) + c(11, 35.5, 1.6, "#2b2b2b", NS) + c(53, 35.5, 1.6, "#2b2b2b", NS))

svg("wall_stone", 64, 64,
    shadow(32, 59, 29, 4) +
    r(4, 20, 56, 38, "#ffffff", 3) +
    r(4, 8, 14, 16, "#ffffff", 2) + r(25, 8, 14, 16, "#ffffff", 2) + r(46, 8, 14, 16, "#ffffff", 2) +
    r(5.5, 21.5, 53, 35, "#e2e2e2", 2, NS) +
    p("M4 34 L60 34 M4 46 L60 46 M22 22 L22 34 M42 22 L42 34 M14 34 L14 46 M32 34 L32 46 M50 34 L50 46 M22 46 L22 58 M42 46 L42 58",
      "none", 'stroke="#8a8a8a" stroke-width="1.5"') +
    r(4, 20, 56, 38, "none", 3))

# ---------- 塔 ----------
def tower_base(col="#9a9a94", dark="#7b7b76"):
    return shadow(32, 59, 22, 5) + p("M14 58 L18 30 L46 30 L50 58 Z", col) + p("M14 58 L18 30 L28 30 L26 58 Z", dark, NS) + \
           p("M18 44 L46 44", "none", 'stroke-width="1.3"')

svg("arrow_tower", 64, 64,
    tower_base() +
    r(12, 22, 40, 12, "#8a5a2b", 2) + p("M18 22 L18 34 M26 22 L26 34 M38 22 L38 34 M46 22 L46 34", "none", 'stroke-width="1.3"') +
    p("M8 24 L32 3 L56 24 Z", "#b5452f") + p("M32 3 L56 24 L32 24 Z", "#cf5c40", NS) + p("M8 24 L32 3 L56 24", "none") +
    r(29, 40, 6, 12, "#2b2b2b", 3) +
    p("M32 3 L32 -2", "none") )

svg("frost_tower", 64, 64,
    tower_base("#8fa3b5", "#71879b") +
    p("M32 2 L44 22 L38 36 L26 36 L20 22 Z", "#bfeaff") + p("M32 2 L44 22 L32 36 Z", "#e9f9ff", NS) +
    p("M32 2 L32 36 M20 22 L44 22", "none", 'stroke="#6fb6dc" stroke-width="1.4"') +
    p("M14 30 L20 18 L24 32 Z", "#9fdcf8") + p("M50 30 L44 18 L40 32 Z", "#9fdcf8") +
    c(32, 18, 3, "#ffffff", NS))

svg("watch_tower", 64, 64,
    shadow(32, 59, 18, 5) +
    p("M24 58 L27 26 L37 26 L40 58 Z", "#8a5a2b") + p("M25 46 L39 36 M39 46 L25 36", "none", 'stroke-width="1.5"') +
    r(14, 18, 36, 12, "#a8743a", 2) + p("M14 24 L50 24", "none", 'stroke-width="1.3"') +
    p("M10 19 L32 3 L54 19 Z", "#4b8f33") + p("M32 3 L54 19 L32 19 Z", "#5aa03a", NS) + p("M10 19 L32 3 L54 19", "none") +
    c(32, 24, 4, "#ffe08a"))

svg("repair_post", 64, 64,
    shadow(32, 58, 24, 5) +
    r(8, 34, 48, 10, "#a8743a", 2) + r(12, 44, 6, 14, "#6b4420", 1) + r(46, 44, 6, 14, "#6b4420", 1) +
    p("M22 34 L22 24 L42 24 L46 28 L38 28 L38 34 Z", "#4a4a4a") +           # 鐵砧
    p("M44 8 L52 26", "none", 'stroke="#6b4420" stroke-width="4"') + r(36, 4, 18, 9, "#b8b8b0", 2, 'transform="rotate(-20 45 8)"') +
    p("M14 12 L14 30", "none", 'stroke="#6b4420" stroke-width="3"') + p("M14 12 L28 16 L14 21 Z", "#e08ac0"))

# ---------- 樹樁門 ----------
def stump(cx, cy=36):
    return (shadow(cx, cy + 20, 15, 5) + r(cx - 13, cy - 8, 26, 28, "#7a5127", 5) +
            e(cx, cy - 8, 13, 8, "#d9b77a") + e(cx, cy - 8, 8, 4.6, "none", 'stroke="#a8743a" stroke-width="1.4"') +
            c(cx, cy - 8, 1.8, "#8a5a2b", NS) + c(cx - 14, cy + 14, 5, "#4b8f33") + c(cx + 13, cy + 16, 4, "#3f7d2c"))

planks = "".join(r(30 + i * 11.4, 20, 11.4, 36, "#9a6a35" if i % 2 == 0 else "#8a5a2b") for i in range(6))
svg("gate_closed", 128, 64,
    planks + r(28, 26, 72, 6, "#4a4a4a", 2) + r(28, 44, 72, 6, "#4a4a4a", 2) +
    c(64, 38, 5, "#d9c27a") + stump(16) + stump(112))

svg("gate_open", 128, 64,
    p("M28 30 L44 10 L50 14 L34 36 Z", "#9a6a35") + p("M100 30 L84 10 L78 14 L94 36 Z", "#9a6a35") +
    stump(16) + stump(112))

svg("gate_broken", 128, 64,
    p("M34 44 L46 38 L48 44 L38 50 Z", "#8a5a2b") + p("M58 50 L72 46 L70 54 Z", "#9a6a35") +
    p("M82 40 L96 46 L92 52 L80 46 Z", "#7a5127") + p("M50 30 L56 24 L60 30 Z", "#9a6a35") +
    p("M70 32 L78 28 L78 36 Z", "#8a5a2b") + stump(16) + stump(112))

# ---------- 星界傳送門 ----------
import math
runes = "".join(c(96 + 74 * math.cos(math.pi * 2 * i / 12), 96 + 74 * math.sin(math.pi * 2 * i / 12), 4, "#6fe0ff", NS) for i in range(12))
pillars = "".join(r(x - 9, y - 12, 18, 24, "#b8b8b0", 4) + r(x - 9, y - 12, 18, 7, "#d6d6ce", 4, NS) for x, y in [(26, 30), (166, 30), (26, 166), (166, 166)])
svg("portal", 192, 192,
    '<defs><radialGradient id="g"><stop offset="0" stop-color="#ffffff"/><stop offset="0.45" stop-color="#7fe0ff"/>'
    '<stop offset="1" stop-color="#2a6fd6"/></radialGradient></defs>' +
    shadow(98, 104, 88, 84, 0.25) +
    c(96, 96, 84, "#9a9a94") + c(96, 96, 84, "none", 'stroke="#7b7b76" stroke-width="10" stroke-dasharray="20 9"') +
    runes + c(96, 96, 62, "url(#g)") +
    p("M96 46 C130 50 140 86 118 104 C104 116 84 108 86 92 C88 82 100 82 102 92", "none", 'stroke="#ffffff" stroke-width="4" stroke-opacity="0.85"') +
    p("M96 146 C62 142 52 106 74 88", "none", 'stroke="#d8f6ff" stroke-width="3" stroke-opacity="0.7"') +
    pillars)

print("ok", len(os.listdir(OUT)))
