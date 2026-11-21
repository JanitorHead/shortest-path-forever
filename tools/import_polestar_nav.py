#!/usr/bin/env python3
"""Import the shipped Polestar format 5 walking maps, derived from Leffe's maps."""

import argparse
import hashlib
import json
import math
import re
import zlib
from array import array
from collections import Counter, defaultdict
from pathlib import Path

from baker.terrain import sample_cluster
from gen_roads import generate as generate_roads
from pack_nav import write_bundle
from refresh_nav_graph import Reader, nav

PIN = Path(__file__).with_name("polestar-nav.json")
MAPS = (0, 1, 2991)
MAP_NAMES = {0: "Eastern Kingdoms", 1: "Kalimdor", 2991: "Zephras Isle"}
FIELDS = ("grid", "height", "floor", "arc", "graph")
LITERAL = rb'"(?:[^"\\]|\\[0-9]{1,3}|\\.)*"'
ENTRY = re.compile(
    rb"^(?:data\.packed\.(grid|height|floor|arc|graph)|t)\[(\d+)\]\s*=\s*"
    rb"(\{\s*" + LITERAL + rb"(?:\s*,\s*" + LITERAL + rb")*\s*,?\s*\})",
    re.MULTILINE,
)
ESCAPE = re.compile(rb'\\([0-9]{1,3}|[abfnrtv"\\])')
ESCAPES = dict(zip(b'abfnrtv"\\', b'\a\b\f\n\r\t\v"\\', strict=True))


def literal_bytes(match):
    def escape(m):
        value = m[1]
        return bytes([int(value) if value.isdigit() else ESCAPES[value[0]]])

    return ESCAPE.sub(escape, match[1:-1])


def pinned_inputs(root):
    pin = json.loads(PIN.read_text())
    inputs = {}
    for name, expected in pin["sha256"].items():
        content = (root / name).read_bytes()
        if hashlib.sha256(content).hexdigest() != expected:
            raise ValueError(f"{name} does not match the SHA-256 for {pin['revision']}")
        inputs[name] = content
    return inputs


def read_map(inputs, map_id):
    prefix = f"addon/Polestar_Nav/Nav/Nav{map_id}"
    source = inputs[prefix + ".lua"]
    meta = {}
    for field in ("format", "cx0", "cy0", "nx", "ny", "cells", "zstep"):
        match = re.search(rb"^\t" + field.encode() + rb" = (-?\d+),$", source, re.MULTILINE)
        if match is None:
            raise ValueError(f"Missing {field} in map {map_id}")
        meta[field] = int(match[1])
    if meta["format"] != 5 or b'\tblocks = "zlib",' not in source:
        raise ValueError(f"Expected format 5 zlib blocks for map {map_id}")
    counts = re.search(rb"^\tcounts = \{ ([^}]+) \}", source, re.MULTILINE)
    expected = {name.decode(): int(count) for name, count in re.findall(rb"(\w+) = (\d+)", counts[1])}
    fields = {field: {} for field in FIELDS}
    part_dir = {0: "addon/Polestar_Nav_EK/", 1: "addon/Polestar_Nav_Kalimdor/"}.get(map_id)
    for name, content in inputs.items():
        region = name.startswith(f"addon/Polestar_Nav_R{map_id}_")
        if not (region or name.startswith(prefix + "_") or (part_dir and name.startswith(part_dir))):
            continue
        if region:
            # Regional pages change the destination table as they load floor and detail records.
            floor_page = re.search(rb"^local t = d\.packed\.floor\n(.*?)(?=^local t = |\Z)", content, re.M | re.S)
            if floor_page is None:
                continue
            content = floor_page[1]
        for match in ENTRY.finditer(content):
            field = match[1].decode() if match[1] else "floor"
            key = int(match[2]) - 1
            if key in fields[field] or not 0 <= key < meta["nx"] * meta["ny"]:
                raise ValueError(f"Duplicate or invalid {field} cluster {key} in {name}")
            blocks = re.findall(LITERAL, match[3])
            fields[field][key] = b"".join(zlib.decompress(literal_bytes(block)) for block in blocks).decode("ascii")
    for field, clusters in fields.items():
        if len(clusters) != expected[field]:
            raise ValueError(f"Map {map_id} {field}: got {len(clusters)}, expected {expected[field]}")
    if fields["grid"].keys() != fields["height"].keys():
        raise ValueError(f"Map {map_id} has mismatched grid and height clusters")
    return meta, fields


class Columns(Reader):
    def varint(self):
        result, shift = 0, 0
        while True:
            symbol = self.take()
            result |= (symbol & 31) << shift
            if symbol < 32:
                return result
            shift += 5

    def signed(self):
        value = self.varint()
        return (value >> 1) ^ -(value & 1)

    def done(self):
        if self.pos != len(self.values):
            raise ValueError("Unexpected trailing format 5 symbols")


