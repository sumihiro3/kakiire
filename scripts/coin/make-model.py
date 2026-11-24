#!/usr/bin/env python3
"""メイカーコインの図案(docs/coin/ の SVG)から、刷るための立体データを作る。

準備(1 回だけ。リポジトリの直下で):
    uv venv build/coin/venv --python 3.13
    uv pip install --python build/coin/venv/bin/python -r scripts/coin/requirements.txt
使い方:
    python3 scripts/coin/make-coin.py                       # 先に図案と検査用のマスクを作る
    build/coin/venv/bin/python scripts/coin/make-model.py
出るもの: docs/coin/print/ に、コインごとの 3MF(色ごとの部品つき)と色別の STL、メッシュから起こした絵 preview.png。

図形はここでは持たない。SVG のグループを README の規則どおりに積む:
  段 n(data-tier)の形 = 段 n 以上のグループの和 − data-cut のグループ。高さは data-z-top。
  段 -1 は裏に埋め込む黒(z 0 から)。back.svg は裏から見た向きなので、立体には 180° 回して置く。
書き出したあと、ファイルを読み直して形・向き・QR を確かめる。合わなければ失敗で終わる。
"""
import importlib.util
import math
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import numpy as np
import trimesh
from manifold3d import CrossSection, FillRule, Manifold, Mesh, OpType
from PIL import Image, ImageDraw, ImageFilter

SRC = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("make_coin", SRC / "make-coin.py")
coin = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(coin)

OUT = coin.OUT / "print"
SVG = "{http://www.w3.org/2000/svg}"
PART_NAMES = {coin.WHITE: "white", coin.INK: "black", coin.RED: "red", coin.GRAY: "gray",
              coin.GREEN: "green", coin.YELLOW: "yellow"}
CURVE_STEP = 0.1        # 曲線を折れ線にするときの 1 辺の長さの目安(mm)
ARC_STEP = 1.5          # 円弧を折れ線にするときの 1 辺の角度(度)
MAX_OFF = 0.1           # 図案のマスクから 1 画素(0.05 mm)を超えてずれてよい面積の上限(mm²)


# ---------- SVG を読む ----------

def matrix(text):
    """transform 属性を 3×3 の行列にする。translate / rotate / scale だけ。"""
    out = np.eye(3)
    rest = re.sub(r"(translate|rotate|scale)\(([^)]*)\)", "", text).strip()
    if rest:
        raise ValueError(f"読めない transform: {text}")
    for name, args in re.findall(r"(translate|rotate|scale)\(([^)]*)\)", text):
        v = [float(a) for a in args.replace(",", " ").split()]
        if name == "translate":
            m = np.array([[1, 0, v[0]], [0, 1, v[1] if len(v) > 1 else 0], [0, 0, 1]])
        elif name == "scale":
            m = np.diag([v[0], v[1] if len(v) > 1 else v[0], 1])
        else:
            if len(v) != 1:
                raise ValueError(f"中心つきの rotate は読めない: {text}")
            c, s = math.cos(math.radians(v[0])), math.sin(math.radians(v[0]))
            m = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        out = out @ m
    return out


def arc_points(start, rx, ry, rotation, large, sweep, end):
    """SVG の円弧(端点の指定)を折れ線にする。始点は含めず、終点まで。"""
    if rotation != 0 or abs(rx - ry) > 1e-9:
        raise ValueError("回転つきの弧・楕円の弧は読めない")
    r = rx
    half = (np.array(start) - np.array(end)) / 2
    mid = (np.array(start) + np.array(end)) / 2
    d2 = half @ half
    r = max(r, math.sqrt(d2))
    k = math.sqrt(max(r * r - d2, 0) / d2) * (-1 if large == sweep else 1)
    center = mid + k * np.array([half[1], -half[0]])
    a0 = math.atan2(start[1] - center[1], start[0] - center[0])
    a1 = math.atan2(end[1] - center[1], end[0] - center[0])
    delta = a1 - a0
    if sweep and delta < 0:
        delta += 2 * math.pi
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    n = max(2, math.ceil(abs(math.degrees(delta)) / ARC_STEP))
    return [(center[0] + r * math.cos(a0 + delta * i / n), center[1] + r * math.sin(a0 + delta * i / n))
            for i in range(1, n + 1)]


