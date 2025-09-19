#!/bin/bash
pkill conky
conky -c ~/.config/conky/conky1.conf &
conky -c ~/.config/conky/conky2.conf &
