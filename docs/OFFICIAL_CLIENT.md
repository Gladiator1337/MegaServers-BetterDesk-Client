# Oficjalny klient BetterDesk (desktop)

Ten fork ([BetterDesk-Client](../)) jest **oficjalnym klientem desktop BetterDesk**:

1. **Nie łączy się** z publiczną infrastrukturą rustdesk.com.
2. Użytkownik **wpisuje** ID / Relay / API / Key (Settings → Network) lub importuje deploy string z panelu.
3. Klient **identyfikuje się** wobec API jako `betterdesk-desktop`.
4. Mechanizmy bake-in (`custom.txt`, MSI template, deploy string) są zachowane pod przyszły **Client Generator** w panelu web.

## Kill public cloud

| Warstwa | Zachowanie |
|---------|------------|
| `RENDEZVOUS_SERVERS` | puste — brak `rs-ny.rustdesk.com` |
| `get_api_server_` | pusty string zamiast `admin.rustdesk.com` |
| `get_key` | brak fallbacku do publicznego `RS_PUB_KEY` |
| Update check | URL pusty — nie woła `api.rustdesk.com` |
| Connect `id@public` | zablokowane / ignorowane |

Bez skonfigurowanego serwera klient **nie rejestruje się** na publicznym cloudu. Status bar pokazuje tip → otwiera Settings → Network.

## Ręczna konfiguracja (produkt codzienny)

1. Panel BetterDesk → Dashboard → **RustDesk Client Configuration**.
2. W kliencie: Settings → Network → ID / Relay / API / Key (lub **Import** deploy string).
3. API: `http://<host>:21114` (native) lub `:21121` (Docker AIO); klucz = `id_ed25519.pub`.

Deploy string = `reverse(base64({host,relay,api,key}))` — ten sam format co stock RustDesk / Dashboard.

## Identyfikacja klienta

`get_sysinfo()` wysyła m.in.:

- `app_name` — `BetterDesk Client` (lub z `custom.txt`)
- exe / proces — `betterdesk` (`betterdesk.exe` na Windows)
- `client` / `client_product` — `betterdesk-desktop` (`BETTERDESK_CLIENT_PRODUCT`)
- `license` — `AGPL-3.0-only`
- `upstream_project` / `upstream_repo` — RustDesk + `https://github.com/rustdesk/rustdesk`
- `source_repo` — `https://github.com/UNITRONIX/BetterDesk-Client`

Helper HTTP: [`src/hbbs_http/betterdesk.rs`](../src/hbbs_http/betterdesk.rs) (`/api/health`, `/api/branding`, `/api/server-key`).

## Attribution / licencja (AGPL-3.0)

BetterDesk Client **jest forkiem klienta RustDesk**. W Settings → About oraz w sysinfo:

- licencja **AGPL-3.0** (plik `LICENSE` w repo)
- link do **kodu źródłowego forka** (`BetterDesk-Client`)
- link do **upstream** (`rustdesk/rustdesk`)
- copyright UNITRONIX + oryginalnych autorów RustDesk / Purslane

Stałe: `UPSTREAM_*` / `FORK_REPO_URL` / `LICENSE_*` w [`libs/hbb_common/src/config.rs`](../libs/hbb_common/src/config.rs) oraz [`flutter/lib/consts.dart`](../flutter/lib/consts.dart).

## Bake-in pod Generator (panel)

| Mechanizm | Rola |
|-----------|------|
| **Plain JSON `custom.txt`** | Phase A — plik zaczyna się od `{`; `default-settings` / `override-settings` |
| **Signed `custom.txt`** | Phase B — base64(NaCl-sign(JSON)); pubkey w `res/betterdesk/custom-client-signing.pub` |
| **MSI template** | [`res/msi/preprocess.py`](../res/msi/preprocess.py) — cab2 z `custom.txt` + branding |
| **Deploy string** | Dashboard / Import — bez przebudowy binarki |
| **Exe license** | `host=`,`key=`,`api=`,`relay=` w nazwie pliku (portable) |

### Generowanie kluczy podpisujących

```bash
python scripts/generate_custom_client_signing_key.py
python scripts/sign_custom_client_config.py examples/betterdesk-custom.example.json > custom.txt
```

Seed (`*.seed`) jest prywatny — trafia do panelu Generatora (jak Support Agent `bundleSigningKey`), **nie** do publicznych mirrorów.

### Przykład `default-settings` (user może zmienić Network)

```json
{
  "app-name": "BetterDesk Client",
  "default-settings": {
    "custom-rendezvous-server": "desk.example.com",
    "relay-server": "desk.example.com",
    "api-server": "http://desk.example.com:21114",
    "key": "<id_ed25519.pub contents>"
  }
}
```

Fleet lock: te same pola w `override-settings` (+ opcjonalnie `hide-server-settings`).

### vs Support Agent Generator

Panel dziś buduje **Support Agent** (CDAP, `branding.json`). Oficjalny desktop używa **RustDesk protocol** + `custom.txt`. Docelowy `product_type: betterdesk-desktop` w panelu powinien reuse’ować `keyService` / `clientConfigHost` i produkować signed `custom.txt` + MSI template — nie `branding.json`.

## Pliki kluczowe

| Temat | Ścieżka |
|-------|--------|
| Defaults / kill public | `libs/hbb_common/src/config.rs` |
| API / key / custom.txt | `src/common.rs` |
| BetterDesk HTTP | `src/hbbs_http/betterdesk.rs` |
| Signing keys | `res/betterdesk/` |
| Scripts | `scripts/generate_custom_client_signing_key.py`, `sign_custom_client_config.py` |
| Łączność | [CONNECTIVITY.md](CONNECTIVITY.md) |
