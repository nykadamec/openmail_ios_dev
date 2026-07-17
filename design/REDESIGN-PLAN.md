# openMail — redesign: moderní minimalistický UI

> Větev: `redesign/modern-minimal`  
> Cíl: nahradit současný "liquid-glass / neon-orange" styl čistým, moderním, minimalistickým designem s důrazem na čitelnost, rychlost a příjemné dlouhodobé používání.

---

## 1. Design direction

### Filozofie
- **Méně je více.** Odstranit oranžové orby, třpyt, skleněné efekty, gradientní tlačítka, duhové avatary.
- **Obsah jako UI.** Hlavní pozornost patří e-mailům; chrome kolem nich má být co nejjednodušší.
- **Klidná hierarchie.** Odlišit pomocí typografie, mezer a jemných barev místo tvarového a efektového hluku.
- **Konzistentní rhythm.** Společná mezera (8 px / 16 px / 24 px), společné zaoblení (12 px / 16 px), jednotná stínová škála.

---

## 2. Barvy

| Role | Hodnota dark | Hodnota light (optional) |
|------|--------------|--------------------------|
| Background | `#0B0B0F` | `#FFFFFF` |
| Surface (cards, panels) | `#141419` | `#F5F5F7` |
| Surface hover/selected | `#1C1C22` | `#E5E5EA` |
| Border | `rgba(255,255,255,0.08)` | `rgba(0,0,0,0.08)` |
| Text primary | `#F2F2F7` | `#1C1C1E` |
| Text secondary | `#8E8E93` | `#6C6C70` |
| Text tertiary | `#636366` | `#A1A1AA` |
| Accent | `#3B82F6` (modrá) | `#2563EB` |
| Accent subtle | `rgba(59,130,246,0.12)` | `rgba(37,99,235,0.10)` |
| Success | `#34C759` | `#34C759` |
| Error | `#FF453A` | `#FF453A` |

> **Proč modrá místo oranžové?** Teplá oranžová působí agresivně a hlasitě; studená modrá je neutrální, spolehlivá, konvenční pro e-mail/communication app (Gmail, Outlook, Apple Mail).

---

## 3. Typografie

- **Font stack:** `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`
- **Měřítko:**
  - Nadpis Inbox: `28 px`, `font-weight: 700`, `letter-spacing: -0.02em`
  - E-mail odesílatel: `15 px`, `weight: 600`
  - Předmět: `15 px`, `weight: 400`
  - Preview: `14 px`, `weight: 400`, barva secondary
  - Čas/čísla: `13 px`, `weight: 500`
  - Tlačítka/labels: `13 px`, `weight: 600`
- **Line-height:** 1.4 pro UI, 1.6 pro čtení e-mailů.

---

## 4. Komponenty

### 4.1 E-mail card
```
┌───────────────────────────────────┐
│ ○  Odesílatel          10:23     │
│    Předmět e-mailu                │
│    Krátký náhled textu...         │
└───────────────────────────────────┘
```
- Rámeček: 1 px border, radius 16 px.
- Padding 16 px.
- Avatar: 40 px kruh, jemná šedá výplní (`#2C2C2E`), bílá iniciála; žádné gradienty.
- Unread: pouze tučnější předmět + modrá tečka místo oranžové záře.
- Hover: mírné zesvětlení surface (`#1C1C22`).
- Star: ikona v metadatech, ne plavající odznak.

### 4.2 Floating tab bar → přesunout do spodní navigační lišty
- Pevná spodní lišta místo glass pill.
- Výška: `64 px + safe-area-inset-bottom`.
- Ikony 24 px, aktivní ikona modrá, neaktivní tertiary.
- Compose jako centrální primární tlačítko (modré, mírně vystouplé), ne jako další ikona v řadě.
- Žádný `backdrop-filter` ani animované pozadí.

### 4.3 Header
- Odstranit "brand-tag" `openMail` nad nadpisem — zbytečný vizuální hluk.
- Nadpis zarovnat vlevo; napravo pouze search (ikona lupy) a profil/avatar.
- Select mód: ikona zařadit do headeru jako kontextový přepínač.

