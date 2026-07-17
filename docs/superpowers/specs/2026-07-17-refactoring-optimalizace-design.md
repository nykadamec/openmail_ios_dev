# openMail — Refactoring a optimalizace

> Větev: `refactoring-optimalizace`  
> Datum: 2026-07-17  
> Stav: návrh ke schválení

---

## 1. Současný stav

Aplikace je funkční e-mailový klient postavený na Flasku + SQLite + Resend API. Aktuální kód po redesignu (`redesign/modern-minimal`) má ale výrazné technické dluhy, které omezují výkon, bezpečnost a udržitelnost.

### 1.1 Metriky a pozorování

| Měření | Výsledek | Poznámka |
|---|---|---|
| `/api/emails?limit=50` | ~7–92 ms | První request pomalejší (DB není warm), pak rychlý díky SQLite cache. |
| `/api/stats` | ~4–8 ms | Málo dat, ale globální COUNT bez `user_id`. |
| `templates/index.html` | 1086 řádků / 48 KB | ~820 řádků inline JS — necacheovatelné, těžko udržovatelné. |
| `static/app.css` | 1244 řádků / 28 KB | Velký monolitický CSS, možné dead rules. |
| `app.py` | 1377 řádků | Všechno v jednom souboru. |
| `emails.db` | 62 sessions / 62 expired | Session table roste bez čištění. |

### 1.2 Kritické problémy

#### Backend

1. **`emails` tabulka nemá `user_id`**
   - Všechny e-mailové dotazy jsou globální.
   - Až přibude druhý uživatel, dojde k úniku dat mezi uživateli.
   - Nelze vytvořit efektivní per-user indexy.

2. **Nevhodné indexy**
   - Existují pouze jednosloupcové indexy (`direction`, `folder`, `is_starred`, `is_spam`, `is_trash`, `is_read`, `custom_folder_id`, `created_at`).
   - SQLite pro hlavní listovací dotaz vybere `idx_emails_trash` a dělá temp B-tree sort (`ORDER BY datetime(created_at)`).
   - Statistiky (`/api/stats`) dělají 6 samostatných `COUNT(*)` bez `user_id`.

3. **Opakované otevírání DB spojení**
   - Každá funkce volá `get_db()`, `conn.execute(...)`, `conn.commit()`, `conn.close()`.
   - Není použit connection pool ani context manager.

4. **`current_user()` volá databázi při každém zavolání**
   - V rámci jednoho requestu se často volá několikrát (např. `login_required` + route handler + helper).

5. **Blokující těžké operace v request threadu**
   - `verify_user`: bcrypt + PBKDF2 + AES-GCM decryption synchronně při přihlášení.
   - `send_email`: síťový call do Resend API synchronně.
   - `sync_emails`: stahování a zpracování e-mailů synchronně.
   - `_process_inbound_email`: stahování příloh z Resend synchronně.

6. **SSE není thread-safe**
   - `_sse_clients` je obyčejný `list`.
   - `notify_sse` iteruje a odstraňuje za běhu bez locku — může vyhodit `RuntimeError` nebo ztratit event.

7. **Session cleanup chybí**
   - Expired sessions se mažou jen při explicitním lookupu konkrétní session.
   - V DB je momentálně 100 % expired sessions.

8. **Žádný migration systém**
   - `init_db()` používá `CREATE ... IF NOT EXISTS`, což neumí přidat sloupce ani změnit indexy.
   - Budoucí schema změny budou ruční a křehké.

9. **Přílohy bez garbage collection**
   - Metadata příloh jsou v JSON sloupci `emails.attachments`.
   - Obsahy jsou na filesystemu pod `data/attachments/{email_id}/`.
   - Při mazání e-mailu zůstávají soubory osiřelé.

#### Frontend

1. **Monolitický inline JavaScript**
   - `templates/index.html` obsahuje ~820 řádků inline JS.
   - Prohlížeč si ho nemůže cacheovat. Při každém načtení stránky se přenáší znovu.
   - Není možné použít linting, testy, tree-shaking.

