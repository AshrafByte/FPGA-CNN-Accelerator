"""The command-line front end: flags, interactive prompts and the printed report.

    app.py       argument parsing and main()
    prompts.py   the interactive flow when no input flags are given
    report.py    a HarnessRun turned into terminal output, CSV and PNG
    terminal.py  text formatting: rules, kernel cards, stats, ASCII layout

Everything it shows is computed by conv_lab.harness; nothing here runs a frame.
"""

from .app import main

__all__ = ["main"]
