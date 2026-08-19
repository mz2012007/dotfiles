#!/usr/bin/env python3
"""Entry point for the myiso installer."""
from installer.app import MyISOInstaller

if __name__ == "__main__":
    app = MyISOInstaller()
    app.run()
