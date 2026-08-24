# Plán: kompletní redesign Composeru

**Stav:** čeká na schválení
**Větev:** `Latest-Dev`
**Cíl:** další iOS release po schválení
**Frame0:** stránka `openMail iOS Composer Redesign`, frame `Composer — Redesigned` (`aVKkwqxax_wYNCTbG1aki`)

## Problém

Aktuální Composer vizuálně neodpovídá Inboxu a Settings: má příliš mnoho oddělených karet, příliš výrazný dropdown kontaktů a nevyváženou vertikální hierarchii.

## Návrh

- Jeden kompaktní, čistý composer podle nativního iOS Mailu.
- Navigation bar: Cancel, Nová zpráva, Send.
- `Komu` jako jeden flexibilní řádek s chips; autocomplete se zobrazí **jen při psaní** a jako kompaktní seznam pod řádkem.
- Subject jako jednoduchý řádek se separator-em, bez samostatné karty.
- Body jako hlavní volná plocha s placeholderem; bez umělého „Zpráva“ titulku.
- Přílohy jako kompaktní řádky pouze pokud existují; add actions jako nenápadné toolbar-like buttons.
- Žádný footer „Odesláno z openMail iOS“.
- Adaptivní systémové barvy, dark mode, spacing a typografie sjednotit s Inbox/Settings.

## Funkce k zachování

- Kontaktové chips, filtrování uložených kontaktů, diakritika při filtrování.
- Kliknutí na návrh přidá kontakt; ruční e-mail zůstává podporovaný.
- Autokorekce, návrhy slov a česká diakritika v TextEditoru.
- Subject, odeslání, přílohy ze souborů/fotek, mazání příloh, alerty a auth/session chování.

## Implementace

1. Designer upraví Frame0 návrh `Composer — Redesigned` podle výše uvedené hierarchie.
2. Po schválení mockupu designer přepíše pouze `ios/openMail/Views/ComposerView.swift` a případně potřebné `Localizable.xcstrings` klíče.
3. Zachovat současnou funkční logiku autocomplete a odesílání; měnit pouze layout/styling, pokud není nutná oprava chování.
4. Ověřit `xcodegen generate` a iOS build.
5. Verzi bumpovat až po samostatném potvrzení konkrétního release čísla.

## Omezení

- Žádné změny backendu.
- Žádné změny Inboxu, Settings ani Contacts mimo Composer.
- Žádný release/source update bez dalšího potvrzení.

## Dodatek po upřesnění požadavku

Uživatel požaduje pouze implementaci nového UI kódu Composeru. Frame0 redesign není součástí implementace a nesmí se dále upravovat. Implementace se omezuje na `ComposerView.swift` a nezbytné lokalizační klíče; bez bumpu verze, buildu release a source update.
