# openMail — Redesign plán (webový prototyp)

> **Intent:** High-fidelity responzivní prototyp celé mailové aplikace s prioritou mobilu.  
> **Publikum:** produktoví manažeři a vývojáři, kteří hodnotí openMail jako alternativní poštovní klient.  
> **Rozsah:** Inbox · Compose / Detail · Navigace / sidebar · Mobile-first.  
> **Vstup:** diagnostika stávajícího UI (screenshoty + `templates/index.html` + `static/liquid-glass.css` na `localhost:5005`).

---

## 1. Shrnutí záměru

Navrhnout **produktový redesign** openMailu, který:

1. zachová silné stránky (tmavý liquid-glass look, oranžový accent `#ff6b35`, floating tab bar, Hugeicons),
2. opraví diagnostikované UX/IA problémy,
3. doručí **high-fidelity HTML prototyp** (ne wireframe) připravený k handoffu do implementace.

**Není cílem** přepsat backend (`app.py`, IMAP/Resend). Prototyp mockuje data a interakce.

---

## 2. Diagnostika stávající verze

### 2.1 Co funguje (ponechat / vylepšit)

| Silná stránka | Důkaz | Doporučení |
|---|---|---|
| Tmavý liquid-glass vizuál | glass karty, orby, blur tab baru | Zachovat jako brand DNA |
| Accent orange | `#ff6b35` / brand-tag OPENMAIL | 1 accent, max 2× na obrazovku |
| Floating tab bar + compose FAB | spodní pill s center compose | Redesign IA tabů, ne mazat pattern |
| Hugeicons (ne emoji) | CDN + stroke ikony | Sjednotit velikosti a active stavy |
| Mobilní viewport meta | `viewport-fit=cover`, safe-area | Rozšířit o desktop 3-pane layout |
| i18n cs/en | locales + Jinja `_()` | Prototyp v CS, EN jako sekundární |

### 2.2 Hlavní problémy (prioritizováno)

#### P0 — blokuje denní použití

| # | Problém | Kde | Dopad |
|---|---|---|---|
| D1 | **Žádné fulltext vyhledávání v inboxu** | jen contacts search | Nelze najít mail v 50+ zprávách |
| D2 | **Reader a Composer = fullscreen overlay** | `.reader` / `.composer` `position: fixed; inset: 0` | Ztráta kontextu seznamu; na desktopu zbytečné |
| D3 | **Desktop = zúžený mobile shell** | `@media (min-width: 768px) { #app { max-width: 640px } }` | PM/dev na notebooku vidí „telefon uprostřed“ |
| D4 | **Tab bar IA je nekonzistentní** | Inbox · Starred · Compose · **Spam** · Sync | Spam není denní tab; Sent/Trash chybí; Sync není „místo“ |
| D5 | **Duplicitní navigace** | Tab bar + menu drawer se překrývají (inbox/starred/spam) | Uživatel neví, kde je primární cesta |

#### P1 — snižuje kvalitu vnímání produktu

| # | Problém | Kde | Dopad |
|---|---|---|---|
| D6 | **Karty = jen e-mail odesílatele**, ne display name | `from-name` ukazuje `team@mobbin.com` | Vizuální šum, horší scannability |
| D7 | **Preview často = raw URL / kód** | Kilocode, Warp, Adobe preview | Inbox vypadá jako debug log |
| D8 | **Hromadné akce skryté** | select mode + bulk bar | Power-user flow je těžko objevitelný |
| D9 | **Reply / Forward chybí v readeru** | jen back · star · trash | Compose bez thread kontextu |
| D10 | **Composer je plain text only** | textarea + attach | Pro dev/PM často OK, ale chybí CC/BCC a draft feedback |
| D11 | **Header zabírá vertikál** | brand + H1 + stats + 2 ikony | Na mobilu méně mailů above the fold |

#### P2 — craft / polish