def contours(d, m):
    """パスを、行列 m をかけた折れ線の輪郭(N×2 の配列)の並びにする。"""
    tokens = re.findall(r"[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", d)
    scale = math.sqrt(abs(np.linalg.det(m[:2, :2])))
    out, points, i, cmd, cur, start = [], [], 0, "", (0.0, 0.0), (0.0, 0.0)

    def num():
        nonlocal i
        i += 1
        return float(tokens[i - 1])

    def curve(control):
        length = sum(math.dist(a, b) for a, b in zip(control, control[1:])) * scale
        n = min(64, max(3, math.ceil(length / CURVE_STEP)))
        for step in range(1, n + 1):
            t, pts = step / n, [np.array(p) for p in control]
            while len(pts) > 1:
                pts = [a + (b - a) * t for a, b in zip(pts, pts[1:])]
            points.append(tuple(pts[0]))

    def close():
        nonlocal points
        if len(points) >= 3:
            pts = np.array(points)
            if np.allclose(pts[0], pts[-1]):
                pts = pts[:-1]
            pts = np.c_[pts, np.ones(len(pts))] @ m.T
            out.append(np.ascontiguousarray(pts[:, :2], dtype=np.float64))
        points = []

    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
        rel = cmd.islower()
        base = cur if rel else (0.0, 0.0)
        op = cmd.upper()
        if op == "M":
            close()
            cur = start = (base[0] + num(), base[1] + num())
            points.append(cur)
            cmd = "l" if rel else "L"
        elif op == "L":
            cur = (base[0] + num(), base[1] + num())
            points.append(cur)
        elif op == "H":
            cur = (base[0] + num(), cur[1])
            points.append(cur)
        elif op == "V":
            cur = (cur[0], base[1] + num())
            points.append(cur)
        elif op in "QC":
            control = [cur] + [(base[0] + num(), base[1] + num()) for _ in range(2 if op == "Q" else 3)]
            curve(control)
            cur = control[-1]
        elif op == "A":
            rx, ry, rotation, large, sweep = num(), num(), num(), num(), num()
            end = (base[0] + num(), base[1] + num())
            points.extend(arc_points(cur, rx, ry, rotation, bool(large), bool(sweep), end))
            cur = end
        elif op == "Z":
            close()
            cur = start
        else:
            raise ValueError(f"読めないパスの命令: {cmd}")
    close()
    return out


def union(sections):
    sections = [s for s in sections if not s.is_empty()]
    if len(sections) > 1:
        return CrossSection.batch_boolean(sections, OpType.Add)
    return sections[0] if sections else CrossSection()


def section(element, m, clips):
    """要素を 2D の形にする(SVG の座標のまま)。知らない要素・属性はエラーにする。"""
    known = {"d", "transform", "fill-rule", "clip-path", "id", "fill", "data-tier", "data-z-top", "data-cut"}
    extra = set(element.attrib) - known
    if extra:
        raise ValueError(f"読めない属性 {sorted(extra)}(<{element.tag.replace(SVG, '')}>)")
    m = m @ matrix(element.get("transform", ""))
    if element.tag == SVG + "path":
        rule = FillRule.EvenOdd if element.get("fill-rule") == "evenodd" else FillRule.NonZero
        shape = CrossSection(contours(element.get("d"), m), rule)
    elif element.tag == SVG + "g":
        shape = union([section(child, m, clips) for child in element])
    else:
        raise ValueError(f"読めない要素 <{element.tag.replace(SVG, '')}>")
    clip = element.get("clip-path")
    if clip:
        if element.get("transform"):
            raise ValueError("transform と clip-path を同じ要素には書けない")
        shape = shape ^ clips[re.fullmatch(r"url\(#(.+)\)", clip).group(1)]
    return shape


def read_design(path):
    """SVG を [(id, 色, 段, 上面の高さ, cut か, 形)] にする。"""
    root = ET.parse(path).getroot()
    clips, groups = {}, []
    for child in root:
        if child.tag == SVG + "title":
            continue
        if child.tag == SVG + "defs":
            for clip in child:
                if clip.tag != SVG + "clipPath":
                    raise ValueError(f"defs の中の読めない要素 <{clip.tag.replace(SVG, '')}>")
                clips[clip.get("id")] = union([section(shape, np.eye(3), {}) for shape in clip])
            continue
        if child.tag != SVG + "g" or child.get("data-tier") is None:
            raise ValueError(f"{path.name}: 段の書いていない要素 <{child.tag.replace(SVG, '')}>")
        shape = section(child, np.eye(3), clips)
        if shape.is_empty():
            raise ValueError(f"{path.name}: {child.get('id')} の形が空")
        groups.append((child.get("id"), child.get("fill").upper(), int(child.get("data-tier")),
                       float(child.get("data-z-top")), child.get("data-cut") == "true", shape))
    return groups


