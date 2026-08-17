# Plán: upozornění na novou iOS IPA verzi přes GitHub

## Cíl

Nativní aplikace nebude sama upravovat Swift/SwiftUI kód ani instalovat novou IPA. Bude pouze kontrolovat dostupnost novější verze a nabídne bezpečný odkaz:

1. v Account → Nastavení aplikace zobrazí aktuální verzi,
2. zkontroluje metadata posledního GitHub release,
3. pokud je dostupná novější verze, zobrazí minimalistický kliknutelný button,
4. po klepnutí otevře GitHub release v systémovém výchozím prohlížeči,
5. instalaci nové IPA provede uživatel přes AltStore/Sideloadly/TrollStore.

## Nutný vstup

GitHub repozitář projektu je:

```text
https://github.com/nykadamec/openmail_ios_dev
```

Implementace bude používat:

```text
https://github.com/nykadamec/openmail_ios_dev/releases/latest
```

Lepší varianta je veřejný raw manifest verzí, například:

```text
https://raw.githubusercontent.com/nykadamec/openmail_ios_dev/main/ios/update.json
```

Bezpečnější manifest umožní porovnat verzi a otevřít přesný release URL bez parsování HTML stránky GitHubu.

## Manifest

Přidat do GitHub repozitáře soubor `ios/update.json`:

```json
{
  "version": "0.0.1",
  "build": 1,
  "title": "openMail 0.0.1",
  "releaseURL": "https://github.com/nykadamec/openmail_ios_dev/releases/tag/v0.0.1",
  "ipaURL": "https://github.com/nykadamec/openmail_ios_dev/releases/download/v0.0.1/openMail-unsigned.ipa",
  "minimumSupportedVersion": "0.0.1"
}
```

Manifest bude obsahovat pouze veřejná metadata. Nebudou v něm hesla, session cookie ani API credentials.

## Implementace iOS

### 1. Verze aplikace

V `ios/project.yml` explicitně nastavit:

```yaml
MARKETING_VERSION: "0.0.1"
CURRENT_PROJECT_VERSION: "1"
```

Aktuální verzi načítat z:

- `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`,
- `Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")`.

### 2. Update service

Vytvořit například `ios/openMail/API/UpdateService.swift`:

- načte manifest přes `URLSession`,
- nastaví timeout a kontrolu HTTPS,
- dekóduje manifest přes `Codable`,
- porovná vzdálenou verzi/build s lokální verzí,
- rozliší `available`, `upToDate`, `unavailable`, `invalidManifest`, `networkError`,
- nebude blokovat Inbox ani login,
- výsledek bude cacheovaný s datem poslední kontroly.

Kontrola se provede:

- při otevření Account → Nastavení aplikace,
- ručně přes tlačítko `Zkontrolovat aktualizace`,
- případně jednou při startu aplikace, pokud nebude zvyšovat latenci.

### 3. Account → Nastavení aplikace

Do `SettingsView` přidat sekci:

- aktuální verze `0.0.1 (1)`,
- stav `Používáte aktuální verzi`,
- při nové verzi minimalistický button například `Nová verze 0.0.2`,
- tlačítko `Zkontrolovat aktualizace`,
- datum poslední kontroly.

Button bude vizuálně jemný, nativní SwiftUI, s případným `.ultraThinMaterial` stylem navazujícím na existující feedback UI. Musí mít minimálně 44 pt touch target a VoiceOver label.

### 4. Otevření GitHubu

Po klepnutí:

```swift
openURL(URL(string: releaseURL))
```

Použít `@Environment(\.openURL)`. Otevírat se bude přesný `releaseURL` z manifestu, ne lokální WebView. Pokud URL není validní, button se nezobrazí a zobrazí se bezpečná chyba.

## Bezpečnost a spolehlivost

- Přijímat pouze `https://` URL.
- Povolit pouze očekávaný GitHub host nebo předem definovaný host.
- Neinstalovat IPA z aplikace automaticky.
- Neprovádět `git pull`, patchování binárky ani dynamické načítání Swift kódu.
- Při nedostupném GitHubu aplikace normálně funguje a Account zobrazí pouze stav kontroly.
- Chybný manifest nesmí způsobit pád aplikace.
- Ověřit, že vzdálená verze je skutečně novější pomocí build čísla, ne pouze lexikografickým porovnáním stringu.

## Lokalizace

Doplnit do `Localizable.xcstrings` v češtině a angličtině:

- `settings.app`
- `settings.appVersion`
- `settings.checkForUpdates`
- `settings.checkingForUpdates`
- `settings.upToDate`
- `settings.updateAvailable`
- `settings.openRelease`
- `settings.updateCheckFailed`
- `settings.invalidUpdateManifest`
- accessibility label a hint pro update button.

## Build a release workflow

1. Nastavit verzi v `ios/project.yml` na `0.0.1`, build `1`.
2. Vygenerovat Xcode projekt přes `xcodegen`.
3. Pouze device build přes `xcodebuild -sdk iphoneos`.
4. Vytvořit `ios/dist/openMail-unsigned.ipa`.
5. Vytvořit GitHub release `v0.0.1` a přiložit IPA.
6. Commitnout `ios/update.json` s odkazem na release.
7. Pro další release zvýšit například na `0.0.2`, build `2`, vytvořit novou IPA a aktualizovat manifest.

## Ověření

- Žádný iOS simulátor, `simctl` ani `iphonesimulator` SDK.
- Device-only unsigned IPA build.
- Ověřit `CFBundleShortVersionString = 0.0.1` a `CFBundleVersion = 1`.
- Testovat fyzicky:
  - aktuální verze → button se nezobrazí nebo ukáže aktuální stav,
  - vyšší vzdálená verze → zobrazí se kliknutelný button,
  - klepnutí → otevře Safari/GitHub release,
  - offline GitHub → aplikace zůstane použitelná,
  - chybný manifest → žádný pád,
  - neplatné/ne-HTTPS URL → neotevírat.
