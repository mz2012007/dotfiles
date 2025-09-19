#!/bin/bash
percent=$(brightnessctl get)
max=$(brightnessctl max)
echo "%{F#F0C674}Light%{F-} $(( percent * 100 / max ))%"