def floor_columns(text):
    reader = Columns(text)
    cells = []
    cell = -1
    for _ in range(reader.varint()):
        cell += reader.varint() + 1
        cells.append(cell)
    counts = [reader.take() for _ in cells]
    values = [reader.take() for _ in range(sum(counts))]
    first = 0
    floors = []
    for cell, count in zip(cells, counts, strict=True):
        height = first
        for layer in range(1, count + 1):
            height += reader.signed()
            if layer == 1:
                first = height
            floors.append((cell, layer, values[len(floors)], height))
    masks = [reader.take(2) % 256 for _ in floors]
    links = defaultdict(list)
    sources = []
    node = 0
    for _ in range(reader.varint()):
        node += reader.signed()
        sources.append(node)
    directions = [reader.take() for _ in sources]
    for node, direction in zip(sources, directions, strict=True):
        links[node].append((direction, reader.take()))
    reader.done()
    return floors, masks, links


def arc_columns(text):
    reader = Columns(text)
    sources = []
    node = 0
    for _ in range(reader.varint()):
        node += reader.varint()
        sources.append(node)
    targets = [node + reader.signed() for node in sources]
    for start, end in zip(sources, targets, strict=True):
        yield start, end, min(reader.varint(), 65535)
    reader.done()


def geometry(map_id, meta):
    nav.MAP, nav.CELLS, nav.ZQ = map_id, meta["cells"], meta["zstep"]
    nav.CX0, nav.CY0, nav.NX, nav.NY = (meta[key] for key in ("cx0", "cy0", "nx", "ny"))
    nav.CS, nav.LINK_COST_SCALE = nav.T / nav.CELLS, 4
    nav.GW, nav.GH = nav.NX * nav.CELLS, nav.NY * nav.CELLS
    nav.ROWS = range(32 - nav.CX0 - nav.NX, 32 - nav.CX0)
    nav.COLS = range(32 - nav.CY0 - nav.NY, 32 - nav.CY0)
    nav.X0, nav.Y0 = nav.CX0 * nav.T, nav.CY0 * nav.T
    nav.SOURCE = "Leffe's walking maps, condensed by Polestar and Fitz (tools/polestar-nav.json)"
    nav.BASE_Z = array("f", [0]) * (nav.GW * nav.GH)
    nav.FLOOR_CELL, nav.FLOOR_Z = array("i"), array("f")
    nav.FLOOR_VAL, nav.FLOOR_LAYER = bytearray(), bytearray()
    nav.FLOORS_OF, nav.FLOORS_AT = defaultdict(list), {}
    nav.LINKS, nav.LINKED_OF = defaultdict(dict), defaultdict(list)
    nav.PARALLEL_LINKS = defaultdict(dict)
    nav.FREE = set()
    nav.TERRAIN, nav.WET_STEPS, nav.NARROW_STEPS = {}, defaultdict(set), defaultdict(set)


