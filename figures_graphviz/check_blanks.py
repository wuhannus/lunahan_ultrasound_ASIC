#!/usr/bin/env python3
"""Checker: measures blank space in Graphviz-generated figures.
Principle 13: blank space (no drawings/text/data) < 15% after outer crop.
Method: count non-white pixels inside the content bounding box.
A pixel is "content" if any R,G,B < 240 (i.e., not near-white).
"""
import subprocess, os, sys, numpy as np
from PIL import Image

THRESHOLD = 15.0  # max allowed blank %

def check_one(dot_path, png_path):
    """Render DOT to PNG, crop, measure blank. Returns (blank_pct, passed, w, h)."""
    # Render
    r = subprocess.run(['dot','-Kdot','-Tpng','-Gdpi=250','-o',png_path,dot_path],
                      capture_output=True, text=True)
    if r.returncode != 0:
        return None, False, 0, 0, f"DOT error: {r.stderr[:80]}"
    
    im = Image.open(png_path).convert('RGB')
    arr = np.array(im)
    
    # Crop outer whitespace (keep only the content region)
    mask = ~((arr[:,:,0] > 248) & (arr[:,:,1] > 248) & (arr[:,:,2] > 248))
    if not mask.any():
        return 100.0, False, im.width, im.height, "all white"
    
    rows = np.any(mask, axis=1); cols = np.any(mask, axis=0)
    ymin, ymax = np.where(rows)[0][[0, -1]]
    xmin, xmax = np.where(cols)[0][[0, -1]]
    # Tight crop with 0 padding
    ymin = max(0, ymin); ymax = min(im.height-1, ymax)
    xmin = max(0, xmin); xmax = min(im.width-1, xmax)
    
    cropped = arr[ymin:ymax+1, xmin:xmax+1]
    
    # Count "blank" pixels inside crop: near-white or near the bg color
    # Content pixels = non-near-white
    is_blank = (cropped[:,:,0] > 248) & (cropped[:,:,1] > 248) & (cropped[:,:,2] > 248)
    blank_count = np.sum(is_blank)
    total = cropped.shape[0] * cropped.shape[1]
    blank_pct = blank_count / total * 100 if total > 0 else 100
    
    passed = blank_pct < THRESHOLD
    
    # Save cropped version
    im2 = im.crop((xmin, ymin, xmax+1, ymax+1))
    im2.save(png_path)
    
    return blank_pct, passed, im2.width, im2.height, ""

def check_all():
    """Check all fig*_final.dot files."""
    results = []
    for i in range(1, 8):
        dot = f'fig{i}_final.dot'
        png = f'fig{i}_final.png'
        if not os.path.exists(dot):
            continue
        bp, ok, w, h, err = check_one(dot, png)
        if bp is None:
            print(f'  FAIL fig{i}: {err}')
            results.append((i, None, False))
        else:
            status = 'PASS' if ok else f'FAIL ({bp:.1f}%)'
            print(f'  {status:20s} fig{i}: {w}x{h}  blank={bp:.1f}%')
            results.append((i, bp, ok))
    
    all_pass = all(r[2] for r in results)
    print(f'\n  {"ALL PASS" if all_pass else "SOME FAIL"}  (threshold: <{THRESHOLD}%)')
    return all_pass

if __name__ == '__main__':
    check_all()
