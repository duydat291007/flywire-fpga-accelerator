#!/usr/bin/env python3
"""Live dashboard for the FPGA fly accelerator (Tkinter; pyserial for the board).

Sources (exactly one):
  --port COM5            live telemetry from the Basys 3 USB-UART (115200 8N1)
  --offline              reference-model simulation, clearly labeled; NOT FPGA output
  --replay FILE          replay a capture (hex bytes, one per line, or raw binary)

Other options:
  --list                 list serial ports and exit
  --log FILE             save every received byte (binary) for later replay
  --selftest N           headless: run N offline packets through the parser, print stats
  --food / --threat      offline mode: start with food / threat present

Examples (Windows PowerShell, project venv active):
  python dashboard\\fly_dashboard.py --list
  python dashboard\\fly_dashboard.py --port COM5
  python dashboard\\fly_dashboard.py --offline
"""

import argparse
import pathlib
import queue
import sys
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "model"))

from fly_model import constants as C                              # noqa: E402
from fly_model import network as net                              # noqa: E402
from fly_model.packet import (FLAG_DROPPED, FLAG_FOOD, FLAG_RUNNING,  # noqa: E402
                              FLAG_SYSTOLIC, FLAG_THREAT, PacketParser, encode)
from fly_model.world import FlySim                                # noqa: E402

CLK_HZ = 100_000_000


# ---------------------------------------------------------------------------
# Byte sources. Each runs in a thread and pushes bytes into a queue.
# ---------------------------------------------------------------------------
class SerialSource:
    label = "LIVE FPGA"

    def __init__(self, port, baud=115200):
        try:
            import serial                                          # pyserial
        except ImportError:
            sys.exit("pyserial is not installed. Run scripts/setup_python.ps1 (or pip install pyserial).")
        self.serial = serial
        self.port, self.baud = port, baud
        self.ser = self.open()
        self.detail = f"{port} @ {baud} 8N1"
        self.status = "connected"
        self.reconnects = 0

    def open(self):
        # exclusive=True (Linux/macOS): a second dashboard on the same port fails
        # immediately with a clear error instead of both readers losing data.
        kw = {"exclusive": True} if sys.platform != "win32" else {}
        try:
            return self.serial.Serial(self.port, self.baud, timeout=0.05, **kw)
        except self.serial.SerialException as e:
            if "lock" in str(e).lower() or "busy" in str(e).lower():
                sys.exit(f"{self.port} is already in use - is another dashboard open? "
                         f"(close it, or run: pkill -f fly_dashboard)")
            raise

    def run(self, q, stop):
        """Read forever. If the USB link drops (a usbipd detach, a board reset,
        another program grabbing the port), keep retrying instead of dying."""
        while not stop.is_set():
            try:
                if self.ser is None:
                    self.ser = self.serial.Serial(self.port, self.baud, timeout=0.05,
                                                  **({"exclusive": True} if sys.platform != "win32" else {}))
                    self.reconnects += 1
                    self.status = f"reconnected ({self.reconnects})"
                data = self.ser.read(256)
                if data:
                    q.put(data)
            except (self.serial.SerialException, OSError) as e:
                self.status = f"LINK LOST - retrying: {e}"
                try:
                    if self.ser is not None:
                        self.ser.close()
                except Exception:
                    pass
                self.ser = None
                time.sleep(1.0)
        if self.ser is not None:
            self.ser.close()


