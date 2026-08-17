# Plán: nativní iOS klient pro openMail

## Zadání (schváleno uživatelem)

- Nativní iOS aplikace, **SwiftUI**, jen iPhone.
- Deployment target: **iOS 27** (SDK 27.0 dostupné, Xcode 27.0).
- **Bundle ID:** `nykadamec.openmail`.
- Cíl: **unsigned `.ipa`** pro sideload (AltStore / Sideloadly / TrollStore / jailbreak).
- **Bez push notifikací.**
- Lokalizace: **podle systému** (`cs` / `en`).
- Klient konzumuje existující Flask REST API na `https://email.adamec.pro` — žádná e-mailová logika v aplikaci.

## Architektura

```
iOS openMail (SwiftUI, iOS 27) ──HTTPS──► email.adamec.pro/api/*
                                           session cookie (URLSession)
```

- Auth: `POST /login` (form-urlencoded) → server nastaví `session_id`; `URLSession` cookie storage ji drží dál.
- Ověření relace: `GET /api/me`.
- Žádná lokální databáze; stav je v paměti, data se načítají z API.

## Build pipeline (unsigned IPA)

1. `xcodegen` → generuje `openMail.xcodeproj` z `ios/project.yml`.
2. `xcodebuild -project openMail.xcodeproj -scheme openMail -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
3. Zabalí `build/Build/Products/Release-iphoneos/openMail.app` do `Payload/` a zazipuje → `openMail-unsigned.ipa`.
4. Ověření artefaktu: struktura zipu, `Info.plist`, `lipo -archs` = arm64.

## API kontrakt (ověřený z backendu)

| Endpoint | Metoda | Tělo / parametry | Odpověď |
|---|---|---|---|
| `/login` | POST | form: `username`, `password`, `remember_me` | set-cookie `session_id` |
| `/api/me` | GET | – | `{id, username, email, from_name}` |
| `/api/emails` | GET | `folder`, `direction`, `starred`, `is_spam`, `is_trash`, `custom_folder_id`, `q`, `limit`, `offset` | `{emails:[...], total, limit, offset}` |
| `/api/emails/<id>` | GET | – | plný email vč. `body_text`, `body_html`, `attachments:[{filename, content_type}]` |
| `/api/emails/<id>` | PATCH | `{is_starred, is_read, folder, is_spam, is_trash, custom_folder_id}` | email |
| `/api/send` | POST | JSON `{to, subject, body, attachments:[{filename, content(base64), content_type}]}` | `{status:"sent", id}` |
| `/api/attachments/<email_id>/<filename>` | GET | `?download=1` volitelně | soubor |
| `/api/stats` | GET | – | `{inbound, outbound, starred, unread, spam, trash}` |
| `/api/folders` | GET | – | custom složky `{id, name, color, icon}` (defenzivní parsing) |
| `/api/logout` | POST | – | – |

Seznamový email: `{id, folder, custom_folder_id, sender_name, sender_email, recipient, subject, preview, is_starred, is_read, is_spam, is_trash, created_at, received_at}`.

## Rozsah v1 (potvrzeno)

1. Přihlášení + session.
2. Složky: inbox, starred, sent, spam, trash + custom.
3. Seznam e-mailů s neomezeným stránkováním (infinite scroll, limit 50).
4. Detail e-mailu: HTML (WKWebView, bez scriptů) / plain text.
5. Napsat a odeslat e-mail s přílohami.
6. Přílohy u e-mailu: stažení, zobrazení (QuickLook).
7. Globální vyhledávání (`q`).
8. Hvězdička, stats v hlavičce, logout.

## Struktura souborů

```
ios/
├── project.yml
├── openMail/
│   ├── openMailApp.swift
│   ├── API/
│   │   ├── APIClient.swift      (URLSession, cookies, base64 přílohy)
│   │   ├── Models.swift         (Email, Attachment, Stats, Folder, User)
│   │   └── AuthStore.swift      (login/logout/me, @Observable)
│   ├── Views/
│   │   ├── LoginView.swift
│   │   ├── InboxView.swift       (seznam + složky + search + infinite scroll)
│   │   ├── EmailDetailView.swift (WKWebView wrapper, attachment list)
│   │   ├── ComposerView.swift    (to/subject/body/attachments/send)
│   │   └── SettingsView.swift    (účet, logout)
│   └── Resources/
│       ├── Localizable.xcstrings (cs, en)
│       └── Assets.xcassets
└── scripts/build-ipa.sh
```

## Ověření

1. `node`/git kontroly se netýkají; použít:
   - `xcodegen generate` bez chyb,
   - `xcodebuild` (simulator) build bez chyb,
   - simulátor: `simctl install + launch`, přihlášení a načtení inboxu z produkce,
   - `xcodebuild` (iphoneos, unsigned) build bez chyb,
   - kontrola `.ipa`: zip struktura `Payload/openMail.app`, `lipo -archs`, `plutil -p Info.plist` (bundle id `nykadamec.openmail`).
2. Smoke test na simulátoru (iPhone 17) proti `https://email.adamec.pro`.

## Bezpečnost

- Session cookie nikdy neukládat do kódu/repo.
- Žádné tajné klíče v aplikaci (backend drží RESEND/icloud credentials).
- ATS: HTTPS-only (doména je HTTPS, není potřeba exception).