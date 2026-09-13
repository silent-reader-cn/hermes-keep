#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Icon generation pipeline for Hermes client.
Generates all platform icons from a single source: assets/branding/hermes-agent-icon-1024.png
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
    for p in tray_icons:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    ok = verify_generated_artifacts()
    if not ok:
        print("\n[ERROR] Verification failed!", file=sys.stderr)
        sys.exit(1)

    print("\n[SUCCESS] All platform icon assets generated and verified successfully!")


if __name__ == "__main__":
    main()
