# Agent notes for openMail

Single-user Flask email client for `dominik@adamec.pro`. Python backend + server-rendered HTML/JS frontend, SQLite data, Cloudflare Tunnel public access.

## Project type and entrypoints

- Backend: Flask app bootstrapped in `app.py` (sets `PYTHONPATH=src`).
- Real app factory is `src/openmail/__init__.py` (`create_app()`).
- Frontend is server-rendered Jinja templates in `templates/` plus vanilla JS in `static/js/`.
- Service worker `sw.js` is intentionally cache-busting only; it always fetches fresh static assets and API responses.

## Running locally

Use the venv and run from the repo root:

```bash
source .venv/bin/activate
python app.py                 # development with debug + reloader if FLASK_DEBUG=true
# or
bash start.sh                 # production-style: no reloader + cloudflared tunnel
bash stop.sh                  # kill Flask + tunnel via .flask.pid / .cloudflared.pid
```

- Default local URL: `http://127.0.0.1:5005`
- Public URL: `https://email.adamec.pro`
- `start.sh` hardcodes port `5005` unless overridden by `FLASK_PORT`.

## Python path convention

Many scripts need `PYTHONPATH=src:.` to import `openmail.*`. Use it when running ad-hoc scripts:

```bash
PYTHONPATH=src:. python scripts/add_user.py <username> <password> <email> --from-name "Name"
```

## Environment and secrets

- Copy `.env.example` to `.env` at repo root; `python-dotenv` loads it automatically.
- Required for sending/receiving: `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `ICLOUD_USER`, `ICLOUD_APP_PASSWORD`.
- Email encryption key is not in `.env.example` but the code expects a 32-byte base64 key. Generate one with:
  ```bash
  python -c "import base64, secrets; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())"
  ```
- Cloudflare Access is optional; enable via `CLOUDFLARE_ACCESS_ENABLED=true` plus team domain and AUD tag.

## Database

- SQLite file at `emails.db` (repo root).
- Migrations are in `migrations/*.sql` and applied sequentially by `src/openmail/db/migrations.py`.
- App auto-runs migrations on startup. Manual run:
  ```bash
  source .venv/bin/activate
  PYTHONPATH=src:. python src/openmail/db/migrations.py
  ```

## Adding users

Use the script, not direct DB edits:

```bash
source .venv/bin/activate
PYTHONPATH=src:. python scripts/add_user.py info adamec info@adamec.pro --from-name "Info Adamec"
```

The target email must be configured/routable in Resend for the domain.

## Key directories

- `src/openmail/routes/` — Flask route modules (`emails`, `folders`, `contacts`, `auth`, `settings`, `public`).
- `src/openmail/services/` — business logic (`email_service`, `folder_service`, `contact_service`, `resend_service`, `stats_service`).
- `src/openmail/auth/` — sessions, users, current-user context, Cloudflare Access.
- `src/openmail/crypto/` — KDF + data encryption key handling.
- `src/openmail/db/` — migration runner.
- `static/js/` — `app.js`, `api.js`, `email.js`, `ui.js`, `utils.js`, `sse.js`.
- `templates/` — `index.html`, `login.html`, `email.html`, `setup.html`.

## Build/test/lint status

No formal test runner, linter, formatter, or CI config is present in this repo. Verify changes by:

1. Running the app with `python app.py` or `bash start.sh`.
2. Checking `logs/app.log` for runtime errors.
3. Manually exercising the affected endpoint or UI flow.

## Deployment / public access

- `start.sh` launches `cloudflared tunnel --config ~/.cloudflared/config.yml run`. The tunnel config lives outside the repo.
- Do not commit `.env`, `emails.db`, or backup files (`*.backup-*`). They are already generated locally.

## Common gotchas

- `app.py` alters `sys.path` so `src/` is importable when the file is run directly. Do not rely on `src/` being on the path in tests unless you set `PYTHONPATH=src:.` yourself.
- `sw.js` disables caching. If a user reports stale JS/CSS, the issue is not service-worker caching.
- The iCloud SMTP endpoint cannot send as `dominik@adamec.pro` unless it is configured as an iCloud alias; the app uses Resend SMTP relay for outbound instead.
