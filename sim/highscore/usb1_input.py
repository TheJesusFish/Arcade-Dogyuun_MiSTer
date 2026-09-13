#!/usr/bin/env python3
"""Emit a guarded key sequence on the authorized Dogyuun USB-1 MiSTer."""

import argparse
import os
import struct
import time


EV_SYN = 0
EV_KEY = 1
SYN_REPORT = 0

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502

KEYS = {
    "esc": 1,
    "start": 2,
    "coin": 6,
    "enter": 28,
    "fire": 29,
    "f1": 59,
    "leftalt": 56,
    "space": 57,
    "f12": 88,
    "up": 103,
    "left": 105,
    "right": 106,
    "end": 107,
    "down": 108,
}
CHORDS = {
    "savestate": ("leftalt", "f1"),
    "loadstate": (None, "f1"),
}

CONFIRMATION = "USB-1@10.4.20.123"
OUTER_GUARD = "DOGYUUN_USB1_OUTER_GUARD"
SUPPORTED_CORES = {"dogyuun", "dogyuuna", "dogyuunb", "dogyuunt"}


def emit(fd, event_type, code, value):
    os.write(fd, struct.pack("@llHHI", 0, 0, event_type, code, value))


def sync(fd):
    emit(fd, EV_SYN, SYN_REPORT, 0)


def set_key(fd, code, pressed):
    emit(fd, EV_KEY, code, 1 if pressed else 0)
    sync(fd)


def pulse(fd, code, hold):
    set_key(fd, code, True)
    time.sleep(hold)
    set_key(fd, code, False)


def chord(fd, modifier, key, hold):
    if modifier is not None:
        set_key(fd, KEYS[modifier], True)
        time.sleep(0.03)
    pulse(fd, KEYS[key], hold)
    if modifier is not None:
        time.sleep(0.03)
        set_key(fd, KEYS[modifier], False)


def read_identity(path):
    with open(path, "r", encoding="ascii") as stream:
        return stream.read().strip()


def parse_sequence(text):
    actions = []
    for raw in text.split(","):
        token = raw.strip().lower()
        if not token:
            raise ValueError("empty sequence token")
        if token.startswith("wait="):
            delay = float(token[5:])
            if delay < 0.0 or delay > 30.0:
                raise ValueError("wait must be between 0 and 30 seconds")
            actions.append(("wait", delay))
        elif token in KEYS:
            actions.append(("key", token))
        elif token in CHORDS:
            actions.append(("chord", token))
        else:
            raise ValueError("unsupported sequence token: {}".format(token))
    return actions


def create_keyboard(fd):
    import fcntl

    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for code in sorted(set(KEYS.values())):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)

    descriptor = struct.pack(
        "@80sHHHHI",
        b"Codex Dogyuun USB-1 high-score validation",
        0x03,
        0x1209,
        0x0220,
        0x0001,
        0,
    )
    descriptor += struct.pack("@256i", *([0] * 256))
    os.write(fd, descriptor)
    fcntl.ioctl(fd, UI_DEV_CREATE)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--usb1-confirmation", required=True)
    parser.add_argument("--sequence", required=True)
    parser.add_argument("--device-delay", type=float, default=0.75)
    parser.add_argument("--step-delay", type=float, default=0.18)
    parser.add_argument("--hold", type=float, default=0.08)
    args = parser.parse_args()

    import fcntl

    if args.usb1_confirmation != CONFIRMATION:
        parser.error("USB-1 confirmation mismatch")
    if os.environ.get(OUTER_GUARD) != CONFIRMATION:
        parser.error("outer USB-1 guard mismatch")
    core_name = read_identity("/tmp/CORENAME")
    if core_name not in SUPPORTED_CORES:
        parser.error("live core is not a supported Dogyuun set")
    if read_identity("/tmp/RBFNAME") != "DOGYUUN":
        parser.error("live RBF identity is not DOGYUUN")

    try:
        actions = parse_sequence(args.sequence)
    except ValueError as error:
        parser.error(str(error))

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    try:
        create_keyboard(fd)
        time.sleep(args.device_delay)
        for action, value in actions:
            if action == "wait":
                time.sleep(value)
            elif action == "key":
                pulse(fd, KEYS[value], args.hold)
                time.sleep(args.step_delay)
            else:
                chord(fd, *CHORDS[value], args.hold)
                time.sleep(args.step_delay)
    finally:
        try:
            fcntl.ioctl(fd, UI_DEV_DESTROY)
        finally:
            os.close(fd)

    print("PASS: emitted {} guarded actions".format(len(actions)))


if __name__ == "__main__":
    main()
