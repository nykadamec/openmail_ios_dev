# Plán: Předělat email reader na samostatnou stránku

## Cíl
Přestat používat modal/popup pro zobrazení e-mailu a místo toho otevírat e-mail jako samostatnou stránku (`/email/<id>`). To vyřeší problémy s iOS Safari viewportem, scrollováním a obsahem pod toolbarem.

## Proč to dělat
- Modal v fixed fullscreen může na iOS Safari způsobovat problémy s výpočtem viewportu po zavření.
- Samostatná stránka má přirozené scrollování a výšku dokumentu, takže obsah půjde pod Safari toolbar bez hacků.
- Mobilní tab bar může zůstat skrytý na stránce detailu e-mailu, stejně jako teď.

## Soubory k úpravě / vytvoření
1. `src/openmail/routes/public.py` – přidat route `/email/<int:email_id>`.
2. `src/openmail/routes/emails.py` – upravit `GET /api/emails/<id>`, aby se e-mail při načtení označil jako přečtený (už se děje, ale ověříme).
3. `templates/email.html` – nový template pro detail e-mailu.
4. `static/js/app.js` – klik na e-mail přejde na `/email/<id>` místo `openEmail()`.
5. `static/app.css` – upravit styly pro detail stránky, skrýt tab bar na stránce `/email/*`, přizpůsobit reader layout.
6. `static/js/email.js` – nový modul pro stránku detailu (načtení e-mailu, tlačítko zpět, označení přečteného).

## Krok za krokem

### 1. Backend route pro detail stránky
V `src/openmail/routes/public.py` přidat:
```python
@bp.route("/email/<int:email_id>")
@login_required
def email_detail(email_id: int):
    email = email_service.get_email(email_id)
    if not email:
        return redirect(url_for('public.index'))
    return render_template("email.html", email=email, from_email=FROM_EMAIL)
```

### 2. Template `templates/email.html`
Vytvořit nový HTML template:
- Meta tagy jako v `index.html` (viewport, PWA, theme-color, apple-mobile-web-app-capable).
- Header s tlačítkem zpět a názvem složky / předmětem.
- Meta informace: odesílatel, příjemce, čas.
- Tělo e-mailu (plain text + HTML iframe).
- Přílohy.
- Skrytý tab bar (prostě ho nebudeme vkládat do template).
- Načíst statický modul `/static/js/email.js`.

### 3. Načtení a označení e-mailu jako přečtený
`GET /api/emails/<id>` už v `email_service.get_email()` nastavuje `is_read = 1`. Stačí zajistit, že frontend detail stránky to zavolá.

### 4. Frontend – přechod na detail stránky
V `static/js/app.js` upravit click handler na `.email-card`:
```js
// Místo openEmail(id):
window.location.href = `/email/${id}`;
```

### 5. Nový modul `static/js/email.js`
Vytvořit modul, který po načtení stránky:
- Zavolá `/api/emails/<id>` pro načtení dat.
- Vykreslí předmět, meta, tělo, přílohy.
- Připojí handler na tlačítko zpět (`history.back()`).

### 6. CSS úpravy
- Skrýt tab bar na stránce `/email/*` (už máme `body.reader-open .tab-bar-wrap`, ale pro detail stránky to nepoužijeme; raději přidáme třídu na `body` v `email.html` např. `page-email-detail` a CSS `.page-email-detail .tab-bar-wrap { display: none; }`).
- Upravit `.reader` nebo vytvořit `.email-detail` layout tak, aby obsah šel přirozeně pod Safari toolbar.
- Header na detail stránce bude fixed/sticky s pozadím a blur.

### 7. Odstranění nebo zachování starého modal readeru
- V `index.html` ponecháme `.reader` div pro desktop, ale na mobilu se nepoužije.
- V `app.js` zachováme `openEmail()`/`closeReader()` pro desktop, ale na mobilu přejde na `/email/<id>`.

## Ověření
- Otevřít inbox na mobilu, kliknout na e-mail → otevře se `/email/<id>`.
- Ověřit, že obsah e-mailu jde scrollovat až pod Safari toolbar.
- Ověřit, že mobilní tab bar není vidět.
- Ověřit, že tlačítko zpět vrací do inboxu.
- Ověřit, že e-mail se označí jako přečtený.
- Ověřit, že na desktopu zůstává stávající chování (modal), pokud ho chceme ponechat.
