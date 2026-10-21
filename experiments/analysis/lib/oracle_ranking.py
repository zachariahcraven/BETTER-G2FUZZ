#!/usr/bin/env python3
"""Oracle ranking for the B4 ceiling experiment (see the task spec)."""
import sys
import json
import os

# Add project root to path to import g2fuzz
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../")))
from g2fuzz.py_utils.scheduler import credit

def main():
    if len(sys.argv) < 2:
        print("Usage: %s <POOL_OUT_DIR>" % sys.argv[0], file=sys.stderr)
        sys.exit(1)

    pool_out_dir = sys.argv[1]
    creds = credit(pool_out_dir)

    if not creds:
        print("No generators found in credit()", file=sys.stderr)
        sys.exit(1)

    # Sort: finds (desc), productive (desc), seeds (desc), name (asc)
    sorted_gens = sorted(
        creds.keys(),
        key=lambda g: (-creds[g]['finds'], -creds[g]['productive'], -creds[g]['seeds'], g)
    )

    print(json.dumps(sorted_gens))

if __name__ == "__main__":
    main()
