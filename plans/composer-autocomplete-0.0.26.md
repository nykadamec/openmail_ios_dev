# Plán: Composer autocomplete + oprava psaní 0.0.26

**Stav:** čeká na schválení
**Návratový bod:** `Latest-Dev` HEAD `e0847b6` (0.0.25)
**Cílová verze:** 0.0.26 (MARKETING_VERSION 0.0.26, CURRENT_PROJECT_VERSION 25)

## Cíl

1. **Autocomplete v poli Komu:** při psaní do `To` se pod polem zobrazí filtrované návrhy z uložených kontaktů (`/api/contacts`). Tap na `+` přidá kontakt jako chip.
2. **Oprava psaní v těle zprávy:** povolit diakritiku, návrhy slov, autokorekci (aktuálně vypnutá). 
3. **Design podle mockupu:** minimalistický iOS Mail styl (1 sekce vše) — stránka `openMail iOS Composer Mockup` (`-KC0LV0RB8rWM9SzeUnN-`) — bez footeru „Odesláno z...“.
4. **Verze 0.0.26:** bump project.yml + update.json + build IPA + GitHub release + source.json.

## Analýza současného stavu

- `ComposerView.swift`: `TextField("composer.to", text: $to)` — jeden string, bez chipů, bez filtrování. `TextEditor` pro body má `autocorrectionDisabled()` (proto nefunguje diakritika/návrhy). Přílohy fungují.
- `API`: `GET /api/contacts?q=` existuje, vrací list kontaktů. iOS `APIClient.listContacts` / `ContactsView` už to používá.
- `ContactsView` hvězdička opravena v 0.0.25 (starred-addresses).
- Mockup: postaven čistě na nové stránce, bez duplikátů, footer již smazán.

## Navrhované změny

### A. ComposerView.swift — UI

- `Komu:` řádek: `chips: [Contact]` + `toInput: String` (aktuální psaný text). Chips jako `ForEach` s `Rectangle` pill + avatar + `x` pro odebrání. Input je `TextField` vedle chips, filtrovat `contacts.filter { name/email contains prefix }`.
- Dropdown `Navržené kontakty`: `if !toInput.isEmpty && !filtered.isEmpty` zobrazit kartu (max 5 výsledků) pod polem Komu. Každý řádek: avatar 32 + jméno + email + `+` tlačítko. Tap přidá do chips, vyčistí input.
- Odeslání: `to` se sestaví jako `chips.map(\.email).joined(separator: ", ") + (toInput.isEmpty ? "" : ", \(toInput)")` — kompatibilní s backend `send(to:)`.
- Načtení kontaktů: `@State contacts: [Contact] = []`, `task { contacts = try await client.listContacts() }` při `onAppear`.
- Předmět beze změny, jen vizuální sladění s mockupem (oddělovače #e5e5ea).

### B. ComposerView.swift — psaní

- `TextEditor(text: $bodyText)`:
  - odstranit `.autocorrectionDisabled()` a `.textInputAutocapitalization(.never)` pokud je na body,
  - přidat `.autocorrectionDisabled(false)` (default), `spellChecking` povolit,
  - `smartDashesType`, `smartQuotesType` ponechat default (iOS),
  - `keyboardType(.default)`, `textContentType(.none)` pro body,
  - zajistit `font .system(17)`, `lineSpacing`, bez placeholder překryvu.

### C. APIClient.swift

- Ověřit `listContacts(q:)` existuje, pokud ne — přidat. Jinak beze změny.

### D. Localizable.xcstrings (pokud chybí)

- `composer.toPlaceholder` — „Přidat příjemce“, `composer.suggestedContacts` — „Navržené kontakty“, `composer.noSuggestions` — prázdný stav (volitelné). Vše cs+en translated.

### E. Verzování

- `ios/project.yml`: `MARKETING_VERSION 0.0.25 → 0.0.26`, `CURRENT_PROJECT_VERSION 24 → 25`
- `ios/update.json`: `version 0.0.25 → 0.0.26`, `build 24 → 25`, `title`, `releaseURL/ipaURL` na v0.0.26, `changelog` přidat 2 položky nahoře: „Autocomplete příjemců z kontaktů v Composeru“ + „Opravena diakritika a návrhy slov v těle zprávy“. History: přidat entry 0.0.25 se starým changelogem.
- `UpdateService.swift` komentář s aktuální verzí aktualizovat (volitelné).

## Implementační kroky

1. Větev: z `Latest-Dev` (e0847b6) → nová práce pro 0.0.26 (zůstane na Latest-Dev, nebo `release-0.0.26` — podle zvyku; navrhuji pracovat na `Latest-Dev` a po schválení tag v0.0.26).
2. Editor provede A+B (+D pokud potřeba), ověří `xcodegen generate`.
3. Fixer provede E (verze) + `bash ios/scripts/build-ipa.sh`, ověří plist 0.0.26/25.
4. Commit: `feat(ios): composer autocomplete + body autocorrection (0.0.26)` + samostatný `release: prepare iOS 0.0.26` nebo sloučit.
5. Push Latest-Dev, `gh release create v0.0.26`, update `/tmp/openmail-source/source.json` a push.

## Verifikace

- Build: `BUILD SUCCEEDED`, IPA 0.0.26/25.
- iOS: v Composeru psaní „Do“ nabídne Dominika, tap přidá chip, psaní těla nabízí diakritiku a slov.
- Kontakty prázdné → dropdown se nezobrazí.
- Dark mode: chips a karta návrhů viditelné.
- GitHub release + source.json `0.0.26` (raw cache 5 min).

## Omezení

- Žádné změny backendu.
- Žádné další UI mimo Composer (kromě verze).
- Footer „Odesláno z...“ se nikde nevrací.

## Rizika

- Filtrování case-insensitive, diakritika v jménech — řešit `folding(options:.diacriticInsensitive)`.
- Chip overflow (více příjemců) — `WrappingHStack` nebo `ScrollView horizontal`.
