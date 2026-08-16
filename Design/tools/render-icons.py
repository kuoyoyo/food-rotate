#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 Design/icons/*.svg 渲染成實際尺寸的對照圖，讓任何人都能自己重跑
S2 那幾輪的圖示判斷 —— 而不是只能相信規格裡寫的結論。

    python3 Design/tools/render-icons.py

產出在 Design/.render-out/（已 gitignore，圖不進 repo，腳本才進）。

────────────────────────────────────────────────────────────────
為什麼需要這支腳本
────────────────────────────────────────────────────────────────
S2 的每一個圖示決策 —— 湯的不能是放大鏡、小吃不能是丸子、
肉食烤紋只能 2 道、油邊內縮只能 0.78 —— 都是「渲染到 17pt 看過」
得出的結論。規格裡留下的是結論，證據原本在暫存區，已經不存在了。

沒有能重跑的渲染，就分不出「我驗過了」跟「我覺得可以」。
（QC 報告 P3-2；與 S6 要求工程「先寫一支會紅的測試」是同一條標準。）

────────────────────────────────────────────────────────────────
⚠️ 方法上最重要的一件事：放大，不要重畫
────────────────────────────────────────────────────────────────
線條「糊在一起」是**點陣化當下**發生的：兩條線的距離小於一個像素，
它們就在那一刻併成一條，之後再也分不開。

所以要判斷小尺寸會不會糊，唯一正確的做法是
    **先渲染到 17pt 的真實像素，再把那張小圖放大來看。**

如果直接用大尺寸渲染再縮小、或直接看 144px 的圖，
線永遠是分開的 —— 你會看到一個在真機上不存在的畫面，然後以為它沒問題。
本腳本的 `_magnify()` 用最近鄰放大，就是為了保住這件事：
放大的是**像素**，不是重新畫一次。

────────────────────────────────────────────────────────────────
量測定義（S2 用的就是這兩個，寫在這裡免得日後靠記憶）
────────────────────────────────────────────────────────────────
墨跡 bbox   alpha > 0.5 的像素的最小外接矩形，以畫布邊長的百分比表示。
面積利用率  = bbox 寬佔比 × bbox 高佔比。
            量的是「這個圖示用掉了多少格子」，不是墨水的多寡。
            24×24 的格子留太多白，圖示在 17pt 就會顯得比鄰居小一號。
            參考值：定案的九個落在 57–81%（跑一次就會印出當下的值）。
            S2 一開始那批平均只有 44%，就是靠這個數字看出來的 ——
            「感覺有點小」講不清楚，「用掉 44% 的格子」講得清楚。

量測一律在 48pt（144px）上做 —— 量的是**畫的內容**，
不是點陣化的副作用。糊不糊則一律在 17pt 上看。這兩件事不能混用同一張圖。

已知值（用來確認渲染器沒壞）：**肉食 83% × 69%，面積 57%**。
換渲染器之後這三個數對不上，先懷疑渲染器，不要先改圖示。
第一版這支腳本用 `qlmanage`，它不縮放 SVG，量出來九個全是 100% ——
一個看起來成功、其實量錯對象的驗證。理由詳見 svg2png.swift 檔頭。

────────────────────────────────────────────────────────────────
為什麼是這三個尺寸
────────────────────────────────────────────────────────────────
17pt  候選清單的列內圖示，也是全 App 最小的出現場合 —— 生死線在這裡
24pt  篩選器與清單標題
48pt  規格與這份對照圖的檢視用，不是 App 裡的實際尺寸

一律以 @3x 換算成實際像素（17pt → 51px），因為圖示是在真機的像素上糊掉的，
不是在點上。
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

# ── 路徑 ────────────────────────────────────────────────────────
HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.dirname(HERE)
ROOT = os.path.dirname(DESIGN)
ICONS = os.path.join(DESIGN, "icons")
OUT = os.path.join(DESIGN, ".render-out")
TOKENS = os.path.join(ROOT, "FoodRotate", "DesignTokens.swift")

SCALE = 3                      # @3x
FORM_PT = [17, 24, 48]
APP_PT = [60, 40, 29, 20]
MAGNIFY = 6                    # 17pt 檢視圖的放大倍率（最近鄰）

# 九個 form 圖示的顯示順序 = 吃法標籤在 App 裡的順序。
# 撞形檢查要照這個順序看，因為鄰居撞形才是真的會混淆。
FORM_ORDER = [
    "form-rice", "form-noodles", "form-soup", "form-hotpot",
    "form-bread", "form-snack", "form-meat", "form-light", "form-unknown",
]


