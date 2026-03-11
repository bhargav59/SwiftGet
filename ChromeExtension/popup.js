'use strict';

const NATIVE_HOST = 'com.swiftget.nativehost';

// ─── DOM References ───────────────────────────────────────────────────────────

const urlInput     = document.getElementById('url-input');
const addBtn       = document.getElementById('add-btn');
const urlError     = document.getElementById('url-error');
const enabledToggle = document.getElementById('enabled-toggle');
const statusDot    = document.getElementById('status-dot');
const downloadsList = document.getElementById('downloads-list');
const settingsBtn  = document.getElementById('settings-btn');
const optionsLink  = document.getElementById('options-link');
const openAppLink  = document.getElementById('open-app-link');

// ─── Init ─────────────────────────────────────────────────────────────────────

(async () => {
  // Load settings
  const { settings } = await chrome.storage.sync.get('settings');
  if (settings) {
    enabledToggle.checked = settings.enabled ?? true;
  }

  // Check native host connectivity
  const connected = await pingNativeHost();
  statusDot.classList.toggle('connected', connected);
  statusDot.title = connected ? 'Connected to SwiftGet' : 'SwiftGet not running';

  // Auto-fill URL from active tab
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab?.url && !tab.url.startsWith('chrome://')) {
      urlInput.value = tab.url;
    }
  } catch (_) {}

  // Load active downloads (future: query native host)
  renderDownloads([]);
})();

// ─── Event Listeners ──────────────────────────────────────────────────────────

addBtn.addEventListener('click', () => addDownload());
urlInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') addDownload(); });

enabledToggle.addEventListener('change', async () => {
  const { settings = {} } = await chrome.storage.sync.get('settings');
  settings.enabled = enabledToggle.checked;
  await chrome.storage.sync.set({ settings });
});

settingsBtn.addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
  window.close();
});

optionsLink.addEventListener('click', (e) => {
  e.preventDefault();
  chrome.runtime.openOptionsPage();
  window.close();
});

openAppLink.addEventListener('click', (e) => {
  e.preventDefault();
  chrome.tabs.create({ url: 'swiftget://open', active: false });
  window.close();
});

// ─── Add Download ─────────────────────────────────────────────────────────────

async function addDownload() {
  const urlStr = urlInput.value.trim();
  urlError.style.display = 'none';

  if (!urlStr) {
    showError('Please enter a URL.');
    return;
  }

  let url;
  try {
    url = new URL(urlStr.startsWith('http') ? urlStr : 'https://' + urlStr);
  } catch (_) {
    showError('Invalid URL. Please enter a valid web address.');
    return;
  }

  addBtn.disabled = true;
  addBtn.textContent = '…';

  const params = new URLSearchParams({ url: url.href });
  const schemeURL = `swiftget://add?${params.toString()}`;

  chrome.tabs.create({ url: schemeURL, active: false }, (tab) => {
    setTimeout(() => {
      if (tab?.id) chrome.tabs.remove(tab.id).catch(() => {});
    }, 600);
    addBtn.disabled = false;
    addBtn.textContent = '✓';
    setTimeout(() => {
      addBtn.textContent = 'Add';
    }, 1500);
  });
}

function showError(msg) {
  urlError.textContent = msg;
  urlError.style.display = 'block';
}

// ─── Downloads Rendering ──────────────────────────────────────────────────────

function renderDownloads(downloads) {
  downloadsList.replaceChildren();

  if (!downloads || downloads.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty-state';
    empty.textContent = 'No active downloads';
    downloadsList.appendChild(empty);
    return;
  }

  for (const dl of downloads) {
    const item = document.createElement('div');
    item.className = 'dl-item';

    const name = document.createElement('div');
    name.className = 'dl-name';
    name.textContent = dl.filename ?? '';
    item.appendChild(name);

    const progressWrap = document.createElement('div');
    progressWrap.className = 'dl-progress';
    const progressFill = document.createElement('div');
    progressFill.className = 'dl-progress-fill';
    progressFill.style.width = `${Math.round((dl.progress ?? 0) * 100)}%`;
    progressWrap.appendChild(progressFill);
    item.appendChild(progressWrap);

    const meta = document.createElement('div');
    meta.className = 'dl-meta';
    const statusSpan = document.createElement('span');
    statusSpan.textContent = formatStatus(dl.status);
    const speedSpan = document.createElement('span');
    speedSpan.textContent = dl.speed > 0 ? formatBytes(dl.speed) + '/s' : '';
    meta.appendChild(statusSpan);
    meta.appendChild(speedSpan);
    item.appendChild(meta);

    downloadsList.appendChild(item);
  }
}

// ─── Native Messaging ─────────────────────────────────────────────────────────

function pingNativeHost() {
  return new Promise((resolve) => {
    try {
      const port = chrome.runtime.connectNative(NATIVE_HOST);
      let resolved = false;
      port.onMessage.addListener(() => {
        resolved = true;
        port.disconnect();
        resolve(true);
      });
      port.onDisconnect.addListener(() => {
        if (!resolved) resolve(false);
      });
      port.postMessage({ action: 'ping' });
      setTimeout(() => { if (!resolved) { port.disconnect(); resolve(false); } }, 2000);
    } catch (_) {
      resolve(false);
    }
  });
}

// ─── Utilities ────────────────────────────────────────────────────────────────

function formatBytes(bytes) {
  if (bytes >= 1_048_576) return (bytes / 1_048_576).toFixed(1) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return bytes + ' B';
}

function formatStatus(status) {
  const map = {
    downloading: '⬇ Downloading',
    paused: '⏸ Paused',
    completed: '✓ Complete',
    failed: '✗ Failed',
    queued: '⏳ Queued',
  };
  return map[status] ?? status;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
