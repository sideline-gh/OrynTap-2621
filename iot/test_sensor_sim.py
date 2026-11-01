"""Tests for the door-counter logic.  Run:  python3 -m unittest iot/test_sensor_sim.py -v"""
import random, sys, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sensor_sim import DoorCounter, ToFSensor, walk_through

FREE, BUSY = 900, 400     # mm: empty door / person under the sensor

def frames(counter, pairs):
    """Feed (A, B) readings, return the last event."""
    event = None
    for a, b in pairs:
        event = counter.feed(a, b) or event
    return event

class DoorCounterTest(unittest.TestCase):
    def test_in_is_a_then_b(self):
        c = DoorCounter(capacity=10, start=0)
        self.assertEqual(frames(c, [(BUSY, FREE), (BUSY, BUSY), (FREE, BUSY), (FREE, FREE)]), "IN")
        self.assertEqual(c.inside, 1)

    def test_out_is_b_then_a(self):
        c = DoorCounter(capacity=10, start=5)
        self.assertEqual(frames(c, [(FREE, BUSY), (BUSY, BUSY), (BUSY, FREE), (FREE, FREE)]), "OUT")
        self.assertEqual(c.inside, 4)

    def test_turning_back_changes_nothing(self):
        c = DoorCounter(capacity=10, start=5)
        self.assertIsNone(frames(c, [(BUSY, FREE), (FREE, FREE)]))   # A blocked, then walked away
        self.assertEqual(c.inside, 5)

    def test_never_above_capacity(self):
        c = DoorCounter(capacity=3, start=3)
        a, b = ToFSensor("A"), ToFSensor("B")
        self.assertEqual(frames(c, walk_through("IN", a, b)), "IGNORED (room full)")
        self.assertEqual(c.inside, 3)

    def test_never_below_zero(self):
        c = DoorCounter(capacity=3, start=0)
        a, b = ToFSensor("A"), ToFSensor("B")
        self.assertEqual(frames(c, walk_through("OUT", a, b)), "IGNORED (count already 0)")
        self.assertEqual(c.inside, 0)

    def test_start_value_is_clamped(self):
        self.assertEqual(DoorCounter(capacity=10, start=99).inside, 10)
        self.assertEqual(DoorCounter(capacity=10, start=-5).inside, 0)

    def test_many_random_people_stay_in_range(self):
        random.seed(1)
        c, a, b = DoorCounter(capacity=20, start=10), ToFSensor("A"), ToFSensor("B")
        for _ in range(5000):
            frames(c, walk_through(random.choice(["IN", "OUT"]), a, b))
            self.assertTrue(0 <= c.inside <= 20)

    def test_tof_readings_look_like_millimetres(self):
        s = ToFSensor("A")
        self.assertTrue(all(250 <= s.read_mm(True) <= 550 for _ in range(200)))
        self.assertTrue(all(880 <= s.read_mm(False) <= 920 for _ in range(200)))

if __name__ == "__main__":
    unittest.main()
