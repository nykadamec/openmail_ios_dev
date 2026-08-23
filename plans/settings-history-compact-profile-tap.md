# Plán: kompaktní Version History + klikatelný Profile

**Stav:** čeká na provedení designerem
**Návratový bod:** `backup-0.0.23-history-profile` (`2a68d94`)
**Pracovní větev:** `release-0.0.23`

## Cíl

1. **Version history** v hlavním Settings bude jedna kompaktní karta.
   - V **zavřeném** stavu se v ní zobrazí jen řádek `Version history · Latest 0.0.23 · chevron`. Aktuální verze se bere z `updateService.currentVersion`, nikoliv z historie.
   - **Kliknutím** na kartu se rozbalí inline seznam ostatních verzí (0.0.22 → 0.0.15) jako vnořené řádky, ne jako samostatná obrazovka. Každý řádek zobrazí jen verzi a zůstane minimalistiký.
   - Celkový prostor se zmenší, ale starší verze zůstávají přístupné.

2. **Profile karta** bude celá klikací.
   - Celý řádek s avatarem, jménem a e-mailem se změní na `Button`/`NavigationLink` směřující na nový samostatný `ProfileDetailView`.
   - Profil detail zobrazí stejné údaje, ale bez zbytečných řádků navíc; minimální obsah je username a email.
   - Pravděpodobně bude stačit nové `struct ProfileDetailView: View` uvnitř `SettingsView.swift` (nebo samostatný soubor).

## Omezení

- Designer může zapisovat jen do `ios/openMail/Views/SettingsView.swift` a případně nového `ios/openMail/Views/ProfileDetailView.swift`.
- Smí měnit `Localizable.xcstrings` pouze pokud chybí klíč pro titulek dropdownu (`settings.versionHistoryCompact`).
- Žádné úpravy backendu, jiné obrazovky, lokalizace jinde; zachovat minimalistický styl.
- Nesmí zvýšit verzi, neprovádí release/source update.

## Implementační kroky

1. Nahradit `changelogHistorySection` novým kompaktním blokem: vnější `Button`/`DisclosureGroup` se třemi údaji (název + latest verze + chevron). Po rozbalení iteruje `updateService.mergedHistory()` mimo aktuální verzi a vypíše jednotlivé verze.
2. Přidat nový `ProfileDetailView` (nebo `ProfileRow` s vlastní navigací), přidat `NavigationLink` kolem stávající Profile `HStack`.
3. Ověřit, že `settings.versionHistoryCompact` existuje v xcstrings pro CS i EN; pokud ne, doplnit.
4. `xcodegen generate` + `bash ios/scripts/build-ipa.sh`.

## Verifikace

- Build bez chyb.
- Plist: `CFBundleShortVersionString=0.0.23`, `CFBundleVersion=23`.
- iPhone screenshot: Version history = 1 řádek, Profile celý klikací, dropdown rozbalený ukazuje starší verze, nic neztratilo text v dark mode.
