# openMail — Plán: Hugeicons + Floating Liquid Glass Tab Bar

> **Cíl:** Nahradit všechny emoji ikony Hugeicons ikonami přes CDN a redesignovat spodní tab bar do plovoucího Liquid Glass stylu podle [Apple Liquid Glass Design Navigation Bar](https://dribbble.com/shots/26294545-Apple-Liquid-Glass-Design-Navigation-Bar).

---

## 📋 Přehled úkolů

| # | Úkol | Obtížnost | Závislosti |
|---|------|-----------|------------|
| 1 | **Hugeicons CDN** — načíst `https://use.hugeicons.com/font/icons.css` | ⭐ | — |
| 2 | **Nahradit emoji** — tab bar, menu drawer, header | ⭐⭐ | #1 |
| 3 | **Floating Liquid Glass tab bar** — redesign podle Dribbble | ⭐⭐⭐ | — |
| 4 | **Active indicator morphing** — plynulý přechod mezi taby | ⭐⭐⭐ | #3 |
| 5 | **Verifikace** — visual QA, touch targets, a11y | ⭐⭐ | #2, #4 |

> **Poznámka:** Fáze 1 a 2 lze dělat souběžně. Fáze 3/4 by měly být hotové najednou, aby vizuální jazyk držel pohromadě.

---

## 📁 Soubory, které se mění

| Soubor | Status | Co se děje |
|--------|--------|------------|
| `templates/index.html` | ✏️ upravit | Přidat CDN link, nahradit emoji ikony Hugeicons třídami |
| `static/liquid-glass.css` | ✏️ upravit | Styly pro Hugeicons, nový Liquid Glass tab bar, active pill |
| `templates/login.html` | ✏️ volitelně | Nahradit emoji ikony pokud se vyskytují |
| `templates/setup.html` | ✏️ volitelně | Nahradit emoji ikony pokud se vyskytují |
| `locales/cs.json` + `locales/en.json` | ✏️ upravit | Přidat `aria-label` klíče pro taby |

---

## 1️⃣ Fáze 1: Hugeicons CDN integrace

### CDN link

Přidat do `<head>` v `templates/index.html` (a volitelně login/setup):

```html
<link rel="stylesheet" href="https://use.hugeicons.com/font/icons.css">
<link rel="preconnect" href="https://use.hugeicons.com">
<link rel="preconnect" href="https://ico.hugeicons.com">
```

### Výběr ikon (stroke-rounded, free tier)

| UI element | Třída Hugeicons | Nahrazuje |
|------------|-----------------|-----------|
| Inbox tab | `hgi-stroke hgi-inbox` | 📥 |
| Starred tab | `hgi-stroke hgi-star` | ⭐ |
| Compose tab | `hgi-stroke hgi-edit-01` | ✏️ |
| Spam tab | `hgi-stroke hgi-spam` | 🚫 |
| Sync tab | `hgi-stroke hgi-refresh` | 🔄 |
| Menu toggle | `hgi-stroke hgi-menu-01` | ☰ |
| Contacts | `hgi-stroke hgi-user` | 👤 |
| Settings | `hgi-stroke hgi-settings-01` | ⚙️ |
| Logout | `hgi-stroke hgi-logout-01` | 🚪 |
| Close reader/composer | `hgi-stroke hgi-cancel-01` | × |
| Attachment | `hgi-stroke hgi-attachment-01` | 📎 |
| Send | `hgi-stroke hgi-send-01` | ➤ |

### Markup změny

Tab bar:

```html
<button class="tab" data-folder="inbox" onclick="setFolder('inbox')" aria-label="{{ _('tab.inbox') }}">
  <i class="hgi-stroke hgi-inbox" aria-hidden="true"></i>
  <span class="count" id="tabInboxCount" aria-hidden="true"></span>
</button>
```

Menu drawer:

```html
<button class="menu-item" onclick="openContacts()">
  <i class="hgi-stroke hgi-user icon" aria-hidden="true"></i>
  <span>{{ _("menu.contacts") }}</span>
</button>
```

### CSS normalizace ikon

```css
.hgi-stroke {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: inherit;
  line-height: 1;
  color: currentColor;
}

.icon {
  font-size: 1.25rem;
  width: 24px;
  text-align: center;
}
```

---

## 2️⃣ Fáze 2: Floating Liquid Glass Tab Bar

### Design reference

Dribbble shot od Nikolashvili Nodo:
- **Tvar:** plovoucí zaoblená pilulka, nízká a široká, border radius ≈ 34px.
- **Materiál:** Liquid Glass — silný blur, vysoká saturace, gloss overlay, jemné vnitřní odrazy.
- **Barvy:** tmavý základ s akcentovými gradienty modré/fialové/růžové: `#370D58`, `#380AE1`, `#D62350`, `#A92CAC`, `#EB1094`, `#F6E7F6`.
- **Ikony:** outline stroke style; aktivní ikona svítí bíle, neaktivní je tlumená.
- **Active state:** plovoucí skleněná kapsle, která se plynule přesune pod aktivní ikonu.
- **Stín:** měkký drop shadow pod celou pilulkou.

### HTML struktura

```html
<div class="tab-bar-wrap">
  <nav class="tab-bar" id="tabBar">
    <div class="bar-fill"></div>
    <div class="bar-gloss"></div>
    <div class="active-pill" id="activePill" aria-hidden="true"></div>

    <button class="tab" data-folder="inbox" onclick="setFolder('inbox')" aria-label="{{ _('tab.inbox') }}">
      <i class="hgi-stroke hgi-inbox" aria-hidden="true"></i>
      <span class="count" id="tabInboxCount"></span>
    </button>
    <button class="tab" data-folder="starred" onclick="setFolder('starred')" aria-label="{{ _('tab.starred') }}">
      <i class="hgi-stroke hgi-star" aria-hidden="true"></i>
    </button>
    <button class="tab compose" onclick="openComposer()" aria-label="{{ _('tab.compose') }}">
      <i class="hgi-stroke hgi-edit-01" aria-hidden="true"></i>
    </button>
    <button class="tab" data-folder="spam" onclick="setFolder('spam')" aria-label="{{ _('tab.spam') }}">
      <i class="hgi-stroke hgi-spam" aria-hidden="true"></i>
    </button>
    <button class="tab" onclick="syncEmails()" aria-label="{{ _('tab.sync') }}">
      <i class="hgi-stroke hgi-refresh" aria-hidden="true"></i>
    </button>
  </nav>
</div>
```

### CSS plán

#### Proměnné

```css
:root {
  --tab-bar-bg: rgba(18, 12, 28, 0.72);
  --tab-bar-border: rgba(255, 255, 255, 0.08);
  --tab-bar-gloss: rgba(255, 255, 255, 0.05);
  --tab-active-pill: rgba(255, 255, 255, 0.11);
  --tab-icon: rgba(255, 255, 255, 0.55);
  --tab-icon-active: #fff;
  --tab-accent-inbox: #380AE1;
  --tab-accent-starred: #D62350;
  --tab-accent-spam: #A92CAC;
  --tab-accent-sync: #EB1094;
  --tab-accent-compose: #370D58;
}
```

#### Floating pill container

```css
.tab-bar-wrap {
  position: fixed;
  bottom: calc(var(--safe-bottom) + 22px);
  left: 50%;
  transform: translateX(-50%);
  z-index: 100;
  width: auto;
  min-width: 320px;
  max-width: min(420px, calc(100% - 48px));
}

.tab-bar {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 6px;
  height: 64px;
  padding: 6px 10px;
  border-radius: 34px;
  background: var(--tab-bar-bg);
  backdrop-filter: blur(44px) saturate(220%);
  -webkit-backdrop-filter: blur(44px) saturate(220%);
  border: 1px solid var(--tab-bar-border);
  box-shadow:
    0 18px 50px rgba(0, 0, 0, 0.55),
    0 0 0 1px rgba(255,255,255,0.04) inset,
    0 8px 24px rgba(56, 10, 225, 0.15);
}

.tab-bar .bar-fill {
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background: linear-gradient(
    135deg,
    rgba(255,255,255,0.06) 0%,
    rgba(255,255,255,0.01) 50%,
    rgba(255,255,255,0.04) 100%
  );
  z-index: 0;
}

.tab-bar .bar-gloss {
  position: absolute;
  inset: 1px;
  border-radius: 33px;
  background: linear-gradient(
    180deg,
    rgba(255,255,255,0.09) 0%,
    rgba(255,255,255,0.02) 40%,
    rgba(255,255,255,0) 100%
  );
  pointer-events: none;
  z-index: 1;
}
```

#### Active pill (morphing indicator)

```css
.active-pill {
  position: absolute;
  top: 6px;
  bottom: 6px;
  width: 56px;
  border-radius: 22px;
  background: var(--tab-active-pill);
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.15),
    0 4px 14px rgba(0,0,0,0.25);
  backdrop-filter: blur(8px) saturate(150%);
  z-index: 1;
  transition:
    transform 0.38s cubic-bezier(0.34, 1.56, 0.64, 1),
    width 0.38s cubic-bezier(0.34, 1.56, 0.64, 1),
    background 0.3s ease,
    box-shadow 0.3s ease;
}
```

#### Gradient reflection

```css
.tab-bar::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background:
    radial-gradient(circle at var(--accent-x, 30%) 50%, var(--accent-color, rgba(56,10,225,0.22)), transparent 70%),
    radial-gradient(circle at 80% 20%, rgba(255,255,255,0.05), transparent 40%);
  opacity: 0.7;
  pointer-events: none;
  z-index: 0;
  transition: --accent-x 0.4s ease, --accent-color 0.4s ease;
}
```

#### Tab buttons

```css
.tab {
  position: relative;
  width: 56px;
  height: 52px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: none;
  color: var(--tab-icon);
  font-size: 1.45rem;
  cursor: pointer;
  z-index: 2;
  transition: color 0.25s ease, transform 0.12s ease;
}

.tab i {
  display: inline-flex;
  font-size: 24px;
}

.tab.active {
  color: var(--tab-icon-active);
  transform: scale(1.02);
}

.tab:active {
  transform: scale(0.9);
}

.tab .count {
  position: absolute;
  top: 2px;
  right: 2px;
  min-width: 18px;
  height: 18px;
  padding: 0 4px;
  border-radius: 9px;
  background: var(--accent);
  color: #fff;
  font-size: 0.65rem;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
}
```

### JavaScript — morphing active pill

```javascript
function getTabAccent(folder) {
  const map = {
    inbox: 'rgba(56, 10, 225, 0.22)',
    starred: 'rgba(214, 35, 80, 0.22)',
    spam: 'rgba(169, 44, 172, 0.22)',
    sync: 'rgba(235, 16, 148, 0.22)',
    compose: 'rgba(55, 13, 88, 0.22)',
  };
  return map[folder] || map.inbox;
}

function updateActivePill(tab) {
  const pill = document.getElementById('activePill');
  const bar = document.getElementById('tabBar');
  if (!pill || !bar || !tab) return;

  const barRect = bar.getBoundingClientRect();
  const tabRect = tab.getBoundingClientRect();
  const x = tabRect.left - barRect.left + tabRect.width / 2 - pill.offsetWidth / 2;

  pill.style.transform = `translateX(${x}px)`;
  pill.style.background = getTabAccent(tab.dataset.folder || 'compose');

  // posun gradientního reflexu
  const pct = ((tabRect.left - barRect.left + tabRect.width / 2) / barRect.width) * 100;
  bar.style.setProperty('--accent-x', `${pct}%`);
  bar.style.setProperty('--accent-color', getTabAccent(tab.dataset.folder || 'compose'));
}

function setFolder(folder) {
  // ... existing logic ...

  const tab = document.querySelector(`.tab[data-folder="${folder}"]`);
  if (tab) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    updateActivePill(tab);
  }
}

function openComposer() {
  // ... existing logic ...

  const tab = document.querySelector('.tab.compose');
  if (tab) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    updateActivePill(tab);
  }
}

function syncEmails() {
  // ... existing logic ...

  const tab = document.querySelector('.tab[onclick="syncEmails()"]');
  if (tab) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    updateActivePill(tab);
    // odebrat active po dokončení syncu, pokud se vracíme do inboxu
  }
}

// inicializace
window.addEventListener('resize', () => {
  const active = document.querySelector('.tab.active');
  if (active) updateActivePill(active);
});
```

### Accessibility

- Každý `<button class="tab">` musí mít `aria-label` (přes i18n).
- Badge u inboxu: `aria-label="Unread: N"`.
- `prefers-reduced-motion`: ztlumit morphing na jednoduchou opacity transition, snížit blur.
- Touch target ≥ 44px (aktuální `56×52px` vyhovuje).

---

## 3️⃣ Fáze 3: Volitelné rozšíření

- **Header:** nahradit menu a select toggle (`hgi-menu-01`, `hgi-checkmark-square-01`).
- **Reader / Composer:** close (`hgi-cancel-01`), attachment (`hgi-attachment-01`), send (`hgi-send-01`), star (`hgi-star`).
- **Loading:** sync ikona rotuje pomocí CSS animation.

---

## ✅ Verifikace

| Test | Postup | Očekávaný výsledek |
|------|--------|-------------------|
| CDN load | Otevřít app, DevTools Network | `icons.css` načteno 200 |
| Žádné emoji | Prohlédnout UI | Všechny ikony z Hugeicons, žádné emoji v navigaci |
| Tab switch | Kliknout Starred/Spam/Inbox | Active pill se plynule posune pod novou ikonu |
| Compose | Kliknout Compose | Active pill se posune na compose / zmizí a reader/composer se otevře |
| Reduced motion | Zapnout v OS | Morphing je zjednodušený, blur snížený |
| Touch target | Inspector → Accessibility | Každý tab ≥ 44×44px |
| Kontrast | Lighthouse / axe | Žádné kontrastní chyby |

---

## ⚠️ Rizika a rozhodnutí

| Riziko | Mitigace |
|--------|----------|
| CDN může být pomalý/ne dostupný | `preconnect`; případně fallback na inline SVG nebo system emoji při chybě |
| Font ikony nejsou pixel-perfect | Používat velikosti násobky 8px (24px, 32px), `line-height: 1` |
| Morphing pill se rozbije při resize | `window.addEventListener('resize', recalc)` a recalc při inicializaci |
| Liquid glass blur je náročný | Pro `prefers-reduced-motion` a starší zařízení snížit blur na 20px |
| Gradient ruší čitelnost | Udržet opacity nízkou (≤0.22) a testovat kontrast |

---

## 🎯 Klíčové soubory

| Soubor | Role |
|--------|------|
| `templates/index.html` | CDN link + markup ikon |
| `static/liquid-glass.css` | Všechny styly pro tab bar a ikony |
| `locales/cs.json` + `locales/en.json` | `aria-label` a tooltip texty |
