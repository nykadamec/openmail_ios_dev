# Plán úpravy Settings tlačítka

## Zjištění

- Horní header obsahuje duplicitní tlačítko `data-action="openSettings"`.
- Sidebar obsahuje druhé tlačítko se stejnou akcí.
- `static/js/app.js` registruje handler přes `querySelector()`, takže obslouží jen první tlačítko — horní headerové.

## Navržené změny

1. Odstranit horní Settings icon button z `templates/index.html`.
2. Zajistit registraci `openSettings` přes všechny odpovídající prvky v `static/js/app.js`, aby sidebarový button byl funkční i při budoucím přidání dalšího ovládacího prvku.
3. Neměnit backend ani existující Settings panel.

## Schválený rozsah

- Schváleno: robustní varianta přes `querySelectorAll()`.
- Povolené soubory: `templates/index.html`, `static/js/app.js`.
- Backend a Settings panel se nemění.

## Ověření

- Syntax check JavaScriptu a kontrola diffu.
- Ověřit v portálu `Email`, že horní tlačítko zmizelo.
- Kliknout na Settings v sidebaru a ověřit otevření Settings panelu.

## Stav

- Hotovo: horní Settings button odstraněn.
- Hotovo: handler používá `querySelectorAll()`.
- Ověřeno: `node --check static/js/app.js` a `git diff --check` prošly.
- Flask proces byl restartován, aby načetl změněnou šablonu.
- Portál po restartu vyžaduje nové přihlášení, takže kliknutí v portálu čeká na autentizaci.
