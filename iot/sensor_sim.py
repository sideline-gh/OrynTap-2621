#!/usr/bin/env python3
"""
OrynTap · Project Stage 2, Part D: IoT door-counter SIMULATOR (no hardware).

We do not have an ESP32 or ToF sensors yet. This script pretends to be the
device we would mount at the AITU Library door:

    outside  |  ToF A  |  ToF B  |  inside        (two distance sensors ~20 cm apart,
             |  beam   |  beam   |                 both looking down/across the door)

  * Each ToF sensor measures a distance in mm. Nobody in the door: about 900 mm
    (the floor / the other side of the frame). A person under it: 250-550 mm.
  * A person going IN blocks A first, then B. Going OUT: B first, then A.
    DoorCounter below is the same small state machine the ESP32 firmware would run.
  * The device keeps a running count of people inside, never below 0 and never
    above the seats of the room.
  * Every SEND_INTERVAL seconds it sends ONE number (people inside) to Supabase,
    by calling the database function ingest_reading(p_token, p_people).
    The server adds the timestamp (measured_at).

Security: it uses only the PUBLIC publishable/anon key (the same one that is in
js/config.js) plus this sensor's own secret. Never the service_role key.

Setup and run: see iot/README.md.   Needs only Python 3.8+ (no packages).
  python3 iot/sensor_sim.py               # runs until Ctrl+C, sends every 10 s
  python3 iot/sensor_sim.py --dry-run     # no network: shows the events only
  python3 iot/sensor_sim.py --minutes 2   # stop after 2 minutes
"""
import argparse, json, os, random, sys, time, urllib.error, urllib.request
from datetime import datetime
from pathlib import Path

BLOCKED_MM = 600          # a reading below this means "someone is under the sensor"

# ---------------------------------------------------------------- settings
def load_env(path):
    """Read KEY=value lines from a .env file into os.environ (real env vars win)."""
    p = Path(path)
    if not p.exists():
        return False
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.split(" #")[0].strip().strip('"').strip("'")   # drop "  # comment"
        os.environ.setdefault(key.strip(), value)
    return True

def base_url(url):
    """Accept https://xyz.supabase.co and https://xyz.supabase.co/rest/v1/ alike."""
    url = url.strip().rstrip("/")
    for tail in ("/rest/v1", "/auth/v1"):
        if url.endswith(tail):
            url = url[: -len(tail)]
    return url

# ---------------------------------------------------------------- the two sensors
class ToFSensor:
    """One time-of-flight distance sensor (e.g. VL53L0X). Returns millimetres."""
    def __init__(self, name):
        self.name = name
    def read_mm(self, person_under):
        if person_under:
            return random.randint(250, 550)          # head/shoulders of a person
        return random.randint(880, 920)              # empty door: the far side

class DoorCounter:
    """Direction detection from the ORDER in which beam A and beam B are blocked.
    This is the logic that would run on the ESP32."""
    def __init__(self, capacity, start=0):
        self.capacity = capacity
        self.inside = max(0, min(start, capacity))
        self.sequence = []                            # e.g. ["A", "B"] while someone passes

    def feed(self, a_mm, b_mm):
        """Feed one pair of readings. Returns "IN", "OUT", "IGNORED ..." or None."""
        a, b = a_mm < BLOCKED_MM, b_mm < BLOCKED_MM
        for name, blocked in (("A", a), ("B", b)):
            if blocked and name not in self.sequence:
                self.sequence.append(name)
        if a or b:
            return None                               # person still in the door
        seq, self.sequence = self.sequence, []
        if seq == ["A", "B"]:
            if self.inside >= self.capacity:
                return "IGNORED (room full)"
            self.inside += 1
            return "IN"
        if seq == ["B", "A"]:
            if self.inside <= 0:
                return "IGNORED (count already 0)"
            self.inside -= 1
            return "OUT"
        return None                                   # nothing, or someone turned back

def walk_through(direction, sensor_a, sensor_b):
    """Readings (A, B) while one person passes: 5 frames, like a 20 Hz sample loop."""
    order = [(0, 0), (1, 0), (1, 1), (0, 1), (0, 0)]  # IN: A, then A+B, then B, then clear
    if direction == "OUT":
        order = [(b, a) for a, b in order]            # OUT: the same, mirrored
    return [(sensor_a.read_mm(a), sensor_b.read_mm(b)) for a, b in order]

