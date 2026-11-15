import unittest

from tools.gen_roads import ROAD_COVERAGE, TEXELS, cells_of


def painted(cells, cover):
    """A tile's texels with the given {(i, j): share} painted road, in cells_of's x-major order."""
    weights = bytearray(TEXELS * TEXELS)
    edges = [round(TEXELS * (1 - n / cells)) for n in range(cells + 1)]
    for (i, j), share in cover.items():
        rows, columns = range(edges[i + 1], edges[i]), list(range(edges[j + 1], edges[j]))
        area = len(rows) * len(columns)
        total = round(area * share)
        done = 0
        for row in rows:
            for column in columns:
                if done >= total:
                    break
                weights[row * TEXELS + column] = 255
                done += 1
    return weights


class RoadCellsTest(unittest.TestCase):
    def test_a_narrow_diagonal_road_stays_joined(self):
        # A one-cell road running diagonally covers about a third of each cell it crosses. At the old half-covered
        # rule those cells came out as separate dashes; the quarter rule keeps the road whole.
        cells = 67
        cover = {(i, i): 0.3 for i in range(10, 20)}
        road = cells_of(painted(cells, cover), cells)
        for i in range(10, 20):
            self.assertIn(i * cells + i, road)
        self.assertLess(ROAD_COVERAGE, 0.3, "the documented share covers a narrow road")

    def test_ground_barely_brushed_by_a_road_is_not_road(self):
        cells = 67
        road = cells_of(painted(cells, {(20, 20): 0.2}), cells)
        self.assertNotIn(20 * cells + 20, road)
        self.assertGreaterEqual(ROAD_COVERAGE, 0.2, "the documented share leaves a brushed cell alone")


if __name__ == "__main__":
    unittest.main()
