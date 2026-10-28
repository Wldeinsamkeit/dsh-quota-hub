#!/usr/bin/env python3
"""生成 QuotaBar 图标：菜单栏模板鲸鱼（黑色，系统自动反色）+ 弹窗彩色鲸鱼。"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)))


def whale(size: int, template: bool) -> Image.Image:
    s_n = 4  # 超采样
    im = Image.new('RGBA', (size * s_n, size * s_n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = size * s_n / 64.0

    def P(pts):
        return [(x * s, y * s) for x, y in pts]

    ink = (0, 0, 0, 255) if template else (77, 107, 254, 255)

    # 身体（圆润椭圆）
    d.ellipse(P([(6, 22), (47, 47)]), fill=ink)
    # 头部隆起
    d.ellipse(P([(9, 17), (36, 41)]), fill=ink)
    # 尾鳍
    d.polygon(P([(42, 29), (61, 19), (55, 34), (61, 47), (42, 40)]), fill=ink)

    if not template:
        # 白肚皮
        d.ellipse(P([(13, 36), (43, 49)]), fill=(255, 255, 255, 255))
        # 眼睛
        d.ellipse(P([(19, 27), (25, 33)]), fill=(255, 255, 255, 255))
        d.ellipse(P([(21, 29), (24, 32)]), fill=(25, 35, 70, 255))
        # 嘴角弧线
        d.arc(P([(12, 30), (30, 42)]), start=20, end=110, fill=(255, 255, 255, 220), width=max(1, int(1.5 * s)))
        # 喷水
        d.line(P([(16, 15), (12, 6)]), fill=ink, width=max(1, int(2 * s)))
        d.line(P([(21, 14), (20, 5)]), fill=ink, width=max(1, int(2 * s)))

    return im.resize((size, size), Image.LANCZOS)


whale(36, True).save(os.path.join(OUT, 'whale-bar.png'))     # 菜单栏模板图（黑色）
whale(128, False).save(os.path.join(OUT, 'whale-color.png'))  # 弹窗彩色图
print('icons written to', OUT)


def rainbow(size: int) -> Image.Image:
    """菜单栏小彩虹：同心圆弧（红橙黄绿蓝紫），不透明彩色图。"""
    s_n = 4
    im = Image.new('RGBA', (size * s_n, size * s_n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = size * s_n
    colors = [
        (255, 59, 48, 255),    # red
        (255, 149, 0, 255),    # orange
        (255, 204, 0, 255),    # yellow
        (52, 199, 89, 255),    # green
        (0, 122, 255, 255),    # blue
        (175, 82, 222, 255),   # violet
    ]
    cx, cy = s / 2, s * 0.92
    band = s * 0.105
    r0 = s * 0.80
    for i, color in enumerate(colors):
        r = r0 - i * band
        bbox = [cx - r, cy - r, cx + r, cy + r]
        d.arc(bbox, start=180, end=360, fill=color, width=max(2, int(band * 0.82)))
    return im.resize((size, size), Image.LANCZOS)


rainbow(36).save(os.path.join(OUT, 'rainbow-bar.png'))      # 菜单栏彩色小彩虹
rainbow(64).save(os.path.join(OUT, 'rainbow-color.png'))    # 面板头部用
print('rainbow icons written')
