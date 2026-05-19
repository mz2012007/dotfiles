import os
import tarfile
import subprocess

def extract_deb(deb_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # step 1: extract ar archive
    subprocess.run([
        "ar", "x", deb_path
    ], cwd=out_dir, check=True)

    # step 2: extract data.tar.*
    for f in os.listdir(out_dir):
        if f.startswith("data.tar"):
            data_path = os.path.join(out_dir, f)

            with tarfile.open(data_path) as tar:
                tar.extractall(out_dir)

