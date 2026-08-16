# Plán: Interaktivní meta-blok v čtečce — Add to contacts + Star address

## Cíl
V čtečce e-mailu bude možné interagovat s meta-blokem (odesílatel):
1. **Add to contact** — přidat odesílatele do adresáře (jméno = odesílatel, e-mail = adresa).
2. **Add address to star** — označit adresu jako "vždy hvězdička": všechny budoucí příchozí e-maily z této adresy se automaticky označí hvězdičkou.

## Současný stav
- Backend má `POST /api/contacts` (create_contact) — lze rovnou použít.
- Starring e-mailů existuje (`PATCH /api/emails/<id>` s `is_starred`).
- Neexistuje žádná tabulka pro "starred addresses" ani whitelist.
- Inbound e-maily se ukládají v `resend_service._process_inbound_email()`.

## Návrh

### 1. Nová tabulka `starred_addresses`
```sql
CREATE TABLE IF NOT EXISTS starred_addresses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    email TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, email),
    FOREIGN KEY(user_id) REFERENCES users(id)
);
```
- Migrace: `migrations/008_starred_addresses.sql`.

### 2. Nový API endpoint
- `POST /api/starred-addresses` — přidat adresu.
  - Body: `{"email": "..."}`
  - Vrátí `{"status": "added"}` nebo `{"status": "exists"}`.
- `DELETE /api/starred-addresses` — odebrat adresu.
  - Body: `{"email": "..."}`
  - Vrátí `{"status": "removed"}`.
- `GET /api/starred-addresses` — seznam všech starred adres.
  - Vrátí `{"addresses": ["a@b.cz", ...]}`.
- Lze přidat do `routes/contacts.py` nebo nového `routes/starred.py`. Doporučuji `contacts.py` pro jednoduchost.

### 3. Úprava inbound webhooku
- V `resend_service._process_inbound_email()`, po INSERT e-mailu, zkontrolovat `starred_addresses` pro `sender_email`. Pokud existuje, nastavit `is_starred = 1` v INSERTu.
- Nebo po INSERTu udělat UPDATE. Jednodušší: před INSERTem zkontrolovat a nastavit `is_starred`.

### 4. Service funkce
- `contact_service` nebo nový `starred_service`:
  - `add_starred_address(user_id, email)`
  - `remove_starred_address(user_id, email)`
  - `list_starred_addresses(user_id)`
  - `is_starred_address(user_id, email)` — rychlá kontrola pro webhook.
- Doporučuji přidat do `contact_service.py` pro minimalizování souborů.

### 5. UI — interaktivní meta-blok
- V `ui.js` `renderReader()` — meta-blok dostane tlačítka/ikony pro akce.
- Klik na jméno/avatar → malé popover menu nebo přímo ikony:
  - "Přidat do kontaktů" (ikonka user-add)
  - "Hvězda pro adresu" (ikonka star)
- Nebo jednodušší: dva malé ikonkové tlačítka vedle meta-bloku v `.reader-top .right` nebo pod meta-blokem.
- Po kliknutí zavolat API a zobrazit toast.
- Zkontrolovat, zda kontakt už existuje (aby nedošlo k duplikátu) — `GET /api/contacts?q=email` nebo nechat backend vrátit chybu.

### 6. Lokalizace
- `reader.add_to_contacts` — "Přidat do kontaktů" / "Add to contacts"
- `reader.star_address` — "Hvězda pro adresu" / "Star address"
- `reader.unstar_address` — "Zrušit hvězdu pro adresu" / "Unstar address"
- `toast.contact_added` — "Kontakt přidán" / "Contact added"
- `toast.address_starred` — "Adresa označena hvězdou" / "Address starred"
- `toast.contact_exists` — už existuje v locale (`error.contact_exists`)

## Soubory k úpravě
1. `migrations/008_starred_addresses.sql` — nová tabulka.
2. `src/openmail/services/contact_service.py` — starred address funkce.
3. `src/openmail/routes/contacts.py` — nové endpointy.
4. `src/openmail/services/resend_service.py` — auto-star při inbound.
5. `static/js/ui.js` — interaktivní meta-blok.
6. `static/js/app.js` — handlery pro akce.
7. `static/js/api.js` — nové API metody.
8. `static/app.css` — styly pro akční tlačítka/popover.
9. `locales/cs.json`, `locales/en.json` — nové klíče.

## Testování
1. Otevřít e-mail v čtečce, kliknout "Přidat do kontaktů" → kontakt se vytvoří.
2. Kliknout "Hvězda pro adresu" → adresa se přidá do `starred_addresses`.
3. Poslat testovací e-mail z té adresy → nový e-mail má automaticky hvězdu.
4. Zrušit hvězdu pro adresu → nové e-maily už nemají hvězdu.
5. Duplicitní kontakt → toast "Kontakt již existuje".

## Otázky k potvrzení
1. Má být "Add to contacts" dostupné jen pro inbound e-maily, nebo i pro sent?
2. Má se při "Star address" automaticky přidat i do kontaktů, nebo jen hvězda?
3. UI: ikonkové tlačítka v meta-bloku, nebo popover menu po kliku na jméno?