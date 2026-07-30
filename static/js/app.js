"use strict";

import { __, showToast, debounce, setText, escapeHtml, FROM_EMAIL, currentUserDisplayFrom, currentUserEmail } from './utils.js';
import { API } from './api.js';
import * as ui from './ui.js';
import { connectSSE } from './sse.js';

// State
let currentFolder = 'inbox';
let currentCustomFolderId = null;
let currentEmailId = null;
let currentEmailData = null;
let currentEmails = [];
let customFolders = [];
let selectMode = false;
let selectedIds = new Set();
let acResults = [];
let acSelectedIdx = -1;
let pendingAttachments = [];
let emailOffset = 0;
let emailTotal = 0;
let loadingMore = false;
let scrollObserver = null;
let focusedEmailIdx = -1;
const PAGE_SIZE = 50;

function isDesktop() {
  return window.matchMedia('(min-width: 1024px)').matches;
}

// Cached DOM refs
const els = {};
function cacheElements() {
  const ids = [
    'app', 'emailList', 'reader', 'composer', 'toast', 'tabBar', 'bulkBar', 'bulkCount',
    'menuDrawer', 'menuUsername', 'menuUser', 'settingsPanel', 'settingsUsername',
    'contactsPanel', 'contactsList', 'contactSearch', 'autocompleteList',
    'customFoldersList', 'headerTitle', 'headerSubtitle', 'rSubject', 'rMetaBlock',
    'rBody', 'readerStarBtn', 'htmlToggle', 'toField', 'subjectField', 'bodyField',
    'attachmentPreview', 'attachmentInput', 'selectToggle', 'modal', 'modalContent',
    'currentPassword', 'newPassword', 'contextMenu', 'content',
  ];
  for (const id of ids) els[id] = document.getElementById(id);
}

// ---- Loading ----
async function loadEmails(reset = true) {
  if (reset) {
    emailOffset = 0;
    emailTotal = 0;
    focusedEmailIdx = -1;
    markCardActive(null);
  }
  const params = { limit: PAGE_SIZE, offset: emailOffset };
  if (currentFolder === 'archive') {
    params.folder = 'archive';
    params.direction = 'inbound';
    params.is_trash = 0;
    params.is_spam = 0;
  } else if (currentFolder === 'starred') {
    params.direction = 'inbound';
    params.starred = 1;
    params.is_trash = 0;
  } else if (currentFolder === 'spam') {
    params.direction = 'inbound';
    params.is_spam = 1;
    params.is_trash = 0;
  } else if (currentFolder === 'trash') {
    params.direction = 'inbound';
    params.is_trash = 1;
  } else if (currentFolder === 'custom' && currentCustomFolderId) {
    params.direction = 'inbound';
    params.is_trash = 0;
    params.custom_folder_id = currentCustomFolderId;
  } else {
    params.folder = currentFolder;
    params.direction = currentFolder === 'sent' ? 'outbound' : 'inbound';
    params.is_trash = 0;
    params.is_spam = 0;
  }

  if (reset) {
    els.emailList.innerHTML = `<div class="loading"><div class="spinner"></div>${__('index.header.subtitle')}</div>`;
    // Show something in header while loading, to avoid stale "Synchronizace…"
    if (els.headerSubtitle) els.headerSubtitle.textContent = __('emails.loading') || __('index.header.subtitle');
  }
  try {
    const data = await API.emails(params);
    const emails = (data.emails || []).sort((a, b) => {
      const ta = new Date(a.received_at || a.created_at || 0).getTime();
      const tb = new Date(b.received_at || b.created_at || 0).getTime();
      return tb - ta;
    });
    emailTotal = data.total || emails.length;
    currentEmails = reset ? emails : currentEmails.concat(emails);

    if (reset && emails.length === 0) {
      els.emailList.innerHTML = `<div class="empty">${__('emails.empty')}</div>`;
      return;
    }
    ui.renderEmailList(currentEmails, currentFolder, els.emailList, currentEmailId);
    setupInfiniteScroll();
  } catch (err) {
    if (reset) els.emailList.innerHTML = `<div class="empty">${__('error.generic')}: ${escapeHtml(err.message)}</div>`;
  }
}

async function loadMore() {
  if (loadingMore || emailOffset + PAGE_SIZE >= emailTotal) return;
  loadingMore = true;
  emailOffset += PAGE_SIZE;
  await loadEmails(false);
  loadingMore = false;
}

function setupInfiniteScroll() {
  const existing = document.getElementById('scroll-sentinel');
  if (existing) existing.remove();
  if (emailOffset + PAGE_SIZE >= emailTotal) return;

  const sentinel = document.createElement('div');
  sentinel.id = 'scroll-sentinel';
  sentinel.className = 'scroll-sentinel';
  els.emailList.appendChild(sentinel);

  if (scrollObserver) scrollObserver.disconnect();
  scrollObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) loadMore();
    }
  }, { rootMargin: '200px' });
  scrollObserver.observe(sentinel);
}

