# Plán: Automatický logout při chybějícím DEK (zašifrované e-maily)

> **Cíl:** Když server po restartu nemá v paměti DEK (Data Encryption Key) pro přihlášeného uživatele, aplikace automaticky odhlásí uživatele a přesměruje ho na login, místo aby mu zobrazila zašifrované řetězce.

---

## 🔍 Příčina problému

- E-maily se šifrují pomocí DEK (`USER_DEKS` slovník v paměti serveru).
- DEK se do paměti načte **pouze** při `verify_user()` (login heslem) nebo `create_user()` (setup).
- Session je uložená v SQLite tabulce `sessions` → **přežije restart serveru**.
- DEK v `USER_DEKS` je jen v RAM → **po restartu zmizí**.
- Po restartu má uživatel platnou session cookie, `current_user()` ho pustí dovnitř, ale `_get_user_dek(user_id)` vrátí `None`.
- `decrypt_email_field()` při chybějícím DEK vrátí zašifrovaný token tak jak je → v UI se zobrazí "šifrované" řetězce.

---

## 🛠️ Navrhované řešení

**Princip:** Pokud je uživatel autentizovaný (platná session), ale nemá DEK v paměti, považovat ho za "neodemčeného" → vrátit `401` a smazat session. Frontend už má na 401 redirect na `/login`. Po opětovném přihlášení heslem se DEK obnoví a e-maily se dešifrují.

---

## 📋 Úkoly

### 1. Nový helper `_user_unlocked(user_id)` v `app.py`

Přidat malou funkci, která ověří, že DEK je v paměti:

```python
def _user_unlocked(user_id: int | None) -> bool:
    """True, pokud má uživatel odemčený DEK v paměti."""
    return user_id is not None and user_id in USER_DEKS
```

**Soubor:** `app.py` (vedle `_get_user_dek`, ~řádek 76)
**Obtížnost:** ⭐

---

### 2. Upravit `login_required` tak, aby hlídal DEK

`app.py:492` — `login_required` decorator.

Aktuálně jen kontroluje `current_user()`. Rozšířit tak, aby navíc kontroloval, že DEK je v paměti. Pokud není:
- smazat session (aby cookie nepřežívala),
- pro API cesty vrátit `401`,
- pro HTML cesty redirect na `/login`.

```python
def login_required(f):
    from functools import wraps
    @wraps(f)
    def wrapped(*args, **kwargs):
        user = current_user()
        if not user or not _user_unlocked(user.get('id')):
            sid = request.cookies.get('session_id')
            if sid:
                delete_session(sid)
            resp = make_response(redirect(url_for('login_page')))
            resp.delete_cookie('session_id')
            if request.path.startswith('/api/'):
                return jsonify({'error': 'Locked', 'code': 'dek_missing'}), 401
            return resp
        return f(*args, **kwargs)
    return wrapped
```

**Soubor:** `app.py:492`
**Obtížnost:** ⭐⭐

---

### 3. Zkopírovat stejnou kontrolu do `current_user()` volaných endpointů bez `login_required`

Některé endpointy používají `current_user()` přímo bez dekorátoru (např. `/api/me` na `app.py:689`). Ty musí také vrátit `401` s `code: dek_missing`, když DEK chybí, aby je frontend zachytil a přesměroval.

Konkrétně upravit `/api/me` (`app.py:689`):

```python
@app.route("/api/me")
def me():
    user = current_user()
    if not user or not _user_unlocked(user.get('id')):
        return jsonify({"error": "Locked", "code": "dek_missing"}), 401
    return jsonify(user)
```

**Soubor:** `app.py:689`
**Obtížnost:** ⭐

---

### 4. Frontend: UI na 401 redirect už existuje

`templates/index.html` už obsahuje:
- řádek 358: `if (res.status === 401) { window.location.href = '/login'; }`
- řádek 742: `if (res.status === 401) { window.location.href = '/login'; return; }`
- řádek 981: `if (res.status === 401) { window.location.href = '/login'; return; }`

Žádná změna frontendu není potřeba — po 401 z `/api/me` nebo `/api/emails` se uživatel automaticky přihlásí znovu.

**Soubor:** žádný
**Obtížnost:** —

---

### 5. Drobá úprava chování `index()` route

`app.py:677` — route `/` má `@login_required`, takže po úpravě v bodě 2 automaticky přesměruje na login, když DEK chybí. Žádná další změna není potřeba.

**Soubor:** žádný
**Obtížnost:** —

---

### 6. Inbound webhook — ochrana proti ukládání bez DEK

`app.py:973` — `user_id = _current_user_id() or 1`. Pokud ani user 1 nemá DEK v paměti (např. hned po restartu, nikdo se nepřihlásil), `encrypt_email_field` vyhodí `RuntimeError` a webhook spadne s 500, e-mail se ztratí.

**Doporučení:** Zalomit insert do try/except a při chybějící DEK e-mail uložit do fronty / dočasné tabulky `pending_emails` a po prvním loginu ho došifrovat a vložit. **Tohle je ale mimo rozsah tohoto plánu** — řeší jen případ, kdy přijde e-mail během restartu.

**Zvolené řešení (schváleno uživatelem):** Při chybějícím DEK webhook vrátí `503 Service Unavailable` a Resend to zkusí znovu. Přidat try/except kolem insertu:

```python
try:
    conn.execute("""INSERT INTO emails ...""", (... encrypt_email_field(..., user_id) ...))
except RuntimeError:
    app.logger.error(f"DEK missing for user {user_id}, cannot store inbound email {email_id}")
    conn.close()
    return jsonify({"error": "Server locked"}), 503
```

**Soubor:** `app.py:944-1026`
**Obtížnost:** ⭐⭐ (jen minimalistická varianta)

---

## ✅ Verifikace

| Test | Postup | Očekávaný výsledek |
|------|--------|-------------------|
| Normální login | Přihlásit se heslem | E-maily se zobrazí normálně (dešifrované) |
| Po restartu | `./stop.sh && ./start.sh`, refresh stránky | Automatický redirect na `/login`, žádné zašifrované řetězce |
| Po znovupřihlášení | Po restartu zadat heslo | E-maily se opět dešifrují |
| API bez DEK | `curl /api/emails` s platnou session cookie po restartu | `401` s `{"code": "dek_missing"}` |
| Inbound webhook při restartu | Poslat e-mail, zatímco nikdo není přihlášen | `503`, Resend to zkusí znovu |

---

## 📁 Soubory, které se mění

| Soubor | Řádek | Co se děje |
|--------|-------|------------|
| `app.py` | ~76 | Nový helper `_user_unlocked()` |
| `app.py` | 492 | `login_required` kontroluje DEK, maže session při chybě |
| `app.py` | 689 | `/api/me` vrací 401, když DEK chybí |
| `app.py` | 944-1026 | Inbound webhook vrací 503, když DEK chybí (minimalistická varianta) |

**Frontend (`templates/index.html`): žádná změna** — redirect na 401 už existuje.

---

## ⚠️ Poznámky

- Tento plán **nepřepisuje** kryptografický systém. Jen detekuje "zamčený" stav a chová se k němu jako k odhlášení.
- Cloudflare Access auto-provision uživatelů bez DEK je **mimo rozsah** tohoto plánu (CF Access je momentálně vypnutý v `.env`).
- Pokud bys chtěl, aby e-maily přicházející během restartu serveru nebyly ztraceny, doporučuji dodělat `pending_emails` frontu — to ale děláme jako samostatný plán.