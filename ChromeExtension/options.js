const DEFAULT_FILE_TYPES = [
  '.zip', '.tar', '.gz', '.rar', '.7z', '.dmg', '.pkg', '.iso',
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv',
  '.mp3', '.aac', '.flac', '.wav', '.m4a', '.ogg',
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  '.apk', '.exe', '.msi', '.deb', '.rpm'
];

document.addEventListener('DOMContentLoaded', () => {
  // Load settings
  chrome.storage.sync.get({
    interceptEnabled: true,
    autoCapture: false,
    showFloatingBtn: true,
    fileTypeRules: DEFAULT_FILE_TYPES,
    domainBlacklist: [],
    domainWhitelist: [],
    segmentCount: 8
  }, (settings) => {
    document.getElementById('interceptEnabled').checked = settings.interceptEnabled;
    document.getElementById('autoCapture').checked = settings.autoCapture;
    document.getElementById('showFloatingBtn').checked = settings.showFloatingBtn;
    document.getElementById('fileTypes').value = settings.fileTypeRules.join('\n');
    document.getElementById('domainBlacklist').value = settings.domainBlacklist.join('\n');
    document.getElementById('domainWhitelist').value = settings.domainWhitelist.join('\n');
    document.getElementById('segmentCount').value = settings.segmentCount;
  });
  
  document.getElementById('saveBtn').addEventListener('click', () => {
    const fileTypes = document.getElementById('fileTypes').value
      .split('\n').map(s => s.trim()).filter(Boolean);
    const blacklist = document.getElementById('domainBlacklist').value
      .split('\n').map(s => s.trim()).filter(Boolean);
    const whitelist = document.getElementById('domainWhitelist').value
      .split('\n').map(s => s.trim()).filter(Boolean);
    
    const settings = {
      interceptEnabled: document.getElementById('interceptEnabled').checked,
      autoCapture: document.getElementById('autoCapture').checked,
      showFloatingBtn: document.getElementById('showFloatingBtn').checked,
      fileTypeRules: fileTypes.length > 0 ? fileTypes : DEFAULT_FILE_TYPES,
      domainBlacklist: blacklist,
      domainWhitelist: whitelist,
      segmentCount: parseInt(document.getElementById('segmentCount').value, 10) || 8
    };
    
    chrome.storage.sync.set(settings, () => {
      const confirm = document.getElementById('saveConfirm');
      confirm.style.display = 'inline';
      setTimeout(() => { confirm.style.display = 'none'; }, 2000);
    });
  });
});
