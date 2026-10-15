import struct
import sys

def load_wad_file(filename):
    """Load WAD file with endianness detection"""
    with open(filename, 'rb') as f:
        # Read header
        wad_type = f.read(4)
        num_lumps_bytes = f.read(4)
        directory_offset_bytes = f.read(4)
        endianness_indicator = f.read(4)
        
        # Detect endianness using the endianness indicator
        # "IDEN" in little-endian should be 0x4E454449 when read as big-endian
        # But we stored it as little-endian, so check if we can read it properly
        
        # Try to detect endianness by checking if the indicator makes sense
        # If "IDEN" is stored in little-endian, it's 0x4E454449 in memory
        # When read back as big-endian, it would be "IDEN"
        # We'll use a simple approach: try both endiannesses
        
        # First, try to interpret the indicator as a string
        try:
            indicator_str = endianness_indicator.decode('ascii')
            if indicator_str == "IDEN":
                # This indicates little-endian format was used
                endian = '<'
                print("Detected little-endian format")
            else:
                # Try to detect by checking if we get a reasonable number
                endian = '<'  # Default to little-endian
                print("Defaulting to little-endian format")
        except:
            endian = '<'  # Default to little-endian
            print("Defaulting to little-endian format")
        
        # Now read the rest of the header with detected endianness
        f.seek(4)  # Go back to num_lumps position
        num_lumps = struct.unpack(endian + 'I', f.read(4))[0]
        directory_offset = struct.unpack(endian + 'I', f.read(4))[0]
        
        print(f"WAD Type: {wad_type.decode('ascii')}")
        print(f"Number of lumps: {num_lumps}")
        print(f"Directory offset: {directory_offset}")
        
        # Read directory entries
        f.seek(directory_offset)
        for i in range(num_lumps):
            offset = struct.unpack(endian + 'I', f.read(4))[0]
            size = struct.unpack(endian + 'I', f.read(4))[0]
            lump_type = struct.unpack(endian + 'H', f.read(2))[0]
            compression = struct.unpack(endian + 'H', f.read(2))[0]
            name = f.read(8).rstrip(b'\x00').decode('ascii', errors='ignore')
            
            print(f"Lump {i+1}: {name}, offset={offset}, size={size}, type={lump_type}, compression={compression}")

# Load and display info about our WAD file
load_wad_file('./tmp/hierarchical_wad.wad')