2. **Render-blocking externí CSS**
   - HugeIcons se načítá synchronně z CDN.
   - Zpomaluje first paint.

3. **`innerHTML` templating**
   - `loadEmails` generuje HTML stringy a vkládá je přes `innerHTML`.
   - Reflow cost roste s počtem e-mailů.
   - XSS riziko při `escapeHtml` — aktuálně používá textContent, což je bezpečné, ale zbytečně těžké.

4. **Autokomplet kontaktů**
   - Na každý `oninput` se volá `loadContacts()`, která fetchuje celý seznam kontaktů.

5. **Duplicitní service worker**
   - Existují `sw.js` v kořeni a `static/sw.js`.
   - Route `/sw.js` posílá ten v kořeni; manifest odkazuje na kořenový. `static/sw.js` je nevyužitý.

6. **Opakované DOM lookupy**
   - `document.getElementById(...)` volané stále dokola místo cached referencí.

---

## 2. Cíle refactoringu

1. **Bezpečnost:** per-user izolace dat, thread-safe SSE, robustnější auth.
2. **Výkon:** rychlejší DB dotazy, menší overhead na spojení, neblokující I/O.
3. **Udržitelnost:** modularizace backendu, extrahovaný frontend JS, migration systém.
4. **Škálovatelnost:** možnost přidat více uživatelů a více e-mailů bez degradace.

---

## 3. Přístupy (3 varianty)

### A. Jemný postupný refactoring
- Přidáme `user_id` + composite indexy.
- Zavedeme context manager pro DB spojení.
- Vyextrahujeme pár helperů z `app.py`.
- Resend/sync zůstanou synchronní, ale oddělíme je do vlastních funkcí.
- Frontend: vyčistíme CSS a rozdělíme inline JS do 2–3 statických souborů.

**Výhody:** nízké riziko, rychlé výsledky.  
**Nevýhody:** neřeší monolit `app.py`, SSE thread-safety, background I/O.

### B. Modulární refactoring (doporučeno)
- Rozdělíme `app.py` na moduly podle odpovědnosti (`db`, `crypto`, `auth`, `services`, `routes`, `models`).
- Zavedeme repository pattern pro DB přístup.
- Zavedeme service layer pro byznys logiku (email, sync, contacts).
- Přidáme lightweight migration runner.
- Resend/sync outbound operace přesuneme do background threadu (Flask `copy_current_request_context` nebo vlastní worker queue).
- SSE thread-safe s lockem.
- Frontend JS vyextrahujeme do statických modulů, zachováme plain JS (bez build toolu).

**Výhody:** čistá architektura, testovatelnost, výkon, bezpečnost.  
**Nevýhody:** střední rozsah změn, chce důkladné testování.

### C. Velký refactoring (async framework + worker queue)
- Přejdeme na Quart/Starlette/FastAPI s async DB driverem.
- Resend/sync přesuneme do Celery/RQ/Redis queue.
- Přidáme Redis cache a full-text search.

**Výhody:** maximální škálovatelnost.  
**Nevýhody:** zásadní změna stacku, nové závislosti, největší riziko. Přináší více komplexity, než aktuální stav potřebuje.

### Doporučení

**Varianta B** — modulární refactoring. Je optimální pro aktuální velikost projektu: řeší všechny kritické problémy bez nutnosti měnit framework nebo přidávat infrastrukturu (Redis, Celery).

---

## 4. Detailní plán (varianta B)

### Fáze 1: Databáze a migrace

1. Vytvořit `migrations/` adresář a lightweight runner `db/migrations.py`.
2. Přidat `schema_migrations` tabulku pro sledování aplikovaných migrací.
3. Aplikovat migrace:
   - `001_add_user_id_to_emails.sql`
   - `002_replace_email_indexes.sql`
   - `003_session_indexes_and_cleanup.sql`
   - `004_create_attachments_table.sql` (volitelně)
4. Změnit `init_db()` tak, aby volal `run_migrations()`.
5. Upravit všechny email dotazy v `app.py` (a nových modulech) tak, aby filtrovaly podle `user_id`.

