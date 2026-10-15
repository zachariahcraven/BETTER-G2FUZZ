#!/usr/bin/env python3
"""Draw a Doom map from a WAD file as a PNG (overhead view)."""

import argparse
import re
import struct
import sys
import os
from PIL import Image


def read_wad(filepath):
    """Read a WAD file and return its header info and directory entries."""
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
    except (IOError, OSError) as e:
        print(f"wad_map: error: cannot read file: {e}", file=sys.stderr)
        sys.exit(2)

    if len(data) < 12:
        print("wad_map: error: file too small for WAD header", file=sys.stderr)
        sys.exit(2)

    magic = data[0:4]
    if magic not in (b"IWAD", b"PWAD"):
        print("wad_map: error: invalid WAD magic", file=sys.stderr)
        sys.exit(2)

    num_lumps, dir_offset = struct.unpack("<ii", data[4:12])

    # Each directory entry takes 16 bytes of the file, so a valid count is bounded by the file size
    if num_lumps < 0 or num_lumps > len(data) // 16:
        print("wad_map: error: absurd number of lumps (%d)" % num_lumps, file=sys.stderr)
        sys.exit(2)
    
    # Check if directory fits in file
    if dir_offset < 12:
        print("wad_map: error: directory offset too small", file=sys.stderr)
        sys.exit(2)
    
    # Check if directory entries fit in file
    if num_lumps > 0:
        dir_size = num_lumps * 16
        if dir_offset + dir_size > len(data):
            print("wad_map: error: directory out of range", file=sys.stderr)
            sys.exit(2)
    
    # Parse directory entries
    entries = []
    for i in range(num_lumps):
        offset = dir_offset + i * 16
        if offset + 16 > len(data):
            print("wad_map: error: directory entry out of range", file=sys.stderr)
            sys.exit(2)
        
        file_offset, size, name = struct.unpack("<ii8s", data[offset:offset+16])
        name = name.rstrip(b'\x00').decode('ascii', errors='replace')
        entries.append({
            'offset': file_offset,
            'size': size,
            'name': name
        })
    
    return data, entries


def find_map(data, entries, map_name):
    """Find a map by name and return its lumps."""
    # Find the map marker
    map_marker = None
    for i, entry in enumerate(entries):
        if entry['name'] == map_name:
            map_marker = i
            break
    
    if map_marker is None:
        print(f"wad_map: error: map '{map_name}' not found in WAD", file=sys.stderr)
        sys.exit(2)
    
    # Map lumps we care about
    map_lump_names = {'THINGS', 'LINEDEFS', 'SIDEDEFS', 'VERTEXES', 'SEGS', 
                      'SSECTORS', 'NODES', 'SECTORS', 'REJECT', 'BLOCKMAP'}
    
    # Collect lumps belonging to this map
    map_entries = []
    for i in range(map_marker + 1, len(entries)):
        if entries[i]['name'] in map_lump_names:
            map_entries.append(entries[i])
        else:
            # Found a non-map lump, stop
            break
    
    return map_entries


def parse_lumps(data, map_entries):
    """Parse the relevant lumps from a map."""
    lumps = {}
    
    for entry in map_entries:
        name = entry['name']
        offset = entry['offset']
        size = entry['size']
        
        if offset + size > len(data):
            continue  # Skip malformed entries
        
        lump_data = data[offset:offset + size]
        lumps[name] = lump_data
    
    return lumps


def parse_vertices(lump_data):
    """Parse VERTEXES lump."""
    vertices = []
    for i in range(0, len(lump_data), 4):
        x, y = struct.unpack("<hh", lump_data[i:i+4])
        vertices.append((x, y))
    return vertices


def parse_linedefs(lump_data):
    """Parse LINEDEFS lump."""
    linedefs = []
    for i in range(0, len(lump_data), 14):
        start, end, flags, special, tag, right_side, left_side = struct.unpack("<HHHHHHH", lump_data[i:i+14])
        one_sided = (left_side == 0xFFFF)
        linedefs.append({
            'start': start,
            'end': end,
            'flags': flags,
            'special': special,
            'right_side': right_side,
            'left_side': left_side,
            'one_sided': one_sided
        })
    return linedefs


def parse_things(lump_data):
    """Parse THINGS lump."""
    things = []
    for i in range(0, len(lump_data), 10):
        x, y, angle, thing_type, flags = struct.unpack("<hhhhh", lump_data[i:i+10])
        things.append({'x': x, 'y': y, 'angle': angle, 'type': thing_type, 'flags': flags})
    return things


