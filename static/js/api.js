"use strict";

import { showToast, __ } from './utils.js';

async function _fetch(url, options = {}) {
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (res.status === 401) {
    window.location.href = '/login';
    throw new Error('Unauthorized');
  }
  return res;
}

export async function getJSON(url) {
  const res = await _fetch(url);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || __('error.generic'));
  return data;
}

export async function postJSON(url, body) {
  const res = await _fetch(url, {
    method: 'POST',
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || __('error.generic'));
  return data;
}

export async function patchJSON(url, body) {
  const res = await _fetch(url, {
    method: 'PATCH',
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || __('error.generic'));
  return data;
}

export async function deleteJSON(url, body) {
  const opts = { method: 'DELETE' };
  if (body) opts.body = JSON.stringify(body);
  const res = await _fetch(url, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || __('error.generic'));
  return data;
}

export const API = {
  me: () => getJSON('/api/me'),
  stats: () => getJSON('/api/stats'),
  folders: () => getJSON('/api/folders'),
  emails: (params) => getJSON('/api/emails?' + new URLSearchParams(params).toString()),
  email: (id) => getJSON(`/api/emails/${id}`),
  updateEmail: (id, body) => patchJSON(`/api/emails/${id}`, body),
  trashEmail: (id) => deleteJSON(`/api/emails/${id}`),
  bulkEmails: (body) => postJSON('/api/emails/bulk', body),
  contacts: (q = '') => getJSON('/api/contacts?' + new URLSearchParams({ q }).toString()),
  createContact: (body) => postJSON('/api/contacts', body),
  deleteContact: (id) => deleteJSON(`/api/contacts/${id}`),
  createFolder: (body) => postJSON('/api/custom_folders', body),
  deleteFolder: (id) => deleteJSON(`/api/custom_folders/${id}`),
  send: (body) => postJSON('/api/send', body),
  sync: () => postJSON('/api/sync', {}),
  changePassword: (body) => postJSON('/api/change_password', body),
  logout: () => postJSON('/api/logout', {}),
  setLocale: (lang) => postJSON('/api/locale', { locale: lang }),
  starredAddresses: () => getJSON('/api/starred-addresses'),
  addStarredAddress: (email) => postJSON('/api/starred-addresses', { email }),
  removeStarredAddress: (email) => deleteJSON('/api/starred-addresses', { email }),
  contactExists: (email) => getJSON('/api/contacts/exists?' + new URLSearchParams({ email }).toString()),
};
