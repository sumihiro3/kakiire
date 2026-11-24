#!/usr/bin/env python3
"""メイカーコインの図案を作る(立体のデータは作らない)。

使い方(リポジトリの直下で): python3 scripts/coin/make-coin.py
出るもの: docs/coin/ に進める案の表(front-*.svg)・共通の裏(back.svg)・比較シート(sheet.svg / sheet.png)。
          --all を付けると、見送った案も含めて 5 案とも出す。
          build/coin/ に、細すぎる線に印を付けた検査用の画像(thin-*.png)。

寸法は mm。原点はコインの中心、y は下向き。色は高さの段で分ける(同じ層に 2 色を置かない)。
"""
import json
import math
import random
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).resolve().parent
BUILD = ROOT / "build" / "coin"
OUT = ROOT / "docs" / "coin"
TOOL = BUILD / "cointool"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

RADIUS = 20.0        # 直径 40
RIM = 1.6            # 縁の幅
FIELD_R = RADIUS - RIM
BODY = 2.4           # 地の面の高さ
BACK_INLAY = 0.4     # 裏の黒(QR と枠)を埋め込む深さ。1・2 層目
STEP = 0.4           # 色 1 段の厚み(0.2 の層で 2 枚。1 枚だと下の色が透ける)
MIN_LINE = 0.8       # 0.4 ノズルで刷れる線の下限の目安(線 2 本ぶん)
MIN_GAP = 0.6        # 溝・すき間の下限の目安

QR_TEXT = "HTTPS://KAKIIRE.TEP-LAB.COM"   # 大文字だけにすると英数字モードになり、29 マスが 25 マスで済む
QR_LEVEL = "Q"
QR_MODULE = 0.84     # 0.42 mm の線 2 本ぶん

# 手持ちのフィラメント(Bambu Lab の PLA)に合わせた色。値は Bambu Lab の色コード:
# PLA Basic の Jade White・Gray・Black(10101)と、PLA Matte の Scarlet Red(11200)。
# 緑と黄は見送った案だけが使う、もとの図案の色。
WHITE, RED, GRAY, GREEN, YELLOW, INK = "#FFFFFF", "#DE4343", "#8E9089", "#97C459", "#FFD60A", "#000000"
COLOR_NAMES = {WHITE: "白", RED: "赤", GRAY: "グレー", GREEN: "緑", YELLOW: "黄", INK: "黒"}
PICKED = ("arrow", "mosaic")     # 進める案。--all を付けると 5 案とも出す

# scripts/make-icon.swift の矢印と同じ形(104 マスの座標)。先端は (27, 74)。
ARROW = "M75.1 8.6 Q58.6 30.3 45.9 45.4 L34.3 30.4 L27.0 74.0 L69.6 62.2 L53.5 52.2 Q67.1 38.0 86.9 19.4 Z"
ARROW_TIP = (27.0, 74.0)

ROUNDED = "rounded:bold"
ROUNDED_HEAVY = "rounded:heavy"
GOTHIC = "name:HiraginoSans-W6"
GOTHIC_LIGHT = "name:HiraginoSans-W4"   # 「書」だけ。横画 8 本の線とすき間を同じ幅にそろえるため


