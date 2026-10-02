#!/usr/bin/env bash
# setup_python.sh - project-local venv for Linux/WSL (pyserial for the dashboard).
set -e
cd "$(dirname "$0")/.."
python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
.venv/bin/python -c "import serial; print('pyserial', serial.__version__)"
.venv/bin/python -c "import tkinter" 2>/dev/null && echo "tkinter OK" || echo "tkinter missing: sudo apt install python3-tk (needed only for the GUI)"
.venv/bin/python dashboard/fly_dashboard.py --selftest 100
