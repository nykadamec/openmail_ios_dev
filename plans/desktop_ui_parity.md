# Plán: Parita mobilní a desktop UI

## Cíl
Upravit openMail tak, aby všechny funkce dostupné na mobilu fungovaly i na desktopu (≥1024px), a opravit chybějící/rozbité desktop UI.

## Současný stav
- Desktop layout existuje v CSS jako grid se sidebar-em, seznamem a čtečkou.
- Několik klíčových komponent je však rozbitých nebo chybí.
- Mobilní funkce (tab bar: Compose, Sync; zavření čtečky; long-press menu) nejsou na desktopu dostupné.

## HIGH priority — nutné opravit

### 1. Sidebar je na desktopu neviditelný
- **Soubor:** `static/app.css` (desktop media query ≥1024px)
- **Problém:** `.menu-panel` má stále `position: absolute; transform: translateX(100%)` z mobilních stylů.
- **Oprava:** V desktop media query přidat `.menu-drawer .menu-panel { position: relative; width: 100%; transform: none !important; }`.

### 2. Na desktopu nelze scrollovat seznam e-mailů
- **Soubor:** `static/app.css`
- **Problém:** `.content` na desktopu nemá `overflow-y: auto`.
- **Oprava:** Přidat `overflow-y: auto` do `.content` v desktop media query.

### 3. Na desktopu chybí tlačítka Compose a Sync
- **Soubor:** `templates/index.html`, `static/app.css`
- **Problém:** Tab bar je na desktopu skrytý, a s ním i tlačítka Compose a Sync.
- **Oprava:** Přidat tlačítka „Nový e-mail“ a „Synchronizovat“ do sidebaru (viditelná jen na desktopu pomocí `desktop-only` třídy). Mobilní tab bar zůstane nezměněn.

### 4. Na desktopu nelze zavřít čtečku
- **Soubor:** `templates/index.html`, `static/js/app.js`
- **Problém:** Zpětné tlačítko má třídu `mobile-only` a Escape zavírá čtečku jen na mobilu.
- **Oprava:** Přidat tlačítko × do `.reader-top` pro desktop a/nebo povolit Escape i na desktopu.

### 5. Panely Nastavení a Kontakty se na desktopu otevírají na špatné pozici
- **Soubor:** `static/app.css`
- **Problém:** `.side-panel` má `inset: 0`, desktop media query nechává `left: 0`.
- **Oprava:** V desktop media query nastavit `left: auto; bottom: auto;` (nebo `inset: 0 0 auto auto`) a případně přidat overlay/backdrop.

### 6. Sidebar nezobrazuje aktivní složku
- **Soubor:** `static/app.css`
- **Problém:** Chybí CSS pro `.menu-item.active`.
- **Oprava:** Přidat `.menu-item.active { background: var(--accent-subtle); color: var(--accent); }`.

## MEDIUM priority — vhodné opravit

### 7. Prázdný stav čtečky je hardcodovaný česky
- **Soubor:** `static/app.css`
- **Oprava:** Použít data-atribut nebo přeložený text z `window.__OPENMAIL_LOCALE`.

### 8. Toast je na desktopu příliš vysoko
- **Soubor:** `static/app.css`
- **Oprava:** V desktop media query nastavit `bottom: 24px`.

### 9. Režim výběru (bulk) může být na desktopu nepřehledný
- **Soubor:** `static/app.css`
- **Poznámka:** Výběr se zobrazuje pouze zeleným pozadím. Zvážit zobrazení checkboxu v select módu.

## LOW priority — detaily

### 10. `mobile-only` třída používá `display: initial`
- **Soubor:** `static/app.css`
- **Poznámka:** Může resetovat tlačítka na inline. Použít explicitní hodnoty.

### 11. Swipe a minimalizace tab baru
- Zůstávají mobilní, protože desktop má sidebar. Není nutné měnit.

## Soubory k úpravě
- `templates/index.html`
- `static/app.css`
- `static/js/app.js`
- `locales/cs.json`, `locales/en.json`

## Testování
1. Otevřít aplikaci v prohlížeči při šířce ≥1024px.
2. Ověřit, že sidebar je viditelný a obsahuje všechny položky.
3. Ověřit, že se dá scrollovat seznam e-mailů.
4. Ověřit Compose a Sync tlačítka v sidebaru.
5. Kliknout na e-mail — otevře se v pravé čtečce.
6. Ověřit, že čtečku lze zavřít (tlačítko × nebo Escape).
7. Otevřít Nastavení a Kontakty — panel se objeví vpravo.
8. Ověřit aktivní zvýraznění složky v sidebaru.
9. Přepnout do mobilního viewportu — UI se musí vrátit k mobilnímu layoutu.

## Otázky k potvrzení
1. Kam umístit tlačítka Compose a Sync na desktopu? Doporučuji do sidebaru pod složky.
2. Máme na desktopu přidat do headeru search bar nebo ho nechat jen mobilní?
3. Chceš, aby se panely Nastavení/Kontakty na desktopu zobrazovaly jako pravý slide-in panel (překrývající čtečku), nebo jako samostatná stránka/okno?
