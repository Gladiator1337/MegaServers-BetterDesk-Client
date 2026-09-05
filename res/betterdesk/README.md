# BetterDesk `custom.txt` signing

Used by the official desktop client and (later) the web panel **Client Generator**.

## Files

| File | Purpose |
|------|---------|
| `custom-client-signing.pub` | NaCl/Ed25519 public key embedded in the client (`read_custom_client`) |
| `custom-client-signing.seed` | **Private** 32-byte seed (base64). Create with the script; do not publish |

## Generate keys

```bash
python scripts/generate_custom_client_signing_key.py
```

Requires `pynacl`. After generation, rebuild the client so `include_str!` picks up the new `.pub`.

## `custom.txt` formats

1. **Plain JSON** (Generator Phase A / lab) — file starts with `{`:

```json
{
  "app-name": "BetterDesk",
  "default-settings": {
    "custom-rendezvous-server": "desk.example.com",
    "relay-server": "desk.example.com",
    "api-server": "http://desk.example.com:21114",
    "key": "<id_ed25519.pub>"
  }
}
```

2. **Signed blob** (Generator Phase B+) — base64(NaCl-sign(JSON)), verified with `.pub`.

Server options belong under `default-settings` (user can change) or `override-settings` (locked for fleet builds).

See [docs/OFFICIAL_CLIENT.md](../../docs/OFFICIAL_CLIENT.md).
