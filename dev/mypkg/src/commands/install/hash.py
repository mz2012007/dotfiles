import hashlib

def sha256_file(path, chunk_size=1024 * 1024):
    h = hashlib.sha256()

    with open(path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            h.update(chunk)

    return h.hexdigest()



def verify_hash(file_path, expected_hash):
    actual = sha256_file(file_path)

    return actual == expected_hash