# ---------- 積む ----------

def build(front, back):
    """色ごとの部品 {色: Manifold} と、段ごとの (段, 下面, 上面, 色) を返す。底(裏)が z = 0。"""
    field = [g for g in front if g[2] == 0 and not g[4]]
    disc = union([g[5] for g in field]).scale((1, -1))                     # SVG は y が下向き
    body_top = field[0][3]
    cuts = union([g[5] for g in front if g[4]])
    inlay_top = {g[3] for g in back if g[2] < 0}
    if len(inlay_top) != 1:
        raise ValueError("裏の埋め込みの深さが 1 つに決まらない")
    inlay_top = inlay_top.pop()
    # back.svg は裏から見た図。コインを左右に裏返して見ているので、立体では x・y とも反転(180° 回す)
    inlay = (union([g[5] for g in back if g[2] < 0]).rotate(180) ^ disc).extrude(inlay_top)
    solids = {coin.INK: [inlay], coin.WHITE: [disc.extrude(body_top) - inlay]}
    levels, below = [], body_top
    for level in sorted({g[2] for g in front if g[2] > 0}):
        members = [g for g in front if g[2] == level and not g[4]]
        colors, tops = {g[1] for g in members}, {g[3] for g in members}
        if len(colors) != 1 or len(tops) != 1:
            raise ValueError(f"段 {level} の色か高さが 1 つに決まらない")
        color, top = colors.pop(), tops.pop()
        shape = union([g[5] for g in front if g[2] >= level and not g[4]])
        if not cuts.is_empty():
            shape = shape - cuts
        solids.setdefault(color, []).append(shape.scale((1, -1)).extrude(top - below).translate((0, 0, below)))
        levels.append((level, below, top, color))
        below = top
    parts = {}
    for color, pieces in solids.items():
        part = pieces[0]
        for piece in pieces[1:]:
            part = part + piece
        parts[color] = part
    return parts, levels


def to_trimesh(shape):
    mesh = shape.to_mesh()
    return trimesh.Trimesh(vertices=np.asarray(mesh.vert_properties)[:, :3], faces=np.asarray(mesh.tri_verts), process=False)


# ---------- 書き出す・読み直す ----------

def write_3mf(path, title, parts):
    """色ごとの部品を 1 つのオブジェクトにまとめた素の 3MF(コア仕様だけ。スライサー固有の設定は入れない)。"""
    names = list(parts)
    model = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">',
             f' <metadata name="Title">{title}</metadata>', " <resources>", '  <basematerials id="1">']
    model += [f'   <base name="{PART_NAMES[color]}" displaycolor="{color}FF"/>' for color in names]
    model.append("  </basematerials>")
    for index, color in enumerate(names):
        mesh = to_trimesh(parts[color])
        model.append(f'  <object id="{index + 2}" type="model" name="{PART_NAMES[color]}" pid="1" pindex="{index}"><mesh><vertices>')
        model.append("".join(f'<vertex x="{v[0]:.5f}" y="{v[1]:.5f}" z="{v[2]:.5f}"/>' for v in mesh.vertices))
        model.append("</vertices><triangles>")
        model.append("".join(f'<triangle v1="{t[0]}" v2="{t[1]}" v3="{t[2]}"/>' for t in mesh.faces))
        model.append("</triangles></mesh></object>")
    parent = len(names) + 2
    model.append(f'  <object id="{parent}" type="model" name="{title}"><components>')
    model += [f'   <component objectid="{index + 2}"/>' for index in range(len(names))]
    model += ["  </components></object>", " </resources>", f' <build><item objectid="{parent}"/></build>', "</model>"]
    content_types = ('<?xml version="1.0" encoding="UTF-8"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\n'
                     ' <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\n'
                     ' <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>\n</Types>')
    rels = ('<?xml version="1.0" encoding="UTF-8"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\n'
            ' <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>\n</Relationships>')
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", rels)
        archive.writestr("3D/3dmodel.model", "\n".join(model))


def manifold(vertices, faces, what):
    shape = Manifold(Mesh(np.asarray(vertices, dtype=np.float32), np.asarray(faces, dtype=np.uint32)))
    if shape.status().name != "NoError" or shape.is_empty():
        raise RuntimeError(f"{what}: 閉じた立体になっていない({shape.status().name})")
    return shape


