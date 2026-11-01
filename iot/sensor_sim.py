#!/usr/bin/env python3
"""
OrynTap · Project Stage 2, Part D3: door-sensor simulator.

Pretends to be the people counters at the entrances of the AITU study spaces.
Every few seconds each "sensor" sends the number of people inside to Supabase
by calling the database function ingest_reading(p_token, p_people).

Like a real device it uses only:
  * the PUBLIC anon / publishable key (the same one that is in js/config.js)
  * its own secret token (from register_sensor(), see database/07_stage2.sql)
It never uses the service_role key, and no personal data is sent: one number.

Setup (once):
  1. Run database/07_stage2.sql in the Supabase SQL Editor and the SELECT at
     its end; copy the four secrets.
  2. cp iot/sensors.example.json iot/sensors.local.json and paste the URL,
     the anon key and the secrets. (sensors.local.json is git-ignored.)
Run:
  python3 iot/sensor_sim.py                 # every 15 s until Ctrl+C
  python3 iot/sensor_sim.py --interval 60   # like a real device, once a minute
  python3 iot/sensor_sim.py --once          # one reading per sensor, then stop
  python3 iot/sensor_sim.py --dry-run       # print the numbers, send nothing
Needs only Python 3.8+ (no packages).
"""
import argparse, json, math, random, sys, time, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone
from pathlib import Path

ASTANA = timezone(timedelta(hours=5))
PEAK = {"library": 0.86, "coworking": 0.72, "atrium": 0.70, "rooms": 0.65, "lounge": 0.50, "cafe": 0.60}

def expected_people(kind, capacity, now):
    """Same daily curve as the demo mode: busiest around 14:30, quiet at night."""
    h = now.hour + now.minute / 60
    share = max(0.0, PEAK.get(kind, 0.6) * math.exp(-((h - 14.5) / 4.2) ** 2))
    if h < 8 or h >= 22:
        share = 0.0
    return capacity * share

class Sensor:
    def __init__(self, cfg):
        self.label, self.token = cfg["label"], cfg["token"]
        self.capacity, self.kind = int(cfg["capacity"]), cfg.get("kind", "library")
        self.people = None
    def read(self, now):
        target = expected_people(self.kind, self.capacity, now)
        if self.people is None:
            self.people = target
        # people come and go: move towards the daily curve with some noise
        self.people += 0.3 * (target - self.people) + random.gauss(0, max(1.0, 0.03 * self.capacity))
        self.people = min(max(self.people, 0), self.capacity * 1.1)
        return int(round(self.people))

def send(url, key, token, people, timeout=10):
    req = urllib.request.Request(
        url.rstrip("/") + "/rest/v1/rpc/ingest_reading",
        data=json.dumps({"p_token": token, "p_people": people}).encode(),
        headers={"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return None, str(e)

def main():
    ap = argparse.ArgumentParser(description="OrynTap door-sensor simulator")
    ap.add_argument("--config", default=str(Path(__file__).with_name("sensors.local.json")))
    ap.add_argument("--interval", type=float, default=15, help="seconds between readings (real device: 60)")
    ap.add_argument("--once", action="store_true", help="send one reading per sensor and stop")
    ap.add_argument("--dry-run", action="store_true", help="do not send, only print")
    a = ap.parse_args()
    try:
        cfg = json.loads(Path(a.config).read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"Config not found: {a.config}\nCopy iot/sensors.example.json to iot/sensors.local.json and fill it in.")
    sensors = [Sensor(s) for s in cfg["sensors"]]
    print(f"{len(sensors)} sensors -> {cfg['supabase_url'] if not a.dry_run else 'dry run'} every {a.interval:g} s (Ctrl+C to stop)")
    while True:
        now = datetime.now(ASTANA)
        for s in sensors:
            n = s.read(now)
            if a.dry_run:
                print(f"{now:%H:%M:%S}  {s.label:<28} {n:>4} inside  (not sent)")
                continue
            status, body = send(cfg["supabase_url"], cfg["anon_key"], s.token, n)
            print(f"{now:%H:%M:%S}  {s.label:<28} {n:>4} inside  -> {status} {body.strip()[:60]}")
        if a.once:
            break
        time.sleep(a.interval)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nstopped")
