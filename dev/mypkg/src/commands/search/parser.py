def parse_packages_file(path):
    import gzip

    with gzip.open(path, "rt", encoding="utf-8", errors="ignore") as f:

        pkg = {}

        for line in f:

            line = line.rstrip()

            if not line:
                if pkg:
                    yield pkg
                    pkg = {}
                continue

            if ":" in line:
                k, v = line.split(":", 1)
                pkg[k.strip()] = v.strip()

        if pkg:
            yield pkg