def f(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


# ---------- 部品 ----------

def circle(r):
    return f"M{f(-r)} 0A{f(r)} {f(r)} 0 1 1 {f(r)} 0A{f(r)} {f(r)} 0 1 1 {f(-r)} 0Z"


def ring(r_out, r_in):
    return f'<path fill-rule="evenodd" d="{circle(r_out)}{circle(r_in)}"/>'


def polygon(points):
    return '<path d="M' + "L".join(f"{f(x)} {f(y)}" for x, y in points) + 'Z"/>'


def arrow_transform(tip, scale):
    return f"translate({f(tip[0])} {f(tip[1])}) scale({f(scale)}) translate({-ARROW_TIP[0]} {-ARROW_TIP[1]})"


def arrow(tip, scale):
    return f'<path d="{ARROW}" transform="{arrow_transform(tip, scale)}"/>'


def arrow_moat(tip, scale, width):
    """矢印の白い縁取り。矢印を width だけ太らせた形(線の幅は倍率で割り戻す)。"""
    return (f'<path d="{ARROW}" transform="{arrow_transform(tip, scale)}" stroke="{WHITE}" '
            f'stroke-width="{f(2 * width / scale)}" stroke-linejoin="round"/>')


_glyphs = {}


def glyphs(font, text):
    if (font, text) not in _glyphs:
        out = subprocess.run([str(TOOL), "glyphs", font, text], check=True, capture_output=True, text=True).stdout
        _glyphs[(font, text)] = json.loads(out)
    return _glyphs[(font, text)]


def em_for_cap(font, cap_mm):
    return cap_mm / (glyphs(font, "K")["cap"] / 1000)


def solid(d):
    """字の穴(A や R の中)をふさぐ。小さい字の穴は島になって刷れないため、外側の輪郭だけ残す。"""
    parts = ["M" + p for p in d.split("M") if p]

    def span(part):
        xs = [float(v) for v in re.findall(r"-?\d+\.?\d*", part)][0::2]
        return max(xs) - min(xs)

    return max(parts, key=span) if parts else d


def text_line(font, text, em, x, baseline, anchor="middle", tracking=0.0):
    """横書き 1 行。"""
    return text_run([(font, ch, em, False) for ch in text], x, baseline, anchor, tracking * em)


def text_run(items, x, baseline, anchor="start", gap=0.0):
    """字ごとにフォントと大きさを変えられる横書き。items は (フォント, 字, em, 詰めるか)。
    詰める字は、字の箱ではなく実際の形の幅で置く(かぎ括弧用)。"""
    cursor, placed = 0.0, []
    for font, ch, em, tight in items:
        g, k = glyphs(font, ch)["glyphs"][0], em / 1000
        left, width = (g["box"][0], g["box"][2] - g["box"][0]) if tight else (0.0, g["adv"])
        placed.append((g["d"], cursor - left * k, k, cursor, cursor + width * k))
        cursor += width * k + gap
    width = cursor - gap
    start = x - {"start": 0, "middle": width / 2, "end": width}[anchor]
    svg = "".join(f'<path d="{d}" transform="translate({f(start + gx)} {f(baseline)}) scale({f(k)})"/>'
                  for d, gx, k, _, _ in placed)
    return svg, [(start + a, start + b) for _, _, _, a, b in placed]


def text_arc(font, text, em, radius, center_deg, side, tracking=0.0, fill_holes=False):
    """円に沿わせた字。side="top" は字の頭が外向き、"bottom" は内向き。radius は字の足元の半径。"""
    k = em / 1000
    items, cursor = [], 0.0
    for g in glyphs(font, text)["glyphs"]:
        items.append((g, cursor + g["adv"] * k / 2))
        cursor += g["adv"] * k + tracking * em
    width = cursor - tracking * em
    svg = ""
    for g, s in items:
        deg = center_deg + math.degrees((s - width / 2) / radius)
        place = f"rotate({f(deg)}) translate(0 {f(-radius)})" if side == "top" else f"rotate({f(-deg)}) translate(0 {f(radius)})"
        d = solid(g["d"]) if fill_holes else g["d"]
        svg += f'<path d="{d}" transform="{place} scale({f(k)}) translate({f(-g["adv"] / 2)} 0)"/>'
    return svg


def layer(id, color, tier, svg, cut=False):
    return {"id": id, "color": color, "tier": tier, "svg": svg, "cut": cut}


def clip_field(uid):
    return f'<clipPath id="{uid}-field"><path d="{circle(FIELD_R)}"/></clipPath>'


# ---------- 表の 5 案 ----------

def design_icon(uid):
    tip, scale = (-6.6, 5.2), 0.315
    peak = (-8.3, 7.3)
    left, right = 0.676, 0.79                      # 左右の斜面の傾き
    ridge = [(-21, peak[1] + (21 + peak[0]) * left), peak, (-2.3, peak[1] + 6.0 * right), (3.7, 9.1), (21, 16.4)]
    snow_h = 2.3                                   # 雪の両端の高さ。下のぎざぎざは端より深くして、端をとがらせない
    snow = [peak, (peak[0] + snow_h / right, peak[1] + snow_h), (peak[0] + 1.3, peak[1] + 3.6),
            (peak[0] - 0.1, peak[1] + 2.4), (peak[0] - 1.6, peak[1] + 3.7), (peak[0] - snow_h / left, peak[1] + snow_h)]
    clip = f'clip-path="url(#{uid}-field)"'
    return {
        "defs": clip_field(uid),
        "layers": [
            layer("field", WHITE, 0, f'<path d="{circle(RADIUS)}"/>'),
            layer("sky", GRAY, 1, f'<g {clip}><path d="M-21 1.6H21V21H-21Z"/></g>'),
            layer("mountain", GREEN, 2, f'<g {clip}>{polygon(ridge + [(21, 21), (-21, 21)])}</g>'),
            layer("cut-snow", WHITE, 0, polygon(snow), cut=True),
            layer("cut-arrow-outline", WHITE, 0, arrow_moat(tip, scale, 0.9), cut=True),
            layer("arrow", RED, 3, arrow(tip, scale)),
            layer("rim", RED, 3, ring(RADIUS, FIELD_R)),
        ],
    }


def design_arrow(uid):
    tip, scale = (-10.2, 10.0), 0.445
    # 字の足元を縁に 0.4 mm 食い込ませて、矢印の尾と同じように縁から生やす
    word = text_arc(ROUNDED_HEAVY, "KAKIIRE", em_for_cap(ROUNDED_HEAVY, 4.6), FIELD_R + 0.4, 52, "bottom",
                    tracking=0.18, fill_holes=True)
    return {
        "defs": f'<clipPath id="{uid}-coin"><path d="{circle(RADIUS)}"/></clipPath>',
        "layers": [
            layer("field", WHITE, 0, f'<path d="{circle(RADIUS)}"/>'),
            layer("arrow", RED, 1, f'<g clip-path="url(#{uid}-coin)">{arrow(tip, scale)}</g>'),
            layer("wordmark", RED, 1, word),
            layer("rim", RED, 1, ring(RADIUS, FIELD_R)),
        ],
    }


def design_stamp(uid):
    em = em_for_cap(ROUNDED_HEAVY, 17.0)
    numeral, _ = text_line(ROUNDED_HEAVY, "1", em, -0.6, 8.5)
    return {
        "defs": "",
        "layers": [
            layer("field", WHITE, 0, f'<path d="{circle(RADIUS)}"/>'),
            layer("disc", RED, 1, f'<path d="{circle(RADIUS)}"/>'),
            layer("cut-ring", WHITE, 0, ring(17.5, 16.4), cut=True),
            layer("cut-numeral", WHITE, 0, numeral, cut=True),
        ],
    }


MARKER_TOP = 4.0     # マーカーの上の辺(字の足元からの高さ)。「書」の横画との間に細いすき間ができない位置を測って決めた


def design_kanji(uid):
    big, small = 12.5, 9.0                        # 漢字を大きく、かなを小さく。「書」の横画を太らせるため
    base1, base2 = -1.7, 11.3
    row1, box1 = text_run([(GOTHIC, "「", small, True), (GOTHIC_LIGHT, "書", big, False), (GOTHIC, "き", small, False)],
                          -13.0, base1)
    row2, box2 = text_run([(GOTHIC, "入", big, False), (GOTHIC, "れ", small, False), (GOTHIC, "」", small, True)],
                          -12.65, base2)

    def marker(x0, x1, baseline):
        top, bottom, lean = baseline - MARKER_TOP, baseline + 0.9, 0.5
        return polygon([(x0 - 0.4 + lean, top), (x1 + 0.6 + lean, top), (x1 + 0.6 - lean, bottom), (x0 - 0.4 - lean, bottom)])

    return {
        "defs": clip_field(uid),
        "layers": [
            layer("field", WHITE, 0, f'<path d="{circle(RADIUS)}"/>'),
            layer("marker", YELLOW, 1, f'<g clip-path="url(#{uid}-field)">'
                  f'{marker(box1[1][0], box1[2][1], base1)}{marker(box2[0][0], box2[1][1], base2)}</g>'),
            layer("text", INK, 2, row1 + row2),
            layer("rim", INK, 2, ring(RADIUS, FIELD_R)),
        ],
    }


def design_mosaic(uid):
    cols = 12
    pitch = 2 * FIELD_R / cols
    band = 1.5 * pitch                                             # 字の帯は 3 行ぶん。行を半マスずらして中央に 1 行置く
    rng = random.Random(7)
    tiles = {1: "", 2: ""}
    for row in range(cols + 1):
        y = -FIELD_R - pitch / 2 + row * pitch
        if abs(y + pitch / 2) < band - 0.01:
            continue
        for col in range(cols):
            x = -FIELD_R + col * pitch
            level = rng.choices([0, 1, 2], weights=[3, 4, 3])[0]
            # 縁にかかって小さく欠けるマスは、いちばん高い段にして縁とつなげる(刷れない小さなすき間を作らない)
            inside = sum(math.hypot(x + pitch * (i + 0.5) / 6, y + pitch * (j + 0.5) / 6) < FIELD_R
                         for i in range(6) for j in range(6)) / 36
            if inside == 0:
                continue
            if inside < 0.5:
                level = 2
            rect = f"M{f(x)} {f(y)}h{f(pitch)}v{f(pitch)}h{f(-pitch)}z"
            for lv in range(1, level + 1):
                tiles[lv] += rect
    word, _ = text_line(ROUNDED_HEAVY, "Kakiire", em_for_cap(ROUNDED_HEAVY, 6.0), 0, 3.0, tracking=0.03)
    clip = f'clip-path="url(#{uid}-field)"'
    return {
        "defs": clip_field(uid),
        "layers": [
            layer("field", WHITE, 0, f'<path d="{circle(RADIUS)}"/>'),
            layer("tiles-low", GRAY, 1, f'<g {clip}><path d="{tiles[1]}"/></g>'),
            layer("tiles-high", INK, 2, f'<g {clip}><path d="{tiles[2]}"/></g>'),
            layer("wordmark", INK, 2, word),
            layer("rim", INK, 2, ring(RADIUS, FIELD_R)),
        ],
    }


DESIGNS = [
    ("icon", "A アイコン", design_icon,
     ["アプリのアイコンを丸に収めた。", "矢印が雪の山頂を指す。"]),
    ("arrow", "B 矢印", design_arrow,
     ["縁から矢印が 1 本入ってくる。", "先細りの矢印だけで Kakiire と分かる。"]),
    ("stamp", "C 番号スタンプ", design_stamp,
     ["コインそのものが番号スタンプ。", "番号は 1 枚ごとに変えられる。"]),
    ("kanji", "D 書き入れ", design_kanji,
     ["LP の見出しをそのまま。", "蛍光ペンの上に字が乗る。"]),
    ("mosaic", "E モザイク", design_mosaic,
     ["タイルの高さが 3 段。", "指でなぞって分かるモザイク。"]),
]


# ---------- 裏(共通) ----------

def qr_rows():
    out = subprocess.run([str(TOOL), "qr", QR_TEXT, QR_LEVEL], check=True, capture_output=True, text=True).stdout
    return out.split()


BACK_RING = (FIELD_R, RADIUS)   # 裏の黒い枠の内と外の半径。表の縁と同じ幅で、縁いっぱいまで
BACK_HAS_RING = True
BACK_HAS_WORD = False      # 枠と字を両方入れると QR のまわりの余白が足りなくなるので、字は表に任せる


def design_back(uid, has_ring=BACK_HAS_RING, has_word=BACK_HAS_WORD):
    rows = qr_rows()
    n = len(rows)
    # 字があるときは QR を上へ寄せて、字との間をあける(枠もあるなら、枠と字から同じだけ離す)
    shift = (-1.2 if has_ring else -1.5) if has_word else 0.0
    left, top = -n * QR_MODULE / 2, -n * QR_MODULE / 2 + shift
    d = ""
    for y, row in enumerate(rows):
        x = 0
        while x < n:
            if row[x] == "1":
                run = x
                while run < n and row[run] == "1":
                    run += 1
                d += (f"M{f(left + x * QR_MODULE)} {f(top + y * QR_MODULE)}h{f((run - x) * QR_MODULE)}"
                      f"v{f(QR_MODULE)}h{f(-(run - x) * QR_MODULE)}z")
                x = run
            else:
                x += 1
    layers = [
        layer("field", WHITE, 0, f'<path d="{circle(RADIUS)}"/>'),
        layer("qr", INK, -1, f'<path d="{d}"/>'),
    ]
    if has_word:
        # 枠があるときは字の足元を枠に食い込ませる。脚と枠に囲まれた小さな白い島ができるので、いまは使っていない
        layers.append(layer("wordmark", INK, -1, text_arc(
            ROUNDED_HEAVY, "KAKIIRE", em_for_cap(ROUNDED_HEAVY, 3.2), BACK_RING[0] + 0.4 if has_ring else 18.3,
            0, "bottom", tracking=0.26, fill_holes=True)))
    if has_ring:
        layers.append(layer("ring", INK, -1, ring(BACK_RING[1], BACK_RING[0])))
    corner = math.hypot(n * QR_MODULE / 2, n * QR_MODULE / 2 - shift)
    quiet = ((BACK_RING[0] if has_ring else RADIUS) - corner) / QR_MODULE
    return {"defs": "", "modules": n, "layers": layers, "quiet": quiet}


# ---------- SVG の組み立て ----------

def layers_svg(design, shade=False):
    out = design["defs"] and f"<defs>{design['defs']}</defs>"
    for l in design["layers"]:
        z = BODY + l["tier"] * STEP if l["tier"] >= 0 else BACK_INLAY
        attrs = f'id="{l["id"]}" fill="{l["color"]}" data-tier="{l["tier"]}" data-z-top="{f(z)}"'
        if l["cut"]:
            attrs += ' data-cut="true"'
        if shade and l["tier"] > 0 and not l["cut"]:
            attrs += ' filter="url(#relief)"'
        out += f"<g {attrs}>{l['svg']}</g>"
    return out


def standalone(design, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="42mm" height="42mm" viewBox="-21 -21 42 42">'
            f"<title>{title}</title>{layers_svg(design)}</svg>\n")


def tiers(design):
    """下から順に (色, 厚み)。いちばん下は、白に黒(QR と枠)を埋め込んだ層で、色を "inlay" と書く。"""
    stack = [("inlay", BACK_INLAY), (WHITE, BODY - BACK_INLAY)]
    top = {}
    for l in design["layers"]:
        if l["tier"] > 0 and not l["cut"]:
            top[l["tier"]] = l["color"]
    return stack + [(top[t], STEP) for t in sorted(top)]


def filaments(design):
    seen = [WHITE, INK]
    for color, _ in tiers(design):
        if color != "inlay" and color not in seen:
            seen.append(color)
    return seen


RELIEF = ('<filter id="relief" x="-20%" y="-20%" width="140%" height="140%">'
          '<feDropShadow dx="0.1" dy="0.18" stdDeviation="0.1" flood-color="#000" flood-opacity="0.4"/></filter>')
FONT = "'Hiragino Sans', 'Hiragino Kaku Gothic ProN', sans-serif"


def label(x, y, text, size=22, weight=400, color="#16181D", anchor="middle"):
    return (f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{color}" '
            f'text-anchor="{anchor}">{text}</text>')


def stack_strip(x, y, design, width=150):
    """コインを横から見た色の重なり(厚みは 30 倍)。"""
    out, k = "", 30
    total = sum(h for _, h in tiers(design))
    cy = y + total * k
    for color, h in tiers(design):
        cy -= h * k
        out += (f'<rect x="{x - width / 2}" y="{f(cy)}" width="{width}" height="{f(h * k)}" '
                f'fill="{WHITE if color == "inlay" else color}" stroke="#16181D" stroke-width="0.6"/>')
        if color == "inlay":
            for n in range(1, 15, 2):
                out += f'<rect x="{x - width / 2 + n * width / 15}" y="{f(cy)}" width="{width / 15}" height="{f(h * k)}" fill="{INK}"/>'
    return out, total


def build_sheet(designs, back, notes):
    count = len(designs)
    ppm = 8.6 if count > 3 else 12.5              # 案が少ないときは大きく描く
    left, width = 70, 2240
    col = (width - left * 2) / count
    r = RADIUS * ppm
    cy = 150 + r
    y = cy + r + 60                                # 見出しの位置
    back_top = y + 400
    height = int(back_top + 640)
    out = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
           f'font-family="{FONT}"><defs>{RELIEF}</defs><rect width="{width}" height="{height}" fill="#DFE2E7"/>')
    names = "・".join(title.split(" ")[0] for _, title, _, _ in designs)
    out += label(left, 70, f"Kakiire メイカーコイン 図案({names} 案)" if count < 5 else "Kakiire メイカーコイン 図案 5 案",
                 40, 700, anchor="start")
    out += label(left, 112, f"直径 {f(RADIUS * 2)} mm・縁 {f(RIM)} mm・色 1 段 {f(STEP)} mm(仮の寸法)。"
                 "表の色は高さの段で分けてある。裏の 1・2 層目だけ白と黒が同じ層に来る(AMS で刷る)。裏は共通。", 22, 400, "#454851", "start")
    for i, (key, title, design, concept) in enumerate(designs):
        cx = left + col * i + col / 2
        out += f'<g transform="translate({f(cx)} {f(cy)}) scale({ppm})">{layers_svg(design, shade=True)}</g>'
        out += label(cx, y, title, 30, 700)
        for n, line in enumerate(concept):
            out += label(cx, y + 40 + n * 30, line, 20, 400, "#454851")
        strip, total = stack_strip(cx, y + 110, design)
        out += strip
        colors = "・".join(COLOR_NAMES[c] for c in filaments(design))
        facts = [f"厚み {f(total)} mm(表の段 {len(tiers(design)) - 2})",
                 f"フィラメント {len(filaments(design))} 色: {colors}"] + notes[key]
        for n, line in enumerate(facts):
            out += label(cx, y + 260 + n * 30, line, 19, 400, "#16181D")
    # 裏
    bx, by, bppm = left + 230, back_top + 330, 11
    out += f'<line x1="{left}" y1="{f(back_top)}" x2="{width - left}" y2="{f(back_top)}" stroke="#9AA0AB"/>'
    out += label(left, back_top + 55, "裏(共通)", 30, 700, anchor="start")
    out += f'<g transform="translate({bx} {f(by)}) scale({bppm})" filter="url(#relief)">{layers_svg(back)}</g>'
    n = back["modules"]
    lines = [
        f"QR の中身: {QR_TEXT}(LP)。大文字だけにして {n}×{n} マスに収めた(小文字のままだと 29×29)。",
        f"1 マス {f(QR_MODULE)} mm、QR の 1 辺 {f(n * QR_MODULE)} mm、誤り訂正は {QR_LEVEL}(約 25% まで欠けても読める水準)。",
        "裏は平らで、縁の段を付けない。造形のときはこの面を下(ベッド側)にする。",
        f"黒いマスと枠は、白と同じ高さに埋め込む(下から {f(BACK_INLAY)} mm、1・2 層目)。AMS で刷る前提。",
        "図は裏から見た向き。立体にするときに左右を裏返さないこと(裏返すと読めない)。",
        f"黒い枠は幅 {f(BACK_RING[1] - BACK_RING[0])} mm で縁いっぱいまで(表の縁と同じ幅)。",
        f"QR の角から枠まで {back['quiet']:.1f} マス(規格の余白は 4 マス)。字は入れない(表にあるので)。",
    ] + notes["back"]
    for i, line in enumerate(lines):
        out += label(bx + 290, back_top + 120 + i * 44, line, 22, 400, "#16181D", "start")
    return out + "</svg>\n", height


