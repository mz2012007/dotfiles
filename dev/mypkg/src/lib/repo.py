def build_packages_url(config):
    base = config["repo"]["base_url"]
    suite = config["repo"]["suite"]
    arch = config["repo"]["arch"]

    return f"{base}/dists/{suite}/main/binary-{arch}/Packages.gz"





def BASE_URL(config):
    base = config["now_repo"]["base_url"]
    suite = config["now_repo"]["suite"]
    arch = config["now_repo"]["arch"]
    return f"{BASE_URL}/dists/{SUITE}/main/binary-{ARCH}/Packages.gz"
