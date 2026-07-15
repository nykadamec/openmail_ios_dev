# Adamec.pro Mail

Jednoduchý lokální e-mailový klient pro `dominik@adamec.pro`, běžící na tvém Macu a dostupný přes `https://email.adamec.pro`.

## Co to umí

- Odesílat e-maily z adresy `dominik@adamec.pro` přes Resend SMTP relay.
- Přijímat e-maily pro `dominik@adamec.pro` přes iCloud IMAP.
- Webové UI v prohlížeči.
- SQLite ukládání e-mailů lokálně.
- Cloudflare Tunnel pro veřejný přístup.

## Poskytovatelé

| Akce | Provider | Adresa |
|---|---|---|
| Příjem | iCloud Mail (IMAP) | `dominik@adamec.pro` |
| Odesílání | Resend (SMTP relay) | `dominik@adamec.pro` |

## Spuštění

```bash
./start.sh
```

- Lokálně: http://127.0.0.1:5005
- Veřejně: https://email.adamec.pro

## Zastavení

```bash
./stop.sh
```

## První použití

1. Otevři https://email.adamec.pro
2. Klikni na „Synchronizovat“ pro načtení e-mailů.
3. Pro odeslání klikni na „+ Nový e-mail“.

## Záloha DNS

Záloha všech DNS záznamů pro `adamec.pro` je v:

```
cloudflare-backup/adamec.pro-dns-backup.zip
```

## Řešené problémy

### Odesílání z `dominik@adamec.pro`

iCloud SMTP vrací chybu `From address is not one of your addresses`. Řešení:
- Nastavit `dominik@adamec.pro` jako alias v iCloudu, nebo
- Použít externí SMTP relay jako Resend.com, SendGrid apod.

## Soubory

- `app.py` — Flask backend
- `templates/index.html` — webové UI
- `.env` — konfigurace
- `requirements.txt` — Python závislosti
- `start.sh` / `stop.sh` — spouštěcí skripty
- `cloudflare-backup/` — záloha DNS


## Cloudflare Access (Zero Trust)

To secure the app behind Cloudflare Access:

1. Go to Cloudflare Zero Trust Dashboard → Access → Applications
2. Add an Application for 
3. Set the **Audience Tag (AUD)** — copy it from application settings
4. Configure your **Team Domain** (e.g. )
5. Set identity provider (One-time PIN, Google, GitHub, etc.) and enable MFA if desired
6. Update  on the server:



7. Restart the server

When enabled, Cloudflare handles authentication before the user ever reaches the app login page. The app validates the  header and creates a local session automatically.
