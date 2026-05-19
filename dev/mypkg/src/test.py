from lib.network import check_network_status, resolve_url_v2


def main():

    url = "https://example.com"

    print("\n=== NETWORK TEST ===")
    net = check_network_status()

    print("interface_up :", net["interface_up"])
    print("dns_ok       :", net["dns_ok"])
    print("internet_ok  :", net["internet_ok"])
    print("status       :", net["status"])

    if not net["status"]:
        print("\n❌ Network is NOT OK")
        return

    print("\n=== RESOLVE TEST ===")
    info = resolve_url_v2(url)

    print("url     :", info.url)
    print("name    :", info.name)
    print("size    :", info.size)
    print("status  :", info.status)
    print("valid   :", info.is_valid)
    print("error   :", info.error)

    if info.error:
        print("\n❌ Resolve failed")
    else:
        print("\n✔ System OK")


if __name__ == "__main__":
    main()