| # | Problém | Dopad |
|---|---|---|
| D12 | Active tab = jen tečka dole, slabá hierarchie | Horší state clarity |
| D13 | Badge „46“ na inboxu + subtitle „46 Nepřečteno“ = redundance | Dvojité počítání |
| D14 | Empty / loading / error stavy nevýrazné | Horší first-run dojem |
| D15 | Touch targets někde 36px (reader buttons) | Pod 44px guideline |
| D16 | Žádný swipe gesture na kartách | Očekávání mobile-first mail klientů |

### 2.3 Diagnostický verdikt (1 věta)

> openMail už vypadá jako prémiový mobile mail client, ale chová se jako **single-column phone app i na desktopu**, s **rozbitou navigační IA** a **chybějícími power-user nástroji** (search, reply, multi-pane, lepší scannability).

---

## 3. Uživatelé a jobs-to-be-done

### Primární persona
**PM / vývojář** — rychle triážuje notifikace (GitHub, Warp, Resend, design tools), občas odpoví, potřebuje search a klávesové zkratky na desktopu.

### Jobs

| Job | Priorita |
|---|---|
| Rychle projít nepřečtené a označit/triážovat | P0 |
| Otevřít mail a odpovědět / smazat / archivovat | P0 |
| Najít konkrétní zprávu nebo odesílatele | P0 |
| Napsat nový mail s přílohou | P0 |
| Přepnout složku (Inbox / Sent / Starred / Trash) | P1 |
| Hromadně vyčistit spam / nepřečtené | P1 |

---

## 4. Informační architektura (cíl)

### 4.1 Navigace — mobile

```
┌─────────────────────────────┐
│  Header (folder + search)   │
│  Email list                 │
│                             │
│  ┌─ floating tab bar ─────┐ │
│  │ Inbox  Star  [+]  Sent │ │  ← Spam/Trash/Settings → drawer
│  │              Sync?     │ │  ← Sync jako pull-to-refresh + menu
│  └────────────────────────┘ │
└─────────────────────────────┘
```

**Nová tab bar IA (návrh):**

| Slot | Dnes | Nově | Proč |
|---|---|---|---|
| 1 | Inbox | **Inbox** | primární |
| 2 | Starred | **Starred** | rychlý filtr |
| 3 | Compose FAB | **Compose FAB** | zachovat |
| 4 | Spam | **Sent** | denní složka > spam |
| 5 | Sync | **More / Menu** | otevírá drawer (Spam, Trash, Settings, Sync) |

> **TODO:** Ověřit, jestli Sync zůstane v tab baru (viditelnost sync stavu) nebo jen pull-to-refresh + drawer položka.

### 4.2 Navigace — desktop (≥1024px)

```
┌──────────┬────────────────┬─────────────────────┐
│ Sidebar  │  List pane     │  Reading pane       │
│ folders  │  search+cards  │  detail / empty     │
│ compose  │                │  nebo compose       │
└──────────┴────────────────┴─────────────────────┘
```

- **3-pane** (Gmail/Spark pattern), ne centered 640px phone.
- Sidebar trvale viditelný; drawer mizí.
- Tab bar na desktopu **skrytý** (nahrazuje ho sidebar).

### 4.3 Složky (kanonické)

1. Inbox  
2. Starred  
3. Sent  
4. Drafts *(pokud backend umí — jinak placeholder)*  
5. Spam  
6. Trash  
7. Custom folders  

---

## 5. Obrazovky a soubory prototypu

Každá distinct screen = vlastní HTML (launcher `index.html`).

| Soubor | Obrazovka | Breakpoint focus |
|---|---|---|
| `index.html` | Overview / launcher se screen mapou | — |
| `screens/inbox-mobile.html` | Inbox list + tab bar + header | 390×844 |
| `screens/inbox-desktop.html` | 3-pane inbox + sidebar | 1440×900 |
| `screens/mail-detail-mobile.html` | Reader (thread-like) | 390×844 |
| `screens/compose-mobile.html` | Composer | 390×844 |
| `screens/compose-desktop.html` | Compose v reading pane / modal | 1440×900 |
| `screens/nav-drawer.html` | Menu drawer / sidebar stavy | mobile + desktop |