**Očekávaný dopad:** bezpečnost per-user, listovací dotazy z covering indexu bez temp sortu, rychlejší stats.

### Fáze 2: Modularizace backendu

Nová struktura:

```
openmail/
├── __init__.py          # app factory
├── config.py            # env, constants
├── db/
│   ├── __init__.py      # get_db, close_db, connection context
│   ├── migrations.py    # migration runner
│   └── queries.py       # SQL constants
├── models/
│   ├── user.py
│   ├── email.py
│   ├── session.py
│   ├── contact.py
│   └── folder.py
├── crypto/
│   ├── dek.py           # USER_DEKS, encrypt/decrypt field
│   └── kdf.py           # PBKDF2 helpers
├── auth/
│   ├── session.py       # create/get/delete session, cleanup
│   ├── password.py      # bcrypt verify/change
│   └── cf_access.py     # Cloudflare Access JWT
├── services/
│   ├── email_service.py # list, get, update, bulk, delete
│   ├── resend_service.py# send, sync, webhook processing
│   ├── contact_service.py
│   └── stats_service.py
├── routes/
│   ├── auth.py
│   ├── emails.py
│   ├── contacts.py
│   ├── folders.py
│   ├── settings.py
│   └── public.py        # index, sw.js, manifest
├── sse.py               # thread-safe notify + client registry
└── app.py               # pouze registrace blueprintů a spuštění
```

**Kroky:**
1. Vytvořit `config.py` a přesunout všechny env konstanty.
2. Vytvořit `db/__init__.py` s `get_db_connection()` context managerem (s thread-local connection nebo `g`).
3. Vytvořit `crypto/` a přesunout krypto pomocné funkce.
4. Vytvořit `auth/` s `current_user()` cachem (např. `g.current_user` po prvním lookupu).
5. Vytvořit `services/` a přesunout byznys logiku.
6. Vytvořit `routes/` jako Flask blueprinty.
7. `app.py` zredukovat na ~100 řádků.

**Očekávaný dopad:** přehlednost, testovatelnost, snazší úpravy, menší pravděpodobnost regresí.

### Fáze 3: Výkonnostní vylepšení backendu

1. **DB spojení**
   - Použít `g.db` v rámci requestu — jedno spojení na request.
   - Využít Flask `@app.teardown_appcontext` pro zavření.

2. **Auth cache**
   - `current_user()` uložit do `g.current_user` po prvním volání.
   - Dekryptované DEK ponechat v `USER_DEKS` (již existuje).

3. **Background I/O**
   - `send_email`: spustit Resend API call ve threadu (`ThreadPoolExecutor` nebo `threading.Thread`), vrátit okamžitě `202 Accepted` a následně pushnout SSE event.
   - `sync_emails`: spustit ve threadu, vrátit okamžitě `202`, postupně pushnout progress/nebo final event.
   - `_process_inbound_email` s downloadem příloh: spustit async-like ve thread poolu při sync/webhook.

4. **SSE thread-safe**
   - `_sse_clients` obalit `threading.RLock`.
   - `notify_sse` zkopírovat klienty do lokálního listu před iterací.

5. **Session cleanup**
   - Přidat `cleanup_expired_sessions()` volanou při loginu, logoutu a při startu.
   - Přidat index `idx_sessions_last_seen`.

6. **Krypto optimalizace**
   - Pro listové dotazy nedekryptovat `body_text`/`body_html` — již se neděje, ponechat.
   - Zvážit zmírnění počtu PBKDF2 iterací pro DEK při migraci z legacy (již 100k).
   - bcrypt cost ponechat — přihlášení není častá operace.

7. **Attachment GC**
   - Při `DELETE FROM emails WHERE id IN (...)` smazat `data/attachments/{id}/`.
   - Ideálně přes `attachments` tabulku s `ON DELETE CASCADE`.

### Fáze 4: Frontend refactoring