def read_3mf(path):
    """write_3mf の書いたファイルを読み直して {部品名: Manifold} にする。"""
    ns = "{http://schemas.microsoft.com/3dmanufacturing/core/2015/02}"
    with zipfile.ZipFile(path) as archive:
        root = ET.fromstring(archive.read("3D/3dmodel.model"))
    meshes = {}
    for obj in root.iter(ns + "object"):
        mesh = obj.find(ns + "mesh")
        if mesh is None:
            continue
        vertices = [[float(v.get(k)) for k in "xyz"] for v in mesh.iter(ns + "vertex")]
        faces = [[int(t.get(k)) for k in ("v1", "v2", "v3")] for t in mesh.iter(ns + "triangle")]
        meshes[obj.get("name")] = manifold(vertices, faces, f"{path.name} の {obj.get('name')}")
    components = [c.get("objectid") for c in root.iter(ns + "component")]
    if len(components) != len(meshes) or len(list(root.iter(ns + "item"))) != 1:
        raise RuntimeError(f"{path.name}: 部品のまとめ方が合っていない")
    return meshes


# ---------- 検査 ----------

PPM, SIZE = coin.PPM, coin.SIZE       # make-coin.py の検査用マスクと同じ: 1 mm = 20 px、42 mm 角


def raster(shape):
    """2D の形を、上から見た白黒の画像にする(x 右向き、y 上向き。SVG と同じ画素の並び)。
    Chrome の描いたマスクと同じく「画素の半分以上を覆っていれば黒」になるよう、4 倍で描いて縮める。"""
    over = 4

    def area(contour):
        x, y = contour[:, 0], contour[:, 1]
        return float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))) / 2

    image = Image.new("L", (SIZE * over, SIZE * over), 0)
    draw = ImageDraw.Draw(image)
    # 外の輪郭(反時計回り)は塗り、穴(時計回り)は抜く。大きい順に描けば、穴の中の島も正しく残る
    for contour in sorted(shape.to_polygons(), key=lambda c: -abs(area(c))):
        draw.polygon([((x + 21) * PPM * over, (21 - y) * PPM * over) for x, y in contour],
                     fill=255 if area(contour) > 0 else 0)
    return np.asarray(image.resize((SIZE, SIZE), Image.BOX)) > 127


def off(got, mask):
    """got が mask から 1 画素(0.05 mm)を超えてずれている面積(mm²)。
    境目が画素の途中に来ると描き方の違いで 1 画素ずれるので、その幅は数えない。"""
    image = Image.fromarray(mask.astype(np.uint8) * 255)
    grown = np.asarray(image.filter(ImageFilter.MaxFilter(3))) > 127
    shrunk = np.asarray(image.filter(ImageFilter.MinFilter(3))) > 127
    return float(((got & ~grown) | (shrunk & ~got)).sum()) / PPM ** 2


def flipped(shape, thickness):
    """コインを左右に裏返して置き直す(y 軸まわりに 180°。裏が上を向く)。"""
    return shape.rotate((0, 180, 0)).translate((0, 0, thickness))


def top_view(meshes, thickness):
    """上から見た色つきの絵。0.2 mm ごとの断面を下から塗り重ねる。"""
    image = np.full((SIZE, SIZE, 3), 223, dtype=np.uint8)
    for step in range(round(thickness / 0.2)):
        z = step * 0.2 + 0.1
        for name, shape in meshes.items():
            color = next(c for c, n in PART_NAMES.items() if n == name)
            rgb = [int(color[i:i + 2], 16) for i in (1, 3, 5)]
            image[raster(shape.slice(z))] = rgb
    return image


