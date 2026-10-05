"""生成 App 图标：奶油色背景上的「噗噗」小豆子吉祥物。用法：python3 scripts/make_icon.py"""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 1024
K = 4  # 超采样
W = S * K

def c(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

img = Image.new("RGB", (W, W), c("FFF1E0"))
d = ImageDraw.Draw(img)

# 背景：上浅下暖的竖向渐变
top, bottom = c("FFF6EC"), c("FFDCC4")
for y in range(W):
    t = y / W
    d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))

def ell(cx, cy, rx, ry, fill, layer=None):
    (layer or d).ellipse([(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K], fill=fill)

# 阴影
shadow = Image.new("L", (W, W), 0)
sd = ImageDraw.Draw(shadow)
sd.ellipse([(512 - 330) * K, (850 - 40) * K, (512 + 330) * K, (850 + 40) * K], fill=90)
shadow = shadow.filter(ImageFilter.GaussianBlur(30 * K))
img.paste(c("E9B994"), (0, 0), shadow)
d = ImageDraw.Draw(img)

# 嫩芽
d.rounded_rectangle([(512 - 16) * K, 200 * K, (512 + 16) * K, 330 * K], radius=16 * K, fill=c("6CBF72"))
leaf = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ld = ImageDraw.Draw(leaf)
ld.ellipse([(512 - 190) * K, (180 - 55) * K, (512 - 10) * K, (180 + 55) * K], fill=c("7ACB7E") + (255,))
leaf = leaf.rotate(18, center=(512 * K, 230 * K))
img.paste(leaf, (0, 0), leaf)
leaf2 = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ld2 = ImageDraw.Draw(leaf2)
ld2.ellipse([(512 + 5) * K, (200 - 45) * K, (512 + 160) * K, (200 + 45) * K], fill=c("8FD592") + (255,))
leaf2 = leaf2.rotate(-20, center=(512 * K, 240 * K))
img.paste(leaf2, (0, 0), leaf2)
d = ImageDraw.Draw(img)

# 身体（竖向渐变椭圆）
body = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bd = ImageDraw.Draw(body)
b_top, b_bot = c("FFC994"), c("F4A062")
cx, cy, rx, ry = 512, 580, 360, 290
for y in range(int((cy - ry) * K), int((cy + ry) * K)):
    t = (y - (cy - ry) * K) / (2 * ry * K)
    col = tuple(int(b_top[i] + (b_bot[i] - b_top[i]) * t) for i in range(3)) + (255,)
    bd.line([(0, y), (W, y)], fill=col)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).ellipse([(cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K], fill=255)
img.paste(body, (0, 0), mask)
d = ImageDraw.Draw(img)

# 小脚
ell(400, 862, 70, 32, c("EE9858"))
ell(624, 862, 70, 32, c("EE9858"))

# 高光
hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(hl).ellipse([(300 - 70) * K, (430 - 34) * K, (300 + 70) * K, (430 + 34) * K], fill=(255, 255, 255, 140))
hl = hl.rotate(25, center=(300 * K, 430 * K))
img.paste(hl, (0, 0), hl)
d = ImageDraw.Draw(img)

ink = c("4A3A35")
# 眼睛
for ex in (412, 612):
    ell(ex, 580, 40, 44, ink)
    ell(ex + 14, 562, 14, 14, (255, 255, 255))
# 腮红
for bx in (322, 702):
    ell(bx, 650, 58, 32, c("FF8FA3"))
# 嘴巴
d.arc([(512 - 52) * K, (600 - 34) * K, (512 + 52) * K, (600 + 54) * K], start=20, end=160, fill=ink, width=18 * K)

img = img.resize((S, S), Image.LANCZOS)
out = os.path.join(os.path.dirname(__file__), "..", "Pupudiary", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out)
print("saved", os.path.abspath(out))
