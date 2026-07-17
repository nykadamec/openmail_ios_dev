"""Profilovací skript pro openMail Flask app.
Měří: přihlášení (bcrypt+PBKDF2+DEK decrypt), DB queries, AES decrypt při list_emails.
"""
import os, time, statistics, sqlite3, base64, json
from pathlib import Path

# Musíme nahrát app.py jako modul, aby se inicializoval load_dotenv
import app

DB_PATH = Path("emails.db")
ITERATIONS = 10

def measure_login():
    username = "dominik"
    password = os.environ.get("DEFAULT_USER_PASSWORD", "adamec")
    times = []
    for _ in range(ITERATIONS):
        t0 = time.perf_counter()
        user_id = app.verify_user(username, password)
        t1 = time.perf_counter()
        assert user_id is not None
        times.append(t1 - t0)
    return times

def measure_db_query(folder="inbox", direction="inbound", limit=50):
    conn = app.get_db()
    params = [direction, folder, 0, 0]
    sql = (
        "SELECT id, folder, custom_folder_id, sender_name, sender_email, recipient, "
        "subject, preview, is_starred, is_read, is_spam, is_trash, created_at "
        "FROM emails WHERE direction = ? AND folder = ? AND is_trash = ? AND is_spam = ? "
        "ORDER BY datetime(created_at) DESC LIMIT ? OFFSET ?"
    )
    times = []
    for _ in range(ITERATIONS):
        t0 = time.perf_counter()
        rows = conn.execute(sql, params + [limit, 0]).fetchall()
        t1 = time.perf_counter()
        times.append(t1 - t0)
    conn.close()
    return times, rows

def measure_decrypt(rows):
    user_id = 1
    times = []
    for _ in range(ITERATIONS):
        t0 = time.perf_counter()
        for row in rows:
            d = dict(row)
            app.decrypt_email_field(d.get("sender_name"), user_id)
            app.decrypt_email_field(d.get("sender_email"), user_id)
            app.decrypt_email_field(d.get("recipient"), user_id)
            app.decrypt_email_field(d.get("subject"), user_id)
            app.decrypt_email_field(d.get("preview"), user_id)
        t1 = time.perf_counter()
        times.append(t1 - t0)
    return times

def measure_stats():
    conn = app.get_db()
    queries = [
        ("inbound", "SELECT COUNT(*) FROM emails WHERE direction = 'inbound' AND is_trash = 0"),
        ("outbound", "SELECT COUNT(*) FROM emails WHERE direction = 'outbound' AND is_trash = 0"),
        ("starred", "SELECT COUNT(*) FROM emails WHERE is_starred = 1 AND is_trash = 0"),
        ("unread", "SELECT COUNT(*) FROM emails WHERE direction = 'inbound' AND is_read = 0 AND is_trash = 0"),
        ("spam", "SELECT COUNT(*) FROM emails WHERE is_spam = 1 AND is_trash = 0"),
        ("trash", "SELECT COUNT(*) FROM emails WHERE is_trash = 1"),
    ]
    times = []
    for _ in range(ITERATIONS):
        t0 = time.perf_counter()
        for _, q in queries:
            conn.execute(q).fetchone()
        t1 = time.perf_counter()
        times.append(t1 - t0)
    conn.close()
    return times

def fmt_times(times):
    mean = statistics.mean(times)
    med = statistics.median(times)
    mn = min(times)
    mx = max(times)
    return f"mean={mean*1000:.2f}ms median={med*1000:.2f}ms min={mn*1000:.2f}ms max={mx*1000:.2f}ms"

if __name__ == "__main__":
    print(f"DB path: {DB_PATH.resolve()}")
    print(f"Email count: {app.get_db().execute('SELECT COUNT(*) FROM emails').fetchone()[0]}")
    print(f"User count: {app.get_db().execute('SELECT COUNT(*) FROM users').fetchone()[0]}")
    print(f"Iterations: {ITERATIONS}")
    print()

    print("[login] verify_user (bcrypt + PBKDF2 600k + DEK decrypt)")
    print("  ", fmt_times(measure_login()))
    print()

    print("[db] list_emails query (folder=inbox, limit=50)")
    db_times, rows = measure_db_query()
    print("  ", fmt_times(db_times), f"rows={len(rows)}")
    print()

    print("[decrypt] AES-GCM decrypt 5 fields x 50 rows")
    dec_times = measure_decrypt(rows)
    print("  ", fmt_times(dec_times))
    print()

    print("[db] /api/stats 6 counts")
    print("  ", fmt_times(measure_stats()))
    print()

    # Full request simulation via Flask test client
    print("[http] full login + index + API requests via test client")
    client = app.app.test_client()
    http_times = {"login": [], "index": [], "api_emails": [], "api_stats": [], "api_folders": []}
    for _ in range(ITERATIONS):
        t0 = time.perf_counter()
        r = client.post('/login', data={'username': 'dominik', 'password': os.environ.get('DEFAULT_USER_PASSWORD', 'adamec')})
        t1 = time.perf_counter()
        http_times["login"].append(t1 - t0)

        t0 = time.perf_counter()
        r = client.get('/')
        t1 = time.perf_counter()
        http_times["index"].append(t1 - t0)

        t0 = time.perf_counter()
        r = client.get('/api/emails?folder=inbox&direction=inbound&is_trash=0&is_spam=0&limit=50&offset=0')
        t1 = time.perf_counter()
        http_times["api_emails"].append(t1 - t0)

        t0 = time.perf_counter()
        r = client.get('/api/stats')
        t1 = time.perf_counter()
        http_times["api_stats"].append(t1 - t0)

        t0 = time.perf_counter()
        r = client.get('/api/folders')
        t1 = time.perf_counter()
        http_times["api_folders"].append(t1 - t0)

    for name, times in http_times.items():
        print(f"  {name}: {fmt_times(times)}")