# ── 色票：從 DesignTokens.swift 讀，不手貼 ──────────────────────
def load_tokens():
    """
    色票只有一份來源。手貼過一次就會分岔 —— S1 的蔥綠淺就是這樣錯的。
    """
    try:
        src = open(TOKENS, encoding="utf-8").read()
    except OSError:
        sys.exit("找不到 %s —— 這支腳本要從專案根目錄的結構去讀色票。" % TOKENS)

    def grab(enum_name, member):
        # enum Light { ... static let card = RGB(0xF8F5EE) ... }
        block = re.search(r"enum\s+%s\s*\{(.*?)\n    \}" % enum_name, src, re.S)
        if not block:
            sys.exit("DesignTokens.swift 裡找不到 enum %s" % enum_name)
        m = re.search(r"static let %s\s*=\s*RGB\(0x([0-9A-Fa-f]{6})\)" % member,
                      block.group(1))
        if not m:
            sys.exit("DesignTokens.swift 的 %s 裡找不到 %s" % (enum_name, member))
        h = m.group(1)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

    return {
        "light": {"ink": grab("Light", "text"), "bg": grab("Light", "card")},
        "dark": {"ink": grab("Dark", "text"), "bg": grab("Dark", "card")},
    }


# ── 渲染 ────────────────────────────────────────────────────────
def rasterize(svg_paths, sizes, tmpdir):
    """
    交給 svg2png.swift 一次點陣化完（每叫一次 swift 要編譯一次，所以只叫一次）。
    回傳 {(檔名, px): RGBA 圖}。SVG 是 currentColor 單色，只有 alpha 有意義，
    顏色在 tint() 用 token 上。
    """
    subprocess.run(
        ["swift", os.path.join(HERE, "svg2png.swift"), tmpdir,
         ",".join(str(s) for s in sizes)] + svg_paths,
        check=True)
    out = {}
    for p in svg_paths:
        stem = os.path.splitext(os.path.basename(p))[0]
        for px in sizes:
            f = os.path.join(tmpdir, "%s@%d.png" % (stem, px))
            if not os.path.exists(f):
                sys.exit("渲染器沒有產出 %s" % os.path.basename(f))
            out[(stem, px)] = Image.open(f).convert("RGBA")
    return out


def tint(alpha_img, ink, bg):
    """把單色圖的 alpha 當遮罩，用 token 的 ink 疊在 token 的 bg 上。"""
    out = Image.new("RGB", alpha_img.size, bg)
    out.paste(Image.new("RGB", alpha_img.size, ink), mask=alpha_img.split()[3])
    return out


def _magnify(im, factor):
    """最近鄰放大。放大像素，不重畫 —— 理由見檔頭。"""
    return im.resize((im.width * factor, im.height * factor), Image.NEAREST)


# ── 量測 ────────────────────────────────────────────────────────
def measure(alpha_img):
    """回傳 (寬佔比, 高佔比, 面積利用率)，定義見檔頭。"""
    a = alpha_img.split()[3]
    box = a.point(lambda v: 255 if v > 127 else 0).getbbox()
    if not box:
        return 0.0, 0.0, 0.0
    w = (box[2] - box[0]) / alpha_img.width
    h = (box[3] - box[1]) / alpha_img.height
    return w, h, w * h


