# Plán: Swipe navigace mezi taby v Openmail

## Cíl
Přidat gesto swipe doleva/doprava na hlavní obrazovku (email list), které přepíná mezi hlavními taby: **Inbox → Starred → Spam → Sync** a zpět.

## Soubory k úpravě
1. `static/js/app.js` – přidat touch event listener a logiku přepínání tabů.
2. `static/app.css` – přidat přechodovou animaci při změně tabu (volitelné).
3. `templates/index.html` – není nutné měnit, taby už jsou definované.

## Implementace
### Kroky
1. V `app.js` přidat proměnné pro sledování touch gesta:
   - `touchStartX`, `touchStartY`
   - práh pro swipe (např. 80 px)
   - detekce horizontálního vs vertikálního scrollu
2. Přidat `touchstart`, `touchmove`, `touchend` listener na `#content` nebo celou stránku.
3. Při `touchend` vypočítat rozdíl a přepnout tab:
   - Swipe doleva → další tab v pořadí
   - Swipe doprava → předchozí tab v pořadí
4. Zabránit swipu, pokud je otevřený reader, composer, menu nebo modal.
5. Přidat vizuální feedback (např. posunutí seznamu během swipe a snap po release).

## Pořadí tabů
```
['inbox', 'starred', 'spam']
```
- Sync není stránka, ale akční tlačítko, proto není součástí swipe navigace.

## Ověření
- Otestovat na mobilním zařízení v Safari.
- Ověřit, že vertikální scroll neinterferuje se swipe.
- Ověřit, že nefunguje swipe, když je otevřen reader/composer.
