# Plán: Oprava Settings podle screenshotu

**Stav:** schváleno implementací požadavku uživatele
**Návratový bod:** `backup-0.0.22-before-settings-fix` (`860a1e3`)
**Pracovní větev:** `release-0.0.22`

## Nálezy ze screenshotu

1. Profile karta má bílé pozadí, ale v dark mode je text bílý na bílém pozadí, proto je vidět pouze avatar.
2. Navigation karta má stejný kontrastní problém; ikony a text jsou prakticky neviditelné.
3. Historie zobrazuje lokalizační klíč `settings.changelogVersion` místo přeloženého textu.
4. Settings je v angličtině, což je očekávané při anglickém systémovém jazyce; po opravě musí fungovat CS i EN.

## Implementace

- Designer upraví adaptivní barvy karet a textů pro light/dark mode bez ztráty minimalistického stylu.
- Zachová Profile + Navigation strukturu, avatar a jednobarevné ikony.
- Opraví dynamický changelog title tak, aby se lokalizoval přes existující xcstrings klíč a bezpečný placeholder.
- Ověří, že `Localizable.xcstrings` obsahuje odpovídající CS i EN variantu.
- Nespustí se redesign jiných obrazovek ani změny backendu.

## Verifikace

1. `xcodegen generate`
2. `bash ios/scripts/build-ipa.sh`
3. Ověření IPA verze a instalace/screenshot na připojeném iPhonu v dark mode.
4. Kontrola, že screenshot neobsahuje lokalizační klíče a Profile/Navigation obsahují viditelný text i ikony.
