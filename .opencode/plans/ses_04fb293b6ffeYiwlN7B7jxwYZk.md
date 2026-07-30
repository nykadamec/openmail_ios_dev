# Plán: Přidání nového uživatele `info` s e-mailem `info@adamec.pro`

## Cíl

Vytvořit v openMail nového lokálního uživatele:
- **Přihlašovací jméno:** `info`
- **Heslo:** `adamec`
- **E-mailová adresa:** `info@adamec.pro`

Uživatel bude mít **plně oddělenou schránku**: příchozí e-maily pro `info@adamec.pro` budou patřit jen jemu, a odesílat bude z adresy `info@adamec.pro`. Pro odesílání/příjem se zatím použije **stávající globální Resend API klíč** z `.env` — není nutné vytvářet nový Resend účet.

## Potvrzené rozhodnutí

| Otázka | Odpověď |
|---|---|
| Rozdělení účtů | Plně oddělené účty |
| Historická pošta pro `info` | Pouze nové zprávy adresované `info@adamec.pro` |
| Způsob vytvoření uživatele | Jednorázový skript |
| Resend API klíč | Sdílený globální klíč z `.env` (varianta a) |
| Přihlašovací jméno vs. e-mail | Uživatelské jméno `info`, e-mail `info@adamec.pro` |

## Stav a omezení

- openMail je Flask aplikace s SQLite databází `emails.db`.
- Uživatelé se ukládají do tabulky `users` (sloupce: `id`, `username`, `password_hash`, `dek_salt`, `encrypted_dek`, `created_at`).
- Každý uživatel má vlastní DEK (data encryption key) odvozený od hesla a chráněný pomocí PBKDF2 + AES-GCM.
- Příchozí e-maily jsou přijímány přes Resend webhook `/api/inbound` (`src/openmail/routes/emails.py`, `src/openmail/services/resend_service.py`).
- Tabulka `emails` má sloupec `user_id`, ale aktuálně se do něj ukládá fallback `1`, protože webhook není autentizován sessionem.
- IMAP synchronizace **není implementována** — všechny maily přicházejí přes Resend.
- V `.env` je globální `FROM_EMAIL=dominik@adamec.pro` a `FROM_NAME=Dominik Adamec`. Pro víceuživatelské odesílání je potřeba adresu získat z aktuálního uživatele.

## Rozsah tohoto plánu

1. Rozšířit tabulku `users` o `email` a `from_name`.
2. Vytvořit jednorázový skript, který přidá uživatele `info` s e-mailem `info@adamec.pro` a heslem `adamec`.
3. Upravit příjem přes Resend webhook, aby se `user_id` určovalo podle `recipient` adresáta.
4. Upravit odesílání, aby se použila adresa a jméno aktuálního uživatele.
5. Upravit frontend, aby zobrazoval per-user odesílací adresu místo globální proměnné `window.__OPENMAIL_FROM_EMAIL`.
6. Otestovat přihlášení, odeslání a příjem pro oba uživatele.

## Kroky implementace

### 1. Příprava a záloha

1. Zastavit běžící aplikaci (`./stop.sh`).
2. Vytvořit zálohu `emails.db` např. jako `emails.db.backup-YYYYMMDD-HHMMSS`.
3. Vytvořit zálohu `.env` (pokud ještě není v gitu).
4. Ověřit v Resend dashboardu, že doména `adamec.pro` a adresa `info@adamec.pro` jsou aktivní a směrovatelné.

### 2. Migrace databáze

Vytvořit SQL migraci `migrations/006_add_user_email_and_name.sql`:

```sql
-- Migration 006: add email and from_name to users, populate default user.
ALTER TABLE users ADD COLUMN email TEXT UNIQUE;
ALTER TABLE users ADD COLUMN from_name TEXT;

-- Existing default user 'dominik' gets the configured default email/name.
UPDATE users SET email = 'dominik@adamec.pro', from_name = 'Dominik Adamec' WHERE username = 'dominik';
```

Migraci spustí automaticky `init_db()` při příštím startu aplikace.

### 3. Rozšíření modelu uživatele

Upravit `src/openmail/auth/users.py`:

- Upravit `create_user(username, password, email=None, from_name=None)`, aby ukládal `email` a `from_name` do INSERTu.
- Přidat pomocné funkce:
  - `get_user_by_email(email: str) -> dict | None`
  - `get_user_from_address(user_id: int) -> tuple[str, str]` → vrací `(email, from_name)`. Pokud `from_name` chybí, odvodí z e-mailu nebo vrátí samotnou adresu.
  - `get_user_by_id(user_id: int) -> dict | None`

### 4. Vytvoření jednorázového skriptu

Vytvořit `scripts/add_user.py` (nebo `add_user.sh` wrapper), který:

1. Přidá `src/` do `sys.path`.
2. Načte Flask app context.
3. Zavolá `create_user("info", "adamec", email="info@adamec.pro", from_name="Info Adamec")`.
4. Vypíše potvrzení nebo chybu (např. uživatel už existuje).
5. Skript bude spustitelný jako:
   ```bash
   python scripts/add_user.py info adamec info@adamec.pro "Info Adamec"
   ```

### 5. Přiřazování příchozích e-mailů podle adresáta

Upravit `src/openmail/services/resend_service.py`, funkci `process_inbound_webhook`:

