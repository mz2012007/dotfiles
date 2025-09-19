#!/usr/bin/env python3

import random
import subprocess
from pathlib import Path
import sys

# مجلد الخلفيات
WALL_DIR = Path("/home/mz/backgrounds")

def main():
    # جمع كل الخلفيات
    wallpapers = [p for p in WALL_DIR.glob("*") if p.is_file()]
    if not wallpapers:
        print(f"❌ مفيش خلفيات في المجلد: {WALL_DIR}", file=sys.stderr)
        sys.exit(1)

    # اختيار خلفية عشوائية
    chosen = random.choice(wallpapers)

    # تطبيق ألوان pywal
    subprocess.run(["wal", "-i", str(chosen), "-n"], check=True)

    # ضبط الخلفية باستخدام feh
    subprocess.run(["feh", "--bg-fill", str(chosen)], check=True)



if __name__ == "__main__":
    main()
    
