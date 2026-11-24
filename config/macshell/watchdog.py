#!/usr/bin/env python3
"""Watch the MacShell process started by the parent launcher."""

import os
import select
import signal
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def watch(pid: int) -> None:
    launcher_pid = os.getppid()
    try:
        pidfd = os.pidfd_open(pid)
    except ProcessLookupError:
        return

    try:
        try:
            status = Path(f"/proc/{pid}/status").read_text()
        except FileNotFoundError:
            return
        if f"PPid:\t{launcher_pid}\n" not in status:
            return

        exit_event = select.poll()
        exit_event.register(pidfd, select.POLLIN)
        if exit_event.poll(25_000):
            return

        ready = False
        failures = 0
        while os.getppid() == launcher_pid and not exit_event.poll(0):
            try:
                result = subprocess.run(
                    ["qs", "ipc", "--pid", str(pid), "show"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=3,
                )
                responsive = result.returncode == 0
            except subprocess.TimeoutExpired:
                responsive = False

            # A broken startup should not cause an endless restart loop.
            if responsive:
                ready = True
                failures = 0
            elif ready:
                failures += 1

            if failures == 3:
                if os.getppid() != launcher_pid or exit_event.poll(0):
                    return
                print(
                    f"{datetime.now():%F %T} macshell-watchdog: PID {pid} missed "
                    "three IPC checks; stopping it for restart",
                    flush=True,
                )
                try:
                    signal.pidfd_send_signal(pidfd, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                return

            if exit_event.poll(10_000):
                return
    finally:
        os.close(pidfd)


if __name__ == "__main__":
    watch(int(sys.argv[1]))