def cell_of(k, local):
    c = nav.CELLS
    return (k // nav.NY * c + local // c) * nav.GH + k % nav.NY * c + local % c


def node_of(k, local):
    width = nav.CELLS**2
    return cell_of(k, local) if local < width else nav.FLOORS_OF[k][local - width]


def height_grid(grid, flags, k, grid_text, height_text):
    c = nav.CELLS
    samples = []
    value = 0
    for char in grid_text:
        symbol = nav.B64.index(char)
        if symbol < 48:
            value = symbol
            samples.append(value)
        else:
            samples.extend([value] * (symbol - 47))
    if len(samples) != c * c:
        raise ValueError(f"Unexpected grid dimensions in cluster {k}")
    reader = Columns(height_text)
    heights = {}
    last = repeat = delta = 0
    for local, sample in enumerate(samples):
        node = cell_of(k, local)
        grid[node], flags[node] = divmod(sample, 16)
        if not grid[node]:
            continue
        predicted = heights.get(local - 1) if local % c else None
        if predicted is None:
            predicted = heights.get(local - c, last)
        if repeat:
            last, repeat = predicted + delta, repeat - 1
        else:
            symbol = reader.take()
            if symbol == 47:
                last = reader.take(2) - 2048
            else:
                delta = symbol - 23
                last = predicted + delta
                while reader.pos < len(reader.values) and reader.values[reader.pos] >= 48:
                    repeat += reader.take() - 47
        heights[local] = last
        nav.BASE_Z[node] = last * nav.ZQ
    reader.done()


def add_floors(k, floors):
    size = nav.GW * nav.GH
    for local, layer, value, height in floors:
        cell = cell_of(k, local)
        node = size + len(nav.FLOOR_CELL)
        nav.FLOORS_OF[k].append(node)
        nav.FLOORS_AT.setdefault(cell, []).append(node)
        nav.FLOOR_CELL.append(cell)
        nav.FLOOR_LAYER.append(layer)
        nav.FLOOR_VAL.append(value)
        nav.FLOOR_Z.append(height)


def surface(grid, cell, layer, height):
    floors = nav.FLOORS_AT.get(cell, ())
    if layer == 0:
        return cell if grid[cell] else None
    if layer != -1:
        return floors[layer - 1] if layer <= len(floors) else None
    candidates = ([cell] if grid[cell] else []) + list(floors)
    return min(candidates, key=lambda node: abs(nav.stored_z(node) - height), default=None)


def floor_moves(grid, k, rows):
    floors, masks, links = rows
    n = nav.CELLS**2
    for index, mask in enumerate(masks):
        for direction in range(8):
            if mask & (1 << direction):
                links[n + index].append((direction, -1))
    for local, moves in links.items():
        start = node_of(k, local)
        sx, sy = divmod(nav.cell_of(start), nav.GH)
        for direction, layer in moves:
            dx, dy, _ = nav.MOVES[direction]
            x, y = sx + dx, sy + dy
            if not (0 <= x < nav.GW and 0 <= y < nav.GH):
                continue
            end = surface(grid, x * nav.GH + y, layer, nav.stored_z(start))
            if end is None:
                continue
            nav.LINKS[start][end] = None
            if local >= n and end < nav.GW * nav.GH and nav.cluster_of_cell(end) == k:
                nav.LINKS[end][start] = None


def base_masks(grid, flags, clusters):
    masks = bytearray(len(grid))

    def orthogonal(x, y, tx, ty):
        a, b = x * nav.GH + y, tx * nav.GH + ty
        return grid[a] and grid[b] and not (flags[min(a, b)] & (1 if x != tx else 2))

    for k in clusters:
        x0, x1, y0, y1 = nav.cluster_box(k)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                a = x * nav.GH + y
                if not grid[a]:
                    continue
                for d in (0, 2, 4, 5):
                    dx, dy, _ = nav.MOVES[d]
                    tx, ty = x + dx, y + dy
                    if not (0 <= tx < nav.GW and 0 <= ty < nav.GH):
                        continue
                    b = tx * nav.GH + ty
                    if not grid[b]:
                        continue
                    if dx and dy:
                        explicit = flags[a] & (4 if dy > 0 else 8)
                        dry_detour = False
                        opened = bool(explicit)
                        for mx, my in ((tx, y), (x, ty)):
                            if orthogonal(x, y, mx, my) and orthogonal(mx, my, tx, ty):
                                opened = True
                                dry_detour |= grid[mx * nav.GH + my] != 2
                        if opened and not explicit and not dry_detour and grid[a] != 2 and grid[b] != 2:
                            nav.WET_STEPS[k].add((a, b))
                            nav.WET_STEPS[nav.cluster_of_cell(b)].add((b, a))
                    else:
                        opened = orthogonal(x, y, tx, ty)
                    if opened:
                        masks[a] |= 1 << d
                        masks[b] |= 1 << (d ^ (3 if d >= 4 else 1))
    return masks


def graph_rows(text):
    reader = Columns(text)
    rows = [(reader.take(3), reader.take(), reader.take(2), reader.take()) for _ in range(reader.take(2))]
    edges = []
    for _, _, _, degree in rows:
        edges.append(
            [
                (reader.take(), reader.take(2), reader.take(3), reader.take(3), reader.take(3), reader.take(2))
                for _ in range(degree)
            ]
        )
    reader.done()
    return rows, edges


def border_moves(grid, masks, graphs):
    decoded = {k: graph_rows(text) for k, text in graphs.items()}
    nodes = {k: [surface(grid, cell_of(k, row[0]), row[1], 0) for row in rows] for k, (rows, _) in decoded.items()}
    # Format 5 writes a neutral price on every edge. Its maximum value is saturation, not an absent price.
    counts = Counter(seen=0, already_made=0, kept=0, faction_only=0)
    for k, (_, rows) in decoded.items():
        for start, edges in zip(nodes[k], rows, strict=True):
            for offset, index, _, _, neutral, _ in edges:
                if offset == 4:
                    continue
                counts["seen"] += 1
                target = k + (offset // 3 - 1) * nav.NY + offset % 3 - 1
                end = nodes[target][index]
                if start is None or end is None:
                    raise ValueError(f"Missing border entrance: {k} -> {target}")
                sx, sy = divmod(nav.cell_of(start), nav.GH)
                ex, ey = divmod(nav.cell_of(end), nav.GH)
                direction = nav.DIRS.get((ex - sx, ey - sy))
                base = start < len(grid) and end < len(grid) and direction is not None
                if end in nav.LINKS.get(start, ()) or (base and masks[start] & (1 << direction)):
                    counts["already_made"] += 1
                else:
                    counts["kept"] += 1
                    nav.LINKS[start][end] = neutral
    return counts


def collision(map_id, meta, fields):
    geometry(map_id, meta)
    grid, flags = bytearray(nav.GW * nav.GH), bytearray(nav.GW * nav.GH)
    for k, text in fields["grid"].items():
        height_grid(grid, flags, k, text, fields["height"][k])
    floors = {k: floor_columns(text) for k, text in sorted(fields["floor"].items())}
    for k, rows in floors.items():
        add_floors(k, rows[0])
    for k, rows in floors.items():
        floor_moves(grid, k, rows)
    masks = base_masks(grid, flags, fields["grid"])
    arcs = Counter()
    for k, text in fields["arc"].items():
        for start, end, cost in arc_columns(text):
            u, v = node_of(k, start), node_of(k, end)
            arcs["seen"] += 1
            if v in nav.LINKS[u] and nav.LINKS[u][v] is None:
                nav.PARALLEL_LINKS[u][v] = cost / 4
                arcs["parallel_to_floor_step"] += 1
            else:
                nav.LINKS[u][v] = cost / 4
    crossings = border_moves(grid, masks, fields["graph"])
    ratio = 1.0
    for node in sorted(nav.LINKS):
        nav.LINKED_OF[nav.cluster_of_cell(node)].append(node)
        x, y = divmod(nav.cell_of(node), nav.GH)
        for target, cost in nav.outgoing_links(node):
            if cost is None:
                continue
            tx, ty = divmod(nav.cell_of(target), nav.GH)
            major, minor = sorted((abs(tx - x), abs(ty - y)), reverse=True)
            if major:
                length = (major + (math.sqrt(2) - 1) * minor) * nav.CS
                ratio = min(ratio, cost / length)
    nav.MIN_STEP_RATIO = math.floor(ratio * 1_000_000) / 1_000_000
    return grid, masks, arcs, crossings


def terrain_fields(map_id, meta, directory):
    # Terrain exceptions distinguish a walkable floor from the ground when they share a cell.
    for k in nav.FLOORS_OF:
        x, y = divmod(k, meta["ny"])
        row, col = 31 - meta["cx0"] - x, 31 - meta["cy0"] - y
        nav.TERRAIN[k] = sample_cluster(directory, map_id, row, col, meta["cells"], nav.ZQ)


def convert(map_id, meta, fields, output, road_cells, jobs, terrain):
    grid, masks, arcs, crossings = collision(map_id, meta, fields)
    print(f"map {map_id}: arcs {dict(arcs)}, crossings {dict(crossings)}", flush=True)
    nav.ROAD_CELLS = nav.read_roads(map_id, road_cells)
    nodes, edges = nav.grid_hpa(grid, masks, jobs)
    if terrain is not None:
        terrain_fields(map_id, meta, terrain)
    nav.emit(nodes, edges, grid, masks, output, MAP_NAMES[map_id])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path, help="sparse checkout at the revision in tools/polestar-nav.json")
    parser.add_argument("output", type=Path, help="scratch directory for source maps and packed bundle")
    parser.add_argument("--map", type=int, choices=MAPS)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--road-cells", type=Path, help="RoadCells.lua generated for these map layouts")
    parser.add_argument(
        "--terrain",
        nargs=2,
        metavar=("MAP", "DIRECTORY"),
        action="append",
        default=[],
        help="use existing TrinityCore terrain extracts for a map's ground surface",
    )
    parser.add_argument("--offline", action="store_true", help="require cached terrain textures for road generation")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    terrains = {}
    for key, path in args.terrain:
        if key not in {str(map_id) for map_id in MAPS} or not Path(path).is_dir():
            parser.error(f"Invalid terrain map or directory: {key} {path}")
        terrains[int(key)] = Path(path)
    inputs = pinned_inputs(args.checkout)
    selected = (args.map,) if args.map is not None else MAPS
    maps = {map_id: read_map(inputs, map_id) for map_id in (selected if args.road_cells else MAPS)}
    args.output.mkdir(parents=True, exist_ok=True)
    road_cells = args.road_cells or args.output / "RoadCells.lua"
    if args.road_cells is None:
        road_cells.write_text(generate_roads({map_id: meta for map_id, (meta, _) in maps.items()}, args.offline))
    if not road_cells.is_file():
        parser.error(f"Missing road cell data: {road_cells}")
    sources = []
    for map_id in selected:
        meta, fields = maps[map_id]
        print(f"map {map_id}: {meta}", flush=True)
        output = args.output / f"Nav{map_id}.lua"
        convert(map_id, meta, fields, output, road_cells, args.jobs, terrains.get(map_id))
        sources.append(output)
    write_bundle(args.output, sources)


if __name__ == "__main__":
    main()