# ---------- 検査 ----------

def screenshot(svg_path, png_path, width, height, scale=1):
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", f"--force-device-scale-factor={scale}",
                    f"--window-size={width},{height}", f"--user-data-dir={BUILD / 'chrome'}",
                    f"--screenshot={png_path}", f"file://{svg_path}"], check=True, capture_output=True)


PPM, SIZE = 20, 840      # 検査用の画像は 1 mm = 20 px、42 mm 角


def raster(name, body, defs="", background="#fff"):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="-21 -21 42 42">'
           f'<rect x="-21" y="-21" width="42" height="42" fill="{background}"/><defs>{defs}</defs>{body}</svg>')
    svg_path, png_path = BUILD / f"{name}.svg", BUILD / f"{name}.png"
    svg_path.write_text(svg)
    screenshot(svg_path, png_path, SIZE, SIZE)
    return png_path


LINE_STEPS = [0.4, 0.5, 0.6, 0.7, 0.8, 1.0]
GAP_STEPS = [0.3, 0.4, 0.5, 0.6, 0.8]
TOLERANCE = 0.5          # この面積(mm²)までは、とがった角や字の付け根のくさびとして数えない


def thin_report(key, design):
    """段ごとに、線(出っぱり)とすき間がどの幅まで残るかを測る。
    幅 w の円が入らない所を「w 未満」と数える。直角の角が丸まるぶんは数えない。
    返すのは (残る線の最小幅, 残るすき間の最小幅)。値は LINE_STEPS / GAP_STEPS の刻み。"""
    import numpy as np
    from PIL import Image

    def erode(mask, radius_mm):
        r = radius_mm * PPM
        out = mask.copy()
        n = int(math.ceil(r))
        for dy in range(-n, n + 1):
            for dx in range(-n, n + 1):
                if dx * dx + dy * dy <= r * r:
                    out &= np.roll(np.roll(mask, dy, 0), dx, 1)
        return out

    def lost(mask, width_mm):
        core = erode(mask, width_mm / 2)
        cover = ~erode(~core, width_mm / 2 * 1.45 + 0.05)
        return mask & ~cover

    def survives(mask, steps):
        ok = 0.0
        for w in steps:
            if lost(mask, w).sum() / PPM ** 2 > TOLERANCE:
                break
            ok = w
        return ok

    line, gap, marks = 9.0, 9.0, None
    for level in sorted({l["tier"] for l in design["layers"] if l["tier"] != 0}):
        body = ""
        for l in design["layers"]:
            if l["cut"]:
                body += f'<g fill="#fff">{l["svg"].replace(WHITE, "#fff")}</g>'
            elif l["tier"] >= level > 0 or l["tier"] == level:
                body += f'<g fill="#000">{l["svg"]}</g>'
        black = np.asarray(Image.open(raster(f"mask-{key}-{level}", body, design["defs"])).convert("L")) < 128
        if level < 0:
            # 裏は白も黒も同じ層に刷るので、両方を「線」として測る(すき間はない)
            solid_mask = ~black
            line, gap = min(line, survives(solid_mask, LINE_STEPS), survives(black, LINE_STEPS)), None
            thin, narrow = lost(solid_mask, MIN_LINE), lost(black, MIN_LINE)
        else:
            solid_mask = black
            line, gap = min(line, survives(solid_mask, LINE_STEPS)), min(gap, survives(~solid_mask, GAP_STEPS))
            thin, narrow = lost(solid_mask, MIN_LINE), lost(~solid_mask, MIN_GAP)
        picture = np.where(thin[..., None], [232, 42, 42], np.where(narrow[..., None], [20, 102, 214],
                           np.where(solid_mask[..., None], [150, 150, 150], [255, 255, 255])))
        marks = picture if marks is None else np.concatenate([marks, picture], axis=1)
    Image.fromarray(marks.astype("uint8")).save(BUILD / f"thin-{key}.png")
    return line, gap


