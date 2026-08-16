# Plán: Implementace "Remember me" do loginu (aktualizovaný)

## Cíl
Přidat na přihlašovací stránku funkci „Remember me“, která:
1. Prodlouží platnost přihlášení z 15 minut na 30 dní.
2. Při návratu na `/login` s platnou session rovnou přesměruje uživatele do aplikace.
3. Uloží uživatelské jméno do cookie, aby se při dalším loginu automaticky předvyplnilo.
4. Neukládá heslo nikde na klientovi ani serveru.

## Varianta UI k potvrzení

**Varianta A (doporučená): Dva samostatné checkboxy**
- `Zůstat přihlášený` — session 30 dní.
- `Zapamatovat uživatelské jméno` — username cookie na 365 dní.
- Uživatel může zapnout jedno, druhé, nebo obojí.

**Varianta B: Jeden checkbox**
- `Zůstat přihlášený` — zároveň zapamatuje username a prodlouží session.
- Jednodušší UI, menší flexibilita.

> **Čekám na potvrzení varianty a délky remember-me (doporučuji 30 dní).**

## Soubory k úpravě

### 1. `migrations/007_add_remember_to_sessions.sql`
```sql
ALTER TABLE sessions ADD COLUMN remember INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_sessions_remember_last_seen ON sessions(remember, last_seen);
```

### 2. `src/openmail/config.py`
Přidat:
```python
REMEMBER_ME_DAYS = int(os.environ.get("REMEMBER_ME_DAYS", "30"))
```

### 3. `src/openmail/auth/session.py`
- Upravit `create_session(user_id, remember=False)` tak, aby uložil flag `remember`.
- Upravit `get_session(sid)`:
  - Načíst `remember` z DB.
  - Pro `remember=1` použít timeout `REMEMBER_ME_DAYS`.
  - Pro `remember=0` zůstává `SESSION_TIMEOUT_MINUTES`.
- Upravit `cleanup_expired_sessions()` tak, aby mazal sessiony podle správného typu platnosti.

### 4. `src/openmail/routes/public.py`
- Upravit `_set_session_cookie(resp, sid, remember=False)`:
  - `remember=True` → `max_age = REMEMBER_ME_DAYS * 24 * 3600`
  - `remember=False` → `max_age = 15 * 60`
- V `login_page()` GET:
  - Pokud `current_user()` existuje, rovnou redirect na index.
  - Předat do template `remember_username` z cookie.
- V `login_page()` POST:
  - Číst checkbox `remember_me` → předat do `create_session` a `_set_session_cookie`.
  - Číst checkbox `remember_username`:
    - Zaškrtnuto → nastavit cookie `remember_username` na 365 dní.
    - Nezaškrtnuto → smazat cookie `remember_username`.
- V `logout()` smazat i cookie `remember_username` (nebo nechat? rozhodnutí viz níže).

### 5. `templates/login.html`
- Přidat checkbox(y) pod pole heslo.
- Předvyplnit `<input name="username">` hodnotou `remember_username`.

### 6. `locales/cs.json` a `locales/en.json`
Přidat klíče:
- `login.remember_me` / `login.remember_me_hint`
- `login.remember_username` / `login.remember_username_hint`
- Upravit `login.footer` podle nové logiky.

### 7. `static/js/login.js` (volitelně, pouze pokud chceme client-side)
Není nutné — předvyplnění username uděláme server-side z cookie.

## Bezpečnostní úvahy
- **Heslo se nikde neukládá** — ani v cookie, ani v localStorage, ani na serveru.
- Session cookie zůstává `HttpOnly` a `SameSite=Lax`.
- Username cookie není citlivá informace, ale může být `HttpOnly` a `SameSite=Lax` (server ji použije pro předvyplnění).
- Remember-me token je stejný bezpečný random token (`secrets.token_urlsafe(32`)) jako krátkodobá session — liší se pouze interním flagem a délkou platnosti.
- Při odhlášení se maže session z DB i session cookie. Username cookie zůstane, pokud uživatel chtěl username zapamatovat — to je žádoucí chování.

## Testování
1. Spustit aplikaci, aplikovat migrace.
2. **Bez remember me**: cookie `session_id` má `Max-Age=900` (15 min), DB má `remember=0`.
3. **S remember me**: cookie `session_id` má `Max-Age=2592000` (30 dní), DB má `remember=1`.
4. Zavřít prohlížeč, znovu otevřít `/` → přihlášený stále platí (remember me).
5. Návrat na `/login` s platnou session → automatický redirect do aplikace.
6. **Remember username**: po odhlášení je pole username vyplněné posledním uživatelem.
7. **Vypnutí remember username**: odhlásit, znovu přihlásit bez zaškrtnutí → pole username je prázdné.
8. Kontrola `logs/app.log` na chyby.

## Provedené rozhodnutí (implementováno)
1. **Varianta UI:** Dva samostatné checkboxy.
2. **Délka remember-me:** 30 dní, nastavitelné přes `.env` `REMEMBER_ME_DAYS`.
3. **Délka username cookie:** 365 dní, nastavitelné přes `.env` `REMEMBER_USERNAME_DAYS`.
4. **Secure cookie:** Automaticky zapnuto mimo `FLASK_DEBUG=true`.

## Známé omezení
Remember me prodlužuje pouze platnost session cookie. Šifrovací klíč (DEK) zůstává v paměti serveru; po restartu serveru uživatel musí znovu zadat heslo, aby mohl číst šifrované e-maily. To je bezpečnostní vlastnost stávající architektury, nikoliv chyba implementace.