- Získat `recipient` z webhook payloadu (pole `to`, případně `envelope_to`).
- Normalizovat adresu (lowercase).
- Najít uživatele pomocí `get_user_by_email(recipient)`.
- Pokud není nalezen, fallback na `user_id = 1` (stávající chování) a zalogovat upozornění.
- Pokud je nalezen, uložit e-mail s `user_id` tohoto uživatele.

### 6. Per-user odesílací adresa

Upravit `src/openmail/services/resend_service.py`:

- Funkce `send_email(...)` bude místo globálního `FROM_EMAIL`/`FROM_NAME` načítat adresu aktuálního uživatele pomocí `current_user_id()` a `get_user_from_address(...)`.
- Pokud uživatel nemá nastavený `email`, použije se fallback globální `FROM_EMAIL` z `config.py` a vypíše se varování do logu.
- Uložení odchozí kopie do `emails` bude používat per-user `sender_email` a `sender_name`.

### 7. Frontend — zobrazení per-user adresy

- Odstranit nebo doplnit globální proměnnou `window.__OPENMAIL_FROM_EMAIL` v `src/openmail/routes/public.py`.
- Vytvořit endpoint `GET /api/me` v `src/openmail/routes/auth.py`, který vrátí aktuálního uživatele: `{id, username, email, from_name}`.
- Upravit `static/js/utils.js` (řádek 3), aby načítal `from_email` z `/api/me` místo globální proměnné, nebo aby používal fallback z globální proměnné jen při absenci API odpovědi.
- V UI (např. při psaní nového e-mailu) zobrazovat aktuální adresu odesílatele podle `/api/me`.
- V horní liště nebo menu zobrazit aktuálního uživatele (`info@adamec.pro`) a tlačítko odhlášení, pokud chybí.

### 8. Odhlášení a přepínání uživatelů

- Ověřit, že existuje endpoint pro odhlášení (např. `POST /api/logout`). Pokud chybí, přidat ho do `src/openmail/routes/auth.py` a frontend tlačítko.
- Ujistit se, že odhlášení maže cookie `session_id` a vyčistí DEK z paměti (`clear_user_dek`).

### 9. Testování

1. Spustit aplikaci (`./start.sh` nebo `./dev.sh`), migrace se automaticky aplikují.
2. Spustit `python scripts/add_user.py info adamec info@adamec.pro "Info Adamec"`.
3. Přihlásit se jako `info` / `adamec` a ověřit:
   - že schránka je prázdná (historické maily `dominik` nejsou vidět),
   - že v UI je vidět `info@adamec.pro` jako adresa odesílatele.
4. Odeslat testovací e-mail z účtu `info` a ověřit v Resend logu, že `From:` je `Info Adamec <info@adamec.pro>`.
5. Poslat e-mail zvenčí na `info@adamec.pro` a ověřit, že se objeví v inboxu uživatele `info` a **ne** v inboxu `dominik`.
6. Přihlásit se jako `dominik` a ověřit, že stále odesílá z `dominik@adamec.pro` a vidí svou původní poštu.
7. Testovat odhlášení a přepnutí mezi uživateli.

### 10. Dokumentace

- Aktualizovat `README.md` o popis víceuživatelského režimu a přidání nového uživatele.
- Vytvořit/upravit `AGENTS.md` v kořenu projektu s postupem pro správu uživatelů, protože projekt ho zatím nemá.

## Soubory k úpravě

| Soubor | Úprava |
|---|---|
| `migrations/006_add_user_email_and_name.sql` | Nová migrace |
| `src/openmail/auth/users.py` | Rozšířit `create_user`, přidat helpery |
| `src/openmail/services/resend_service.py` | Per-user `FROM_EMAIL`, přiřazení příchozích podle adresáta |
| `src/openmail/routes/auth.py` | Endpoint `/api/me`, případně `/api/logout` |
| `src/openmail/routes/public.py` | Odstranit/aktualizovat globální `__OPENMAIL_FROM_EMAIL` |
| `static/js/utils.js` | Načítat `from_email` z `/api/me` |
| `static/js/app.js` nebo `ui.js` | Zobrazit aktuálního uživatele a tlačítko odhlášení |
| `scripts/add_user.py` | Nový jednorázový skript |
| `README.md` | Dokumentace |
| `AGENTS.md` | Postup pro správu uživatelů |

## Rizika a poznámky

- Resend webhook je veřejný — určení uživatele podle `recipient` je jednoduché, ale závisí na správné konfiguraci Resend/domény. Proti spoofingu by bylo vhodné ověřit Resend webhook signature (`RESEND_WEBHOOK_SECRET`), což by se mělo zkontrolovat.
- Uživatel `info` nebude mít přístup k historickým e-mailům, protože tabulka `emails` dosud nemá všechny záznamy správně přiřazené k `user_id`. Existující záznamy zůstanou u `user_id = 1` (`dominik`).
- Pokud Resend účet nepodporuje odesílání z `info@adamec.pro`, odesílání selže — je nutné ověřit v Resend dashboardu.
- Výchozí heslo `adamec` je v `.env` jako `DEFAULT_USER_PASSWORD`; po vytvoření uživatele by se mělo heslo změnit v nastavení.
- Per-user IMAP/SMTP nastavení se v tomto plánu neřeší, protože aplikace IMAP nepoužívá.
