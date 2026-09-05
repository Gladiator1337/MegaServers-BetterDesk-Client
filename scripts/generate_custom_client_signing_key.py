#!/usr/bin/env python3
"""Generate BetterDesk NaCl/Ed25519 keys for signed custom.txt (Client Generator).

Writes:
  res/betterdesk/custom-client-signing.pub
  res/betterdesk/custom-client-signing.seed  (private — keep secret)

Requires: pip install pynacl
"""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "res" / "betterdesk",
    )
    args = parser.parse_args()

    try:
        from nacl.signing import SigningKey
    except ImportError:
        print("Install PyNaCl: pip install pynacl", file=sys.stderr)
        return 1

    sk = SigningKey.generate()
    pub_b64 = base64.b64encode(bytes(sk.verify_key)).decode("ascii")
    seed_b64 = base64.b64encode(bytes(sk)).decode("ascii")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    pub_path = args.out_dir / "custom-client-signing.pub"
    seed_path = args.out_dir / "custom-client-signing.seed"
    pub_path.write_text(pub_b64 + "\n", encoding="utf-8")
    seed_path.write_text(seed_b64 + "\n", encoding="utf-8")

    print(f"Wrote {pub_path}")
    print(f"Wrote {seed_path} (private — for panel Generator only)")
    print("Rebuild the desktop client after updating the public key.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
