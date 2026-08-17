# Plán: diagnostika refreshu, Account nastavení a verze IPA

## Zjištěný stav

### Refresh

`InboxView.fetch()` zachová starý seznam při chybě, ale všechny chyby převádí pouze na obecné `Refresh failed`. Není vidět, zda selhal:

- síťový request nebo TLS/DNS,
- session cookie,
- HTTP 401/403/5xx,
- Cloudflare redirect nebo HTML odpověď místo JSON,
- dekódování `EmailPage`/`EmailSummary`.

API request jde na pevné `https://email.adamec.pro/api/emails` přes `URLSession.shared` a session cookie. Backend endpoint `/api/emails` podle aktuálního kontraktu vrací `{emails, total, limit, offset}`.

### Account

`MainTab` už má třetí tab Account, ale `SettingsView` obsahuje pouze účet a odhlášení. Chybí verze aplikace, diagnostika, ruční sync a update nastavení.

### Update přes Git

Unsigned IPA nemůže sama provést `git pull` a nahradit svůj iOS executable. iOS sandbox, podpis kódu a instalace aplikací tomu brání. Git lze použít pouze jako zdroj:

- dat/configu, který aplikace bezpečně stáhne,
- nebo nové IPA, které musí být následně nainstalováno externím sideload nástrojem.

## Fáze 1: diagnostika refresh chyby

1. Upravit `ios/openMail/API/APIClient.swift` tak, aby zachoval strukturované chyby:
   - network/`URLError` včetně kódu,
   - HTTP status 401, 403, 5xx,
   - decode error s názvem očekávaného typu,
   - bezpečný prefix URL bez cookies, hesel a citlivých dat.
2. Ověřit, že login, `/api/me` a `/api/emails` používají stejnou `URLSession` cookie storage.
3. Do refresh feedbacku zobrazit uživatelsky bezpečnou zprávu, zatímco technický detail logovat pouze do debug logu.
4. Rozlišit v UI:
   - session expired → odhlášení,
   - server/network failure → starý seznam zůstane viditelný,
   - decode/API contract failure → chyba kompatibility,
   - úspěšný prázdný výsledek → skutečně prázdný inbox.
5. Ověřit přesný response body/status bez ukládání session cookie do logu.

## Fáze 2: stabilní refresh flow

1. Zachovat existující atomickou aktualizaci seznamu.
2. Přidat cancellation/lock pro souběh:
   - první načtení,
   - pull-to-refresh,
   - změna složky,
   - změna vyhledávání.
3. Starší request nesmí přepsat výsledek novějšího requestu.
4. `loadMeta()` nesmí zablokovat načtení e-mailů, pokud selžou pouze stats nebo folders.
5. Po opravě znovu zobrazovat Glass feedback pro:
   - počet nových e-mailů,
   - inbox bez nových zpráv,
   - bezpečně formulovanou chybu.

## Fáze 3: Account → App Settings

1. Do `SettingsView` přidat samostatné tlačítko/sekci `Nastavení aplikace`.
2. V nastavení zobrazit:
   - verzi aplikace z `Bundle.main`;
   - stav posledního refresh/sync;
   - ruční `Synchronizovat e-maily`;
   - případně adresu API pouze jako read-only diagnostický údaj.
3. Ruční sync nesmí znamenat update binárky. Pokud se použije `/api/sync`, po dokončení se znovu načte Inbox.
4. Přidat lokalizaci pro češtinu i angličtinu.

## Fáze 4: zvolený update mechanismus

### Varianta A — doporučená: aktualizace dat/configu

- Account nastavení obsahuje přepínač `Automaticky aktualizovat data`.
- Při startu aplikace a ručním syncu se zavolá backend `/api/sync`, následně `/api/emails`.
- Stav a čas poslední aktualizace se uloží lokálně.
- Po restartu aplikace se načtou aktuální e-maily ze serveru.
- Žádné stahování executable ani Git repozitáře do sandboxu.

### Varianta B — update nové IPA přes Git release

- Aplikace pouze načte metadata release z bezpečného HTTPS endpointu/manifestu.
- Zobrazí dostupnou verzi a odkaz/instrukce pro stažení IPA.
- Samotné podepsání a instalaci provede AltStore/Sideloadly/TrollStore nebo jiný externí nástroj.
- Aplikace se sama po restartu nemůže nahradit novým executable.

Git repozitář se nesmí stahovat a spouštět přímo v aplikaci jako mechanismus aktualizace kódu.

## Fáze 5: verze IPA

Do `ios/project.yml` explicitně nastavit:

- `MARKETING_VERSION: "0.0.1"`
- `CURRENT_PROJECT_VERSION: "1"`

Build ověřit přes generovaný `Info.plist` jako:

- `CFBundleShortVersionString = 0.0.1`
- `CFBundleVersion = 1`

## Ověření

- Bez simulátoru, bez `simctl` a bez `iphonesimulator` SDK.
- `xcodegen generate` v `ios/`.
- pouze `xcodebuild -sdk iphoneos` s `CODE_SIGNING_ALLOWED=NO`.
- `ios/dist/openMail-unsigned.ipa`.
- ZIP struktura `Payload/openMail.app`.
- `lipo -archs` = `arm64`.
- ověření Bundle ID a verze `0.0.1` přes `plutil`.
- manuální test na fyzickém zařízení:
  - úspěšný refresh,
  - refresh bez nových e-mailů,
  - vypnutá síť,
  - expirovaná session,
  - ruční sync v Account nastavení,
  - restart aplikace a načtení aktuálních dat.

## Rozhodnutí před implementací

Je nutné zvolit, co znamená „update přes Git“:

1. aktualizace e-mailových dat přes backend (`/api/sync`) — bezpečná a doporučená,
2. kontrola dostupnosti nové IPA/release z Git zdroje — instalace zůstane na externím sideload nástroji.
