"use strict";

import { showToast, __ } from './utils.js';

export function connectSSE(onNewEmail) {
  if (!('EventSource' in window)) return;
  const evt = new EventSource('/api/events');
  evt.addEventListener('new_email', (e) => {
    try {
      const data = JSON.parse(e.data);
      if (data.is_spam) {
        showToast(__('toast.spam', data.subject || ''));
      } else {
        showToast(__('toast.new_email', data.subject || ''));
      }
      onNewEmail();
    } catch {}
  });
  evt.addEventListener('email_sent', (e) => {
    try {
      const data = JSON.parse(e.data);
      if (data.error) showToast(data.error, 'error');
      else showToast(__('toast.email_sent'));
      onNewEmail();
    } catch {}
  });
  evt.addEventListener('sync_complete', (e) => {
    try {
      const data = JSON.parse(e.data);
      if (data.error) showToast(data.error, 'error');
      else showToast(__('toast.sync_done', data.imported || 0));
      onNewEmail();
    } catch {}
  });
  evt.onerror = () => setTimeout(() => connectSSE(onNewEmail), 3000);
}
