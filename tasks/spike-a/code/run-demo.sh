#!/bin/bash
# Build + launch the bar for an interactive human check of the two criteria the
# automated run can't verify: all-Spaces (Ctrl-←/→) and over-fullscreen (put an app
# fullscreen). The bar animates all symbol effects on a 1.25 s loop. Ctrl-C to quit.
set -euo pipefail
cd "$(dirname "$0")"
./bundle.sh
echo "Launching bar (approach A2, animating). Switch Spaces and go fullscreen to verify."
exec SpikeA.app/Contents/MacOS/SpikeA --approach "${1:-a2}" --anim