class ReplaySource:
    label = "REPLAY"

    def __init__(self, path, rate=6000):
        raw = pathlib.Path(path).read_bytes()
        try:
            self.data = bytes(int(t, 16) for t in raw.decode("ascii").split())
        except (UnicodeDecodeError, ValueError):
            self.data = raw
        self.rate = rate          # bytes per second (~ 115200 baud is 11520 B/s)
        self.detail = f"file {path}"

    def run(self, q, stop):
        chunk = max(1, self.rate // 50)
        for i in range(0, len(self.data), chunk):
            if stop.is_set():
                return
            q.put(self.data[i:i + chunk])
            time.sleep(chunk / self.rate)


class OfflineSource:
    """Reference model producing packets in the FPGA format. Never FPGA output.

    The neural update uses numpy when available (bit-identical to the
    plain-Python reference; model/flywire/behavior_check.py verifies this),
    otherwise the slow reference model.
    """
    label = "OFFLINE SIMULATION (reference model, not FPGA output)"

    def __init__(self, steps_per_s=100, packets_per_s=50):
        self.sim = FlySim()
        try:
            import numpy as np
            self.np = np
            self.Wn = np.array(self.sim.W, dtype=np.int64)
        except ImportError:
            self.np = None
            steps_per_s = min(steps_per_s, 10)
        self.sps, self.pps = steps_per_s, packets_per_s
        self.running = True
        self.single = 0
        self.lock = threading.Lock()
        self.detail = f"{steps_per_s} steps/s, {packets_per_s} packets/s" + \
            ("" if self.np else " (numpy missing: slow mode)")
        self.probe = 29          # neurons 232..239: giant fiber and escape DNs

    def step(self):
        if self.np is None:
            self.sim.step()
            return
        np, sim = self.np, self.sim
        u = np.array(sim.world.sensors(), dtype=np.int64)
        V = np.array(sim.V, dtype=np.int64)
        c = (15 * V) // 16 + self.Wn @ np.array(sim.s, dtype=np.int64) + u
        s = c >= sim.threshold
        sim.V = np.where(s, 0, np.maximum(c, 0)).tolist()
        sim.s = s.astype(int).tolist()
        sim.step_count += 1
        sim.world.update(sim.s)

    def run(self, q, stop):
        seq, act, t_step, t_pkt = 0, [0] * C.N_NEURONS, time.time(), time.time()
        while not stop.is_set():
            now = time.time()
            with self.lock:
                due = 0
                if self.running:
                    due = int((now - t_step) * self.sps)
                    if due:
                        t_step += due / self.sps
                else:
                    t_step = now
                    due, self.single = self.single, 0
                for _ in range(min(due, 20)):
                    self.step()
                    act = [min(3, a + s) for a, s in zip(act, self.sim.s)]
                if now - t_pkt >= 1 / self.pps:
                    t_pkt = now
                    w = self.sim.world
                    flags = (FLAG_RUNNING if self.running else 0) | \
                        (FLAG_FOOD if w.food_present else 0) | (FLAG_THREAT if w.threat_present else 0)
                    q.put(encode(dict(
                        seq=seq, step=self.sim.step_count, flags=flags, dropped_total=0, cycles=0,
                        fly=tuple(w.fly), food=tuple(w.food), threat=tuple(w.threat),
                        heading=w.heading, action=w.last_action,
                        eaten=w.eaten, caught=w.caught, jumps=w.jumps,
                        motor=tuple(w.last_motor), activity=act,
                        probe_base=8 * self.probe,
                        potentials=self.sim.V[8 * self.probe:8 * self.probe + 8])))
                    seq = (seq + 1) & 0xFFFF
                    act = [0] * C.N_NEURONS
            time.sleep(0.002)


def list_ports():
    try:
        from serial.tools import list_ports
    except ImportError:
        sys.exit("pyserial is not installed.")
    ports = list(list_ports.comports())
    if not ports:
        print("No serial ports found. Is the Basys 3 connected and powered?")
    for p in ports:
        print(f"{p.device:8} {p.description}  [{p.hwid}]")
    print("\nThe Basys 3 appears as two FTDI ports; telemetry is on the UART one "
          "(usually the higher COM number on Windows).")


# ---------------------------------------------------------------------------
# Headless self-test (used by the regression; needs no display)
# ---------------------------------------------------------------------------
def selftest(n):
    src = OfflineSource(steps_per_s=1000, packets_per_s=200)
    src.sim.world.food_present = True
    src.sim.world.pending_food_respawn = True
    q, stop, parser, got = queue.Queue(), threading.Event(), PacketParser(), []
    th = threading.Thread(target=src.run, args=(q, stop), daemon=True)
    th.start()
    t0 = time.time()
    while len(got) < n and time.time() - t0 < 60:
        try:
            data = q.get(timeout=0.5)
        except queue.Empty:
            continue
        # deliberately split every packet into uneven chunks
        for i in range(0, len(data), 7):
            got += parser.feed(data[i:i + 7])
    stop.set()
    ok = len(got) >= n and parser.crc_errors == 0 and parser.seq_gaps == 0
    print(f"{'PASS' if ok else 'FAIL'} dashboard selftest: {len(got)} packets, crc_err={parser.crc_errors}, "
          f"gaps={parser.seq_gaps}, last step {got[-1]['step'] if got else '-'}, "
          f"eaten {got[-1]['eaten'] if got else '-'}")
    return 0 if ok else 1


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
GROUPS = [  # (index range, short name, colour)
    (net.FOOD_L, "sugar sensor L", "#2e7d32"), (net.FOOD_R, "sugar sensor R", "#66bb6a"),
    (net.THREAT_L, "looming sensor L", "#c62828"), (net.THREAT_R, "looming sensor R", "#ef5350"),
    (net.INTER, "intermediate", "#455a64"),
    (net.GIANT_FIBER, "giant fiber (escape)", "#ff6f00"), (net.ESCAPE_OTHER, "escape DNs", "#ffa726"),
    (net.MDN, "MDN (backward)", "#8e24aa"), (net.DNP09, "DNp09 (forward)", "#1e88e5"),
    (net.STEER_L, "steer L", "#00acc1"), (net.STEER_R, "steer R", "#26c6da"),
    (net.FEED, "proboscis motor (feed)", "#c0ca33"),
]
ACTIONS = ("walk", "back up", "JUMP", "EAT", "wall: turn")
MOTOR_NAMES = ("giantfiber", "MDN", "DNp09", "steerL", "steerR", "proboscis")


def group_of(n):
    for rng_, name, color in GROUPS:
        if n in rng_:
            return name, color
    return "?", "#757575"


def run_gui(source, log_path):
    import tkinter as tk

    q, stop, parser = queue.Queue(), threading.Event(), PacketParser()
    logf = open(log_path, "ab") if log_path else None
    threading.Thread(target=source.run, args=(q, stop), daemon=True).start()

    root = tk.Tk()
    root.title("FPGA fly accelerator dashboard - FlyWire 256-neuron subcircuit")
    root.configure(bg="#111418")
    fg, dim = "#e8eaed", "#9aa0a6"

    banner_bg = {"LIVE FPGA": "#1b5e20", "REPLAY": "#0d47a1"}.get(source.label, "#b71c1c")
    tk.Label(root, text=f"SOURCE: {source.label}   —   {source.detail}", bg=banner_bg, fg="white",
             font=("Segoe UI", 12, "bold"), pady=6).pack(fill="x")

    body = tk.Frame(root, bg="#111418")
    body.pack(padx=10, pady=8)

    # Neural grid: 256 neurons, 16 x 16, outline colour = functional group
    CELL, NG = 26, 16
    left = tk.Frame(body, bg="#111418")
    left.grid(row=0, column=0, padx=(0, 12), sticky="n")
    grid = tk.Canvas(left, width=NG * CELL, height=NG * CELL, bg="#111418", highlightthickness=0)
    grid.pack()
    cells = []
    for n in range(C.N_NEURONS):
        r, c = divmod(n, NG)
        _, color = group_of(n)
        cells.append(grid.create_rectangle(c * CELL + 2, r * CELL + 2, (c + 1) * CELL - 2,
                                           (r + 1) * CELL - 2, fill="#1e2228", outline=color, width=2))
    hover = tk.Label(left, text="hover a neuron for its FlyWire identity", bg="#111418", fg=dim,
                     font=("Consolas", 9), anchor="w", justify="left")
    hover.pack(fill="x")
    try:
        neurons = net.load_neurons()
    except OSError:
        neurons = None

    def on_motion(ev):
        c, r = int(ev.x // CELL), int(ev.y // CELL)
        if 0 <= c < NG and 0 <= r < NG:
            n = r * NG + c
            name, _ = group_of(n)
            if neurons:
                nr = neurons[n]
                hover.configure(text=f"#{n}  {nr['primary_type']} ({nr['side']})  {name}\n"
                                     f"FlyWire root_id {nr['root_id']}")
            else:
                hover.configure(text=f"#{n}  {name}")
    grid.bind("<Motion>", on_motion)
    legend = tk.Frame(left, bg="#111418")
    legend.pack(fill="x", pady=(4, 0))
    for i, (_, name, color) in enumerate(GROUPS):
        tk.Label(legend, text="■ " + name, fg=color, bg="#111418", font=("Segoe UI", 8)).grid(
            row=i // 3, column=i % 3, sticky="w", padx=3)

    # Arena
    SCALE = 7
    arena = tk.Canvas(body, width=C.ARENA * SCALE, height=C.ARENA * SCALE, bg="#0b0d10",
                      highlightthickness=1, highlightbackground="#333")
    arena.grid(row=0, column=1, sticky="n")
    taste_id = arena.create_rectangle(0, 0, 0, 0, outline="#2e7d32", dash=(2, 3))
    loom_id = arena.create_rectangle(0, 0, 0, 0, outline="#5d1f1f", dash=(2, 3))
    food_id = arena.create_oval(0, 0, 0, 0, fill="#43a047", outline="")
    threat_id = arena.create_oval(0, 0, 0, 0, fill="#e53935", outline="")
    fly_id = arena.create_polygon(0, 0, 0, 0, 0, 0, fill="#fdd835", outline="#fff")
    action_id = arena.create_text(8, 8, text="", anchor="nw", fill=fg, font=("Segoe UI", 11, "bold"))

    link = tk.Label(root, text="", bg="#111418", fg="#ffb74d", font=("Consolas", 10, "bold"))
    link.pack(fill="x")
    info = tk.Label(body, text="waiting for packets...", bg="#111418", fg=fg, justify="left",
                    font=("Consolas", 10), anchor="w")
    info.grid(row=1, column=0, columnspan=2, sticky="w", pady=(8, 0))

    # Offline controls (the board uses its own switches and buttons)
    if isinstance(source, OfflineSource):
        ctl = tk.Frame(root, bg="#111418")
        ctl.pack(pady=(0, 8))
        fv = tk.IntVar(value=int(source.sim.world.food_present))
        tv = tk.IntVar(value=int(source.sim.world.threat_present))
        rv = tk.IntVar(value=1)

        def apply():
            with source.lock:
                source.sim.world.food_present = bool(fv.get())
                source.sim.world.threat_present = bool(tv.get())
                source.running = bool(rv.get())

        def press(attr):
            with source.lock:
                setattr(source.sim.world, attr, True)

        def single():
            with source.lock:
                source.single += 1

        for text, var in (("run", rv), ("food", fv), ("threat", tv)):
            tk.Checkbutton(ctl, text=text, variable=var, command=apply, bg="#111418", fg=fg,
                           selectcolor="#333").pack(side="left", padx=4)
        tk.Button(ctl, text="step", command=single).pack(side="left", padx=4)
        tk.Button(ctl, text="place food ahead", command=lambda: press("pending_food_respawn")).pack(side="left", padx=4)
        tk.Button(ctl, text="place threat beside", command=lambda: press("pending_threat_respawn")).pack(side="left", padx=4)
        apply()

    def dot(item, x, y, r, visible=True):
        if not visible:
            arena.coords(item, -10, -10, -10, -10)
            return
        cx, cy = x * SCALE + SCALE / 2, y * SCALE + SCALE / 2
        arena.coords(item, cx - r, cy - r, cx + r, cy + r)

    DXY = ((1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1))

    def draw_fly(x, y, h):
        cx, cy = x * SCALE + SCALE / 2, y * SCALE + SCALE / 2
        dx, dy = DXY[h]
        norm = (dx * dx + dy * dy) ** 0.5
        dx, dy = dx / norm, dy / norm
        L, Wd = 11, 6
        arena.coords(fly_id, cx + L * dx, cy + L * dy,
                     cx - 6 * dx - Wd * dy, cy - 6 * dy + Wd * dx,
                     cx - 6 * dx + Wd * dy, cy - 6 * dy - Wd * dx)
        for item, rad in ((taste_id, C.TASTE_RADIUS), (loom_id, C.LOOM_RADIUS)):
            arena.coords(item, (x - rad) * SCALE, (y - rad) * SCALE,
                         (x + rad + 1) * SCALE, (y + rad + 1) * SCALE)

    last = {"pkt": None, "t": time.time(), "rate": 0.0, "n": 0}

    def refresh():
        newest = None
        while True:
            try:
                data = q.get_nowait()
            except queue.Empty:
                break
            if logf:
                logf.write(data)
            for p in parser.feed(data):
                newest = p
                last["n"] += 1
        now = time.time()
        if now - last["t"] >= 1.0:
            last["rate"] = last["n"] / (now - last["t"])
            last["n"], last["t"] = 0, now
        if newest:
            last["seen"] = now
        stale = now - last.get("seen", now if newest else 0) > 1.0
        st = getattr(source, "status", "")
        link.configure(text=(f"no packets for {now - last.get('seen', now):.0f} s   {st}" if stale and
                             (st.startswith("LINK") or last.get("seen")) else
                             (f"link: {st}" if st.startswith("LINK") else "")))
        if newest:
            last["pkt"] = newest
            for n, a in enumerate(newest["activity"]):
                # 2-bit count of spikes since the previous packet (~2 steps)
                k = a / 3
                fill = f"#{int(90 + 165 * k):02x}{int(60 + 140 * k):02x}{int(20 * (1 - k)):02x}" if a else "#1e2228"
                grid.itemconfigure(cells[n], fill=fill)
            fl = newest["flags"]
            dot(food_id, *newest["food"], 7, bool(fl & FLAG_FOOD))
            dot(threat_id, *newest["threat"], 9, bool(fl & FLAG_THREAT))
            draw_fly(*newest["fly"], newest["heading"])
            for item, flag in ((taste_id, FLAG_FOOD), (loom_id, FLAG_THREAT)):   # sensing ranges
                if not fl & flag:
                    arena.coords(item, -10, -10, -10, -10)
            act_name = ACTIONS[newest["action"]] if newest["action"] < len(ACTIONS) else "?"
            arena.itemconfigure(action_id, text=f"last action: {act_name}")
            cyc = newest["cycles"]
            pb = newest["probe_base"]
            pots = "  ".join(f"{pb + k}:{v:3d}" for k, v in enumerate(newest["potentials"]))
            motor = "  ".join(f"{nm} {v}" for nm, v in zip(MOTOR_NAMES, newest["motor"]))
            info.configure(text=(
                f"step {newest['step']:>9}   {'RUN  ' if fl & FLAG_RUNNING else 'PAUSE'}   "
                f"food {'on ' if fl & FLAG_FOOD else 'off'}  threat {'on ' if fl & FLAG_THREAT else 'off'}   "
                f"eaten {newest['eaten']}  caught {newest['caught']}  jumps {newest['jumps']}\n"
                f"engine {'systolic' if fl & FLAG_SYSTOLIC else ('serial' if source.label == 'LIVE FPGA' else 'n/a (model)')}   "
                f"cycles/update {cyc if cyc else 'n/a'}"
                f"{f' ({cyc / CLK_HZ * 1e6:.1f} us at 100 MHz)' if cyc else ''}\n"
                f"last motor window: {motor}\n"
                f"potentials {pots}\n"
                f"packets {parser.good} ({last['rate']:.0f}/s)   seq {newest['seq']}   "
                f"CRC errors {parser.crc_errors}   header errors {parser.header_errors}   "
                f"seq gaps {parser.seq_gaps}   discarded bytes {parser.discarded_bytes}   "
                f"FPGA-dropped snapshots {newest['dropped_total']}"
                f"{'  (drop since last)' if fl & FLAG_DROPPED else ''}"
                f"{chr(10) + 'link: ' + source.status if hasattr(source, 'status') else ''}"))
        root.after(30, refresh)

    def on_close():
        stop.set()
        if logf:
            logf.close()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)
    refresh()
    root.mainloop()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--port")
    g.add_argument("--offline", action="store_true")
    g.add_argument("--replay")
    g.add_argument("--list", action="store_true")
    g.add_argument("--selftest", type=int, metavar="N")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--log")
    ap.add_argument("--food", action="store_true", help="offline mode: start with food present")
    ap.add_argument("--threat", action="store_true", help="offline mode: start with threat present")
    a = ap.parse_args()
    if a.list:
        return list_ports()
    if a.selftest:
        return selftest(a.selftest)
    if a.port:
        src = SerialSource(a.port, a.baud)
    elif a.replay:
        src = ReplaySource(a.replay)
    elif a.offline:
        src = OfflineSource()
        src.sim.world.food_present = a.food
        src.sim.world.threat_present = a.threat
    else:
        ap.error("choose --port, --offline, --replay, --list or --selftest")
    run_gui(src, a.log)


if __name__ == "__main__":
    sys.exit(main())
