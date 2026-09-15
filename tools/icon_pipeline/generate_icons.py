#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Icon generation pipeline for Hermes client.
Generates all platform icons from the brand masters in assets/branding/:
  - hermes-agent-icon-1024.png         app icon (all platforms, incl. the large
                                       notification icon's ink/paper derivation)
  - hermes-agent-notify-mark-1024.png  notification SMALL icon (setSmallIcon)
Target platforms: Android, Windows, macOS.
"""

from __future__ import annotations

import os
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple

try:
    from PIL import Image
except ImportError:
    print("[ERROR] Pillow is required. Please run: pip install pillow", file=sys.stderr)
    sys.exit(1)


# Path definitions relative to repository root
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE_ICON_PATH = REPO_ROOT / "assets" / "branding" / "hermes-agent-icon-1024.png"

# Android destination paths
ANDROID_RES_DIR = REPO_ROOT / "android" / "app" / "src" / "main" / "res"
ANDROID_LEGACY_SIZES: Dict[str, int] = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Android adaptive icon configurations
ANDROID_ADAPTIVE_DIR = ANDROID_RES_DIR / "mipmap-anydpi-v26"
ANDROID_DRAWABLE_DIR = ANDROID_RES_DIR / "drawable"
# Android notification small icon (Live Update / status bar).
# 24dp @ each density; alpha-only white so the system can tint it per context.
NOTIFICATION_ICON_SIZES: Dict[str, int] = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}
NOTIFICATION_ICON_NAME = "ic_hermes_agent"

# 通知小图标（setSmallIcon）有**独立源稿**，与 app 图标稿分开维护。
#
# 为什么不能拿 app 图标稿反色：24dp 就是 24×24 个真实像素，插画缩下去只剩
# 一团无法辨认的白块（五官全丢，实测只有外轮廓），主人反馈「看不太出来」。
# 小图标必须单独设计成「大块面 + 明确负空间」的记号才能在状态栏成立。
#
# 源稿是纯黑实心剪影 / 纯白纸，抠图极性是“白纸黑墨”：可见区 = 墨，alpha = 墨。
# 不灌水补洞——这张稿里的负空间都是设计出来的，补掉等于毁掉图形。
#
# 生成溯源（WisArt nano-banana-pro 图生图，参考 assets/branding/hermes-agent-icon-1024.png）：
#   "Redraw this character as a single solid black silhouette on a pure white
#    background - one connected black shape with no holes, no interior detail,
#    no facial features, no line work, only two tones. Preserve the outer contour
#    only: blunt bangs, long side hair, the bump of the headphone band and the
#    headphone earcup on the head, the shoulder line. Simplify the contour
#    massively - remove every small bump and hair strand, keep only large
#    unambiguous shapes. ... recognizable when reduced to 24x24 pixels."
NOTIFICATION_SOURCE_PATH = REPO_ROOT / "assets" / "branding" / "hermes-agent-notify-mark-1024.png"
# 墨区阈值：源稿是纯二值黑白，实测阈值切出的墨迹恰好是**单连通域、零碎点**，
# 故只做阈值不做形态学（开/闭运算会啃掉细笔画，反而伤图形）。
NOTIFICATION_INK_THRESHOLD = 140
NOTIFICATION_MASTER_SIZE = 96  # xxxhdpi 24dp

# 内部大图标（通知 setLargeIcon）：反色 + 透明底，并按系统昼夜分两套
#   dark  → drawable-night-xxxhdpi：白线条（深色面板/岛上可见）
#   light → drawable-xxxhdpi：黑线条（浅色面板上可见）
# 单一份透明底素材必在某一侧「隐身」，故用 uiMode 资源限定符分套。
NOTIFICATION_LARGE_ICON_NAME = "ic_hermes_large"
NOTIFICATION_LARGE_ICON_SIZE = 256  # xxxhdpi = 64dp
NOTIFICATION_LARGE_ICON_DIRS: Dict[str, str] = {
    "dark": "drawable-night-xxxhdpi",
    "light": "drawable-xxxhdpi",
}

ANDROID_VALUES_DIR = ANDROID_RES_DIR / "values"
ADAPTIVE_CANVAS_SIZE = 432  # xxxhdpi 108dp viewport (108 * 4)
ADAPTIVE_SAFE_RATIO = 72.0 / 108.0  # 66.67% safe zone ratio (72dp inner circle)

# Windows destination paths
WINDOWS_RESOURCES_DIR = REPO_ROOT / "windows" / "runner" / "resources"
WINDOWS_ICO_SIZES: List[Tuple[int, int]] = [
    (16, 16),
    (24, 24),
    (32, 32),
    (48, 48),
    (64, 64),
    (128, 128),
    (256, 256),
]

# macOS destination paths
MACOS_ICONSET_DIR = REPO_ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_SIZES: Dict[str, int] = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

# Tray icon destination paths
BRANDING_DIR = REPO_ROOT / "assets" / "branding"
TRAY_ICO_SIZES: List[Tuple[int, int]] = [
    (16, 16),
    (32, 32),
]


def trimTransparentPadding(img: Image.Image) -> Image.Image:
    """Crop fully transparent border based on alpha channel and pad to square.

    Uses alpha.getbbox() to find tight content bounds; if bbox is None (fully
    transparent or no alpha) returns original. When cropped region is not square,
    pads to max side centered on transparent canvas. Fixes source with ~10%
    outer padding (e.g. 101px) that makes taskbar icon look shrinked.
    """
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    try:
        alpha = img.split()[3]
    except Exception:
        return img
    bbox = alpha.getbbox()
    if bbox is None:
        return img
    cropped = img.crop(bbox)
    w, h = cropped.size
    if w == h:
        return cropped
    size = max(w, h)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset_x = (size - w) // 2
    offset_y = (size - h) // 2
    canvas.paste(cropped, (offset_x, offset_y), cropped)
    return canvas


def load_source_image(source_path: Path) -> Image.Image:
    """Load and validate the single source icon."""
    if not source_path.exists():
        raise FileNotFoundError(f"Source icon not found at {source_path}")

    img = Image.open(source_path).convert("RGBA")
    if img.size != (1024, 1024):
        print(f"[WARN] Source image size is {img.size}, expected (1024, 1024)")
    return img


SMALL_MASTER_SIZE = 256


def build_small_master(source_img: Image.Image) -> Image.Image:
    """High-contrast master for small-size rendering (taskbar / tray / toast).

    Steps: trim padding -> down to 256px with LANCZOS -> flatten onto an
    OPAQUE WHITE canvas via alpha compositing. The artwork is near-binary
    black on white with transparent outside; forcing alpha=255 would turn
    faint-alpha pixels (whose stored RGB is black) into stray black specks,
    while compositing onto white maps every transparent/AA pixel cleanly to
    the white background.
    """
    trimmed = trimTransparentPadding(source_img)
    master = trimmed.resize(
        (SMALL_MASTER_SIZE, SMALL_MASTER_SIZE), Image.Resampling.LANCZOS
    )
    white = Image.new("RGBA", master.size, (255, 255, 255, 255))
    return Image.alpha_composite(white, master)


def render_icon_size(master: Image.Image, size: int) -> Image.Image:
    """Crisp per-size rendering for taskbar/tray/toast usage.

    Large sizes (>=128) use plain LANCZOS. Small sizes step-halve to at least
    2x the target, then BOX pixel-averaging to final size. A/B-verified on
    this artwork: BOX-only is the cleanest at 16px (no ringing halo, no
    isolated specks); UnsharpMask was tried and rejected — it introduces
    stray pixels and line breaks that read as noise on the taskbar.
    """
    if size >= 128:
        return master.resize((size, size), Image.Resampling.LANCZOS)
    img = master
    while img.size[0] // 2 >= size * 2:
        half = img.size[0] // 2
        img = img.resize((half, half), Image.Resampling.LANCZOS)
    return img.resize((size, size), Image.Resampling.BOX)


def save_ico(path: Path, frames: List[Tuple[int, Image.Image]]) -> None:
    """Assemble an ICO from explicit per-size frames (PNG-compressed, Vista+).

    Pillow's own ICO writer resamples every frame from the source with a
    single bicubic pass; this lets each frame use render_icon_size() instead.
    """
    import io

    buffers: List[Tuple[int, bytes]] = []
    for size, img in frames:
        buf = io.BytesIO()
        img.save(buf, format="PNG", optimize=True)
        buffers.append((size, buf.getvalue()))

    header = struct.pack("<HHH", 0, 1, len(buffers))
    data_offset = len(header) + 16 * len(buffers)
    entries = b""
    body = b""
    for size, data in buffers:
        dim = 0 if size >= 256 else size
        entries += struct.pack(
            "<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), data_offset + len(body)
        )
        body += data
    path.write_bytes(header + entries + body)


def generate_android_legacy_icons(source_img: Image.Image) -> List[Path]:
    """Generate Android legacy mipmap launcher icons."""
    trimmed = trimTransparentPadding(source_img)
    generated: List[Path] = []
    for dir_name, size in ANDROID_LEGACY_SIZES.items():
        out_dir = ANDROID_RES_DIR / dir_name
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "ic_launcher.png"

        resized = trimmed.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(out_file, format="PNG", optimize=True)
        generated.append(out_file)
    return generated


def generate_android_adaptive_icons(source_img: Image.Image) -> List[Path]:
    """
    Generate Android adaptive icon resources:
    - values/ic_launcher_background.xml (solid white background #FFFFFF)
    - drawable/ic_launcher_foreground.png (scaled to fit within 72dp safe zone)
    - mipmap-anydpi-v26/ic_launcher.xml (references background and foreground)
    """
    generated: List[Path] = []

    # 1. Background color resource
    ANDROID_VALUES_DIR.mkdir(parents=True, exist_ok=True)
    bg_xml_file = ANDROID_VALUES_DIR / "ic_launcher_background.xml"
    bg_xml_content = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#FFFFFF</color>\n'
        '</resources>\n'
    )
    bg_xml_file.write_text(bg_xml_content, encoding="utf-8")
    generated.append(bg_xml_file)

    # 2. Foreground drawable (scaled to safe zone)
    ANDROID_DRAWABLE_DIR.mkdir(parents=True, exist_ok=True)
    fg_file = ANDROID_DRAWABLE_DIR / "ic_launcher_foreground.png"

    scaled_dim = int(round(ADAPTIVE_CANVAS_SIZE * ADAPTIVE_SAFE_RATIO))  # 288px
    offset = (ADAPTIVE_CANVAS_SIZE - scaled_dim) // 2  # 72px

    trimmed = trimTransparentPadding(source_img)
    scaled_source = trimmed.resize((scaled_dim, scaled_dim), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (ADAPTIVE_CANVAS_SIZE, ADAPTIVE_CANVAS_SIZE), (0, 0, 0, 0))
    canvas.paste(scaled_source, (offset, offset), scaled_source)
    canvas.save(fg_file, format="PNG", optimize=True)
    generated.append(fg_file)

    # 3. Adaptive icon definition XML
    ANDROID_ADAPTIVE_DIR.mkdir(parents=True, exist_ok=True)
    adaptive_xml_file = ANDROID_ADAPTIVE_DIR / "ic_launcher.xml"
    adaptive_xml_content = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    adaptive_xml_file.write_text(adaptive_xml_content, encoding="utf-8")
    generated.append(adaptive_xml_file)

    return generated


def generate_windows_icon(source_img: Image.Image) -> List[Path]:
    """
    Generate Windows multi-size .ico icon with sizes 16, 24, 32, 48, 64, 128, 256.

    Small frames (16/24/32/48/64) render via the crisp small master so the
    taskbar / alt-tab / tray glyphs stay legible; the installer copy is kept
    byte-identical for SetupIconFile + UninstallDisplayIcon.
    """
    master = build_small_master(source_img)
    generated: List[Path] = []
    WINDOWS_RESOURCES_DIR.mkdir(parents=True, exist_ok=True)
    ico_file = WINDOWS_RESOURCES_DIR / "app_icon.ico"

    frames = [(size, render_icon_size(master, size)) for size, _ in WINDOWS_ICO_SIZES]
    save_ico(ico_file, frames)
    generated.append(ico_file)

    installer_dir = REPO_ROOT / "installer"
    if installer_dir.exists():
        installer_ico = installer_dir / "app_icon.ico"
        installer_ico.write_bytes(ico_file.read_bytes())
        generated.append(installer_ico)
    return generated


def generate_macos_icons(source_img: Image.Image) -> List[Path]:
    """Generate macOS xcassets icons if the directory exists."""
    trimmed = trimTransparentPadding(source_img)
    generated: List[Path] = []
    if not MACOS_ICONSET_DIR.exists():
        return generated

    for filename, size in MACOS_SIZES.items():
        out_file = MACOS_ICONSET_DIR / filename
        resized = trimmed.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(out_file, format="PNG", optimize=True)
        generated.append(out_file)

    return generated


def build_notification_mask(source_img: Image.Image) -> Image.Image:
    """Turn the purpose-drawn black-on-white mark into an alpha-only mask.

    A notification small icon must be alpha-only: the system replaces every
    pixel with its own tint, so the glyph's identity lives entirely in the
    ALPHA channel. On this source the ink is what should be visible, so
    alpha = ink (dark pixels), and every negative space stays transparent.

    No hole filling, no morphology: the mark's negative space is deliberate,
    and measured on this source the plain threshold already yields exactly one
    connected ink component with zero specks - opening/closing would only eat
    the thinner strokes. Pure PIL on purpose (no numpy/scipy needed).
    """
    flat = Image.alpha_composite(
        Image.new("RGBA", source_img.size, (255, 255, 255, 255)), source_img
    ).convert("L")
    return flat.point(lambda v: 255 if v < NOTIFICATION_INK_THRESHOLD else 0)


def trim_square(mask: Image.Image, margin_ratio: float = 0.06) -> Image.Image:
    """Trim to the drawn bounding box, centre on a square canvas, add margin."""
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("notification mask is empty (no ink found in source)")
    glyph = mask.crop(bbox)
    side = max(glyph.size)
    canvas = Image.new("L", (side, side), 0)
    canvas.paste(glyph, ((side - glyph.size[0]) // 2, (side - glyph.size[1]) // 2))
    margin = max(1, int(side * margin_ratio))
    inner = canvas.resize((side - 2 * margin, side - 2 * margin), Image.Resampling.LANCZOS)
    out = Image.new("L", (side, side), 0)
    out.paste(inner, (margin, margin))
    return out.resize((NOTIFICATION_MASTER_SIZE, NOTIFICATION_MASTER_SIZE), Image.Resampling.LANCZOS)


def generate_android_notification_icons(source_img: Image.Image) -> List[Path]:
    """Write ic_hermes_agent.png for every density (24dp small icon).

    Replaces the hand-traced vector that used to live in drawable/: traced
    shapes drifted from the real artwork (and read as headphones at 24dp).
    Now keyed from the dedicated notification master rather than from the
    app-icon artwork: at 24x24 real pixels a downscaled illustration is just
    an unreadable blob, so the small icon has its own purpose-drawn source.
    """
    master = trim_square(build_notification_mask(source_img))
    generated: List[Path] = []
    for dir_name, size in NOTIFICATION_ICON_SIZES.items():
        target_dir = ANDROID_RES_DIR / dir_name
        target_dir.mkdir(parents=True, exist_ok=True)
        alpha = render_icon_size(master, size)
        white = Image.new("L", alpha.size, 255)
        out_file = target_dir / f"{NOTIFICATION_ICON_NAME}.png"
        Image.merge("RGBA", (white, white, white, alpha)).save(
            out_file, format="PNG", optimize=True
        )
        generated.append(out_file)
    return generated


def build_notification_large_icon(source_img: Image.Image, ink_rgb: int) -> Image.Image:
    """Inverted artwork on a TRANSPARENT background, for setLargeIcon().

    The brand artwork is near-binary black ink on white. Compositing onto
    white and taking (255 - luminance) as the alpha channel yields "ink
    visible, paper transparent" with the artwork's detail intact - the
    large-icon slot wants a real picture, unlike the 24dp small icon where
    detail has to be traded for a readable silhouette.

    ink_rgb: 0 -> black ink (light surfaces), 255 -> white ink (dark surfaces).
    """
    flat = Image.alpha_composite(
        Image.new("RGBA", source_img.size, (255, 255, 255, 255)), source_img
    ).convert("L")
    alpha = flat.point(lambda v: 255 - v)  # ink -> opaque, paper -> transparent
    solid = Image.new("L", alpha.size, ink_rgb)
    return Image.merge("RGBA", (solid, solid, solid, alpha))


def generate_android_notification_large_icons(source_img: Image.Image) -> List[Path]:
    """Write ic_hermes_large.png for both night and light resource qualifiers."""
    generated: List[Path] = []
    for mode, dir_name in NOTIFICATION_LARGE_ICON_DIRS.items():
        target_dir = ANDROID_RES_DIR / dir_name
        target_dir.mkdir(parents=True, exist_ok=True)
        icon = build_notification_large_icon(source_img, 255 if mode == "dark" else 0)
        icon = icon.resize(
            (NOTIFICATION_LARGE_ICON_SIZE, NOTIFICATION_LARGE_ICON_SIZE),
            Image.Resampling.LANCZOS,
        )
        out_file = target_dir / f"{NOTIFICATION_LARGE_ICON_NAME}.png"
        icon.save(out_file, format="PNG", optimize=True)
        generated.append(out_file)
    return generated


def generate_tray_icons(source_img: Image.Image) -> List[Path]:
    """Generate dedicated tray icon assets (16x16 PNG, 32x32 PNG, multi-size ICO)
    plus the 48px opaque toast logo (Windows notification appLogoOverride)."""
    master = build_small_master(source_img)
    generated: List[Path] = []
    BRANDING_DIR.mkdir(parents=True, exist_ok=True)

    # 1. 32x32 PNG
    tray_32 = BRANDING_DIR / "tray_icon_32.png"
    render_icon_size(master, 32).save(tray_32, format="PNG", optimize=True)
    generated.append(tray_32)

    # 2. 16x16 PNG
    tray_16 = BRANDING_DIR / "tray_icon_16.png"
    render_icon_size(master, 16).save(tray_16, format="PNG", optimize=True)
    generated.append(tray_16)

    # 3. Multi-size ICO (16x16, 32x32)
    tray_ico = BRANDING_DIR / "tray_icon.ico"
    save_ico(
        tray_ico,
        [(size, render_icon_size(master, size)) for size, _ in TRAY_ICO_SIZES],
    )
    generated.append(tray_ico)

    # 4. 48px toast logo (Windows notification appLogoOverride; opaque,
    #    Windows crops the app logo into a circle so padding stays inside).
    toast_logo = BRANDING_DIR / "notification_logo.png"
    render_icon_size(master, 48).save(toast_logo, format="PNG", optimize=True)
    generated.append(toast_logo)

    return generated


def verify_generated_artifacts() -> bool:
    """Verify all expected icon artifacts exist, are non-empty, and match dimensions."""
    print("\n--- Verifying Generated Artifacts ---")
    all_ok = True

    # 1. Verify Android legacy icons
    for dir_name, expected_size in ANDROID_LEGACY_SIZES.items():
        path = ANDROID_RES_DIR / dir_name / "ic_launcher.png"
        if not path.exists():
            print(f"[FAIL] Missing Android icon: {path.relative_to(REPO_ROOT)}")
            all_ok = False
            continue
        try:
            with Image.open(path) as img:
                if img.size != (expected_size, expected_size):
                    print(f"[FAIL] {path.name} in {dir_name}: expected {expected_size}x{expected_size}, got {img.size}")
                    all_ok = False
                else:
                    file_size = path.stat().st_size
                    print(f"[PASS] Android legacy: {dir_name}/ic_launcher.png ({expected_size}x{expected_size}, {file_size} bytes)")
        except Exception as e:
            print(f"[FAIL] Error reading {path}: {e}")
            all_ok = False

    # 2. Verify Android adaptive icons
    bg_xml = ANDROID_VALUES_DIR / "ic_launcher_background.xml"
    if bg_xml.exists() and bg_xml.stat().st_size > 0:
        ET.parse(bg_xml)
        print(f"[PASS] Android adaptive background XML: {bg_xml.relative_to(REPO_ROOT)} ({bg_xml.stat().st_size} bytes)")
    else:
        print(f"[FAIL] Missing or empty {bg_xml}")
        all_ok = False

    adaptive_xml = ANDROID_ADAPTIVE_DIR / "ic_launcher.xml"
    if adaptive_xml.exists() and adaptive_xml.stat().st_size > 0:
        ET.parse(adaptive_xml)
        print(f"[PASS] Android adaptive launcher XML: {adaptive_xml.relative_to(REPO_ROOT)} ({adaptive_xml.stat().st_size} bytes)")
    else:
        print(f"[FAIL] Missing or empty {adaptive_xml}")
        all_ok = False

    fg_png = ANDROID_DRAWABLE_DIR / "ic_launcher_foreground.png"
    if fg_png.exists():
        with Image.open(fg_png) as img:
            if img.size == (ADAPTIVE_CANVAS_SIZE, ADAPTIVE_CANVAS_SIZE):
                print(f"[PASS] Android adaptive foreground: {fg_png.relative_to(REPO_ROOT)} ({img.size[0]}x{img.size[1]}, {fg_png.stat().st_size} bytes)")
            else:
                print(f"[FAIL] Adaptive foreground size mismatch: expected {ADAPTIVE_CANVAS_SIZE}x{ADAPTIVE_CANVAS_SIZE}, got {img.size}")
                all_ok = False
    else:
        print(f"[FAIL] Missing {fg_png}")
        all_ok = False

    # 3. Verify Windows ICO
    win_ico = WINDOWS_RESOURCES_DIR / "app_icon.ico"
    if win_ico.exists() and win_ico.stat().st_size > 0:
        with open(win_ico, "rb") as f:
            data = f.read()
        reserved, ico_type, count = struct.unpack("<HHH", data[:6])
        if ico_type == 1 and count >= len(WINDOWS_ICO_SIZES):
            frame_sizes = []
            for i in range(count):
                entry = data[6 + i * 16 : 6 + (i + 1) * 16]
                w, h = entry[0], entry[1]
                w = 256 if w == 0 else w
                h = 256 if h == 0 else h
                frame_sizes.append((w, h))
            print(f"[PASS] Windows ICO: {win_ico.relative_to(REPO_ROOT)} ({count} frames: {frame_sizes}, {len(data)} bytes)")
        else:
            print(f"[FAIL] Invalid ICO header or frame count in {win_ico}")
            all_ok = False
    else:
        print(f"[FAIL] Missing or empty {win_ico}")
        all_ok = False

    # 4. Verify macOS icons
    if MACOS_ICONSET_DIR.exists():
        for filename, expected_size in MACOS_SIZES.items():
            path = MACOS_ICONSET_DIR / filename
            if not path.exists():
                print(f"[FAIL] Missing macOS icon: {filename}")
                all_ok = False
                continue
            with Image.open(path) as img:
                if img.size != (expected_size, expected_size):
                    print(f"[FAIL] macOS {filename}: expected {expected_size}x{expected_size}, got {img.size}")
                    all_ok = False
                else:
                    print(f"[PASS] macOS: {filename} ({expected_size}x{expected_size}, {path.stat().st_size} bytes)")

    # 5. Verify Tray icons
    tray_32 = BRANDING_DIR / "tray_icon_32.png"
    if tray_32.exists() and tray_32.stat().st_size > 0:
        with Image.open(tray_32) as img:
            if img.size == (32, 32):
                print(f"[PASS] Tray icon 32: {tray_32.relative_to(REPO_ROOT)} ({tray_32.stat().st_size} bytes)")
            else:
                print(f"[FAIL] Tray icon 32 size mismatch: expected 32x32, got {img.size}")
                all_ok = False
    else:
        print(f"[FAIL] Missing or empty {tray_32}")
        all_ok = False

    tray_16 = BRANDING_DIR / "tray_icon_16.png"
    if tray_16.exists() and tray_16.stat().st_size > 0:
        with Image.open(tray_16) as img:
            if img.size == (16, 16):
                print(f"[PASS] Tray icon 16: {tray_16.relative_to(REPO_ROOT)} ({tray_16.stat().st_size} bytes)")
            else:
                print(f"[FAIL] Tray icon 16 size mismatch: expected 16x16, got {img.size}")
                all_ok = False
    else:
        print(f"[FAIL] Missing or empty {tray_16}")
        all_ok = False

    tray_ico = BRANDING_DIR / "tray_icon.ico"
    if tray_ico.exists() and tray_ico.stat().st_size > 0:
        with open(tray_ico, "rb") as f:
            data = f.read()
        reserved, ico_type, count = struct.unpack("<HHH", data[:6])
        if ico_type == 1 and count >= len(TRAY_ICO_SIZES):
            print(f"[PASS] Tray ICO: {tray_ico.relative_to(REPO_ROOT)} ({count} frames, {len(data)} bytes)")
        else:
            print(f"[FAIL] Invalid Tray ICO header or frame count in {tray_ico}")
            all_ok = False
    else:
        print(f"[FAIL] Missing or empty {tray_ico}")
        all_ok = False

    # 6. Verify toast notification logo (48px, opaque)
    toast_logo = BRANDING_DIR / "notification_logo.png"
    if toast_logo.exists() and toast_logo.stat().st_size > 0:
        with Image.open(toast_logo) as img:
            if img.size != (48, 48):
                print(f"[FAIL] toast logo size: expected 48x48, got {img.size}")
                all_ok = False
            elif img.convert("RGBA").getpixel((24, 24))[3] != 255:
                print(f"[FAIL] toast logo center pixel not opaque")
                all_ok = False
            else:
                print(f"[PASS] toast notification logo: {toast_logo.relative_to(REPO_ROOT)} (48x48, {toast_logo.stat().st_size} bytes)")
    else:
        print(f"[FAIL] Missing or empty {toast_logo}")
        all_ok = False

    # 7. Android notification small icon (alpha-only silhouette, one per density)
    for dir_name, expected_size in NOTIFICATION_ICON_SIZES.items():
        path = ANDROID_RES_DIR / dir_name / f"{NOTIFICATION_ICON_NAME}.png"
        if not path.exists():
            print(f"[FAIL] Missing notification icon: {path.relative_to(REPO_ROOT)}")
            all_ok = False
            continue
        with Image.open(path) as img:
            rgba = img.convert("RGBA")
            if rgba.size != (expected_size, expected_size):
                print(f"[FAIL] {dir_name}/{NOTIFICATION_ICON_NAME}.png: expected "
                      f"{expected_size}x{expected_size}, got {rgba.size}")
                all_ok = False
                continue
            alpha = rgba.split()[3]
            data = list(alpha.getdata())
            visible = sum(1 for v in data if v > 200)
            coverage = visible / (expected_size * expected_size)
            alpha_only = all(
                rgba.getpixel((x, y))[:3] == (255, 255, 255)
                for x in range(0, expected_size, 5)
                for y in range(0, expected_size, 5)
            )
            corners_clear = all(
                alpha.getpixel(pos) == 0
                for pos in ((0, 0), (expected_size - 1, 0),
                            (0, expected_size - 1), (expected_size - 1, expected_size - 1))
            )
            if not 0.05 <= coverage <= 0.65:
                print(f"[FAIL] {dir_name}/{NOTIFICATION_ICON_NAME}.png: ink coverage "
                      f"{coverage:.1%} out of sane range 5%-65%")
                all_ok = False
            elif not alpha_only:
                print(f"[FAIL] {dir_name}/{NOTIFICATION_ICON_NAME}.png: not alpha-only "
                      f"(visible pixels must be pure white so the system can tint)")
                all_ok = False
            elif not corners_clear:
                print(f"[FAIL] {dir_name}/{NOTIFICATION_ICON_NAME}.png: corners must stay "
                      f"transparent (safe-area margin)")
                all_ok = False
            else:
                print(f"[PASS] Android notification: {dir_name}/{NOTIFICATION_ICON_NAME}.png "
                      f"({expected_size}x{expected_size}, ink {coverage:.1%}, "
                      f"{path.stat().st_size} bytes)")

    # 8. Android notification large icon (inverted artwork, transparent bg, night+light)
    for mode, dir_name in NOTIFICATION_LARGE_ICON_DIRS.items():
        path = ANDROID_RES_DIR / dir_name / f"{NOTIFICATION_LARGE_ICON_NAME}.png"
        if not path.exists():
            print(f"[FAIL] Missing notification large icon: {path.relative_to(REPO_ROOT)}")
            all_ok = False
            continue
        with Image.open(path) as img:
            rgba = img.convert("RGBA")
            expected = NOTIFICATION_LARGE_ICON_SIZE
            if rgba.size != (expected, expected):
                print(f"[FAIL] {dir_name}/{NOTIFICATION_LARGE_ICON_NAME}.png: expected "
                      f"{expected}x{expected}, got {rgba.size}")
                all_ok = False
                continue
            alpha = rgba.split()[3]
            data = list(alpha.getdata())
            inked = sum(1 for v in data if v > 32) / len(data)
            corners_clear = all(
                alpha.getpixel(pos) == 0
                for pos in ((0, 0), (expected - 1, 0),
                            (0, expected - 1), (expected - 1, expected - 1))
            )
            want_rgb = 255 if mode == "dark" else 0
            rgb_ok = all(
                rgba.getpixel((x, y))[:3] == (want_rgb, want_rgb, want_rgb)
                for x in range(0, expected, 11)
                for y in range(0, expected, 11)
                if rgba.getpixel((x, y))[3] > 32
            )
            if not 0.05 <= inked <= 0.60:
                print(f"[FAIL] {dir_name}/{NOTIFICATION_LARGE_ICON_NAME}.png: ink coverage "
                      f"{inked:.1%} out of sane range 5%-60%")
                all_ok = False
            elif not corners_clear:
                print(f"[FAIL] {dir_name}/{NOTIFICATION_LARGE_ICON_NAME}.png: background must "
                      f"stay transparent (corners are opaque)")
                all_ok = False
            elif not rgb_ok:
                print(f"[FAIL] {dir_name}/{NOTIFICATION_LARGE_ICON_NAME}.png: ink colour must be "
                      f"{'white' if mode == 'dark' else 'black'} on every visible pixel")
                all_ok = False
            else:
                print(f"[PASS] Android notification large icon ({mode}): {dir_name}/"
                      f"{NOTIFICATION_LARGE_ICON_NAME}.png ({expected}x{expected}, ink "
                      f"{inked:.1%}, transparent bg, {path.stat().st_size} bytes)")

    return all_ok


def main() -> None:
    """Main execution entry point."""
    print("==================================================")
    print(" Hermes Icon Generation Pipeline")
    print("==================================================")
    print(f"Pillow Version : {getattr(Image, '__version__', 'unknown')}")
    print(f"Repository Root: {REPO_ROOT}")
    print(f"Source Asset   : {SOURCE_ICON_PATH.relative_to(REPO_ROOT)}")

    source_img = load_source_image(SOURCE_ICON_PATH)
    print(f"Source Image Loaded: {source_img.size} mode={source_img.mode}")

    print("\n1. Generating Android Legacy Icons...")
    android_legacy = generate_android_legacy_icons(source_img)
    for p in android_legacy:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n2. Generating Android Adaptive Icons...")
    android_adaptive = generate_android_adaptive_icons(source_img)
    for p in android_adaptive:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n3. Generating Windows ICO...")
    windows_ico = generate_windows_icon(source_img)
    for p in windows_ico:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n4. Generating macOS AppIcon Set...")
    macos_icons = generate_macos_icons(source_img)
    for p in macos_icons:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n5. Generating Tray Icons...")
    tray_icons = generate_tray_icons(source_img)

    print("\n6. Generating Android notification small icon (Live Update / status bar)...")
    notify_src = load_source_image(NOTIFICATION_SOURCE_PATH)
    print(f"Notification Master: {NOTIFICATION_SOURCE_PATH.relative_to(REPO_ROOT)}"
          f" ({notify_src.size[0]}x{notify_src.size[1]}, mode={notify_src.mode})")
    notification_icons = generate_android_notification_icons(notify_src)
    for p in notification_icons:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n7. Generating Android notification large icon (setLargeIcon, night/light)...")
    for p in generate_android_notification_large_icons(source_img):
        print(f"   -> {p.relative_to(REPO_ROOT)}")
    for p in tray_icons:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    ok = verify_generated_artifacts()
    if not ok:
        print("\n[ERROR] Verification failed!", file=sys.stderr)
        sys.exit(1)

    print("\n[SUCCESS] All platform icon assets generated and verified successfully!")


if __name__ == "__main__":
    main()