> **TODO:** Pokud preferuješ 1 multi-state soubor místo 6 screenů, řekni — default je multi-file dle project metadata.

---

## 6. Layout a komponenty po obrazovkách

### 6.1 Inbox (list)

**Cíl:** maximální scannability, méně chrome.

| Element | Spec |
|---|---|
| Brand | drobný OPENMAIL accent nahoře **nebo** jen v sidebaru na desktopu |
| Title | název složky (Inbox) |
| Stats | 1 řádek: `46 nepřečteno · 59 celkem` — bez spam count (spam v drawer badge) |
| Search | sticky search bar pod headerem (D1) |
| Filters chips | Vše · Nepřečtené · S hvězdou *(optional P1)* |
| Email row | avatar · **display name** · subject · 1-line preview · time · unread dot · star |
| Select mode | long-press / checkbox edge; bulk bar s ikonami |
| Empty state | ilustrace + CTA „Synchronizovat“ |
| Loading | skeleton cards (ne spinner uprostřed) |

**Row hierarchy (scannability fix D6/D7):**

```
[Avatar]  Display Name                    23:05  ●
          Subject line (semibold if unread)
          Preview — sanitized, no raw URLs
```

### 6.2 Mail detail (reader)

| Element | Spec |
|---|---|
| Top bar | Back · Subject truncate · ⋯ more |
| Actions | Reply · Reply all · Forward · Star · Trash · Spam |
| Meta | avatar, from name + email, to, relative time |
| Body | HTML iframe (existující) + text fallback toggle |
| Attachments | chips se size + download |
| Bottom (mobile) | floating action row: Reply primary |

### 6.3 Compose

| Element | Spec |
|---|---|
| Top | Cancel · **Nový e-mail** · Send (accent) |
| Fields | To (chips + autocomplete) · Cc/Bcc toggle · Subject · Body |
| Attach | paperclip + preview list (name, size, remove) |
| Validation | empty To / invalid email → inline error |
| Desktop | panel v reading pane NEBO centered sheet 640px |

### 6.4 Navigace

**Mobile drawer**

- User header (avatar, email)
- Folder list s badges
- Secondary: Contacts, Settings, Language, Logout
- Sync s last-synced timestamp

**Desktop sidebar**

- Logo + Compose button (accent)
- Folder nav s active rail
- Bottom: settings + user

---

## 7. Interakce a stavy

### Klíčové flows

1. **Open mail** — tap card → reader (mobile push / desktop pane select)  
2. **Compose** — FAB / sidebar → composer s focus na To  
3. **Reply** — z readeru předvyplní To + Re: subject  
4. **Search** — debounced filter list (mock)  
5. **Select multi** — checkbox mode → bulk read/trash/spam  
6. **Folder switch** — tab / sidebar → list reload + header title  
7. **Sync** — pull-to-refresh (mobile) + explicit Sync v menu  

### Stavy komponent (P0 pro high-fidelity)

| Komponenta | Stavy |
|---|---|
| Email row | default · unread · starred · selected · hover (desktop) · active |
| Tab / nav item | default · active · badge |
| Buttons | default · hover · active · disabled |
| Search | empty · focused · has query · no results |
| Reader | loading · HTML · plain · error |
| Composer | empty · invalid · sending · sent toast |

### Gestures (mobile, mock v prototypu)

- Pull-to-refresh  
- Swipe left na kartě → Trash  
- Swipe right → Star  
- *(vizuálně naznačit v 1–2 kartách jako education)*

---

## 8. Datový / content model (mock)

```ts
Email {
  id, fromName, fromEmail, to, subject, preview,
  bodyHtml?, bodyText?, time, isRead, isStarred, isSpam,
  folder: 'inbox'|'sent'|'starred'|'spam'|'trash',
  attachments: { name, size, url }[]
}
Folder { id, label, unreadCount, icon }
```

**Pravidla mock copy:**