def verdict(line, gap):
    """gap が None なら、線だけで判定する(裏)。"""
    def width(value, steps):
        return f"{f(value)} mm 以上" if value == steps[-1] else (f"約 {f(value)} mm" if value else f"{f(steps[0])} mm 未満")

    ok = line >= MIN_LINE and (gap is None or gap >= MIN_GAP)
    out = [f"いちばん細い線 {width(line, LINE_STEPS)}"]
    if gap is not None:
        out.append(f"いちばん狭いすき間 {width(gap, GAP_STEPS)}")
    return out + ["→ 0.4 mm ノズルの目安に収まる" if ok else "→ 目安より細い所がある(要試し刷り)"]


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    source = SRC / "cointool.swift"
    if not TOOL.exists() or TOOL.stat().st_mtime < source.stat().st_mtime:
        subprocess.run(["swiftc", "-O", str(source), "-o", str(TOOL)], check=True)

    designs, notes = [], {}
    for old in OUT.glob("front-*.svg"):
        old.unlink()
    for key, title, build, concept in DESIGNS:
        if "--all" not in sys.argv and key not in PICKED:
            continue
        design = build(key)
        (OUT / f"front-{key}.svg").write_text(standalone(design, f"Kakiire maker coin / front / {title}"))
        designs.append((key, title, design, concept))
        notes[key] = verdict(*thin_report(key, design))
        print(key, notes[key])

    back = design_back("back")
    (OUT / "back.svg").write_text(standalone(back, "Kakiire maker coin / back (viewed from the back)"))
    thin_report("back", back)      # マスク(build/coin/mask-back--1.png)は make-model.py の検査でも使う

    # 図を画像にして読む。そのままと、印刷のにじみ・離して撮った粗さのつもりでぼかして縮めた版。
    # コインの外が白いと余白が実物より広く見えるので、暗い机に置いたつもりの版でも読む。
    blur_px, small = 5, 220
    ok = True
    for name, background in [("back", "#fff"), ("back-dark", "#2B2B2B")]:
        png = raster(name, layers_svg(back), background=background)
        sharp = subprocess.run([str(TOOL), "decode", str(png)], capture_output=True, text=True).stdout.strip()
        rough = subprocess.run([str(TOOL), "decode", str(png), str(small), str(blur_px)],
                               capture_output=True, text=True).stdout.strip()
        print(f"QR({name}):", sharp, "/ ぼかして縮めた版:", rough)
        ok = ok and sharp == QR_TEXT and rough == QR_TEXT
    per_module = QR_MODULE * PPM * small / SIZE
    notes["back"] = [f"いちばん細い所は QR の 1 マス({f(QR_MODULE)} mm。白・黒とも)。",
                     (f"読み取り確認: この図の画像から同じ URL が読めた(コインの外が白でも暗くても。半径 {f(blur_px / PPM)} mm 相当で"
                      f"ぼかし、1 マス {per_module:.1f} px まで縮めた版でも可)。" if ok else "注意: この図の画像から QR を読めていない。"),
                     "実物のコインと、スマホのカメラで大文字の URL が開くかは未確認。"]

    sheet = OUT / "sheet.svg"
    svg, height = build_sheet(designs, back, notes)
    sheet.write_text(svg)
    screenshot(sheet, OUT / "sheet.png", 2240, height, scale=2)
    screenshot(sheet, BUILD / "sheet-1x.png", 2240, height)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
