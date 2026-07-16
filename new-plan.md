# openMail — Celkový plán

> **Cíl:** Přejmenovat aplikaci, přidat i18n lokalizaci a 4 nové funkce (HTML render, stránkování, přílohy, hromadné akce).

---

## 📋 Přehled úkolů

| # | Úkol | Obtížnost | Závislosti |
|---|------|-----------|------------|
| 1 | **Přejmenování** — "Adamec.pro Mail" → "openMail" | ⭐ | — |
| 2 | **i18n systém** — vlastní lokalizace cs/en | ⭐⭐⭐ | — |
| 3 | **HTML render** — zobrazit HTML e-maily v iframe | ⭐ | — |
| 4 | **Stránkování** — načítat po 50, infinite scroll | ⭐⭐ | — |
| 5 | **Přílohy** — stahovat z Resendu, přikládat | ⭐⭐⭐ | — |
| 6 | **Hromadné akce** — checkboxy + bulk operace | ⭐⭐ | — |

> **Všechny úkoly jsou nezávislé** — lze dělat v libovolném pořadí.

---

## 📁 Soubory, které se mění

| Soubor | Status | Co se děje |
|--------|--------|------------|
| `README.md` | ✏️ upravit | Název projektu |
| `start.sh` | ✏️ upravit | Echo hláška |
| `stop.sh` | ✏️ upravit | Echo hláška |
| `app.py` | ✏️ upravit | i18n + 3 nové endpointy |
| `templates/index.html` | ✏️ upravit | i18n + 4 funkce (HTML+JS) |
| `templates/login.html` | ✏️ upravit | i18n |
| `templates/setup.html` | ✏️ upravit | i18n |
| `static/liquid-glass.css` | ✏️ upravit | Styly pro nové funkce |
| `i18n.py` | 🆕 nový | i18n backend |
| `locales/cs.json` | 🆕 nový | České texty |
| `locales/en.json` | 🆕 nový | Anglické texty |

---

## 1️⃣ Fáze 1: Přejmenování

**8 změn v 6 souborech.** Prostá textová náhrada.

| Soubor | Řádek | Staré | Nové |
|--------|-------|-------|------|
| `README.md` | 1 | `# Adamec.pro Mail` | `# openMail` |
| `start.sh` | 22 | `echo "Adamec.pro Mail started"` | `echo "openMail started"` |
| `stop.sh` | 14 | `echo "Adamec.pro Mail stopped"` | `echo "openMail stopped"` |
| `templates/index.html` | 9 | `<title>Adamec.pro Mail</title>` | `<title>openMail</title>` |
| `templates/index.html` | 21 | `<div class="brand-tag">Adamec.pro Mail</div>` | `<div class="brand-tag">openMail</div>` |
| `templates/login.html` | 6 | `<title>Přihlášení — Adamec.pro Mail</title>` | `<title>Přihlášení — openMail</title>` |
| `templates/login.html` | 121 | `<div class="tag">Adamec.pro Mail</div>` | `<div class="tag">openMail</div>` |
| `templates/setup.html` | 6 | `<title>Nastavení — Adamec.pro Mail</title>` | `<title>Nastavení — openMail</title>` |

---

## 2️⃣ Fáze 2: i18n systém

### Nové soubory

#### `locales/cs.json`
Všechny české texty rozdělené do sekcí:
- `login.*` — přihlašovací stránka
- `setup.*` — nastavení
- `index.*` — hlavní UI (menu, composer, reader, settings, kontakty, vyhledávání)
- `toast.*` — notifikace
- `folder.*` — názvy složek (Inbox, Sent, Spam, Trash, Drafts)
- `action.*` — tlačítka (send, delete, archive, ...)

#### `locales/en.json`
Stejná struktura, anglické hodnoty.

#### `i18n.py`
```python
# API:
#   t(key, **kwargs) -> str          # překlad s interpolací
#   get_locale() -> str              # aktuální jazyk ("cs"|"en")
#   _load()                          # reload z disku
#   set_locale(lang)                 # změnit jazyk (session)
#
# Cache: načte JSON při prvním volání, reload při změně
# Fallback: pokud klíč chybí, vrátí "??key??"
```

### Změny v `app.py`

1. **Import:** `from i18n import t, get_locale, set_locale, _load`
2. **Context processor:** vloží do šablon:
   - `locale` — aktuální jazyk
   - `t(key)` — Python překlad
   - `_(key)` — Jinja2 alias pro `t()`
   - `locale_json` — JSON objekt pro JS
3. **Endpoint `GET /api/locale`** — vrací `{"locale": "cs", "data": {...}}`
4. **Endpoint `POST /api/locale`** — přijme `{"locale": "en"}`, uloží do session + cookie
5. **Nahradit hardcoded stringy** v Pythonu (toasty, chybové hlášky) voláním `t()`

### Změny v šablonách

| Šablona | Rozsah |
|---------|--------|
| `login.html` | Všechny texty → `{{ _("login.xxx") }}` |
| `setup.html` | Všechny texty → `{{ _("setup.xxx") }}` |
| `index.html` (HTML) | Menu, composer, reader, settings → `{{ _("index.xxx") }}` |
| `index.html` (JS) | `const LOCALE = {{ locale_json\|safe }}` + helper `__(key)` → nahradit ~50 stringů |

### Přepínač jazyka

- **Settings panel:** tlačítka 🇨🇿 Čeština / 🇬🇧 English
- **Login stránka:** malé ikony dole
- Uložení do cookie (1 rok) + session
- Při změně: reload stránky

---

## 3️⃣ Fáze 3: 4 funkce

### 3.1 HTML render

**Cíl:** E-maily s `body_html` zobrazit formátovaně, ne jako plain text.