# ---------------------------------------------------------------- Supabase
def http(method, url, key, body=None, timeout=10):
    req = urllib.request.Request(url, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:                            # no internet, wrong URL ...
        return None, str(e)

def get_space(url, key, space_id):
    status, body = http("GET", f"{url}/rest/v1/study_spaces?id=eq.{int(space_id)}&select=name,seat_capacity", key)
    if status != 200 or not json.loads(body):
        sys.exit(f"Could not read study space {space_id} from Supabase ({status}): {body[:200]}")
    return json.loads(body)[0]

def send_reading(url, key, token, people):
    return http("POST", f"{url}/rest/v1/rpc/ingest_reading", key, {"p_token": token, "p_people": people})

def message(body):
    try:
        data = json.loads(body)
        return data if isinstance(data, str) else data.get("message", body)
    except Exception:
        return body.strip()

# ---------------------------------------------------------------- main loop
def main():
    ap = argparse.ArgumentParser(description="OrynTap simulated door counter (2 ToF sensors)")
    ap.add_argument("--env", default=str(Path(__file__).with_name(".env")), help="settings file (default iot/.env)")
    ap.add_argument("--dry-run", action="store_true", help="do not connect to Supabase, only print")
    ap.add_argument("--minutes", type=float, default=0, help="stop after this many minutes (0 = until Ctrl+C)")
    ap.add_argument("--capacity", type=int, default=250, help="seats, only used with --dry-run")
    ap.add_argument("--seed", type=int, help="random seed, to repeat the same run")
    a = ap.parse_args()
    if a.seed is not None:
        random.seed(a.seed)

    load_env(a.env)
    interval = max(6.0, float(os.environ.get("SEND_INTERVAL", "10")))   # server accepts 1 reading / 5 s
    start = int(os.environ.get("START_PEOPLE", "40"))
    url = key = token = None
    if a.dry_run:
        name, capacity = "Library (dry run)", a.capacity
    else:
        missing = [k for k in ("SUPABASE_URL", "SUPABASE_KEY", "SENSOR_TOKEN", "SPACE_ID") if not os.environ.get(k)]
        if missing:
            sys.exit(f"Missing in {a.env}: {', '.join(missing)}\nCopy iot/.env.example to iot/.env and fill it in (see iot/README.md).")
        url, key, token = base_url(os.environ["SUPABASE_URL"]), os.environ["SUPABASE_KEY"], os.environ["SENSOR_TOKEN"]
        if key.startswith("sb_secret_") or "service_role" in key:
            sys.exit("SUPABASE_KEY must be the PUBLIC publishable/anon key, never the secret/service_role key.")
        space = get_space(url, key, os.environ["SPACE_ID"])
        name, capacity = space["name"], int(space["seat_capacity"])

    counter = DoorCounter(capacity, start)
    sensor_a, sensor_b = ToFSensor("A (outside)"), ToFSensor("B (inside)")
    print(f"SIMULATED door counter: {name}, {capacity} seats, start {counter.inside} inside")
    print(f"2 ToF sensors (A outside, B inside), threshold {BLOCKED_MM} mm; sending every {interval:g} s"
          + (" (dry run, nothing is sent)" if a.dry_run else f" to {url}") + ". Ctrl+C to stop.\n")

    stop_at = time.time() + a.minutes * 60 if a.minutes else None
    next_send = time.time()                            # send the starting count at once
    sent = failed = 0
    while stop_at is None or time.time() < stop_at:
        # One simulated second: maybe somebody walks through the door.
        # More people come in when the room is empty, more leave when it is full.
        fill = counter.inside / capacity
        r = random.random()
        direction = "IN" if r < 0.45 * (1 - fill) else "OUT" if r < 0.45 * (1 - fill) + 0.45 * fill + 0.03 else None
        if direction:
            readings = walk_through(direction, sensor_a, sensor_b)
            event = None
            for a_mm, b_mm in readings:
                event = counter.feed(a_mm, b_mm) or event
            first = readings[1]
            print(f"{datetime.now():%H:%M:%S}  {direction:<3}  A {first[0]:>3} mm, B {first[1]:>3} mm"
                  f"  -> {event or 'no change'}  | inside: {counter.inside}")

        if time.time() >= next_send:
            stamp = f"{datetime.now():%H:%M:%S}"
            if a.dry_run:
                print(f"{stamp}  SEND people_inside={counter.inside} (dry run, not sent)")
            else:
                status, body = send_reading(url, key, token, counter.inside)
                ok = status == 200
                sent += ok; failed += not ok
                print(f"{stamp}  SEND people_inside={counter.inside}  -> {status} {message(body)}")
                if status in (400, 401, 403) and "Unknown or disabled sensor" in body:
                    sys.exit("The SENSOR_TOKEN is wrong or the sensor is disabled. Register it again (database/08_iot_occupancy.sql).")
            next_send += interval
        time.sleep(1)
    print(f"\nfinished: {sent} readings sent, {failed} failed, {counter.inside} inside")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nstopped")
