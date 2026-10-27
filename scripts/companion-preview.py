#!/usr/bin/env python3
"""Draws the companion pixel art from Sources/Corner/Views/CompanionSprites.swift into a PNG,
each character in its main poses, for working on the art without rebuilding the app.

    python3 scripts/companion-preview.py out.png
"""
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "Sources/Corner/Views/CompanionSprites.swift").read_text()


def parse_sprites(text):
    sprites = {}
    for name, body in re.findall(r'static let (\w+) = """\n(.*?)\n\s*"""', text, re.S):
        rows = [r.strip() for r in body.split("\n")]
        widths = {len(r) for r in rows}
        assert len(widths) == 1, f"{name}: rows of different widths {sorted(widths)}"
        sprites[name] = rows
    return sprites


def parse_palettes(text):
    palettes = {}
    for name, body in re.findall(r'static let (\w+): \[Character: UInt32\] = \[(.*?)\]', text, re.S):
        palettes[name] = {k: int(v, 16) for k, v in re.findall(r'"(.)": 0x([0-9A-Fa-f]{6})', body)}
    return palettes


SPRITES = parse_sprites(SOURCE)
PALETTES = parse_palettes(SOURCE)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def blit(self, rows, x, y, flip=False):
        for r, row in enumerate(rows):
            for c, ch in enumerate(row[::-1] if flip else row):
                if ch == "." or ch == " ":
                    continue
                X, Y = x + c, y + r
                if 0 <= X < self.w and 0 <= Y < self.h:
                    self.px[Y][X] = ch

    def image(self, palette, scale):
        img = Image.new("RGBA", (self.w * scale, self.h * scale), (0, 0, 0, 0))
        for y in range(self.h):
            for x in range(self.w):
                ch = self.px[y][x]
                if ch is None:
                    continue
                rgb = palette.get(ch)
                assert rgb is not None, f"no colour for {ch!r}"
                color = ((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255)
                for dy in range(scale):
                    for dx in range(scale):
                        img.putpixel((x * scale + dx, y * scale + dy), color)
        return img


def with_rows(head, rows):
    return head[:6] + rows + head[12:]


def back_hair(hair, offset):
    """The hair from behind: the head shape filled with hair, under the front hair."""
    ox, oy = offset
    head = SPRITES["head"]
    out = [list(r) for r in hair]
    def edge(r, c):
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            R, C = r + dr, c + dc
            if not (0 <= R < len(head) and 0 <= C < len(head[0])) or head[R][C] == ".":
                return True
        return False
    for r, row in enumerate(head):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            R, C = r - oy, c - ox
            if 0 <= R < len(out) and 0 <= C < len(out[0]) and out[R][C] == ".":
                out[R][C] = "K" if edge(r, c) else ("h" if r >= 11 else "H")
    return ["".join(r) for r in out]


HAIR = {
    "ninja": ("ninjaHair", (-2, -5)),
    "swordsman": ("swordsmanHair", (-2, -5)),
    "mage": ("mageHat", (-3, -10)),
}


def figure(kind, pose):
    c = Canvas(40, 46)
    bx, by = 12, 30  # body top-left; the head sits 12 rows up
    hair_name, (hx, hy) = HAIR[kind]
    hair = SPRITES[hair_name]
    head = SPRITES["head"]
    face = {"open": None, "blink": "eyesBlink", "happy": "eyesHappy", "side": "eyesSide",
            "surprised": "eyesSurprised", "yawn": "eyesYawn"}
    def draw_head(expr, back=False):
        h = head if not face[expr] else with_rows(head, SPRITES[face[expr]])
        c.blit(h, bx, by - 12)
        c.blit(back_hair(hair, (hx, hy)) if back else hair, bx + hx, by - 12 + hy)

    if kind == "ninja" and pose not in ("back",):
        c.blit(SPRITES["scarfTail1"], bx - 5, by - 2)
    if kind == "swordsman" and pose in ("stand", "walk", "wave"):
        c.blit(SPRITES["sheath"], bx + 2, by + 5)
    if pose == "stand":
        c.blit(SPRITES["stand"], bx, by)
        draw_head("open")
    elif pose == "walk":
        c.blit(SPRITES["walk"], bx, by)
        draw_head("side")
    elif pose == "sit":
        c.blit(SPRITES["sit"], bx, by + 4)
        c.px  # sit is shorter
        h = with_rows(head, SPRITES["eyesBlink"])
        c.blit(h, bx, by + 4 - 12)
        c.blit(hair, bx + hx, by + 4 - 12 + hy)
    elif pose == "wave":
        c.blit(SPRITES["standOneArm"], bx, by)
        draw_head("happy")
        c.blit(SPRITES["armWave"], bx + 11, by - 5)
    elif pose == "back":
        c.blit(SPRITES["back"], bx, by)
        draw_head("open", back=True)
    elif pose == "hang":
        c.blit(SPRITES["reach"], bx, by)
        draw_head("surprised")
        c.blit(SPRITES["armUp"], bx + 10, by - 14)
        c.blit(SPRITES["armUp"], bx - 1, by - 14, flip=True)
    if kind == "ninja" and pose not in ("back", "sit"):
        c.blit(SPRITES["scarf"], bx + 2, by)
    if kind == "mage" and pose == "stand":
        c.blit(SPRITES["staff"], bx + 13, by - 6)
    return c


def cat(pose):
    c = Canvas(40, 46)
    if pose == "sit":
        c.blit(SPRITES["catSit"], 12, 26)
    elif pose == "blink":
        c.blit(SPRITES["catSit"][:6] + SPRITES["catBlink"] + SPRITES["catSit"][10:], 12, 26)
    elif pose == "happy":
        c.blit(SPRITES["catSit"][:6] + SPRITES["catHappy"] + SPRITES["catSit"][10:], 12, 26)
        c.blit(SPRITES["heart"], 24, 18)
    elif pose == "walk1":
        c.blit(SPRITES["catWalk1"], 10, 29)
    elif pose == "walk2":
        c.blit(SPRITES["catWalk2"], 10, 29)
    elif pose == "sleep":
        c.blit(SPRITES["catSleep"], 11, 33)
        c.blit(SPRITES["zee"], 28, 26)
    return c


def main(out):
    poses = ["stand", "walk", "wave", "sit", "back", "hang"]
    kinds = ["ninja", "swordsman", "mage"]
    scale = 6
    sheet = Image.new("RGBA", (len(poses) * 40 * scale, len(kinds) * 46 * scale), (40, 44, 70, 255))
    for r, kind in enumerate(kinds):
        palette = {**PALETTES["common"], **PALETTES[kind]}
        for i, pose in enumerate(poses):
            sheet.alpha_composite(figure(kind, pose).image(palette, scale), (i * 40 * scale, r * 46 * scale))
    palette = {**PALETTES["common"], **PALETTES["cat"]}
    sheet2 = Image.new("RGBA", (sheet.width, sheet.height + 46 * scale), (40, 44, 70, 255))
    sheet2.alpha_composite(sheet, (0, 0))
    for i, pose in enumerate(["sit", "blink", "happy", "walk1", "walk2", "sleep"]):
        sheet2.alpha_composite(cat(pose).image(palette, scale), (i * 40 * scale, len(kinds) * 46 * scale))
    sheet = sheet2
    sheet.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "companions.png")
