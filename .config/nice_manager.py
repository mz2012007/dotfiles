#!/usr/bin/env python3
import os

CONFIG_PATH = os.path.expanduser("~/.nice_app_config")

NICE_NAME_TO_VALUE = {
    "realtime": -20,
    "high": -10,
    "normal": 0,
    "low": 10,
    "verylow": 19
}

NICE_VALUE_TO_NAME = {v: k for k, v in NICE_NAME_TO_VALUE.items()}


def load_config():
    apps = {}
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, "r") as f:
            for line in f:
                if "=" in line:
                    name, value = line.strip().split("=", 1)
                    try:
                        apps[name] = int(value)
                    except ValueError:
                        continue
    return apps


def save_config(apps):
    with open(CONFIG_PATH, "w") as f:
        for app, nice in apps.items():
            f.write(f"{app}={nice}\n")


def show_applications(apps):
    print("== Saved Applications ==")
    apps_list = list(apps.keys())
    for i, app in enumerate(apps_list, 1):
        nice = apps[app]
        name = NICE_VALUE_TO_NAME.get(nice, "unknown")
        print(f"{i}) {app} (nice={name})")
    print(f"{len(apps_list)+1}) [Enter a new application]")
    return apps_list


def choose_nice_value():
    names = list(NICE_NAME_TO_VALUE.keys())
    print("Choose a nice value:")
    for i, name in enumerate(names, 1):
        print(f"{i}) {name}")
    while True:
        choice = input(f"Enter number [1-{len(names)}]: ")
        if choice.isdigit() and 1 <= int(choice) <= len(names):
            return NICE_NAME_TO_VALUE[names[int(choice)-1]]
        else:
            print("Invalid input, try again.")


def main():
    apps = load_config()
    apps_list = show_applications(apps)

    choice = input("Choose a number or enter new app name: ").strip()
    if choice.isdigit():
        index = int(choice)
        if 1 <= index <= len(apps_list):
            app = apps_list[index - 1]
        elif index == len(apps_list) + 1:
            app = input("Enter new application name: ").strip()
        else:
            print("Invalid choice.")
            return
    else:
        app = choice

    if app in apps:
        current_nice = apps[app]
        current_name = NICE_VALUE_TO_NAME.get(current_nice, "unknown")
        print(f"Application '{app}' is saved with nice value = {current_name}")
        yn = input("Do you want to change the nice value? (y/N): ").strip().lower()
        if yn == 'y':
            apps[app] = choose_nice_value()
        else:
            print("Keeping current value.")
    else:
        print(f"New application '{app}'")
        apps[app] = choose_nice_value()

    save_config(apps)
    print("Configuration updated successfully.")


if __name__ == "__main__":
    main()