| Krok | Soubor | Co |
|------|--------|----|
| 1 | `templates/index.html` | V `openEmail()`: pokud `e.body_html` existuje → `<iframe sandbox="allow-same-origin" srcdoc="...">` |
| 2 | `templates/index.html` | Přidat tlačítko "HTML / Plain" toggle |
| 3 | `static/liquid-glass.css` | `.reader .body-html iframe` — 100% šířka, border: none |
| 4 | `static/liquid-glass.css` | `.html-toggle` — aktivní/neaktivní styl |

**Bezpečnost:** `sandbox` bez `allow-scripts` a `allow-top-navigation` — žádný JS, žádný únik.

### 3.2 Stránkování

**Cíl:** Načítat e-maily po dávkách, ne všechny najednou.

| Krok | Soubor | Co |
|------|--------|----|
| 1 | `app.py` | `/api/emails?limit=50&offset=0` → vrací `{"emails": [...], "total": N, "limit": 50, "offset": 0}` |
| 2 | `templates/index.html` | `loadEmails(reset=true)` — načte prvních 50, vykreslí |
| 3 | `templates/index.html` | `loadMore()` — načte dalších 50, append do seznamu |
| 4 | `templates/index.html` | `IntersectionObserver` na sentinel elementu → trigger `loadMore()` |
| 5 | `templates/index.html` | Sentinel: `<div id="scroll-sentinel" class="scroll-sentinel">` na konci seznamu |

**Edge cases:**
- Pokud `offset >= total` → žádný další request
- Během načítání: `loadingMore = true` → blokovat duplicitní volání
- Při změně složky: `loadEmails(reset=true)` → smazat seznam, začít od 0

### 3.3 Přílohy

**Cíl:** Stahovat přílohy z příchozích e-mailů, přikládat k odchozím.

| Krok | Soubor | Co |
|------|--------|----|
| 1 | `app.py` | `parse_inbound_event()` — pro každý `attachment` v Resend webhooku: stáhnout, uložit do `data/attachments/{email_id}/`, aktualizovat DB |
| 2 | `app.py` | `GET /api/attachments/<email_id>/<file>` — vrátí soubor s `Content-Disposition: attachment` |
| 3 | `app.py` | `/api/send` — přijmout `attachments: [{filename, content: base64, content_type}]`, poslat přes Resend API |
| 4 | `templates/index.html` | Reader: zobrazit seznam příloh s download linkem |
| 5 | `templates/index.html` | Composer: `<input type="file" multiple>` → base64 encode → preview seznamu |

**Edge cases:**
- Chybějící `data/attachments/` adresář → vytvořit při prvním stažení
- Příloha bez filename → `attachment.bin`
- Velké přílohy → Resend limit 10MB, validovat před odesláním
- Smazaný e-mail → přílohy zůstávají na disku (GC není potřeba)

### 3.4 Hromadné akce

**Cíl:** Vybrat více e-mailů a provést akci hromadně.

| Krok | Soubor | Co |
|------|--------|----|
| 1 | `app.py` | `POST /api/emails/bulk` — `{"ids": [1,2,3], "action": "read\|unread\|trash\|spam\|delete"}` |
| 2 | `templates/index.html` | Tlačítko "Vybrat" v toolbaru → přepne do select režimu |
| 3 | `templates/index.html` | Každý `.email-card` dostane checkbox |
| 4 | `templates/index.html` | Bulk bar: "Vybráno: N" + tlačítka (Přečteno, Nepřečteno, Koš, Spam, Smazat) |
| 5 | `templates/index.html` | "Select all" checkbox v hlavičce |
| 6 | `static/liquid-glass.css` | `.email-card .checkbox`, `.email-card.selected`, `.bulk-bar` |

**Edge cases:**
- Žádný e-mail nevybrán → tlačítka disabled
- Akce "delete" → potvrzovací dialog
- Po akci: reload seznamu, zrušit select režim
- Bulk na prázdné složce → žádná chyba

---

## ✅ Verifikace

Po implementaci všech fází:

| Test | Postup | Očekávaný výsledek |
|------|--------|-------------------|
| Přejmenování | Otevřít app | Title = "openMail", brand = "openMail" |
| i18n CS | Bez `Accept-Language` | Vše česky |
| i18n EN | `Accept-Language: en` | Vše anglicky |
| i18n přepínač | Settings → English | Reload → EN, cookie přežije |
| HTML render | Otevřít HTML e-mail | Iframe s formátováním |
| Stránkování | 100+ e-mailů | Prvních 50, scroll → dalších 50 |
| Přílohy | Odeslat s přílohou | Vidět v Sent, stáhnout |
| Bulk | Vybrat 3 → "Přečteno" | Badge zmizí |
| Bulk | Vybrat → "Koš" | Přesun do Trash |

---

## 🎯 Klíčové soubory

| Soubor | Role |
|--------|------|
| `i18n.py` | 🆕 Celý i18n backend |
| `locales/cs.json` | 🆕 Zdrojová locale |
| `locales/en.json` | 🆕 Překlad |
| `app.py` | Context processor, `/api/locale`, 3 nové endpointy |
| `templates/index.html` | HTML + JS — největší změny |
| `templates/login.html` + `setup.html` | i18n v Jinja2 |
| `static/liquid-glass.css` | Styly pro HTML render, bulk, attachments |

---

## ⚠️ Předpoklady

- Resend API podporuje `attachments` v `emails.send()` a inbound webhook posílá `attachments[]`
- Všechny 4 funkce ve Fázi 3 jsou na sobě nezávislé
- DB tabulka `emails` už má sloupec `attachments TEXT` a `headers TEXT`
