# Plán: Remember Me / Zůstat přihlášen pro iOS 0.0.9

## Aktuální problém

- `APIClient` používá `URLSession.shared` a backend session cookie `session_id`.
- iOS login nyní posílá `remember_me=1` vždy, přestože UI volbu nemá.
- `AuthStore` existuje pouze v paměti; po restartu aplikace se vždy vytvoří jako nepřihlášený.
- `/api/me` se při startu nevolá, takže existující cookie se nevyužije k obnově UI.
- Neexistuje Keychain vrstva.
- Backend podporuje běžnou session přibližně 15 minut a remembered session až 30 dní s rolling `last_seen`.

## Cíl 0.0.9

Přidat skutečnou volbu **Zůstat přihlášen** a bezpečně obnovovat session po restartu aplikace bez ukládání hesla.

## 1. Keychain vrstva

Přidat `ios/openMail/API/KeychainStore.swift` nad Security frameworkem:

- service: `nykadamec.openmail.auth`,
- account: například `session_id`,
- uložit pouze hodnotu session cookie,
- nikdy neukládat heslo ani nelogovat cookie,
- použít `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
- bezpečně ošetřit Keychain chyby bez pádu aplikace,
- podporovat save/read/delete.

Session cookie je citlivý bearer credential; při ukládání použít pouze zařízení, ne iCloud migraci.

## 2. APIClient session management

Upravit API klienta tak, aby měl kontrolovatelnou cookie storage pro openMail:

- používat vlastní `URLSession` místo nekontrolovatelného spoléhání na globální `URLSession.shared`,
- při úspěšném loginu získat `session_id` cookie pro `email.adamec.pro`,
- při aktivním Remember Me uložit cookie do Keychain,
- při vypnutém Remember Me cookie do Keychain neukládat,
- při obnově načíst cookie z Keychain, vytvořit `HTTPCookie` a vložit ji do session storage,
- odstranit pouze openMail `session_id` cookie pro `email.adamec.pro`.

`APIClient.login(username:password:rememberMe:)` nesmí natvrdo posílat `remember_me=1`; hodnotu musí dostat z UI/AuthStore.

## 3. Login UI

V `LoginView.swift` přidat:

- Toggle/checkbox `Zůstat přihlášen` / `Stay signed in`,
- konzervativní výchozí hodnotu `false`,
- stručný hint typu „Až 30 dní na tomto zařízení“,
- zachování username podle UX, ale neukládat heslo mimo Keychain/session mechanismus,
- loading stav při loginu a lokalizované chyby.

Při submitu předat `rememberMe` do `AuthStore.login` a následně do `APIClient.login`.

## 4. Obnova session při startu

Rozšířit `AuthStore` o `isRestoringSession` a `restoreSession() async`.

Start flow:

1. `OpenMailApp` vytvoří `AuthStore`.
2. Root zobrazí neutrální loading stav místo okamžitého LoginView.
3. `AuthStore.restoreSession()` zkusí aktuální cookie.
4. Zavolá `/api/me`.
5. Pokud cookie chybí, načte Keychain cookie, vloží ji do API session a zkusí `/api/me` znovu.
6. Při úspěchu nastaví `user` a `isAuthenticated`.
7. Při 401 smaže neplatný Keychain credential/cookie a zobrazí LoginView.
8. Při síťové chybě neprohlásí uživatele automaticky za odhlášeného; zobrazí retry/offline stav.

Automatické ukládání hesla a tiché opakované přihlášení heslem se nepoužije.

## 5. Centrální expirace session

401 z kteréhokoli API requestu musí vést ke stejnému výsledku:

- smazat cookie a Keychain session,
- nastavit `user = nil` a `isAuthenticated = false`,
- zabránit souběžným logoutům,
- zobrazit lokalizovanou zprávu „Relace vypršela, přihlaste se znovu“.

## 6. Logout

`AuthStore.logout()` a `APIClient.logout()` musí:

- best-effort zavolat backend `/logout`,
- vždy lokálně smazat openMail session cookie,
- vždy smazat Keychain credential,
- vyčistit stav AuthStore i při chybě sítě.

Nebude se mazat celý `HTTPCookieStorage` ani globální `URLCredentialStorage`, aby logout nezasahoval do jiných aplikací/procesů.

## 7. Lokalizace

Doplnit `Localizable.xcstrings` pro `cs` a `en`:

- `login.rememberMe`,
- `login.rememberMeHint`,
- `login.restoringSession`,
- `login.sessionExpired`,
- `login.restoreFailed`,
- `login.retry`.

## 8. Verze a release

Pro verzi `0.0.9`:

- `MARKETING_VERSION: "0.0.9"`,
- `CURRENT_PROJECT_VERSION: "9"`,
- aktualizovat `ios/update.json` na `0.0.9`/build `9`,
- přidat changelog o Remember Me, Keychain session a obnově po restartu,
- aktualizovat bundled release notes v `UpdateService.swift`,
- aktualizovat `openmail-source/source.json` pro KSign/ESign/AltStore,
- vytvořit release `v0.0.9` s unsigned arm64 IPA.

`minimumSupportedVersion` ponechat minimálně na `0.0.8`, dokud nebude ověřena migrace; zvýšit ji pouze pokud nová verze vyžaduje nekompatibilní session změnu.

## 9. Ověření bez simulátoru

Pouze device-only workflow:

- Swift parse/diff check,
- `xcodegen generate`,
- `xcodebuild -sdk iphoneos` unsigned IPA build,
- ověření bundle verze `0.0.9`/build `9`, arm64 a IPA struktury,
- na fyzickém zařízení ověřit Remember Me vypnuté/zapnuté, restart, expirovanou session, ruční logout a offline start.

Simulator, `simctl` ani `iphonesimulator` build se nepoužije.