# ── 排版 ────────────────────────────────────────────────────────
def font(size):
    for path in ("/System/Library/Fonts/Hiragino Sans GB.ttc",
                 "/System/Library/Fonts/SFNSMono.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def label_of(svg_path):
    """用 SVG 裡的 aria-label（中文名），沒有就退回檔名。"""
    try:
        m = re.search(r'aria-label="([^"]+)"', open(svg_path, encoding="utf-8").read())
        if m:
            return m.group(1)
    except OSError:
        pass
    return os.path.splitext(os.path.basename(svg_path))[0]


def contact_sheet(tiles, labels, theme, title, cell=None, gap=24, pad=32):
    """
    九個並排。**撞形只有並排看得出來** ——
    S2 的每一次退回（湯的像放大鏡、小吃像丸子、肉食像魚）
    都是在鄰居旁邊才看出來的，單張圖驗不到。
    """
    ink, bg = theme["ink"], theme["bg"]
    cell = cell or max(t.width for t in tiles)
    lab_h = 30
    W = pad * 2 + len(tiles) * cell + (len(tiles) - 1) * gap
    H = pad * 2 + 44 + cell + lab_h
    sheet = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(sheet)
    d.text((pad, pad - 6), title, fill=ink, font=font(20))

    for i, (t, lab) in enumerate(zip(tiles, labels)):
        x = pad + i * (cell + gap)
        y = pad + 44
        sheet.paste(t, (x + (cell - t.width) // 2, y + (cell - t.height) // 2))
        d.text((x + cell // 2, y + cell + 8), lab, fill=ink,
               font=font(15), anchor="ma")
    return sheet


# ── 主流程 ──────────────────────────────────────────────────────
def main():
    if not shutil.which("swift"):
        sys.exit("找不到 swift —— 這支腳本要 macOS 的 Xcode command line tools。")

    tokens = load_tokens()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    tmpdir = tempfile.mkdtemp()

    forms = [os.path.join(ICONS, n + ".svg") for n in FORM_ORDER]
    missing = [p for p in forms if not os.path.exists(p)]
    if missing:
        sys.exit("少了這些圖示：%s" % ", ".join(os.path.basename(p) for p in missing))
    labels = [label_of(p) for p in forms]
    apps = [os.path.join(ICONS, n + ".svg")
            for n in ("app-icon", "app-icon-tinted")
            if os.path.exists(os.path.join(ICONS, n + ".svg"))]

    print("色票讀自 DesignTokens.swift："
          "淺 ink #%02X%02X%02X on #%02X%02X%02X／"
          "深 ink #%02X%02X%02X on #%02X%02X%02X"
          % (tokens["light"]["ink"] + tokens["light"]["bg"]
             + tokens["dark"]["ink"] + tokens["dark"]["bg"]))
    print("渲染中……")

    px_all = sorted({pt * SCALE for pt in FORM_PT + APP_PT})
    img = rasterize(forms + apps, px_all, tmpdir)
    stems = [os.path.splitext(os.path.basename(p))[0] for p in forms]
    print()

    # 1. 九個並排，每個尺寸淺深各一張（撞形檢查）
    for pt in FORM_PT:
        px = pt * SCALE
        for name, theme in tokens.items():
            zh = "淺色" if name == "light" else "深色"
            tiles = [tint(img[(s, px)], theme["ink"], theme["bg"]) for s in stems]
            sheet = contact_sheet(
                tiles, labels, theme,
                "%dpt @%dx = %dpx ・ %s ・ 實際大小" % (pt, SCALE, px, zh),
                cell=max(px, 72))
            out = os.path.join(OUT, "form-%02dpt-%s.png" % (pt, name))
            sheet.save(out)
            print("  ", os.path.basename(out))

    # 2. 17pt 放大檢視 —— 這張才看得到誰糊在一起
    px17 = 17 * SCALE
    for name, theme in tokens.items():
        zh = "淺色" if name == "light" else "深色"
        tiles = [_magnify(tint(img[(s, px17)], theme["ink"], theme["bg"]), MAGNIFY)
                 for s in stems]
        sheet = contact_sheet(
            tiles, labels, theme,
            "17pt 的像素放大 %d 倍（最近鄰）・%s ・"
            "看的是 %dpx 那張，不是重畫的" % (MAGNIFY, zh, px17),
            gap=16)
        out = os.path.join(OUT, "form-17pt-magnified-%s.png" % name)
        sheet.save(out)
        print("  ", os.path.basename(out))

    # 3. App Icon 四個尺寸（它自帶背景，不上 token 色）
    for p in apps:
        tag = os.path.splitext(os.path.basename(p))[0]
        tiles = [Image.alpha_composite(
                     Image.new("RGBA", img[(tag, pt * SCALE)].size,
                               tokens["dark"]["bg"] + (255,)),
                     img[(tag, pt * SCALE)]).convert("RGB")
                 for pt in APP_PT]
        labs = ["%dpt (%dpx)" % (pt, pt * SCALE) for pt in APP_PT]
        sheet = contact_sheet(tiles, labs, tokens["dark"],
                              "%s ・實際大小" % tag, cell=APP_PT[0] * SCALE)
        out = os.path.join(OUT, "%s.png" % tag)
        sheet.save(out)
        print("  ", os.path.basename(out))

    # 4. 量測表（在 48pt 上量，理由見檔頭）
    print("\n量測（48pt/%dpx 上量；面積利用率 = 寬佔比 × 高佔比）" % (48 * SCALE))
    print("%-9s %-14s %6s %6s %7s" % ("檔名", "名稱", "寬", "高", "面積"))
    for stem, lab in zip(stems, labels):
        w, h, area = measure(img[(stem, 48 * SCALE)])
        print("%-9s %-14s %5.0f%% %5.0f%% %6.0f%%"
              % (stem.replace("form-", ""), lab, w * 100, h * 100, area * 100))

    mw, mh, ma = measure(img[("form-meat", 48 * SCALE)])
    ok = (round(mw * 100), round(mh * 100), round(ma * 100)) == (83, 69, 57)
    print("\n渲染器自檢（肉食應為 83%% × 69%%，面積 57%%）：%s"
          % ("通過" if ok else "❌ 對不上 —— 先懷疑渲染器，不要先改圖示"))

    shutil.rmtree(tmpdir, ignore_errors=True)
    print("產出：%s" % OUT)
    print("先看 form-17pt-*.png（生死線），再看 form-17pt-magnified-*.png（誰糊了）。")


if __name__ == "__main__":
    main()
