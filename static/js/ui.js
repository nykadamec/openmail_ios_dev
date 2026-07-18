"use strict";

import { escapeHtml, formatDate, formatFullDate, avatarColor, initial, __, stripHtml, FROM_EMAIL } from './utils.js';

export function renderEmailList(emails, currentFolder, listEl, activeId = null) {
  if (!emails.length) {
    listEl.innerHTML = `<div class="empty">${__('emails.empty')}</div>`;
    return;
  }
  const frag = document.createDocumentFragment();
  for (let i = 0; i < emails.length; i++) {
    const e = emails[i];
    const isSent = currentFolder === 'sent';
    const identifier = isSent ? (e.recipient || '') : (e.sender_email || e.sender_name || '?');
    const fromLabel = isSent ? (e.recipient || __('error.not_found')) : (e.sender_name || e.sender_email || __('error.not_found'));

    const card = document.createElement('div');
    card.className = `email-card ${e.is_read ? '' : 'unread'} ${e.is_starred ? 'starred' : ''} ${e.is_spam ? 'spam' : ''} ${activeId === e.id ? 'active' : ''}`;
    card.style.animationDelay = `${i * 0.04}s`;
    card.dataset.id = e.id;
    card.innerHTML = `
      <i class="hgi-stroke hgi-star card-star ${e.is_starred ? 'active' : ''}" aria-hidden="true"></i>
      ${e.is_spam ? '<span class="spam-badge">SPAM</span>' : ''}
      <div class="content-row">
        <div class="avatar" style="background: ${avatarColor(identifier)}">${escapeHtml(initial(identifier))}</div>
        <div class="body">
          <div class="meta-row">
            <div class="from-name">${escapeHtml(fromLabel)}</div>
            <div class="time">${formatDate(e.created_at)}</div>
          </div>
          <div class="subject">${escapeHtml(e.subject || __('error.not_found'))}</div>
        </div>
      </div>
    `;
    frag.appendChild(card);
  }
  listEl.innerHTML = '';
  listEl.appendChild(frag);
}

export function updateEmailCardRead(id) {
  const card = document.querySelector(`.email-card[data-id="${id}"]`);
  if (card) card.classList.remove('unread');
}

export function renderReader(email, currentFolder, elements) {
  const { rSubject, rMetaBlock, rBody, readerEl, readerStarBtn, htmlToggle } = elements;
  rSubject.textContent = email.subject || __('error.not_found');

  const isSent = currentFolder === 'sent';
  const identifier = isSent ? (email.recipient || '') : (email.sender_email || email.sender_name || '?');
  const from = email.sender_name || email.sender_email || __('error.not_found');
  const fromEmail = email.sender_email ? `<${email.sender_email}>` : '';

  rMetaBlock.innerHTML = `
    <div class="avatar" style="background: ${avatarColor(identifier)}">${escapeHtml(initial(identifier))}</div>
    <div class="info">
      <div class="from">${escapeHtml(isSent ? email.recipient : from)}</div>
      <div class="to">${escapeHtml(isSent ? __('composer.to') + ': ' + FROM_EMAIL : fromEmail)}</div>
    </div>
    <div class="time">${formatFullDate(email.created_at)}</div>
  `;

  let bodyHtml = '';
  if (email.body_html) {
    // Strip scripts to avoid sandbox warnings; iframe has no allow-scripts.
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
    bodyHtml = `<div class="body-html"><iframe sandbox="allow-same-origin" srcdoc="${escapeHtml(wrappedHtml).replace(/"/g, '&quot;')}"></iframe></div>
      <div class="body-plain" style="display:none">${escapeHtml(email.body_text || stripHtml(email.body_html))}</div>`;
  } else {
    bodyHtml = `<div class="body-plain">${escapeHtml(email.body_text || __('error.not_found'))}</div>`;
  }

  if (email.attachments?.length) {
    bodyHtml += `<div class="attachments"><div class="attachments-title">${__('reader.attachments')}</div>`;
    for (const a of email.attachments) {
      bodyHtml += `<div class="attachment-item"><a href="/api/attachments/${email.id}/${encodeURIComponent(a.filename)}" download>${escapeHtml(a.filename)}</a></div>`;
    }
    bodyHtml += '</div>';
  }

  rBody.innerHTML = bodyHtml;

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

  readerStarBtn.innerHTML = '<i class="hgi-stroke hgi-star" aria-hidden="true"></i>';
  readerStarBtn.classList.toggle('active', email.is_starred);
  readerEl.classList.add('open');
}

export function renderContacts(contacts, container) {
  if (!contacts.length) {
    container.innerHTML = `<div class="empty">${__('emails.empty')}</div>`;
    return;
  }
  const frag = document.createDocumentFragment();
  for (const c of contacts) {
    const item = document.createElement('div');
    item.className = 'contact-item';
    item.dataset.id = c.id;
    item.innerHTML = `
      <div class="avatar" style="background: ${avatarColor(c.email)}">${escapeHtml(initial(c.name))}</div>
      <div class="contact-info">
        <div class="contact-name">${escapeHtml(c.name)}</div>
        <div class="contact-email">${escapeHtml(c.email)}</div>
      </div>
      <button class="contact-action" aria-label="${__('contacts.delete')}">
        <i class="hgi-stroke hgi-delete-01" aria-hidden="true"></i>
      </button>
    `;
    frag.appendChild(item);
  }
  container.innerHTML = '';
  container.appendChild(frag);
}

export function renderFolders(customFolders, container, __) {
  if (!customFolders.length) {
    container.innerHTML = '';
    return;
  }
  const frag = document.createDocumentFragment();
  for (const f of customFolders) {
    const btn = document.createElement('button');
    btn.className = 'menu-item';
    btn.dataset.customFolder = f.id;
    btn.innerHTML = `
      <span class="icon" style="color:${f.color}">${f.icon}</span><span>${escapeHtml(f.name)}</span>
      <span class="menu-delete" aria-label="${__('action.delete')}">
        <i class="hgi-stroke hgi-cancel-01" aria-hidden="true"></i>
      </span>
    `;
    frag.appendChild(btn);
  }
  container.innerHTML = '';
  container.appendChild(frag);
}

export function renderAutocomplete(results, container, onSelect) {
  if (!results.length) {
    container.innerHTML = '';
    return;
  }
  container.innerHTML = results.map((c, i) => `
    <div class="ac-item" data-idx="${i}">
      <div class="ac-avatar" style="background: ${avatarColor(c.email)}">${escapeHtml(initial(c.name))}</div>
      <div>
        <div class="ac-name">${escapeHtml(c.name)}</div>
        <div class="ac-email">${escapeHtml(c.email)}</div>
      </div>
    </div>
  `).join('');
  container.querySelectorAll('.ac-item').forEach((el, i) => {
    el.addEventListener('click', () => onSelect(results[i]));
  });
}

export function showModal(html) {
  const modal = document.getElementById('modal');
  const content = document.getElementById('modalContent');
  content.innerHTML = html;
  modal.classList.add('open');
}

export function closeModal() {
  document.getElementById('modal')?.classList.remove('open');
}
