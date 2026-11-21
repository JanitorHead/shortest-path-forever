"""Rebuild HPA graphs from format 3 or 4 grids, without extracting or rasterizing terrain.

The collision fields remain byte-identical. Their original generator is retained in the header; the graph names
its own recipe and the hash of the fields it consumed. Use only for graph changes, never geometry changes.
"""

import argparse
import hashlib
import json
import re
from array import array
from collections import defaultdict
from pathlib import Path

from baker import gen_nav as nav
from baker.inputs import generator_bytes, generator_digest, generator_files
from forever_tools.fsio import atomic_write
from pack_nav import FIELDS, SECTION, read_map, read_packed

COMPATIBILITY = Path(__file__).with_name("baker") / "graph_compatibility.json"


def collision_compatible(original, current):
    """A graph-only edit needs an explicit reviewed compatibility declaration for the exact producer versions.

    Any later generator edit invalidates the declaration, including a geometry edit. A fresh full bake already
    has the current generator and needs no migration declaration.
    """
    compatibility = json.loads(COMPATIBILITY.read_text())
    return original == current or (
        compatibility["schema"] == 1
        and compatibility["generator"] == current
        and original in compatibility["collision_generators"]
    )


class Reader:
    def __init__(self, text):
        self.values = [nav.B64.index(c) for c in text]
        self.pos = 0

    def take(self, width=1):
        value = 0
        for _ in range(width):
            value = value * 64 + self.values[self.pos]
            self.pos += 1
        return value

    def delta(self):
        value = self.take()
        return value if value < 63 else 63 + self.take(3)


