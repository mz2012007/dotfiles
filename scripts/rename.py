import os

# folder containing mp3 files
FOLDER = "."

# constant increment
OFFSET = 114

# get all mp3 files sorted
files = sorted([
    f for f in os.listdir(FOLDER)
    if f.endswith(".mp3")
])

# rename loop
for i, filename in enumerate(files, start=1):
    old_path = os.path.join(FOLDER, filename)

    new_number = i + OFFSET
    new_name = f"{new_number}.mp3"
    new_path = os.path.join(FOLDER, new_name)

    # rename file
    os.rename(old_path, new_path)

    print(f"{filename} → {new_name}")