def draw_map(vertices, linedefs, things, size=1024):
    """Draw the map as a PNG image."""
    # Filter vertices that are actually used by linedefs
    used_vertices = set()
    for linedef in linedefs:
        used_vertices.add(linedef['start'])
        used_vertices.add(linedef['end'])
    
    # Get bounds of used vertices
    if not used_vertices:
        return None
    
    xs = [vertices[i][0] for i in used_vertices if i < len(vertices)]
    ys = [vertices[i][1] for i in used_vertices if i < len(vertices)]
    
    if not xs:
        return None
    
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    
    # Add small margin
    margin = 10
    min_x -= margin
    max_x += margin
    min_y -= margin
    max_y += margin
    
    width = max_x - min_x
    height = max_y - min_y
    
    if width <= 0 or height <= 0:
        return None
    
    # Determine scale to fit size
    if width > height:
        scale = size / width
        img_width = size
        img_height = int(height * scale)
    else:
        scale = size / height
        img_height = size
        img_width = int(width * scale)
    
    # Create image with dark background
    img = Image.new('RGB', (img_width, img_height), (30, 30, 30))
    pixels = img.load()
    
    # Colors
    COLOR_ONE_SIDED = (255, 255, 255)  # Bright white
    COLOR_TWO_SIDED = (128, 128, 128)  # Dim gray
    COLOR_SPECIAL = (255, 255, 0)      # Yellow for special lines
    
    # Draw lines
    warnings = []
    warning_count = 0
    
    for linedef in linedefs:
        start_idx = linedef['start']
        end_idx = linedef['end']
        
        if start_idx >= len(vertices) or end_idx >= len(vertices):
            if warning_count == 0:
                warnings.append(f"skipping line with missing vertex")
            warning_count += 1
            continue
        
        x1, y1 = vertices[start_idx]
        x2, y2 = vertices[end_idx]
        
        # Transform coordinates to image space
        # Doom's y points up, image y points down
        x1_img = int((x1 - min_x) * scale)
        y1_img = int(img_height - 1 - (y1 - min_y) * scale)
        x2_img = int((x2 - min_x) * scale)
        y2_img = int(img_height - 1 - (y2 - min_y) * scale)
        
        # Determine color
        if linedef['special'] != 0:
            color = COLOR_SPECIAL
        elif linedef['one_sided']:
            color = COLOR_ONE_SIDED
        else:
            color = COLOR_TWO_SIDED
        
        # Draw line using simple Bresenham-like approach
        dx = abs(x2_img - x1_img)
        dy = abs(y2_img - y1_img)
        sx = 1 if x1_img < x2_img else -1
        sy = 1 if y1_img < y2_img else -1
        err = dx - dy
        
        x, y = x1_img, y1_img
        while True:
            if 0 <= x < img_width and 0 <= y < img_height:
                pixels[x, y] = color
            if x == x2_img and y == y2_img:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy
    
    # Draw things
    for thing in things:
        if thing['type'] >= len(vertices):
            continue
        
        x, y = thing['x'], thing['y']
        x_img = int((x - min_x) * scale)
        y_img = int(img_height - 1 - (y - min_y) * scale)
        
        if 0 <= x_img < img_width and 0 <= y_img < img_height:
            if 1 <= thing['type'] <= 4:
                color = (0, 255, 0)  # Green for player starts
            else:
                color = (100, 100, 100)  # Grey for others
            
            # Draw small dot
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    nx, ny = x_img + dx, y_img + dy
                    if 0 <= nx < img_width and 0 <= ny < img_height:
                        pixels[nx, ny] = color
    
    return img, warnings


def main():
    parser = argparse.ArgumentParser(description='Draw a Doom map from a WAD file')
    parser.add_argument('wad', help='WAD file path')
    parser.add_argument('map', nargs='?', help='Map name (e.g., MAP01, E1M1)')
    parser.add_argument('-o', '--output', help='Output PNG file')
    parser.add_argument('--size', type=int, default=1024, help='Image size on longer side')
    parser.add_argument('--list', action='store_true', help='List map names')
    
    args = parser.parse_args()
    
    # --list mode
    if args.list:
        try:
            data, entries = read_wad(args.wad)
            
            # Find maps: ExMy / MAPxx markers whose map lumps include LINEDEFS
            map_lump_names = {'THINGS', 'LINEDEFS', 'SIDEDEFS', 'VERTEXES', 'SEGS',
                              'SSECTORS', 'NODES', 'SECTORS', 'REJECT', 'BLOCKMAP'}
            map_names = []
            for i, entry in enumerate(entries):
                name = entry['name']
                if not re.fullmatch(r'E\dM\d|MAP\d\d', name):
                    continue
                j = i + 1
                while j < len(entries) and entries[j]['name'] in map_lump_names:
                    if entries[j]['name'] == 'LINEDEFS':
                        map_names.append(name)
                        break
                    j += 1
            
            for name in map_names:
                print(name)
        except SystemExit:
            raise
        except Exception as e:
            print(f"wad_map: error: {e}", file=sys.stderr)
            sys.exit(2)
        return
    
    # Drawing mode
    if not args.map:
        print("wad_map: error: map name required (use --list to see available maps)", file=sys.stderr)
        sys.exit(2)
    
    try:
        data, entries = read_wad(args.wad)
        map_entries = find_map(data, entries, args.map)
        lumps = parse_lumps(data, map_entries)
        
        if 'VERTEXES' not in lumps or 'LINEDEFS' not in lumps:
            print("wad_map: error: map missing required lumps", file=sys.stderr)
            sys.exit(2)
        
        vertices = parse_vertices(lumps['VERTEXES'])
        linedefs = parse_linedefs(lumps['LINEDEFS'])
        things = parse_things(lumps.get('THINGS', b'')) if 'THINGS' in lumps else []
        
        if not linedefs:
            print("wad_map: error: map has no lines to draw", file=sys.stderr)
            sys.exit(2)
        
        result = draw_map(vertices, linedefs, things, args.size)
        
        if result is None:
            print("wad_map: error: map has no drawable lines", file=sys.stderr)
            sys.exit(2)
        
        img, warnings = result
        
        # Print warnings
        for warning in warnings:
            print(f"wad_map: warning: {warning}", file=sys.stderr)
        
        # Determine output filename
        output = args.output
        if output is None:
            output = args.map + '.png'
        
        img.save(output)
        
    except SystemExit:
        raise
    except Exception as e:
        print(f"wad_map: error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
