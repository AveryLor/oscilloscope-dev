"""Entry point for the oscilloscope display. See app.py for the window."""

from __future__ import annotations

import argparse
import sys

from PySide6.QtWidgets import QApplication

from .app import MainWindow
from .link import DEFAULT_BAUD, list_ports


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="serial port to connect to on launch, e.g. /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD, help=f"default {DEFAULT_BAUD}")
    parser.add_argument("--list", action="store_true", help="list serial ports and exit")
    args = parser.parse_args()

    if args.list:
        for port in list_ports():
            print(port)
        return

    app = QApplication(sys.argv)
    window = MainWindow(port=args.port, baud=args.baud)
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