- Realistické PM/dev maily (GitHub, deploy, design tools) — **ne** lorem ipsum.
- Preview sanitizace: strip URLs delší než ~40 znaků → `domain…`.
- Display name preferovat před raw email.

---

## 9. Vizuální systém (bind na stávající brand)

### Tokens (ze stávajícího `liquid-glass.css`)

| Role | Hodnota |
|---|---|
| `--bg` | `#000000` |
| `--fg` / text | `#ffffff` |
| `--muted` | `rgba(235,235,245,0.6)` |
| `--border` | `rgba(255,255,255,0.08)` |
| `--accent` | `#ff6b35` |
| `--accent-deep` | `#c8431f` |
| Glass surfaces | `rgba(20–40, *, 0.45–0.55)` + blur |

### Typografie

- **UI sans:** system stack (`-apple-system` …) — OK pro utilitární mail UI  
- **Mono:** časy, badge counts, e-mailové adresy v meta  
- Display serif **nepoužívat** (data-dense product, ne marketing)

### Posture rules

1. Jeden accent — CTA compose + unread dot / primary send.  
2. Karty s jemným glass, ne těžké stíny všude.  
3. Desktop layout využívá šířku; mobile zachová floating glass chrome.  
4. Žádné emoji jako ikony (Hugeicons only).  
5. Touch targets ≥ 44px.

---

## 10. Responzivní breakpointy

| Breakpoint | Layout |
|---|---|
| `< 768px` | Single column · floating tab bar · overlays for reader/compose |
| `768–1023px` | List + optional split (list 40% / detail 60%), bez full sidebar |
| `≥ 1024px` | 3-pane: sidebar 240 · list 360 · reading flex |

---

## 11. Acceptance checks (P0)

Prototyp prochází, pokud:

- [ ] Mobile inbox ukazuje search + scannable rows (name ≠ jen email)
- [ ] Tab bar IA: Inbox · Starred · Compose · Sent · More (nebo schválená alternativa)
- [ ] Desktop ≥1024px: 3-pane, ne 640px phone shell
- [ ] Reader má Reply + Trash + Star; Compose má To/Subject/Body/Attach
- [ ] Drawer/sidebar pokrývá Spam, Trash, Settings, Sync
- [ ] Empty, loading, selected, unread stavy jsou viditelné
- [ ] Accent budget dodržen; Hugeicons konzistentní
- [ ] Touch targets ≥ 44px na primary controls
- [ ] i18n-ready copy v češtině (EN klíče v komentáři volitelně)

---

## 12. Out of scope (tato fáze)

- Reálné IMAP/SMTP napojení v prototypu  
- Přepis `app.py`  
- Offline PWA  
- Multi-account  
- Calendar / tasks  
- Plný rich-text editor (plain + attach stačí)

---

## 13. Otevřené otázky

- [ ] **Sync v tab baru vs. jen pull-to-refresh?** (default plán: pryč z tabu → More menu + pull)
- [ ] **Drafts složka** — zobrazit i bez backend podpory (placeholder)?
- [ ] **Archiv** jako akce, nebo stačí Trash?
- [ ] **Jeden multi-state HTML** vs. **více screen souborů** (default: multi-file)
- [ ] **Light mode** — ne (brand je dark-only), potvrdit
- [ ] Preferovaný desktop density: compact (Gmail) vs. comfortable (Apple Mail)

---

## 14. Next step

1. **Uprav tento dokument** (`prototype-plan.md`) — zejména otevřené otázky v §13 a tab bar IA v §4.1.  
2. Až bude plán schválený, přepni do **Design mode** s instrukcí:  
   *„Vygeneruj high-fidelity prototyp podle `prototype-plan.md`.“*  
3. Design mode doručí HTML screeny + launcher; implementace do `templates/index.html` přijde až po vizuálním sign-offu.

---

*Diagnostika založená na: browser captures 2026-07-16, `templates/index.html`, `static/liquid-glass.css`, form answers (web_prototype · inbox/compose/nav · mobile_first · high_fidelity · PM/dev audience).*