1. **Vyextrahovat JS**
   - `static/js/app.js` — hlavní aplikace, state, init.
   - `static/js/api.js` — všechny fetch wrappery.
   - `static/js/ui.js` — render funkcionalita (email card, reader, composer).
   - `static/js/utils.js` — helpers (escape, date, avatar).
   - `static/js/sse.js` — EventSource a reconnect.
   - Šablona `index.html` bude mít jen `<script type="module" src="/static/js/app.js"></script>`.

2. **Vykreslování**
   - Nahradit `innerHTML` string templating `DocumentFragment` + `createElement` pro e-mail cards.
   - Cachovat DOM reference (např. `const els = { list: ... }`).
   - Renderovat e-maily po dávkách při velkém počtu (virtual scrolling až při >200 items).

3. **CSS**
   - Provést dead-code analysis a odstranit nepoužité třídy.
   - Rozdělit `app.css` na `base.css`, `components.css`, `layout.css` (volitelně).
   - Ponechat dark mode jako default.

4. **HugeIcons**
   - Ponechat CDN, ale přidat `preload` nebo `dns-prefetch`.
   - Alternativa: stáhnout používané ikony lokálně (nejlépo až po analýze použitých tříd).

5. **Autokomplet**
   - Cachovat kontakty po prvním loadu.
   - Debounce na input (300 ms).

6. **Service worker**
   - Smazat `static/sw.js` duplikát.
   - Ponechat `sw.js` v kořeni.
   - Zlepšit cache strategii pro `/api/` — vracet offline-friendly data.

### Fáze 5: Testování a profilování

1. **Smoke testy**
   - Přihlášení, odhlášení, list e-mailů, otevření e-mailu, poslání e-mailu, sync, trashed, spam, kontakty, složky.

2. **Výkonnostní testy**
   - `/api/emails?limit=50` — cíl <20 ms p95.
   - `/api/stats` — cíl <10 ms p95.
   - Přihlášení — cíl <500 ms (bcrypt limitující).
   - 1000 e-mailů v DB — ověřit, že list zůstává rychlý.

3. **Load test**
   - Simulace 10 souběžných uživatelů na `/api/emails` pomocí `ab` nebo `wrk`.
   - Ověřit, že SSE nedělá race conditions.

4. **Bezpečnostní kontrola**
   - Dva uživatelé — každý vidí jen své e-maily.
   - Expired session neprojde.
   - Přílohy se mažou při hard-delete.

---

## 5. Časový odhad

| Fáze | Odhad |
|---|---|
| 1. Databáze a migrace | 2–3 h |
| 2. Modularizace backendu | 4–6 h |
| 3. Výkonnostní vylepšení backendu | 3–4 h |
| 4. Frontend refactoring | 4–5 h |
| 5. Testování a profilování | 2–3 h |
| **Celkem** | **15–21 h** |

---

## 6. Rizika a mitigace

| Riziko | Mitigace |
|---|---|
| Při migraci dojde ke ztrátě dat. | Záloha DB před migracemi; idempotentní migrace; `ALTER TABLE` s `DEFAULT`. |
| Modularizace rozbije existující importy. | Postupný přesun, testy po každém modulu. |
| Background threads při syncu mohou ztratit výjimku. | Použít `concurrent.futures` s proper logging; request context copy. |
| Frontend extrakce může změnit pořadí načítání. | Použít `type="module"` + `defer`; smoke test. |
| PWA service worker může držet starou verzi. | Bump `CACHE_NAME` po změně. |

---

## 7. Open questions

1. Chceš udržet plain JS bez build toolu, nebo zavést Vite/esbuild?
2. Chceš background worker implementovat přes `ThreadPoolExecutor` v rámci Flasku, nebo raději SQLite queue + samostatný worker thread?
3. Má smysl přidat unit testy (pytest), nebo stačí smoke testy a profiling?
4. Máme odstranit `static/sw.js` duplikát a ponechat jen `sw.js` v kořeni?

---

## 8. Schválení

Tento dokument čeká na schválení před zahájením implementace.