### 4.4 Menu drawer
- Tmavý panel (`#141419`) s ostrým okrajem (bez blur).
- Sekce s malými uppercase labels, 11 px, tertiary.
- Menu itemy: 16 px padding, ikona 20 px, hover surface.
- Badges: modrá kulatá badge místo oranžové.

### 4.5 Reader
- Full-screen overlay se světlým/tmavým pozadím dle režimu.
- Horní toolbar: zpět, akce (star, move, delete) jako ikony ve stejné vzdálenosti.
- Meta-block: větší avatar, jméno + e-mail, čas; odděleno 1 px border.
- Tělo e-mailu: iframe se zvýšeným kontrastem a generickou dark/light base CSS.
- Toggle HTML/plain text: jednoduchý text button, ne oranžový gradient.

### 4.6 Composer
- Full-screen, čistý bílý/tmavý list.
- Pole "To / Subject" jako jednoduché řádky s jemným spodním borderem.
- Send tlačítko: modré, zaoblené 12 px, bez gradientu a glow.
- Autocomplete: dropdown podobný systémovému, jemný stín, radius 12 px.

### 4.7 Login / Setup
- Odebrat rozmazané orby a glass card.
- Centrovaná bílá/tmavá karta s jemným stínem, bez `backdrop-filter`.
- Primární tlačítko modré, monochromatické.
- Footer a brand tag mnohem menší/subtilnější.

---

## 5. Layout

### Mobile (default)
- Jeden sloupec: seznam e-mailů přes celou šíři.
- Reader/composer/settings overlay přes celou obrazovku.
- Spodní navigační lišta vždy viditelná.
- Safe-area respektováno.

### Desktop (≥ 900 px) — nice-to-have v 2. fázi
- Sidebar vlevo (folder tree), detail vpravo.
- Dvoupanelový layout jako moderní mail app (Apple Mail, Gmail split).
- Seznam e-mailů může být uprostřed s pevnou šířkou ~360 px.

---

## 6. Mikrointerakce

- **Tlačítka:** `:active { scale(0.97) }`, trvání 100 ms.
- **Cards:** hover `background` transition 150 ms.
- **Loaders:** jednoduchý 1.5 px border spinner v barvě accent.
- **Toasts:** slide-up z dolního okraje, žádný glassmorphism.
- **Modals:** fade + scale 0.98, trvání 200 ms.

---

## 7. Závislosti

- Zůstáváme u HugeIcons — jsou konzistentní a lehké.
- Zrušit vlastní SVG displacement mapy a liquid-glass efekty (soubory `displacementMap.txt`, `*.css` glass šum).
- CSS bude psané jako jeden čistý soubor `static/app.css`.

---

## 8. Krok za krokem implementace

1. **Základní design tokeny** — `static/app.css` s proměnnými, resetem a utility třídami.
2. **Globalní chrome** — header, spodní navigační lišta, menu drawer.
3. **E-mail card** — refactor `.email-card`, avatary, stavy unread/starred/spam.
4. **Reader** — redesign toolbaru, metadat, iframe base CSS.
5. **Composer + Settings + Contacts** — nový styl formulářů a panelů.
6. **Login / Setup** — odstranit glassmorphism, sjednotit styl.
7. **Cleanup** — smazat/znehodnotit starý `liquid-glass.css` a displacement mapy.
8. **Responzivita** — safe-area, desktop breakpoint.
9. **Testování** — proklikat appku, ověřit dark/light přepínač, kontrolovat kontrast.

---

## 9. Co se mění a co zůstává

| Zůstává | Mění se |
|---------|---------|
| HTML struktura šablon (převážně) | Barvy, typografie, spacing |
| JS logika (load, reader, composer) | CSS názvy a vizuální stavy |
| HugeIcons ikony | Barva a velikost ikon |
| Flask routes / API | Login/setup karty a styly |
| i18n překlady | Žádná změna textů kvůli designu |

---

## 10. Následující krok

> Chceš, abych začal psát nový `static/app.css` a refaktoroval `templates/index.html` podle tohoto plánu? Doporučuji začít CSS tokeny a hlavní chrome (header + tab bar), pak přejít na cards a reader.
