# OrynTap · Part D: IoT door counter (Python simulation)

> **No real hardware is connected.** We do not have an ESP32 or ToF sensors yet.
> `sensor_sim.py` is a **software simulation** of the device we would mount at the
> AITU Library door. It sends exactly what the real device would send, so the
> database and the website do not need to change when real hardware arrives.

## How the (future) device works

```
 outside │ ToF A │ ToF B │ inside        ESP32 + 2 × VL53L0X time-of-flight sensors
         │ beam  │ beam  │               in the door frame, about 20 cm apart
```

| Step | Real device (future) | In this simulation |
|---|---|---|
| 1. Measure | Each ToF sensor measures the distance in mm, ~20 times a second | `ToFSensor.read_mm()`: ~900 mm when the door is empty, 250–550 mm when a person is under it |
| 2. Direction | A blocked first, then B = **IN**; B first, then A = **OUT** | `DoorCounter.feed()`: the same state machine |
| 3. Count | Keep a running count, never below 0, never above the seats | `DoorCounter.inside`, clamped to 0 … capacity |
| 4. Send | Every 10 s: HTTPS POST of one number to Supabase | `send_reading()`: calls `rpc/ingest_reading` |
| 5. Show | The website shows people inside, free seats, last update | Home page → “Live occupancy” panel, refreshed every 10 s |

People are simulated with random IN/OUT events (once a second there may be someone in the door;
more people come in when the room is empty, more leave when it is full).

**Data flow:** `sensor_sim.py` → `ingest_reading()` → table `sensor_readings` (people_inside, measured_at)
→ view `space_sensor_now` (adds seats and free seats) → website panel.

## Security

* The simulator uses only the **public** publishable/anon key (the one already in `js/config.js`)
  plus its **own sensor secret**. The database stores only the SHA-256 hash of that secret.
* It refuses to start with a `sb_secret_…` / service_role key.
* Settings live in `iot/.env`, which is in `.gitignore`. Only `iot/.env.example` is committed.
* RLS is unchanged: anonymous users cannot read or write `sensor_readings` directly. They can
  only call `ingest_reading()` (with a valid secret) and read the latest count per space
  (`space_sensor_now`). Fewer than 3 people is shown as “fewer than 3”.
* `ingest_reading()` rejects a wrong secret, a negative count, more people than seats,
  and more than one reading per 5 seconds.

## Setup (once)

1. **Supabase → SQL Editor**: run `database/07_stage2.sql` (if not done yet), then
   `database/08_iot_occupancy.sql`.
2. Still in the SQL Editor, run the `SELECT … register_sensor(…)` at the end of `08`.
   Copy `space_id` and the long `secret` (shown only once).
   *Optional:* run the `UPDATE public.sensors SET active = false …` line from `08` to switch off
   the four sensors of the earlier simulation, if you registered them.
3. Create the settings file:
   ```bash
   cp iot/.env.example iot/.env        # Windows: copy iot\.env.example iot\.env
   ```
   Fill in `SUPABASE_URL`, `SUPABASE_KEY` (the publishable key from `js/config.js`),
   `SENSOR_TOKEN` (the secret) and `SPACE_ID`.

**Dependencies:** none. Python 3.8 or newer only (`python3 --version`); everything else is
the standard library, so there is no `pip install`.

## Run

```bash
python3 iot/sensor_sim.py                  # until Ctrl+C, sends every 10 s
python3 iot/sensor_sim.py --minutes 3      # stop after 3 minutes
python3 iot/sensor_sim.py --dry-run        # no Supabase: only shows the events
python3 -m unittest iot/test_sensor_sim.py -v   # tests of the counting logic
```
(On Windows use `py` instead of `python3`.)

Example output (a test run against a local copy of our database):
```
SIMULATED door counter: Library, 250 seats, start 120 inside
2 ToF sensors (A outside, B inside), threshold 600 mm; sending every 10 s to https://YOUR-PROJECT.supabase.co. Ctrl+C to stop.

18:09:51  OUT  A 903 mm, B 492 mm  -> OUT  | inside: 119
18:09:51  SEND people_inside=119  -> 200 ok
18:09:52  IN   A 531 mm, B 910 mm  -> IN  | inside: 120
18:09:55  IN   A 404 mm, B 881 mm  -> IN  | inside: 121
18:10:01  SEND people_inside=121  -> 200 ok
```

Open the website (AITU selected): the Home page shows **Live occupancy · Simulated sensor**
with *People inside*, *Free seats* (= seats − people inside) and *Last update*. It refreshes every
10 seconds. The panel disappears 15 minutes after the last reading.

## Check in Supabase

```sql
SELECT * FROM public.sensor_readings ORDER BY measured_at DESC LIMIT 10;  -- new rows every 10 s
SELECT * FROM public.space_sensor_now;                                     -- what the website reads
```

## Troubleshooting

| Message | Fix |
|---|---|
| `Missing in iot/.env: …` | copy `.env.example` to `.env` and fill in all four values |
| `Could not read study space …` | wrong `SUPABASE_URL`, `SUPABASE_KEY` or `SPACE_ID` |
| `400 Unknown or disabled sensor` | wrong `SENSOR_TOKEN`: register the sensor again |
| `404` on `ingest_reading` | `07_stage2.sql` / `08_iot_occupancy.sql` not run in this project |
| `skipped (too frequent)` | `SEND_INTERVAL` below 6 s; the database accepts one reading per 5 s |
| Panel not visible | simulator not running for 15 min, or another university selected |
