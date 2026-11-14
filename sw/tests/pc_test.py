"""Exercise piped commands and a real POSIX pseudo-terminal."""
import os
import pty
import select
import subprocess
import sys
import termios
import time

binary = sys.argv[1]
env = dict(os.environ, GAME2048_SEED="123")


def replay(commands):
    return subprocess.run([binary], input=commands, env=env,
                          stdout=subprocess.PIPE, check=True, timeout=5).stdout


commands = b"wasd\x1b[A\x1b[B\x1b[C\x1b[Drq"
first = replay(commands)
assert first == replay(commands), "same seed and commands must replay exactly"
assert first.count(b"Score:") == 10, "initial + eight moves + restart"
assert replay(b"q") == replay(b"xyzq"), "unknown input must preserve board"
assert replay(b"") == replay(b"q"), "EOF must quit cleanly"
assert b"Moves: 0" in first.rsplit(b"Score:", 1)[1], "restart resets moves"
print("PASS PC command replay, arrows, restart, unknown input and EOF")

master, slave = pty.openpty()
before = termios.tcgetattr(slave)
process = subprocess.Popen([binary], stdin=slave, stdout=slave, stderr=slave, env=env)
output = bytearray()
try:
    deadline = time.monotonic() + 5
    # Wait for the complete initial frame, then send an input to initialize raw mode.
    while output.count(b"+------+------+------+------+") < 5:
        assert time.monotonic() < deadline, "initial frame timeout"
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            output.extend(os.read(master, 65536))
    os.write(master, b"w")
    while termios.tcgetattr(slave)[3] & termios.ICANON:
        assert time.monotonic() < deadline, "raw input initialization timeout"
        time.sleep(0.01)
    os.write(master, b"\x1b[Dr\x03")
    while process.poll() is None:
        assert time.monotonic() < deadline, "terminal interaction timeout"
        readable, _, _ = select.select([master], [], [], 0.1)
        if readable:
            output.extend(os.read(master, 65536))
    assert process.returncode == 0
    assert termios.tcgetattr(slave) == before, "terminal settings must be restored"
    print("PASS PTY immediate input, arrow, restart, Ctrl-C and terminal restore")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    os.close(slave)
