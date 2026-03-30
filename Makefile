.PHONY: run setup identify init

run:
	.venv/bin/python3 gamepad_claude.py

init:
	.venv/bin/python3 gamepad_claude.py --init

identify:
	.venv/bin/python3 gamepad_claude.py --identify

setup:
	python3 -m venv .venv
	.venv/bin/pip install pygame-ce pynput faster-whisper sounddevice numpy