def check(key, three_mf, stls, levels, thickness):
    """書き出したファイルを読み直して確かめる。返すのは (報告の行, 表の絵, 裏の絵)。"""
    meshes = read_3mf(three_mf)
    lines = []
    for name, shape in meshes.items():
        # STL は頂点のつながりを持たない。QR のマスが角で接する所は読み直すと辺を共有して見えるので、
        # 「閉じているか」は 3MF の側(read_3mf)で確かめ、STL は体積が同じことを見る
        mesh = trimesh.load(stls[name])
        if abs(mesh.volume - shape.volume()) > 0.01:
            raise RuntimeError(f"{stls[name].name}: 3MF の部品と体積が違う")
        lines.append(f"  {name}: {shape.volume():.1f} mm³、三角形 {shape.num_tri()}")
    names = list(meshes)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            shared = (meshes[a] ^ meshes[b]).volume()
            if shared > 0.01:
                raise RuntimeError(f"{key}: {a} と {b} が重なっている({shared:.3f} mm³)")
    # 部品を 1 つに足してから測ることはしない。角で接するタイルを足すと、すき間に余計な面ができることがあった
    boxes = np.array([shape.bounding_box() for shape in meshes.values()])
    low, high = boxes[:, :3].min(axis=0), boxes[:, 3:].max(axis=0)
    size = high - low
    if not (np.allclose(low, [-coin.RADIUS, -coin.RADIUS, 0], atol=0.01) and np.allclose(size, [40, 40, thickness], atol=0.01)):
        raise RuntimeError(f"{key}: 大きさか置き場所が違う({low} 〜 {high})")
    lines.insert(0, f"  大きさ {size[0]:.2f} × {size[1]:.2f} × {size[2]:.2f} mm、底は z = {low[2]:.2f}、部品の重なりなし")

    # 表: 段ごとの断面を、図案の検査用マスクと重ねる
    for level, below, top, color in levels:
        mask = np.asarray(Image.open(coin.BUILD / f"mask-{key}-{level}.png").convert("L")) < 128
        z = (below + top) / 2
        got = raster(meshes[PART_NAMES[color]].slice(z))
        wrong = off(got, mask)
        other = sum(shape.slice(z).area() for name, shape in meshes.items() if name != PART_NAMES[color])
        lines.append(f"  表の段 {level}(z {below:.1f}〜{top:.1f}、{coin.COLOR_NAMES[color]}): "
                     f"図案から 0.05 mm を超えてずれた面積 {wrong:.3f} mm²(左右を逆にすると {off(got[:, ::-1], mask):.0f} mm²)")
        if wrong > MAX_OFF or other > 0:
            raise RuntimeError(f"{key}: 段 {level} の形か色が図案と合わない(ずれ {wrong:.3f} mm²、ほかの色 {other:.3f} mm²)")

    # 裏: 立体を裏返して上から見た形を、back.svg のマスク(黒 = 埋め込み)と重ねる。鏡像ならここで落ちる
    turned = {name: flipped(shape, thickness) for name, shape in meshes.items()}
    mask = np.asarray(Image.open(coin.BUILD / "mask-back--1.png").convert("L")) < 128
    got = raster(turned["black"].slice(thickness - 0.1))
    wrong, mirrored = off(got, mask), off(got[:, ::-1], mask)
    lines.append(f"  裏(立体を裏返して上から): 図案から 0.05 mm を超えてずれた面積 {wrong:.3f} mm²(左右を逆にすると {mirrored:.0f} mm²)")
    if wrong > MAX_OFF or mirrored < 10:
        raise RuntimeError(f"{key}: 裏の向きか形が図案と合わない(ずれ {wrong:.3f} mm²)")

    front, back = top_view(meshes, thickness), top_view(turned, thickness)
    png = coin.BUILD / f"model-back-{key}.png"
    Image.fromarray(back).save(png)
    for args in ([], ["220", "5"]):
        text = subprocess.run([str(coin.TOOL), "decode", str(png)] + args, capture_output=True, text=True).stdout.strip()
        if text != coin.QR_TEXT:
            raise RuntimeError(f"{key}: 立体の裏の絵から QR を読めない({text})")
    lines.append(f"  裏の絵から QR を読めた: {coin.QR_TEXT}(ぼかして縮めた版でも)")
    return lines, front, back


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    back = read_design(coin.OUT / "back.svg")
    views = []
    for key in coin.PICKED:
        parts, levels = build(read_design(coin.OUT / f"front-{key}.svg"), back)
        thickness = levels[-1][2]
        name = f"kakiire-coin-{key}"
        three_mf = OUT / f"{name}.3mf"
        write_3mf(three_mf, name, parts)
        stls = {}
        for color, shape in parts.items():
            stls[PART_NAMES[color]] = OUT / f"{name}-{PART_NAMES[color]}.stl"
            to_trimesh(shape).export(stls[PART_NAMES[color]])
        lines, front, back_view = check(key, three_mf, stls, levels, thickness)
        print(f"{three_mf.name}(厚み {thickness:.1f} mm)")
        print("\n".join(lines))
        views.append(np.concatenate([front, back_view], axis=1))
    Image.fromarray(np.concatenate(views, axis=0)).save(OUT / "preview.png")
    print("検査はすべて通った。docs/coin/print/preview.png は、書き出した立体を上から見た絵(左が表、右が裏)")


if __name__ == "__main__":
    sys.exit(main())