async function loadStats() {
  try {
    const s = await API.stats();
    const sub = [];
    if (s.unread) sub.push(s.unread + ' ' + __('action.unread'));
    if (s.spam) sub.push(s.spam + ' ' + __('folder.spam'));
    sub.push(s.inbound + ' ' + __('folder.inbox'));
    els.headerSubtitle.textContent = sub.join(' · ');
    setText('menuBadgeInbox', s.unread);
    setText('menuBadgeStarred', s.starred);
    setText('menuBadgeSpam', s.spam);
    setText('menuBadgeTrash', s.trash);
  } catch {}
}

async function loadMe() {
  try {
    const user = await API.me();
    window.__CURRENT_USER_EMAIL = user.email || '';
    window.__CURRENT_USER_FROM_NAME = user.from_name || '';
    els.menuUsername.textContent = user.email || ('@' + user.username);
    els.menuUser.textContent = (user.username ? user.username[0].toUpperCase() : '?');
    els.settingsUsername.textContent = user.email || user.username;
    const composerFrom = document.getElementById('composerFrom');
    if (composerFrom) composerFrom.textContent = currentUserDisplayFrom();
  } catch (e) {}
}

async function loadFolders() {
  try {
    const data = await API.folders();
    customFolders = data.custom || [];
    ui.renderFolders(customFolders, els.customFoldersList, __);
  } catch {}
}

// ---- Navigation ----
function setFolder(folder, customFolderId = null) {
  currentFolder = folder;
  currentCustomFolderId = customFolderId;
  hideContextMenu();
  closeReader();
  // Preserve tab bar minimal state across folder changes
  const wasMinimal = els.tabBar?.classList.contains('minimal');
  if (els.tabBar) {
    els.tabBar.querySelectorAll('.tab').forEach(el => el.classList.remove('active'));
    const active = els.tabBar.querySelector(`.tab[data-folder="${folder}"]`);
    if (active) active.classList.add('active');
    if (wasMinimal) els.tabBar.classList.add('minimal');
  }
  if (els.menuDrawer) {
    els.menuDrawer.querySelectorAll('.menu-item').forEach(el => el.classList.remove('active'));
    const activeMenu = els.menuDrawer.querySelector(`.menu-item[data-folder="${folder}"]`);
    if (activeMenu) activeMenu.classList.add('active');
  }

  const titles = { inbox: __('folder.inbox'), sent: __('folder.sent'), starred: __('folder.starred'), spam: __('folder.spam'), trash: __('folder.trash'), custom: __('folder.inbox') };
  const customName = customFolders.find(f => f.id === customFolderId)?.name;
  if (els.headerTitle) els.headerTitle.textContent = titles[folder] || customName || folder;
  loadEmails();
  loadStats();
}

