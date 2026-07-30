"use strict";

export const FROM_EMAIL = window.__OPENMAIL_FROM_EMAIL || '';
export const LOCALE = window.__OPENMAIL_LOCALE || {};

export function currentUserEmail() {
  return window.__CURRENT_USER_EMAIL || window.__OPENMAIL_FROM_EMAIL || '';
}

export function currentUserFromName() {
  return window.__CURRENT_USER_FROM_NAME || '';
}

export function currentUserDisplayFrom() {
  const email = currentUserEmail();
  const name = currentUserFromName();
  if (!email) return '';
  return name ? `${name} <${email}>` : email;
}

export function __(key, ...args) {
  let val = LOCALE[key];
  if (!val) return '??' + key + '??';
  if (args.length) {
    let i = 0;
    val = val.replace(/\{(\w+)\}/g, (_, k) => args[i++] ?? ('{' + k + '}'));
  }
  return val;
}

const AVATAR_COLORS = ['#2C2C2E', '#3A3A3C', '#48484A', '#636366', '#8E8E93'];

export function avatarColor(seed) {
  if (!seed) return AVATAR_COLORS[0];
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h << 5) - h + seed.charCodeAt(i);
  return AVATAR_COLORS[Math.abs(h) % AVATAR_COLORS.length];
}

export function initial(text) {
  if (!text) return '?';
  const c = text.replace(/[^a-zA-Z0-9]/g, '');
  return (c[0] || text[0] || '?').toUpperCase();
}

export function escapeHtml(text) {
  if (!text) return '';
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

export function stripHtml(html) {
  if (!html) return '';
  const tmp = document.createElement('div');
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || '';
}

export function formatDate(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr;
  const now = new Date();

  // Calendar-day comparison: 17.7 23:00 is "yesterday" on 18.7 00:30
  const dateDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const nowDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const dayDiff = Math.round((nowDay - dateDay) / 86400000);

  const sameYear = d.getFullYear() === now.getFullYear();
  const pad = (n) => String(n).padStart(2, '0');
  const datePart = sameYear
    ? `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}`
    : `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}`;

  const time = d.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit' });

  if (dayDiff === 0) return `${__('date.today')} (${datePart}) ${time}`;
  if (dayDiff === 1) return `${__('date.yesterday')} (${datePart}) ${time}`;
  if (dayDiff < 7) return `${__('date.days_ago', dayDiff)} ${time}`;
  if (dayDiff < 30) return `${__('date.weeks_ago', Math.floor(dayDiff / 7))} ${time}`;
  return `${__('date.months_ago', Math.floor(dayDiff / 30))} ${time}`;
}

export function formatFullDate(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr;
  return d.toLocaleString('cs-CZ', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

let toastTimer = null;
export function showToast(msg, type = 'success') {
  const toastEl = document.getElementById('toast');
  if (!toastEl) return;
  toastEl.textContent = msg;
  toastEl.className = 'toast show ' + type;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.className = 'toast', 2500);
}

export function debounce(fn, ms) {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

export function setText(id, val) {
  const el = document.getElementById(id);
  if (el) el.textContent = val || '';
}
