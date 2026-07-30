"use strict";

import { __, showToast, escapeHtml, formatFullDate, avatarColor, initial, FROM_EMAIL } from './utils.js';
import { API } from './api.js';

const emailId = window.__OPENMAIL_EMAIL_ID;

function renderBody(email) {
  const rBody = document.getElementById('rBody');
  if (!rBody) return;
  let bodyHtml = '';
  if (email.body_html) {
    const parser = new DOMParser();
    const doc = parser.parseFromString(email.body_html, 'text/html');
    doc.querySelectorAll('script').forEach(s => s.remove());
    const safeBodyHtml = doc.body.innerHTML;
    const emailCss = `<style>
      :root { color-scheme: dark; }
      html, body { margin: 0; min-height: 100vh; scrollbar-width: none; -ms-overflow-style: none; }
      body { width: 100% !important; max-width: 100% !important; padding: 16px; font: 15px/1.5 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: rgba(255,255,255,0.92); background: transparent; overflow-x: hidden; overflow-y: auto; word-break: break-word; box-sizing: border-box; }
      ::-webkit-scrollbar { width: 0; height: 0; background: transparent; }
      a { color: #60a5fa; text-decoration: underline; word-break: break-word; }
      p, h1, h2, h3 { margin: 0 0 12px; }
      img, video, svg { max-width: 100% !important; height: auto !important; }
      table, td { max-width: 100% !important; word-break: break-word; overflow-wrap: anywhere; }
      table { width: 100% !important; }
      pre { white-space: pre-wrap; word-break: break-word; overflow-wrap: anywhere; }
      blockquote { border-left: 2px solid rgba(255,255,255,0.2); padding-left: 12px; margin-left: 0; color: rgba(255,255,255,0.7); }
    </style>`;
    const wrappedHtml = emailCss + safeBodyHtml;
    const srcdoc = wrappedHtml.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    bodyHtml = `<div class="body-html"><iframe sandbox="allow-same-origin" srcdoc="${srcdoc}"></iframe></div>
      <div class="body-plain" style="display:none">${escapeHtml(email.body_text || '')}</div>`;
  } else {
    bodyHtml = `<div class="body-plain">${escapeHtml(email.body_text || email.preview || __('error.not_found'))}</div>`;
  }
  if (email.attachments?.length) {
    bodyHtml += `<div class="attachments"><div class="attachments-title">${__('reader.attachments')}</div>`;
    for (const a of email.attachments) {
      bodyHtml += `<div class="attachment-item"><a href="/api/attachments/${email.id}/${encodeURIComponent(a.filename)}" download>${escapeHtml(a.filename)}</a></div>`;
    }
    bodyHtml += '</div>';
  }
  rBody.innerHTML = bodyHtml;

  const iframe = rBody.querySelector('.body-html iframe');
  if (iframe) {
    const resize = () => {
      try {
        const doc = iframe.contentDocument || iframe.contentWindow?.document;
        if (doc) {
          iframe.style.height = Math.max(doc.documentElement.scrollHeight, doc.body?.scrollHeight || 0) + 'px';
        }
      } catch (e) {
        // cross-origin or sandbox restriction; keep min-height fallback
      }
    };
    iframe.addEventListener('load', resize);
    window.addEventListener('resize', resize);
    setTimeout(resize, 100);
    setTimeout(resize, 500);
  }
}

function renderEmail(email) {
  const rSubject = document.getElementById('rSubject');
  const rFrom = document.getElementById('rFrom');
  const rTo = document.getElementById('rTo');
  const rTime = document.getElementById('rTime');
  const senderAvatar = document.getElementById('senderAvatar');
  const readerStarBtn = document.getElementById('readerStarBtn');
  const htmlToggle = document.getElementById('htmlToggle');

  if (rSubject) rSubject.textContent = email.subject || __('error.not_found');

  const isSent = email.folder === 'sent';
  const identifier = isSent ? (email.recipient || '') : (email.sender_email || email.sender_name || '?');
  const from = email.sender_name || email.sender_email || __('error.not_found');
  const fromEmail = email.sender_email ? `<${email.sender_email}>` : '';

  if (rFrom) rFrom.textContent = isSent ? email.recipient : from;
  if (rTo) rTo.textContent = isSent ? __('composer.to') + ': ' + FROM_EMAIL : fromEmail;
  if (rTime) rTime.textContent = formatFullDate(email.received_at || email.created_at);
  if (senderAvatar) {
    senderAvatar.style.background = avatarColor(identifier);
    senderAvatar.textContent = initial(identifier);
  }

  if (readerStarBtn) {
    readerStarBtn.classList.toggle('active', email.is_starred);
    readerStarBtn.innerHTML = '<i class="hgi-stroke hgi-star" aria-hidden="true"></i>';
  }

  renderBody(email);

  if (htmlToggle) {
    const hasHtml = !!email.body_html;
    htmlToggle.style.display = hasHtml ? '' : 'none';
    htmlToggle.classList.toggle('active', false);
    htmlToggle.onclick = () => {
      const htmlEl = rBody.querySelector('.body-html');
      const plainEl = rBody.querySelector('.body-plain');
      if (htmlEl) htmlEl.style.display = htmlEl.style.display === 'none' ? '' : 'none';
      if (plainEl) plainEl.style.display = plainEl.style.display === 'none' ? '' : 'none';
      htmlToggle.classList.toggle('active', plainEl && plainEl.style.display !== 'none');
    };
  }
}

async function loadEmail() {
  if (!emailId) {
    showToast('Missing email ID', 'error');
    return;
  }
  try {
    const email = await API.email(emailId);
    renderEmail(email);
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function toggleStar() {
  try {
    const email = await API.email(emailId);
    const newStar = email.is_starred ? 0 : 1;
    await API.updateEmail(emailId, { is_starred: newStar });
    const readerStarBtn = document.getElementById('readerStarBtn');
    if (readerStarBtn) readerStarBtn.classList.toggle('active', !!newStar);
    showToast(newStar ? __('folder.starred') : __('folder.unstarred'));
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function moveToTrash() {
  try {
    await API.trashEmail(emailId);
    showToast(__('toast.email_deleted'));
    setTimeout(() => history.back(), 400);
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function init() {
  loadEmail();
  document.getElementById('backBtn')?.addEventListener('click', () => history.back());
  document.getElementById('readerStarBtn')?.addEventListener('click', toggleStar);
  document.getElementById('trashBtn')?.addEventListener('click', moveToTrash);
}

init();
