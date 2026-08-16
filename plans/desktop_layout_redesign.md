# Plán: Redesign desktop layoutu (≥1024px)

## Cíl
Kompletně předesignovat desktopový layout openMail, aby odpovídal modernímu e-mailovému klientovi, byl funkční a poskytoval plnou paritu s mobilní verzí. Mobilní layout (pod 1024px) zůstává beze změny.

## Rozsah
- `templates/index.html` — struktura desktop layoutu
- `static/app.css` — desktop media query (≥1024px)
- `static/js/app.js` — úpravy JS, pokud redesign vyžaduje
- `locales/cs.json`, `locales/en.json` — nové texty

## Návrh layoutu (doporučený směr)

### 1. Sidebar (vlevo, 260px)
- Zůstává na pozici `grid-column: 1`.
- Kompaktnější položky, ikona + text.
- Nahoře logo openMail + uživatel.
- Sekce: Složky, Adresář, Účet.
- Tlačítka Compose a Sync v horní části.
- Aktivní složka zvýrazněna accent barevně.

### 2. Header (nahoře, sloupec 2–3)
- Menší, čistší: nadpis složky + počty vlevo, akce vpravo.
- Akce: search (nově), select mode, settings.

### 3. Obsah — seznam e-mailů (střed, ~380–420px)
- Čisté karty s avatarem, odesílatelem, předmětem, časem.
- Bez zbytečných rámečků, separátory.
- Scrollování oddělené.

### 4. Čtečka (vpravo, flexibilní)
- Vyplní zbylý prostor.
- Nahoře meta: avatar, odesílatel, čas.
- Tělo e-mailu.
- Akce: star, trash, HTML toggle, zavřít (×).

### 5. Panely Nastavení / Kontakty
- Pravý slide-in panel (380px) překrývající čtečku.
- Zavírání tlačítkem × nebo kliknutím mimo (backdrop).

### 6. Toast, bulk bar, modal
- Toast vpravo dole (24px).
- Bulk bar dole v seznamu (sticky), ne hardcodovaná šířka.

## Soubory k úpravě
- `static/app.css` — přepsat celou desktop media query sekci
- `templates/index.html` — úpravy struktury pro desktop (logo, desktop-only prvky, backdrop)
- `static/js/app.js` — logika zavírání panelů kliknutím mimo
- `locales/*.json` — případné nové klíče

## Testování
1. Otevřít aplikaci při šířce ≥1024px.
2. Ověřit všechny funkce: sidebar, seznam, čtečka, compose, sync, panely, bulk bar, toast.
3. Ověřit aktivní složku, scrollování.
4. Přepnout na mobilní viewport — nic se nesmí rozbít.
5. Zkontrolovat `logs/app.log`.

## Poznámka
Záloha aktuálního stavu je v `backups/` (soubor `*.backup-20260807-165608`).

## Stav: IMPLEMENTOVÁNO ✅
- Grid layout: sidebar 260px + seznam 380px + čtečka 1fr (≥1024px).
- Header s vyhledávacím polem (client-side filtr e-mailů).
- Sidebar s logem openMail, uživatelem, Compose a Sync tlačítky.
- Aktivní složka zvýrazněna, čtečka zavíratelná (×/Escape).
- Panely Nastavení/Kontakty jako pravý slide-in s backdrop (zavírání kliknutím mimo).
- Toast vpravo dole, bulk bar nad seznamem.
- Přeložený prázdný stav čtečky (`reader.empty`).
- Otestováno: server běží, CSS/JS se načítají, API odpovídá.

### Poznámka k search
Backend nepodporuje full-text vyhledávání e-mailů, proto je search implementován jako client-side filtr aktuálně načteného seznamu (`static/js/app.js` — `renderEmailListWithFilter`).