// ---- Reader ----
async function openEmail(id) {
  try {
    const e = await API.email(id);
    currentEmailId = id;
    currentEmailData = e;

    // Mark card as read immediately in the DOM
    const card = document.querySelector(`.email-card[data-id="${id}"]`);
    if (card) {
      card.classList.remove('unread');
      markCardActive(card);
    }

    // Update in-memory state
    const local = currentEmails.find(em => em.id === id);
    if (local && !local.is_read) {
      local.is_read = 1;
      loadStats();
    }

    ui.renderReader(e, currentFolder, {
      rSubject: els.rSubject,
      rMetaBlock: els.rMetaBlock,
      rBody: els.rBody,
      readerEl: els.reader,
      readerStarBtn: els.readerStarBtn,
      htmlToggle: els.htmlToggle,
    });
    bodyScrollY = window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
    document.body.style.top = `-${bodyScrollY}px`;
    document.documentElement.classList.add('reader-open');
    document.body.classList.add('reader-open');
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function markCardActive(card) {
  document.querySelectorAll('.email-card').forEach(c => c.classList.remove('active'));
  if (card) card.classList.add('active');
}

function focusEmailByIndex(idx) {
  const cards = Array.from(document.querySelectorAll('.email-card'));
  if (idx < 0) idx = 0;
  if (idx >= cards.length) idx = cards.length - 1;
  focusedEmailIdx = idx;
  cards[idx]?.scrollIntoView({ block: 'nearest' });
  markCardActive(cards[idx]);
}

function openFocusedEmail() {
  const cards = Array.from(document.querySelectorAll('.email-card'));
  const card = cards[focusedEmailIdx];
  if (card) {
    const id = parseInt(card.dataset.id, 10);
    openEmail(id);
  }
}

function closeReader() {
  els.reader.classList.remove('open');
  document.documentElement.classList.remove('reader-open');
  document.body.classList.remove('reader-open');
  document.body.style.top = '';
  document.documentElement.style.scrollBehavior = 'auto';
  window.scrollTo(0, bodyScrollY);
  // Force Safari to recalculate the document height / viewport
  const app = document.getElementById('app');
  if (app) {
    app.style.minHeight = '100dvh';
    requestAnimationFrame(() => {
      app.style.minHeight = '';
      document.documentElement.style.scrollBehavior = '';
    });
  }
  currentEmailId = null;
  currentEmailData = null;
  if (isDesktop()) {
    markCardActive(null);
  }
}

async function toggleStar(id) {
  const e = currentEmails.find(em => em.id === id);
  if (!e) return;
  const newStar = e.is_starred ? 0 : 1;
  try {
    await API.updateEmail(id, { is_starred: newStar });
    e.is_starred = newStar;
    const card = document.querySelector(`.email-card[data-id="${id}"]`);
    const star = card?.querySelector('.card-star');
    if (star) star.classList.toggle('active', !!newStar);
    showToast(newStar ? __('folder.starred') : __('folder.unstarred'));
    loadStats();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function showContextMenu(x, y, id) {
  if (!els.contextMenu) return;
  // Measure using a temporary visible clone so the real element keeps display:none until positioned
  const clone = els.contextMenu.cloneNode(true);
  clone.style.visibility = 'hidden';
  clone.style.position = 'fixed';
  clone.style.left = '-9999px';
  clone.style.top = '-9999px';
  clone.classList.add('open');
  document.body.appendChild(clone);
  const rect = clone.getBoundingClientRect();
  document.body.removeChild(clone);

  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const menuW = rect.width || 220;
  const menuH = rect.height || 160;

  // Keep fully inside viewport with small margin
  const safeX = Math.max(12, Math.min(x, vw - menuW - 12));
  const safeY = Math.max(12, Math.min(y, vh - menuH - 12));

  els.contextMenu.style.left = `${safeX}px`;
  els.contextMenu.style.top = `${safeY}px`;
  els.contextMenu.classList.add('open');
  els.contextMenu.dataset.emailId = id;
}

function hideContextMenu() {
  els.contextMenu?.classList.remove('open');
}

let suppressNextCardClick = false;
let suppressNextMenuClick = false;
let bodyScrollY = 0;

function initLongPressContextMenu() {
  if (isDesktop()) return;
  const LONG_PRESS_MS = 450;
  let timer = null;
  let startX = 0;
  let startY = 0;
  let targetCard = null;
  let longPressFired = false;
  const appEl = document.getElementById('app');

  function clearLongPressState() {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    if (targetCard) {
      targetCard.style.webkitUserSelect = '';
      targetCard.style.userSelect = '';
    }
    targetCard = null;
    appEl?.classList.remove('long-press-active');
  }

  els.emailList.addEventListener('touchstart', (e) => {
    if (selectMode || els.contextMenu?.classList.contains('open')) return;
    const touch = e.touches[0];
    const card = e.target.closest('.email-card');
    if (!card) return;
    startX = touch.clientX;
    startY = touch.clientY;
    targetCard = card;
    longPressFired = false;
    suppressNextCardClick = false;
    suppressNextMenuClick = false;
    appEl?.classList.add('long-press-active');

    timer = setTimeout(() => {
      timer = null;
      longPressFired = true;
      const id = parseInt(targetCard?.dataset.id || '', 10);
      if (!id) return;
      // Use the touch point, but keep inside viewport
      const x = Math.min(Math.max(startX, 16), window.innerWidth - 180);
      const y = Math.min(Math.max(startY, 16), window.innerHeight - 200);
      // Haptic feedback if available
      if (navigator.vibrate) navigator.vibrate(40);
      suppressNextCardClick = true;
      suppressNextMenuClick = true;
      showContextMenu(x, y, id);
    }, LONG_PRESS_MS);
  }, { passive: true });

  els.emailList.addEventListener('touchmove', (e) => {
    if (!timer) return;
    const touch = e.touches[0];
    const delta = Math.hypot(touch.clientX - startX, touch.clientY - startY);
    // Cancel long-press if finger moves more than 12px
    if (delta > 12) {
      clearLongPressState();
    }
  }, { passive: true });

  els.emailList.addEventListener('touchend', () => {
    clearLongPressState();
  });

  els.emailList.addEventListener('touchcancel', () => {
    clearLongPressState();
  });

  // Prevent the first click/tap after a long-press from activating a context-item
  els.contextMenu?.addEventListener('click', (e) => {
    if (suppressNextMenuClick) {
      e.preventDefault();
      e.stopPropagation();
      suppressNextMenuClick = false;
    }
  }, true);

  // Hide context menu on any scroll
  els.content?.addEventListener('scroll', () => hideContextMenu(), { passive: true });
}

function initTabBarScrollBehavior() {
  if (isDesktop() || !els.tabBar) return;
  let lastScrollY = 0;
  let ticking = false;
  const SCROLL_DOWN_THRESHOLD = 18;
  const SCROLL_UP_THRESHOLD = 8;

  function getScrollY() {
    return window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
  }
  function resetScrollState() {
    lastScrollY = getScrollY();
  }
  function shouldIgnoreScroll() {
    return (
      els.reader?.classList.contains('open') ||
      els.composer?.classList.contains('open') ||
      els.menuDrawer?.classList.contains('open') ||
      els.settingsPanel?.classList.contains('open') ||
      els.contactsPanel?.classList.contains('open') ||
      document.getElementById('modal')?.classList.contains('open')
    );
  }
  // Reset scroll tracking after folder changes so old scrollTop doesn't force un-minimize
  const originalSetFolder = setFolder;
  setFolder = function(folder, customFolderId = null) {
    const result = originalSetFolder(folder, customFolderId);
    requestAnimationFrame(resetScrollState);
    return result;
  };

  window.addEventListener('scroll', () => {
    if (ticking || shouldIgnoreScroll()) return;
    ticking = true;
    requestAnimationFrame(() => {
      const y = getScrollY();
      const delta = y - lastScrollY;
      if (delta > SCROLL_DOWN_THRESHOLD && y > 20) {
        els.tabBar.classList.add('minimal');
      } else if (delta < -SCROLL_UP_THRESHOLD) {
        els.tabBar.classList.remove('minimal');
      }
      lastScrollY = y;
      ticking = false;
    });
  }, { passive: true });
}

async function contextAction(action) {
  const id = parseInt(els.contextMenu?.dataset.emailId || '', 10);
  if (!id) return;
  try {
    if (action === 'read' || action === 'unread') {
      await API.updateEmail(id, { is_read: action === 'read' ? 1 : 0 });
    } else if (action === 'archive') {
      await API.updateEmail(id, { folder: 'archive', is_spam: 0 });
    } else if (action === 'delete') {
      await API.updateEmail(id, { is_trash: 1 });
    }
    hideContextMenu();
    loadEmails();
    loadStats();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function toggleStarFromReader() {
  if (!currentEmailId) return;
  const current = currentEmails.find(e => e.id === currentEmailId);
  const newStar = current ? (current.is_starred ? 0 : 1) : 1;
  try {
    await API.updateEmail(currentEmailId, { is_starred: newStar });
    els.readerStarBtn.classList.toggle('active', !!newStar);
    showToast(__('folder.starred'));
    loadEmails();
    loadStats();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function moveToTrash() {
  if (!currentEmailId) return;
  try {
    await API.trashEmail(currentEmailId);
    showToast(__('toast.email_deleted'));
    closeReader();
    loadEmails();
    loadStats();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ---- Composer ----
function openComposer() {
  els.composer.classList.add('open');
  els.autocompleteList.innerHTML = '';
  const composerFrom = document.getElementById('composerFrom');
  if (composerFrom) composerFrom.textContent = currentUserDisplayFrom();
  // Highlight compose button in tab bar
  els.tabBar?.querySelectorAll('.tab, .compose-wrap .compose').forEach(el => el.classList.remove('active'));
  const composeBtn = els.tabBar?.querySelector('.compose-wrap .compose');
  if (composeBtn) composeBtn.classList.add('active');
  setTimeout(() => els.toField.focus(), 100);
}

function closeComposer() {
  els.composer.classList.remove('open');
  // Restore active folder tab
  const composeBtn = els.tabBar?.querySelector('.compose-wrap .compose');
  if (composeBtn) composeBtn.classList.remove('active');
  els.tabBar?.querySelectorAll('.tab[data-folder]').forEach(el => {
    el.classList.toggle('active', el.dataset.folder === currentFolder);
  });
  els.toField.value = '';
  els.subjectField.value = '';
  els.bodyField.value = '';
  els.autocompleteList.innerHTML = '';
  els.attachmentPreview.innerHTML = '';
  pendingAttachments = [];
}

async function sendEmail() {
  const payload = {
    to: els.toField.value,
    subject: els.subjectField.value,
    body: els.bodyField.value,
    attachments: pendingAttachments,
  };
  if (!payload.to || !payload.subject) {
    showToast(__('error.missing_recipient'), 'error');
    return;
  }
  try {
    const result = await API.send(payload);
    if (result.error) {
      showToast(result.error, 'error');
      return;
    }
    showToast(__('toast.email_sent'));
    closeComposer();
    loadEmails();
    loadStats();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function syncEmails() {
  showToast(__('toast.sync_started'));
  try {
    await API.sync();
    // result comes via SSE
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ---- Contacts ----
function openContacts() {
  closeMenu();
  els.contactsPanel.classList.add('open');
  loadContacts();
}

function closeContacts() {
  els.contactsPanel.classList.remove('open');
}

async function loadContacts() {
  const q = els.contactSearch?.value || '';
  try {
    const contacts = await API.contacts(q);
    ui.renderContacts(contacts, els.contactsList);
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function showNewContact() {
  ui.showModal(`
    <h2>${__('contacts.new.title')}</h2>
    <div class="field"><label>${__('contacts.new.name')}</label><input type="text" id="newContactName" autofocus></div>
    <div class="field"><label>${__('contacts.new.email')}</label><input type="email" id="newContactEmail"></div>
    <div class="field"><label>${__('contacts.new.notes')}</label><input type="text" id="newContactNotes"></div>
    <div class="modal-actions">
      <button class="cancel-btn" onclick="closeModal()">${__('contacts.new.cancel')}</button>
      <button class="primary-btn" id="createContactBtn">${__('contacts.new.save')}</button>
    </div>
  `);
  document.getElementById('createContactBtn')?.addEventListener('click', createContact);
}

async function createContact() {
  const name = document.getElementById('newContactName').value;
  const email = document.getElementById('newContactEmail').value;
  const notes = document.getElementById('newContactNotes').value;
  if (!name || !email) {
    showToast(__('toast.fill_name_email'), 'error');
    return;
  }
  try {
    await API.createContact({ name, email, notes });
    showToast(__('contacts.saved'));
    ui.closeModal();
    loadContacts();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function deleteContact(id) {
  if (!confirm(__('contacts.delete_confirm'))) return;
  try {
    await API.deleteContact(id);
    loadContacts();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ---- Autocomplete ----
const fetchAutocomplete = debounce(async (q) => {
  try {
    acResults = await API.contacts(q);
    ui.renderAutocomplete(acResults, els.autocompleteList, (c) => {
      els.toField.value = c.email;
      els.autocompleteList.innerHTML = '';
    });
  } catch {}
}, 150);

function onToInput() {
  const val = els.toField.value;
  if (val.length < 1) {
    els.autocompleteList.innerHTML = '';
    return;
  }
  fetchAutocomplete(val);
}

// ---- Folders ----
function showNewFolder() {
  ui.showModal(`
    <h2>${__('folder.new.title')}</h2>
    <div class="field"><label>${__('folder.new.name')}</label><input type="text" id="newFolderName" autofocus></div>
    <div class="field"><label>${__('folder.new.name')}</label><input type="color" id="newFolderColor" value="#3B82F6"></div>
    <div class="field">
      <select id="newFolderIcon" style="width:100%;padding:12px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:12px;color:#fff;">
        <option value='<i class="hgi-stroke hgi-folder-01" aria-hidden="true"></i>'>Folder</option>
        <option value='<i class="hgi-stroke hgi-folder-open" aria-hidden="true"></i>'>Open folder</option>
        <option value='<i class="hgi-stroke hgi-star" aria-hidden="true"></i>'>Star</option>
        <option value='<i class="hgi-stroke hgi-fire" aria-hidden="true"></i>'>Fire</option>
        <option value='<i class="hgi-stroke hgi-briefcase-01" aria-hidden="true"></i>'>Briefcase</option>
        <option value='<i class="hgi-stroke hgi-home-01" aria-hidden="true"></i>'>Home</option>
        <option value='<i class="hgi-stroke hgi-book-01" aria-hidden="true"></i>'>Book</option>
        <option value='<i class="hgi-stroke hgi-target-01" aria-hidden="true"></i>'>Target</option>
      </select>
    </div>
    <div class="modal-actions">
      <button class="cancel-btn" onclick="closeModal()">${__('folder.new.cancel')}</button>
      <button class="primary-btn" id="createFolderBtn">${__('folder.new.create')}</button>
    </div>
  `);
  document.getElementById('createFolderBtn')?.addEventListener('click', createFolder);
}

async function createFolder() {
  const name = document.getElementById('newFolderName').value;
  const color = document.getElementById('newFolderColor').value;
  const icon = document.getElementById('newFolderIcon').value;
  if (!name) {
    showToast(__('error.name_required'), 'error');
    return;
  }
  try {
    await API.createFolder({ name, color, icon });
    showToast(__('folder.new.created'));
    ui.closeModal();
    loadFolders();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function deleteFolder(id) {
  if (!confirm(__('folder.new.title') + '?')) return;
  try {
    await API.deleteFolder(id);
    loadFolders();
    if (currentCustomFolderId === id) setFolder('inbox');
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ---- Bulk actions ----
function toggleSelectMode() {
  selectMode = !selectMode;
  selectedIds.clear();
  els.app.classList.toggle('select-mode', selectMode);
  els.bulkBar?.classList.toggle('show', false);
  const icon = selectMode
    ? '<i class="hgi-stroke hgi-checkmark-square-01" aria-hidden="true"></i>'
    : '<i class="hgi-stroke hgi-square" aria-hidden="true"></i>';
  els.selectToggle.innerHTML = icon;
  document.querySelectorAll('.email-card').forEach(card => card.classList.remove('selected'));
  updateBulkBar();
}

function onSelectChange(id, checked) {
  const numId = parseInt(id, 10);
  if (checked) selectedIds.add(numId);
  else selectedIds.delete(numId);
  const card = document.querySelector(`.email-card[data-id="${id}"]`);
  if (card) card.classList.toggle('selected', checked);
  updateBulkBar();
}

function updateBulkBar() {
  const count = selectedIds.size;
  els.bulkBar.classList.toggle('show', count > 0);
  els.bulkCount.textContent = __('action.selected', count);
  els.bulkBar.querySelectorAll('button').forEach(b => b.disabled = count === 0);
}

async function bulkAction(action) {
  if (selectedIds.size === 0) {
    showToast(__('toast.bulk_empty'), 'error');
    return;
  }
  if (action === 'delete' && !confirm(__('action.confirm_delete', selectedIds.size))) return;
  try {
    const data = await API.bulkEmails({ ids: Array.from(selectedIds), action });
    showToast(__('toast.bulk_done', data.count));
    toggleSelectMode();
    loadEmails();
    loadStats();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ---- Settings ----
function openSettings() {
  closeMenu();
  els.settingsPanel.classList.add('open');
}

function closeSettings() {
  els.settingsPanel.classList.remove('open');
}

async function changePassword() {
  const current_pw = els.currentPassword.value;
  const new_pw = els.newPassword.value;
  if (!current_pw || !new_pw) {
    showToast(__('toast.fill_fields'), 'error');
    return;
  }
  try {
    await API.changePassword({ current_password: current_pw, new_password: new_pw });
    showToast(__('toast.password_changed'));
    els.currentPassword.value = '';
    els.newPassword.value = '';
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function setLanguage(lang) {
  await API.setLocale(lang);
  window.location.reload();
}

async function clearCache() {
  try {
    if ('caches' in window) {
      const keys = await caches.keys();
      await Promise.all(keys.map(k => caches.delete(k)));
    }
    showToast(__('settings.cache_cleared'));
    setTimeout(() => window.location.reload(true), 900);
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// ---- Menu ----
function toggleMenu() {
  els.menuDrawer.classList.add('open');
}
function closeMenu() {
  els.menuDrawer.classList.remove('open');
}
async function logout() {
  try {
    await API.logout();
  } catch {}
  window.location.href = '/login';
}

// ---- Attachments ----
function onAttachmentsChange() {
  pendingAttachments = [];
  els.attachmentPreview.innerHTML = '';
  for (const file of els.attachmentInput.files) {
    const reader = new FileReader();
    reader.onload = (e) => {
      pendingAttachments.push({
        filename: file.name,
        content: e.target.result.split(',')[1],
        content_type: file.type || 'application/octet-stream',
      });
      const div = document.createElement('div');
      div.className = 'attachment-chip';
      div.innerHTML = `<i class="hgi-stroke hgi-attachment-01" aria-hidden="true"></i> ${escapeHtml(file.name)} (${Math.round(file.size / 1024)} KB)`;
      els.attachmentPreview.appendChild(div);
    };
    reader.readAsDataURL(file);
  }
}

// ---- Swipe navigation ----
const SWIPE_THRESHOLD = 100;
const SWIPE_LOCK_ANGLE = 0.55; // radians; ~31 degrees
const SWIPE_TABS = ['inbox', 'starred', 'spam'];

function initSwipeNavigation() {
  if (isDesktop()) return;
  const surface = document.getElementById('content') || document.body;
  const appEl = document.getElementById('app');
  let startX = 0;
  let startY = 0;
  let currentX = 0;
  let currentY = 0;
  let isTracking = false;
  let gestureLocked = false; // 'horizontal' | 'vertical' | false
  let didSwipe = false;

  surface.addEventListener('touchstart', (e) => {
    if (shouldBlockSwipe()) return;
    const touch = e.touches[0];
    startX = touch.clientX;
    startY = touch.clientY;
    currentX = startX;
    currentY = startY;
    isTracking = true;
    gestureLocked = false;
    didSwipe = false;
  }, { passive: true });

  surface.addEventListener('touchmove', (e) => {
    if (!isTracking) return;
    const touch = e.touches[0];
    currentX = touch.clientX;
    currentY = touch.clientY;
    const deltaX = currentX - startX;
    const deltaY = currentY - startY;

    // Until the gesture is locked, decide whether this is horizontal or vertical
    if (!gestureLocked) {
      const absX = Math.abs(deltaX);
      const absY = Math.abs(deltaY);
      const minLock = 14;
      if (absX < minLock && absY < minLock) return;
      // Angle from horizontal; smaller means more horizontal
      const angle = Math.atan2(absY, absX);
      if (angle < SWIPE_LOCK_ANGLE) {
        gestureLocked = 'horizontal';
        appEl?.classList.add('swipe-active');
        // Prevent vertical scroll during the horizontal swipe
        if (els.content) els.content.style.overflowY = 'hidden';
      } else {
        gestureLocked = 'vertical';
        // Let the browser handle the scroll; stop tracking this touch for swipe
        isTracking = false;
      }
      return;
    }

    if (gestureLocked === 'horizontal') {
      didSwipe = true;
      applySwipeTransform(deltaX);
    }
  }, { passive: true });

  surface.addEventListener('touchend', () => {
    if (!isTracking) return;
    isTracking = false;
    appEl?.classList.remove('swipe-active');
    if (els.content) els.content.style.overflowY = '';
    const deltaX = currentX - startX;
    const deltaY = currentY - startY;
    resetSwipeTransform();

    // Only trigger if the gesture was locked horizontally and passed threshold
    if (gestureLocked !== 'horizontal' || Math.abs(deltaX) < SWIPE_THRESHOLD) {
      didSwipe = false;
      return;
    }

    const idx = SWIPE_TABS.indexOf(currentFolder);
    if (idx === -1) return;
    if (deltaX < 0 && idx < SWIPE_TABS.length - 1) {
      setFolder(SWIPE_TABS[idx + 1]);
    } else if (deltaX > 0 && idx > 0) {
      setFolder(SWIPE_TABS[idx - 1]);
    }
  });

  surface.addEventListener('touchcancel', () => {
    isTracking = false;
    gestureLocked = false;
    appEl?.classList.remove('swipe-active');
    if (els.content) els.content.style.overflowY = '';
    resetSwipeTransform();
  });

  // Prevent accidental click after a horizontal swipe gesture
  surface.addEventListener('click', (e) => {
    if (didSwipe) {
      e.preventDefault();
      e.stopPropagation();
      didSwipe = false;
    }
  }, true);
}

function shouldBlockSwipe() {
  return (
    selectMode ||
    els.reader?.classList.contains('open') ||
    els.composer?.classList.contains('open') ||
    els.menuDrawer?.classList.contains('open') ||
    els.settingsPanel?.classList.contains('open') ||
    els.contactsPanel?.classList.contains('open') ||
    document.getElementById('modal')?.classList.contains('open')
  );
}

function applySwipeTransform(deltaX) {
  const list = els.emailList;
  if (!list) return;
  list.style.transform = `translateX(${deltaX * 0.4}px)`;
  list.style.opacity = String(Math.max(0.5, 1 - Math.abs(deltaX) / 600));
}

function resetSwipeTransform() {
  const list = els.emailList;
  if (!list) return;
  list.style.transform = '';
  list.style.opacity = '';
}

// ---- Global event delegation ----
function onGlobalClick(e) {
  const target = e.target.closest('[data-action]') || e.target;
  const action = target.dataset?.action;
  if (!action) return;
  e.preventDefault();
  e.stopPropagation();
  switch (action) {
    // handled by inline data-action in HTML later
  }
}

// ---- Init ----
function initEventListeners() {
  document.getElementById('menuDrawer')?.addEventListener('click', (e) => {
    if (e.target.id === 'menuDrawer') closeMenu();
  });
  document.getElementById('logoutForm')?.addEventListener('submit', () => {});

  // Menu buttons
  document.querySelectorAll('[data-folder]').forEach(btn => {
    btn.addEventListener('click', () => {
      const folder = btn.dataset.folder;
      if (folder) {
        if (els.composer?.classList.contains('open')) closeComposer();
        setFolder(folder);
      }
    });
  });
  document.querySelector('[data-action="toggleMenu"]')?.addEventListener('click', toggleMenu);
  document.querySelector('[data-action="selectMode"]')?.addEventListener('click', toggleSelectMode);
  document.querySelector('[data-action="htmlToggle"]')?.addEventListener('click', () => {
    // handler lives in ui.renderReader via htmlToggle.onclick
  });
  document.querySelector('[data-action="openComposer"]')?.addEventListener('click', openComposer);
  document.querySelector('[data-action="sync"]')?.addEventListener('click', syncEmails);
  document.querySelector('[data-action="openContacts"]')?.addEventListener('click', openContacts);
  document.querySelector('[data-action="openSettings"]')?.addEventListener('click', openSettings);
  document.querySelector('[data-action="closeMenu"]')?.addEventListener('click', closeMenu);
  document.querySelector('[data-action="logout"]')?.addEventListener('click', logout);
  document.querySelector('[data-action="closeContacts"]')?.addEventListener('click', closeContacts);
  document.querySelector('[data-action="closeSettings"]')?.addEventListener('click', closeSettings);
  document.querySelector('[data-action="closeReader"]')?.addEventListener('click', closeReader);
  document.querySelector('[data-action="closeComposer"]')?.addEventListener('click', closeComposer);
  document.querySelector('[data-action="sendEmail"]')?.addEventListener('click', sendEmail);
  document.querySelector('[data-action="toggleStarFromReader"]')?.addEventListener('click', toggleStarFromReader);
  document.querySelector('[data-action="moveToTrash"]')?.addEventListener('click', moveToTrash);
  document.querySelector('[data-action="newFolder"]')?.addEventListener('click', showNewFolder);
  document.querySelector('[data-action="newContact"]')?.addEventListener('click', showNewContact);
  document.querySelector('[data-action="changePassword"]')?.addEventListener('click', changePassword);
  document.querySelector('[data-action="clearCache"]')?.addEventListener('click', clearCache);

  // Bulk bar
  if (els.bulkBar) {
    els.bulkBar.querySelectorAll('button').forEach(btn => {
      const action = btn.dataset.bulk;
      if (action) btn.addEventListener('click', () => bulkAction(action));
    });
  }

  // Email list clicks
  els.emailList.addEventListener('click', (e) => {
    if (suppressNextCardClick) {
      e.preventDefault();
      e.stopPropagation();
      suppressNextCardClick = false;
      return;
    }
    const star = e.target.closest('.card-star');
    if (star) {
      const card = star.closest('.email-card');
      const id = parseInt(card?.dataset.id, 10);
      if (id) {
        e.stopPropagation();
        toggleStar(id);
      }
      return;
    }
    const card = e.target.closest('.email-card');
    if (!card) return;
    const id = parseInt(card.dataset.id, 10);
    focusedEmailIdx = Array.from(document.querySelectorAll('.email-card')).indexOf(card);
    if (selectMode) {
      const isSelected = !selectedIds.has(id);
      onSelectChange(id, isSelected);
      return;
    }
    if (isDesktop()) {
      openEmail(id);
    } else {
      window.location.href = `/email/${id}`;
    }
  });

  // Context menu on desktop (right click)
  els.emailList.addEventListener('contextmenu', (e) => {
    if (!isDesktop()) return;
    const card = e.target.closest('.email-card');
    if (!card) return;
    e.preventDefault();
    const id = parseInt(card.dataset.id, 10);
    showContextMenu(e.clientX, e.clientY, id);
  });

  // Context menu on mobile (long press)
  initLongPressContextMenu();

  document.addEventListener('click', (e) => {
    if (!els.contextMenu?.classList.contains('open')) return;
    const item = e.target.closest('.context-item');
    if (item) {
      e.preventDefault();
      contextAction(item.dataset.ctx);
    } else if (!els.contextMenu.contains(e.target)) {
      hideContextMenu();
    }
  });

  document.addEventListener('keydown', (e) => {
    // Ignore if typing in an input/textarea
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes(e.target.tagName)) return;
    if (els.composer?.classList.contains('open')) {
      if (e.key === 'Escape') { e.preventDefault(); closeComposer(); }
      return;
    }
    if (els.reader?.classList.contains('open') || isDesktop()) {
      switch (e.key) {
        case 'j':
          e.preventDefault();
          focusEmailByIndex(focusedEmailIdx + 1);
          if (isDesktop()) openFocusedEmail();
          break;
        case 'k':
          e.preventDefault();
          focusEmailByIndex(focusedEmailIdx - 1);
          if (isDesktop()) openFocusedEmail();
          break;
        case 'Enter':
          e.preventDefault();
          openFocusedEmail();
          break;
        case 'Delete':
        case 'Backspace':
          if (currentEmailId) {
            e.preventDefault();
            moveToTrash();
          }
          break;
        case 'e':
          if (currentEmailId) {
            e.preventDefault();
            // spam toggle
            const cur = currentEmails.find(em => em.id === currentEmailId);
            const newSpam = cur ? (cur.is_spam ? 0 : 1) : 1;
            API.updateEmail(currentEmailId, { is_spam: newSpam }).then(() => {
              showToast(newSpam ? __('folder.spam') : __('folder.inbox'));
              loadEmails();
              loadStats();
            }).catch(err => showToast(err.message, 'error'));
          }
          break;
        case 's':
          if (currentEmailId) {
            e.preventDefault();
            toggleStarFromReader();
          }
          break;
        case 'r':
          e.preventDefault();
          showToast(__('action.reply_placeholder') || 'Reply not yet implemented', 'error');
          break;
        case 'c':
          e.preventDefault();
          openComposer();
          break;
        case 'Escape':
          if (els.reader?.classList.contains('open') && !isDesktop()) {
            e.preventDefault();
            closeReader();
          }
          break;
      }
    }
  });

  // Custom folders and delete buttons inside menu
  els.customFoldersList.addEventListener('click', (e) => {
    const item = e.target.closest('.menu-item');
    const del = e.target.closest('.menu-delete');
    if (del) {
      e.stopPropagation();
      const id = parseInt(item?.dataset.customFolder, 10);
      if (id) deleteFolder(id);
      return;
    }
    if (item) {
      const id = parseInt(item.dataset.customFolder, 10);
      if (id) { setFolder('custom', id); closeMenu(); }
    }
  });

  // Contacts delete
  els.contactsList.addEventListener('click', (e) => {
    const del = e.target.closest('.contact-action');
    if (del) {
      const item = del.closest('.contact-item');
      const id = parseInt(item?.dataset.id, 10);
      if (id) deleteContact(id);
    }
  });

  // Composer autocomplete
  els.toField.addEventListener('input', onToInput);
  els.toField.addEventListener('keydown', (e) => {
    const items = els.autocompleteList.querySelectorAll('.ac-item');
    if (!items.length) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      acSelectedIdx = Math.min(acSelectedIdx + 1, items.length - 1);
      items.forEach((el, i) => el.classList.toggle('active', i === acSelectedIdx));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      acSelectedIdx = Math.max(acSelectedIdx - 1, 0);
      items.forEach((el, i) => el.classList.toggle('active', i === acSelectedIdx));
    } else if (e.key === 'Enter' && acSelectedIdx >= 0) {
      e.preventDefault();
      const c = acResults[acSelectedIdx];
      if (c) {
        els.toField.value = c.email;
        els.autocompleteList.innerHTML = '';
      }
      acSelectedIdx = -1;
    } else if (e.key === 'Escape') {
      els.autocompleteList.innerHTML = '';
      acSelectedIdx = -1;
    }
  });

  // Swipe navigation between tabs on mobile
  initSwipeNavigation();

  // Minimize tab bar on scroll down / restore on scroll up
  initTabBarScrollBehavior();

  // Language switch
  document.querySelectorAll('[data-lang]').forEach(btn => {
    btn.addEventListener('click', () => setLanguage(btn.dataset.lang));
  });

  // Attachment input
  els.attachmentInput.addEventListener('change', onAttachmentsChange);
  document.querySelector('[data-action="attach"]')?.addEventListener('click', () => els.attachmentInput.click());

  // Contact search
  els.contactSearch.addEventListener('input', debounce(loadContacts, 150));
}

document.addEventListener('DOMContentLoaded', () => {
  try {
    cacheElements();
    initEventListeners();
    loadMe();
    loadFolders();
    setFolder('inbox');
    console.log('[openMail] app initialized');
  } catch (err) {
    console.error('[openMail] init failed:', err);
    const list = document.getElementById('emailList');
    if (list) list.innerHTML = `<div class="empty">Chyba inicializace: ${escapeHtml(err.message)}</div>`;
  }
});

window.addEventListener('load', () => {
  setTimeout(() => connectSSE(() => { loadEmails(); loadStats(); }), 500);
  ['click', 'keydown', 'mousemove', 'touchstart', 'scroll'].forEach(evt => {
    document.addEventListener(evt, () => {
      clearTimeout(window.__activityTimer);
      window.__activityTimer = setTimeout(() => {
        fetch('/api/me', { method: 'HEAD', cache: 'no-store' }).catch(() => {});
      }, 60000);
    }, { passive: true });
  });
});

// Service worker
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js');
}
