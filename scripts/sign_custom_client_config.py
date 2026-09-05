#!/usr/bin/env python3
"""Sign a BetterDesk custom-client JSON for custom.txt (Generator bake-in).

Usage:
  python scripts/sign_custom_client_config.py path/to/config.json > custom.txt

Reads seed from res/betterdesk/custom-client-signing.seed
Requires: pip install pynacl
"""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_file", type=Path)
    parser.add_argument(
        "--seed",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "res"
        / "betterdesk"
        / "custom-client-signing.seed",
    )
    args = parser.parse_args()

    try:
        from nacl.signing import SigningKey
    except ImportError:
        print("Install PyNaCl: pip install pynacl", file=sys.stderr)
        return 1

    if not args.seed.is_file() or not args.seed.read_text(encoding="utf-8").strip():
        print(
            f"Missing signing seed at {args.seed}. Run generate_custom_client_signing_key.py first.",
            file=sys.stderr,
        )
        return 1

    seed = base64.b64decode(args.seed.read_text(encoding="utf-8").strip())
    sk = SigningKey(seed)
    raw = args.json_file.read_bytes()
    # sodiumoxide sign::verify expects signature || message
    signed_msg = sk.sign(raw)
    out = base64.b64encode(signed_msg.signature + signed_msg.message).decode("ascii")
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
