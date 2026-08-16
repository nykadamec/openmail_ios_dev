# Plán opravy Sync tlačítka

## Zjištění

- Mobilní i desktopové tlačítko používají `data-action="sync"`.
- `static/js/app.js` připojuje handler přes `querySelector()`, takže obslouží pouze desktopové tlačítko.
- `syncEmails()` ignoruje odpověď z `POST /api/sync` a čeká na SSE událost `sync_complete`.
- Backend při ruční synchronizaci vrací výsledek přímo z endpointu, ale `sync_complete` neposílá.

## Navržené změny

1. Připojit `syncEmails` k mobilnímu prvku `[data-action="sync"]`.

## Schválený rozsah

- Schváleno: pouze oprava mobilního handleru.
- Neschváleno pro tuto změnu: úprava zpracování výsledku API nebo SSE.

## Ověření

- Syntax check upraveného JavaScriptu.
- Ověření mobilního portálu kliknutím na Sync a kontrolou, že se požadavek spustí.
- Kontrola, že desktopové tlačítko zůstane funkční.

## Stav

- Hotovo: mobilní i desktopový Sync handler se registrují přes `querySelectorAll()`.
- Ověřeno: `node --check static/js/app.js` a `git diff --check` prošly.
- Ověřeno v portálu `mobile`: kliknutí vyvolalo `POST /api/sync` s odpovědí HTTP 200.