def decode(source, fields, map_id):
    """Restore the generator's grid, stored heights and directed links from the documented collision fields."""

    def number(name):
        match = re.search(rf"\t{name} = (-?\d+),", source)
        if match is None:
            raise ValueError(f"Missing navigation metadata: {name}")
        return int(match[1])

    fmt = number("format")
    if fmt not in (3, 4) or (fmt == 3 and "\tsteep = true," not in source):
        raise ValueError("Graph refresh requires format 3 with stored steep heights or format 4")
    nav.MAP, nav.CELLS = map_id, number("cells")
    nav.CX0, nav.CY0 = number("cx0"), number("cy0")
    nav.NX, nav.NY = number("nx"), number("ny")
    nav.GW, nav.GH = nav.NX * nav.CELLS, nav.NY * nav.CELLS
    nav.CS, nav.ZQ = nav.T / nav.CELLS, number("zstep")
    if min(nav.NX, nav.NY, nav.CELLS, nav.ZQ) <= 0:
        raise ValueError("Navigation dimensions and height step must be positive")
    if set(fields["grid"]) != set(fields["height"]) or not set(fields["floor"]) <= set(fields["grid"]):
        raise ValueError("Navigation collision field inventories disagree")
    weight = re.search(r"\tswim = ([\d.]+),", source)
    if weight is None:
        raise ValueError("Missing navigation metadata: swim")
    swim = float(weight[1])
    if swim != nav.SWIM:
        raise ValueError("Stored water weight differs from the generator")
    size, c = nav.GW * nav.GH, nav.CELLS
    grid = bytearray(size)
    cuts = bytearray(size) if fmt == 4 else set()
    nav.BASE_Z = array("f", [0]) * size
    nav.FLOOR_CELL, nav.FLOOR_Z = array("i"), array("f")
    nav.FLOOR_VAL, nav.FLOOR_LAYER = bytearray(), bytearray()
    nav.FLOORS_OF, nav.FLOORS_AT = defaultdict(list), {}
    nav.LINKS, nav.LINKED_OF, nav.FREE = defaultdict(dict), defaultdict(list), set()
    nav.TERRAIN = {}
    nav.WET_STEPS = defaultdict(set)

    def global_cell(k, local):
        return (k // nav.NY * c + local // c) * nav.GH + k % nav.NY * c + local % c

    def global_node(k, local):
        return global_cell(k, local) if local < c * c else nav.FLOORS_OF[k][local - c * c]

    pending, wet = [], []
    directions = dict(sorted((d, xy) for xy, d in nav.DIRS.items()))

    def read_mask(reader, node, mask):
        for d, (dx, dy) in directions.items():
            if not mask & (1 << d):
                continue
            if fmt == 3:
                pending.append((node, dx, dy, reader.take(), None, True, False))
            else:
                layers = reader.take()
                selected = (
                    [layer for layer in range(6) if layers & (1 << layer)]
                    if layers
                    else [reader.take() for _ in range(reader.take(2))]
                )
                pending.extend((node, dx, dy, layer, None, False, False) for layer in selected)

    for key, text in sorted(fields["grid"].items()):
        k = key - 1
        if not 0 <= k < nav.NX * nav.NY:
            raise ValueError(f"Navigation cluster outside map: {key}")
        values = []
        reader = Reader(text)
        palette = [reader.take(2) for _ in range(reader.take())] if fmt == 4 else []
        while reader.pos < len(reader.values):
            value = reader.take()
            if value >= 48:
                values.extend([values[-1]] * (value - 47))
            else:
                values.append((reader.take(2) if value == 47 else palette[value]) if fmt == 4 else value)
        assert len(values) == c * c
        heights, last, repeat, delta = {}, 0, 0, 0
        reader = Reader(fields["height"][key])
        for local, value in enumerate(values):
            node = global_cell(k, local)
            if isinstance(cuts, bytearray):
                kind, cuts[node] = divmod(value, 256)
            else:
                kind, flags = divmod(value, 16)
                if kind == 1 and flags & 8:
                    kind, flags = 3, flags & ~8
                for d in range(4):
                    if flags & (1 << d):
                        cuts.add(node * 4 + d)
            grid[node] = kind
            if kind:
                pred = heights.get(local - 1) if local % c else None
                if pred is None:
                    pred = heights.get(local - c, last)
                if repeat:
                    repeat, z = repeat - 1, pred + delta
                else:
                    symbol = reader.take()
                    if symbol == 47:
                        z = reader.take(2) - 2048
                    else:
                        delta, z = symbol - 23, pred + symbol - 23
                        while reader.pos < len(reader.values) and reader.values[reader.pos] >= 48:
                            repeat += reader.take() - 47
                heights[local] = last = z
                nav.BASE_Z[node] = z * nav.ZQ
        assert reader.pos == len(reader.values)
        if key not in fields["floor"]:
            continue
        reader = Reader(fields["floor"][key])
        local, masks = 0, []
        for _ in range(reader.take(3)):
            local += reader.delta()
            node = size + len(nav.FLOOR_CELL)
            cell = global_cell(k, local)
            nav.FLOOR_CELL.append(cell)
            nav.FLOOR_VAL.append(reader.take())
            nav.FLOOR_Z.append(reader.take(2) - 2048)
            floors = nav.FLOORS_AT.setdefault(cell, [])
            floors.append(node)
            nav.FLOOR_LAYER.append(len(floors))
            nav.FLOORS_OF[k].append(node)
            mask = reader.take(2)
            if fmt == 4:
                masks.append((node, mask))
            else:
                read_mask(reader, node, mask)
        local = 0
        if fmt == 4:
            for _ in range(reader.take(3)):
                local += reader.delta()
                masks.append((global_node(k, local), reader.take(2)))
            for node, mask in masks:
                read_mask(reader, node, mask)
        else:
            for _ in range(reader.take(3)):
                local += reader.delta()
                kind, layer = reader.take(), reader.take()
                pending.append((global_node(k, local), *directions[kind % 8], layer, None, kind % 16 < 8, kind >= 16))
        for _ in range(reader.take(3)):
            local, dx, dy, layer, cost = (
                reader.take(3),
                reader.take() - 8,
                reader.take() - 8,
                reader.take(),
                reader.take(2),
            )
            pending.append((global_node(k, local), dx, dy, layer, cost, False, False))
        local = 0
        if fmt == 4:
            while reader.pos < len(reader.values):
                local += reader.delta()
                wet.append((global_node(k, local), *directions[reader.take()], reader.take()))
        assert reader.pos == len(reader.values)

    def landing(node, dx, dy, layer):
        x, y = divmod(nav.cell_of(node), nav.GH)
        if not (0 <= x + dx < nav.GW and 0 <= y + dy < nav.GH):
            raise ValueError("Navigation link lands outside map")
        target = (x + dx) * nav.GH + y + dy
        return nav.FLOORS_AT[target][layer - 1] if layer else target

    for node, dx, dy, layer, cost, both, free in pending:
        target = landing(node, dx, dy, layer)
        nav.LINKS[node][target] = cost
        if free:
            nav.FREE.add((node, target))
        if both:
            nav.LINKS[target][node] = cost
            if free:
                nav.FREE.add((target, node))
    for node, dx, dy, layer in wet:
        nav.WET_STEPS[nav.cluster_of_cell(node)].add((node, landing(node, dx, dy, layer)))
    for node in sorted(nav.LINKS):
        nav.LINKED_OF[nav.cluster_of_cell(node)].append(node)
    nav.ROAD_CELLS = nav.read_roads(map_id)
    return grid, cuts


def collision_digest(fields):
    digest = hashlib.sha256()
    for field in FIELDS[1:]:
        for key, text in sorted(fields[field].items()):
            digest.update(f"{field}:{key}:".encode() + text.encode() + b"\0")
    return digest.hexdigest()


def refresh_digest(root=nav.ROOT):
    """Everything that interprets the saved fields or selects/costs entrances, including the road input."""
    digest = hashlib.sha256()
    paths = [
        *generator_files(),
        COMPATIBILITY,
        Path(__file__),
        Path(__file__).with_name("pack_nav.py"),
        root / "Data" / "RoadCells.lua",
    ]
    for path in sorted(paths):
        digest.update(path.name.encode() + b"\0" + generator_bytes(path) + b"\0")
    return digest.hexdigest()


def graph_nodes(fields, degree_width=1, base_degree_width=0):
    """The existing graph's entrances, resolved against the unchanged floor order."""
    nodes = {}
    for key, text in fields["graph"].items():
        k, reader = key - 1, Reader(text)
        found = set()
        for _ in range(reader.take(2)):
            local, layer = reader.take(3), reader.take()
            x, y = divmod(local, nav.CELLS)
            cell = (k // nav.NY * nav.CELLS + x) * nav.GH + k % nav.NY * nav.CELLS + y
            found.add(nav.FLOORS_AT[cell][layer - 1] if layer else cell)
            reader.take(2)
            reader.take(degree_width + base_degree_width)
        nodes[k] = found
    return nodes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument(
        "--inspect", action="store_true", help="decode and count entrances, without intra-cluster searches"
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    match = re.fullmatch(r"Nav(\d+)\.lua", args.source.name)
    if match is None:
        parser.error("source must be named Nav<map>.lua")
    map_id = int(match[1])
    reader = read_packed if args.source.parent.name == "Nav" else read_map
    source, fields, _, _ = reader(args.source, map_id)
    original = re.search(r"-- Generator: (\w+)\.", source)
    if original is None or not collision_compatible(original[1], generator_digest()):
        raise ValueError("Collision producer changed without a reviewed graph-only compatibility declaration; rebake")
    grid, cuts = decode(source, fields, map_id)
    if args.inspect:
        nodes, edges = nav.grid_entrances(grid, cuts, args.jobs)
        print(f"{len(nodes)} clusters, {sum(map(len, nodes.values()))} entrances, {len(edges)} crossings", flush=True)
        width = re.search(r"\tdegreeWidth = (\d+),", source)
        base_width = re.search(r"\tbaseDegreeWidth = (\d+),", source)
        old = graph_nodes(fields, int(width[1]) if width else 1, int(base_width[1]) if base_width else 0)
        changed = [k for k in nodes.keys() | old.keys() if nodes.get(k, set()) != old.get(k, set())]
        print(f"changed clusters {len(changed)}, entrances {sum(len(nodes.get(k, ())) for k in changed)}", flush=True)
        return
    nodes, edges = nav.grid_hpa(grid, cuts, args.jobs)
    fields["graph"] = {k + 1: text for k, text in nav.encode_map(nodes, edges, grid, cuts, collision=False)[0].items()}
    source = source.replace("component(2) degree(1)", "component(2) degree(degreeWidth or 1)")
    source = re.sub(r"^\tbaseDegreeWidth = \d+,\n", "", source, flags=re.MULTILINE)
    source = source.replace("degree(degreeWidth or 1)]", "degree(degreeWidth or 1) baseDegree(baseDegreeWidth or 0)]")
    source = re.sub(r"^\tdegreeWidth = \d+,\n", "", source, flags=re.MULTILINE)
    source = re.sub(r"^\tformat = [34],$", r"\g<0>\n\tdegreeWidth = 2,\n\tbaseDegreeWidth = 2,", source, flags=re.M)
    source = re.sub(r"-- (?:Graph generator|Graph input): .*\n", "", source)
    source = source.replace(
        "-- Map ", f"-- Graph generator: {refresh_digest()}.\n-- Graph input: {collision_digest(fields)}.\n-- Map ", 1
    )
    source = SECTION.sub(lambda m: f"\t{m[1]} = {{}},\n" if m[1] in FIELDS else m[0], source)
    source = re.sub(r"^\t(?:packed|counts) = .*\n", "", source, flags=re.MULTILINE)
    for field in FIELDS:
        entries = "".join(f'\t\t[{key}] = "{text}",\n' for key, text in sorted(fields[field].items()))
        source = source.replace(f"\t{field} = {{}},\n", f"\t{field} = {{\n{entries}\t}},\n")
    atomic_write(args.output, source)
    print(f"map {map_id}: graph rebuilt; collision input {collision_digest(fields)}", flush=True)


if __name__ == "__main__":
    main()
