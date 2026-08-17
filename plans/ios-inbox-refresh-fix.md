# Plán: bezpečný refresh Inboxu a Glass Effect feedback

## Požadavek

- Opravit pull-to-refresh v iOS Inboxu, při kterém seznam zmizí a zobrazí se `No messages`.
- Zachovat původní e-maily, dokud nové načtení úspěšně neskončí.
- Po úspěšném refreshi zobrazit počet skutečně nových e-mailů.
- Při neúspěchu zobrazit jemnou minimalistickou Glass Effect bublinu.
- Bez spuštění iOS simulátoru; ověřovat pouze device build a unsigned IPA.

## Implementace

1. Upravit `ios/openMail/Views/InboxView.swift`:
   - oddělit první načtení, změnu složky a pull-to-refresh,
   - nevymazávat aktuální `emails` před dokončením refresh requestu,
   - aplikovat novou stránku atomicky až po úspěchu,
   - porovnat ID původních a nově načtených e-mailů,
   - zachovat původní data při chybě,
   - zabránit souběžným refresh requestům,
   - rozlišit skutečně prázdný inbox od chyby.

2. Přidat znovupoužitelnou feedback komponentu:
   - `.ultraThinMaterial`, jemný rámeček, zaoblení a stín,
   - success / up-to-date / error stav,
   - automatické skrytí přibližně po 2–3 sekundách,
   - možnost zavření klepnutím,
   - světlý i tmavý režim,
   - VoiceOver label a dostatečný kontrast.

3. Doplnit lokalizaci v `ios/openMail/Resources/Localizable.xcstrings`:
   - `refresh.newEmails`,
   - `refresh.noNewEmails`,
   - `refresh.failed`,
   - `refresh.emptyInbox`,
   - včetně správné české/anglické pluralizace.

4. Opravit tiché zachytávání chyb tak, aby chyba nezpůsobila falešný stav `No messages`.

## Ověření

- `xcodegen generate`.
- Pouze device build přes `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`.
- Vytvořit `ios/dist/openMail-unsigned.ipa`.
- Ověřit ZIP strukturu, bundle ID, `MinimumOSVersion` a architekturu `arm64`.
- Nespouštět `simctl`, Simulator.app ani žádný `iphonesimulator` build.
