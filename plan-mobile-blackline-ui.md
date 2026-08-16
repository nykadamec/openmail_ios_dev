# BLACKLINE — redesign mobilní UI (viewport < 1024px)

## Zadání
Kompletně nový mobilní design email klienta. Kreativní redesign, ne evoluce.
Odmítnutý předchozí směr (NESMÍ se opakovat): světle modrý akcent, serif titulky,
kulaté floating karty.

## Designový koncept: „BLACKLINE“ — polní terminál / přístrojová deska
Prémiový technický instrument roku 2026 (reference: Nothing OS, Teenage
Engineering, Linear sharpness). Přesný opak odmítnutého měkkého modrého stylu.

- **Materiál:** skutečná černá `#09090B`, vlasové linky (hairlines, 9–18 % bílé),
  plochy dokotvené k okrajům (edge-to-edge), žádné plovoucí pilulky.
- **Geometrie:** ostré hrany (radius 2–6 px), čtvercové avatary, čtvercová
  tlačítka, čtvercový spinner.
- **Signálová barva:** kyselá limetka `#CFF13F` — černý text na limetce pro
  primární akce. Chybová: `#FF5A4E`.
- **Typografie:**
  - Display: kondenzovaná groteska (Avenir Next Condensed / Roboto Condensed /
    Arial Narrow stack), uppercase, titulky složené „těžce“.
  - Mono mikro-labely (ui-monospace stack): čas, badge, sekce, taby, count,
    eyebrow — uppercase, letterspacing, tabulární číslice.
  - Tělo: systémový sans (čitelnost e-mailů).
- **Podpisové detaily:** blikající blokový kurzor za titulkem (jen
  `prefers-reduced-motion: no-preference`), limetkový čtvereček před podtitulkem,
  číslování sekcí/akcí přes CSS countery (01/02/03), nepřečtené = 3px limetkový
  sloupek vlevo + tenký lime gradient, select mode = avatar se mění na checkbox.

## Oblasti a řešení (vše v `@media (max-width: 1023px)`, připojeno na konec app.css)
1. `:root` předefinice tokenů (barvy, radiusy, font stacks) — pouze v media query.
2. **Header** — kondenzovaný uppercase titulek + blokový kurzor, mono podtitul
   se status čtverečkem, ostrý cluster s hamburgerem (pressed = limetka/černá).
3. **Hamburger action panel** — bottom sheet přes celou šířku (místo plovoucí
   karty), mono eyebrow s vlasovou linkou, řádky 54px číslované counterem,
   z-index nad tab barem.
4. **Email karty** — ledger řádky edge-to-edge s hairline děliči; unread = lime
   sloupek + gradient + bílý bold; čas mono; čtvercový avatar s mono iniciálou;
   selected = lime wash + inset ring; select mode mění avatar na checkbox
   (vybraný = plná limetka s černou iniciálou); starred = lime hvězda.
5. **Tab bar** — docknutý full-width bar s horní hairline + blur (ne floating
   pill); aktivní tab = lime ikona + 2px lime tick nahoře; compose = protrudující
   čtvercové lime tlačítko s černou ikonou; minimal varianta sladěná.
6. **Reader** — ostré toolbar tlačítka, kondenzovaný předmět, meta-block jako
   ostrá „spec“ karta, mono čas/email; attachment karty ostré s lime icon tile
   a mono meta; akce jako outlined mono buttony (≥40px touch).
7. **Mobilní vyhledávání** — ostré pole, focus = lime border + jemný ring.
8. **Drawer** — ostrý panel, lime čtvercový avatar s černou mono iniciálou,
   sekce číslované counterem, aktivní položka = lime wash + inset sloupek,
   badge = ostrá lime s černým mono číslem.
9. **Bulk bar** — dokotvený nad tab bar (edge-to-edge), mono count, ostré
   outlined buttony, horizontální scroll jako pojistka.
10. **Toast / context menu / modal / composer / panely** — sjednocení: ostré
    radiusy, lime primárky s černým textem, mono labely, toast s lime sloupkem.
11. **Safe-area** — tab bar padding-bottom safe, bulk/toast nad barem, header
    max() pro landscape notch, reader/composer dle base.
12. **Touch targety** — řádky ≥48px, taby 52px, icon-btn 40px, akce příloh ≥40px.
13. **Reduced motion** — mobile-scoped blok vypíná cardEnter, blink a zkracuje
    transitions; fade animace readeru/composeru/panelů vypnuty.

## Omezení
- Žádná změna `id`, `data-action`, JS logiky. `templates/index.html` neměním
  (není vizuálně nutné — vše lze pokrýt CSS včetně pseudo-elementů).
- Desktop (`min-width: 1024px`) beze změny — nová pravidla jen v max-width blocích
  na konci souboru (cascade vyhrává nad base pravidly).

## Ověření
- `node --check static/js/app.js`
- `git diff --check`
- Vizuální self-review: statický mock v temp adresáři + Playwright screenshoty
  v mobilním viewportu (inbox / sheet+select / drawer / reader).
