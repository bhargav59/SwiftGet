'use strict';

const DEFAULT_EXTENSIONS = [
  'zip','tar','gz','bz2','7z','rar','xz','iso','dmg','pkg',
  'mp4','m4v','mov','avi','mkv','webm','flv','ts',
  'mp3','aac','flac','wav','m4a','ogg','opus',
  'pdf','doc','docx','xls','xlsx','ppt','pptx','epub',
  'apk','exe','msi','deb','rpm',
];

const elEnabled      = document.getElementById('opt-enabled');
const elFloatingBtn  = document.getElementById('opt-floating-btn');
const elExtensions   = document.getElementById('opt-extensions');
const elWhitelist    = document.getElementById('opt-whitelist');
const elBlacklist    = document.getElementById('opt-blacklist');
const saveBtn        = document.getElementById('save-btn');
const saveStatus     = document.getElementById('save-status');

// ─── Load ─────────────────────────────────────────────────────────────────────

(async () => {
  const { settings = {} } = await chrome.storage.sync.get('settings');
  elEnabled.checked     = settings.enabled ?? true;
  elFloatingBtn.checked = settings.showFloatingButton ?? true;
  elExtensions.value    = (settings.interceptExtensions ?? DEFAULT_EXTENSIONS).join(', ');
  elWhitelist.value     = (settings.domainWhitelist ?? []).join('\n');
  elBlacklist.value     = (settings.domainBlacklist ?? []).join('\n');
})();

// ─── Save ─────────────────────────────────────────────────────────────────────

saveBtn.addEventListener('click', async () => {
  const extensionList = elExtensions.value
    .split(/[\s,]+/)
    .map(s => s.trim().toLowerCase().replace(/^\./, ''))
    .filter(Boolean);

  const whitelist = elWhitelist.value
    .split(/[\s,\n]+/)
    .map(s => s.trim())
    .filter(Boolean);

  const blacklist = elBlacklist.value
    .split(/[\s,\n]+/)
    .map(s => s.trim())
    .filter(Boolean);

  const settings = {
    enabled: elEnabled.checked,
    showFloatingButton: elFloatingBtn.checked,
    interceptExtensions: extensionList.length ? extensionList : DEFAULT_EXTENSIONS,
    domainWhitelist: whitelist,
    domainBlacklist: blacklist,
  };

  await chrome.storage.sync.set({ settings });

  // Notify background worker
  const [bgSW] = await chrome.runtime.getBackgroundPage
    ? [chrome.runtime.getBackgroundPage()]
    : [];
  _ = bgSW; // background handles storage.onChanged

  saveStatus.classList.add('visible');
  setTimeout(() => saveStatus.classList.remove('visible'), 2500);
});
