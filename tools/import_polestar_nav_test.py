"""Conversion checks using two neighbouring Zephras Isle clusters from the pinned release."""

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from import_polestar_nav import PIN, collision, pinned_inputs
from refresh_nav_graph import nav

FIXTURE = Path(__file__).with_name("fixtures") / "polestar-zephras.json"
ROOT = Path(__file__).resolve().parent.parent
LUA = r"""
dofile(arg[1])
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local g, floor = ns.PathGrid, math.floor
local st = assert(g.State(2991))
for k in pairs(st.D.grid) do
    k = k - 1
    local val = assert(g.grid(st, k))
    for u = 0, #val - 1 do
        if val[u + 1] ~= 0 then
            local cell = g.cellOf(st, k, u)
            local x = floor(k / st.ny) * st.C + floor(cell / st.C)
            local y = (k % st.ny) * st.C + cell % st.C
            local ks, vs, costs, seen = {}, {}, {}, {}
            local function report(dx, dy)
                local key = (dx + 8) * 16 + dy + 8
                if seen[key] then return end
                seen[key] = true
                local n = g.neighbours(st, k, u, x, y, dx, dy, true, ks, vs, costs)
                for i = 1, n do
                    io.write(k, ",", u, ",", ks[i], ",", vs[i], ",", costs[i], "\n")
                end
            end
            for d = 0, 7 do
                report(g.DX[d], g.DY[d])
            end
            for _, entry in ipairs(st.links[k][u + 1] or {}) do
                report(entry % 16 - 8, floor(entry / 16) % 16 - 8)
            end
        end
    end
end
"""


class ImportPolestarTest(unittest.TestCase):
    def test_pinned_inputs_reject_modified_data(self):
        pin = json.loads(PIN.read_text())
        first = next(iter(pin["sha256"]))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            file = root / first
            file.parent.mkdir(parents=True)
            file.write_bytes(b"modified data")
            with self.assertRaisesRegex(ValueError, "does not match the SHA-256"):
                pinned_inputs(root)

    def test_directed_moves_round_trip(self):
        fixture = json.loads(FIXTURE.read_text())
        fields = {field: {int(k): text for k, text in entries.items()} for field, entries in fixture["fields"].items()}
        grid, masks, arcs, crossings = collision(2991, fixture["metadata"], fields)
        self.assertGreater(arcs["parallel_to_floor_step"], 0)
        self.assertEqual(crossings["kept"], 4)
        self.assertGreater(crossings["already_made"], 0)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            data = path / "Nav2991.lua"
            harness = path / "moves.lua"
            harness.write_text(LUA)
            nav.emit({}, {}, grid, masks, data, "Zephras Isle")
            result = subprocess.check_output(["luajit", str(harness), str(data)], cwd=ROOT)
        moves = sorted(set(result.splitlines()))
        digest = hashlib.sha256(b"\n".join(moves)).hexdigest()
        self.assertEqual(len(moves), fixture["moves"])
        self.assertEqual(digest, fixture["sha256"])


if __name__ == "__main__":
    unittest.main()
