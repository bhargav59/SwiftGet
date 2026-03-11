// SwiftGet Background Service Worker (Manifest V3)
// Intercepts downloads and routes qualifying files to SwiftGet

const NATIVE_HOST = 'com.swiftget.native';
const DEFAULT_FILE_TYPES = [
  '.zip', '.tar', '.gz', '.rar', '.7z', '.dmg', '.pkg', '.iso',
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv',
  '.mp3', '.aac', '.flac', '.wav', '.m4a', '.ogg',
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  '.apk', '.exe', '.msi', '.deb', '.rpm'
];

let nativePort = null;
let interceptEnabled = true;
let fileTypeRules = DEFAULT_FILE_TYPES;
let domainBlacklist = [];
let domainWhitelist = [];

// Initialize settings from storage
chrome.storage.sync.get({
  interceptEnabled: true,
  fileTypeRules: DEFAULT_FILE_TYPES,
  domainBlacklist: [],
  domainWhitelist: [],
  segmentCount: 8
}, (settings) => {
  interceptEnabled = settings.interceptEnabled;
  fileTypeRules = settings.fileTypeRules;
  domainBlacklist = settings.domainBlacklist;
  domainWhitelist = settings.domainWhitelist;
});

// Listen for storage changes
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'sync') return;
  if (changes.interceptEnabled) interceptEnabled = changes.interceptEnabled.newValue;
  if (changes.fileTypeRules) fileTypeRules = changes.fileTypeRules.newValue;
  if (changes.domainBlacklist) domainBlacklist = changes.domainBlacklist.newValue;
  if (changes.domainWhitelist) domainWhitelist = changes.domainWhitelist.newValue;
});

// Intercept downloads
chrome.downloads.onCreated.addListener((downloadItem) => {
  if (!interceptEnabled) return;
  
  const url = downloadItem.url;
  const hostname = new URL(url).hostname;
  
  // Check domain rules
  if (domainBlacklist.some(d => hostname.includes(d))) return;
  if (domainWhitelist.length > 0 && !domainWhitelist.some(d => hostname.includes(d))) return;
  
  // Check file type
  const matchesFileType = fileTypeRules.some(ext => 
    url.toLowerCase().includes(ext) || 
    (downloadItem.filename && downloadItem.filename.toLowerCase().endsWith(ext))
  );
  
  if (!matchesFileType) return;
  
  // Cancel the Chrome download and send to SwiftGet
  chrome.downloads.cancel(downloadItem.id, () => {
    chrome.downloads.erase({ id: downloadItem.id });
    sendToSwiftGet(url, downloadItem.filename || '');
  });
});

// Message handler from content scripts
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message.type) {
    case 'VIDEO_DETECTED':
      handleVideoDetected(message.data, sender.tab);
      sendResponse({ success: true });
      break;
    case 'DOWNLOAD_URL':
      sendToSwiftGet(message.url, message.filename || '');
      sendResponse({ success: true });
      break;
    case 'GET_SETTINGS':
      chrome.storage.sync.get(null, (settings) => sendResponse(settings));
      return true; // Keep message channel open
    case 'PING_NATIVE':
      pingNativeHost().then(result => sendResponse(result));
      return true;
    default:
      break;
  }
});

function sendToSwiftGet(url, filename, cookies = '', headers = {}) {
  const message = {
    action: 'download',
    url: url,
    filename: filename,
    cookies: cookies,
    headers: headers,
    segmentCount: 8
  };
  
  try {
    const port = chrome.runtime.connectNative(NATIVE_HOST);
    port.postMessage(message);
    port.onDisconnect.addListener(() => {
      if (chrome.runtime.lastError) {
        // Native host not available — fallback to URL scheme
        const swiftgetURL = `swiftget://add?url=${encodeURIComponent(url)}`;
        chrome.tabs.create({ url: swiftgetURL });
      }
    });
  } catch (e) {
    // Fallback to custom URL scheme
    const swiftgetURL = `swiftget://add?url=${encodeURIComponent(url)}`;
    chrome.tabs.create({ url: swiftgetURL });
  }
}

async function pingNativeHost() {
  return new Promise((resolve) => {
    try {
      const port = chrome.runtime.connectNative(NATIVE_HOST);
      port.postMessage({ action: 'ping' });
      port.onMessage.addListener((response) => {
        port.disconnect();
        resolve({ connected: true, version: response.version });
      });
      port.onDisconnect.addListener(() => {
        resolve({ connected: false });
      });
      setTimeout(() => {
        port.disconnect();
        resolve({ connected: false });
      }, 3000);
    } catch (e) {
      resolve({ connected: false, error: e.message });
    }
  });
}

function handleVideoDetected(data, tab) {
  if (!interceptEnabled) return;
  
  // Show notification or badge
  chrome.action.setBadgeText({ text: '▶', tabId: tab?.id });
  chrome.action.setBadgeBackgroundColor({ color: '#0070F3', tabId: tab?.id });
  
  // Optionally auto-capture based on settings
  chrome.storage.sync.get({ autoCapture: false }, (settings) => {
    if (settings.autoCapture && data.url) {
      sendToSwiftGet(data.url, data.title || 'video', data.cookies, data.headers);
    }
  });
}
