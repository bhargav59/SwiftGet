/**
 * SwiftGet Chrome Extension — Service Worker (background.js)
 *
 * Responsibilities:
 * 1. Intercept qualifying downloads and redirect to SwiftGet
 * 2. Monitor declarativeNetRequest rules based on user settings
 * 3. Relay messages from content scripts to the native host
 * 4. Manage extension state via chrome.storage
 */

'use strict';

// ─── Constants ───────────────────────────────────────────────────────────────

const NATIVE_HOST = 'com.swiftget.nativehost';

/** Default file extensions to intercept and send to SwiftGet. */
const DEFAULT_INTERCEPT_EXTENSIONS = [
  'zip', 'tar', 'gz', 'bz2', '7z', 'rar', 'xz', 'iso', 'dmg', 'pkg',
  'mp4', 'm4v', 'mov', 'avi', 'mkv', 'webm', 'flv', 'ts',
  'mp3', 'aac', 'flac', 'wav', 'm4a', 'ogg', 'opus',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub',
  'apk', 'exe', 'msi', 'deb', 'rpm',
];

/** Video hosting platforms where we inject the floating download button. */
const VIDEO_PLATFORMS = [
  'youtube.com', 'youtu.be',
  'vimeo.com',
  'dailymotion.com',
  'twitter.com', 'x.com',
  'instagram.com',
  'facebook.com', 'fb.watch',
  'tiktok.com',
  'reddit.com',
  'twitch.tv',
  'rumble.com',
  'pinterest.com',
  'linkedin.com',
  'bilibili.com',
  'niconico.jp', 'nicovideo.jp',
];

// ─── State ───────────────────────────────────────────────────────────────────

let settings = {
  enabled: true,
  interceptExtensions: DEFAULT_INTERCEPT_EXTENSIONS,
  domainWhitelist: [],
  domainBlacklist: [],
  showFloatingButton: true,
};

// ─── Initialization ──────────────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(async () => {
  const stored = await chrome.storage.sync.get('settings');
  if (stored.settings) {
    settings = { ...settings, ...stored.settings };
  } else {
    await chrome.storage.sync.set({ settings });
  }
  console.log('[SwiftGet] Extension installed / updated. Settings loaded.');
});

chrome.storage.onChanged.addListener((changes) => {
  if (changes.settings) {
    settings = { ...settings, ...changes.settings.newValue };
  }
});

// ─── Download Interception ───────────────────────────────────────────────────

chrome.downloads.onCreated.addListener(async (downloadItem) => {
  if (!settings.enabled) return;
  if (!shouldIntercept(downloadItem)) return;

  // Cancel the Chrome-managed download immediately
  chrome.downloads.cancel(downloadItem.id);
  chrome.downloads.erase({ id: downloadItem.id });

  // Get the referrer from the active tab
  let referrer = '';
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs[0]) referrer = tabs[0].url ?? '';
  } catch (_) {}

  // Get cookies for this URL
  const cookies = await collectCookies(downloadItem.finalUrl ?? downloadItem.url);

  // Send to SwiftGet native host
  await sendToSwiftGet({
    action: 'add',
    url: downloadItem.finalUrl ?? downloadItem.url,
    filename: downloadItem.filename ? downloadItem.filename.split('/').pop() : undefined,
    referrer,
    cookies,
    requestID: String(downloadItem.id),
  });
});

/**
 * Decide whether a download should be intercepted by SwiftGet.
 */
function shouldIntercept(item) {
  const url = item.finalUrl ?? item.url ?? '';

  // Domain blacklist — never intercept
  if (settings.domainBlacklist.some(d => url.includes(d))) return false;

  // Domain whitelist — always intercept if set
  if (settings.domainWhitelist.length > 0) {
    return settings.domainWhitelist.some(d => url.includes(d));
  }

  // Extension-based filtering
  try {
    const urlObj = new URL(url);
    const ext = urlObj.pathname.split('.').pop()?.toLowerCase() ?? '';
    return settings.interceptExtensions.includes(ext);
  } catch (_) {
    return false;
  }
}

// ─── Video Detection ─────────────────────────────────────────────────────────

/**
 * Called by content scripts when they detect a video stream URL.
 */
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'VIDEO_DETECTED') {
    handleVideoDetected(message, sender).then(sendResponse);
    return true; // Keep the message channel open for async response
  }

  if (message.type === 'DOWNLOAD_VIDEO') {
    handleDownloadVideo(message, sender).then(sendResponse);
    return true;
  }

  if (message.type === 'GET_SETTINGS') {
    sendResponse(settings);
  }

  if (message.type === 'PING') {
    pingNativeHost().then(sendResponse);
    return true;
  }
});

async function handleVideoDetected(message, sender) {
  if (!settings.enabled || !settings.showFloatingButton) return { ok: false };
  // Relay to the content script of the same tab to show the UI
  // (already handled client-side; this is a hook for future server-side logic)
  return { ok: true };
}

async function handleDownloadVideo(message, sender) {
  const { url, videoURL, filename, quality, format, cookies } = message;

  let referrer = '';
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs[0]) referrer = tabs[0].url ?? '';
  } catch (_) {}

  const targetURL = videoURL ?? url;
  const pageCookies = cookies ?? await collectCookies(targetURL);

  const result = await sendToSwiftGet({
    action: 'add',
    url: targetURL,
    filename: filename ?? `video.${format ?? 'mp4'}`,
    referrer,
    cookies: pageCookies,
    requestID: `video-${Date.now()}`,
  });

  // Show a notification
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon48.png',
    title: 'SwiftGet',
    message: result ? `Sending to SwiftGet: ${filename ?? url}` : 'Failed to contact SwiftGet.',
  });

  return { ok: result };
}

// ─── Native Messaging ────────────────────────────────────────────────────────

let nativePort = null;

function ensureNativePort() {
  if (nativePort) return nativePort;
  nativePort = chrome.runtime.connectNative(NATIVE_HOST);
  nativePort.onDisconnect.addListener(() => {
    nativePort = null;
    const err = chrome.runtime.lastError;
    if (err) {
      console.warn('[SwiftGet] Native port disconnected:', err.message);
    }
  });
  return nativePort;
}

function sendToSwiftGet(message) {
  return new Promise((resolve) => {
    // Primary path: swiftget:// URL scheme (more reliable for one-shot messages)
    const params = new URLSearchParams();
    if (message.url) params.set('url', message.url);
    if (message.filename) params.set('filename', message.filename);
    if (message.referrer) params.set('referrer', message.referrer);
    if (message.cookies) params.set('cookies', message.cookies);

    const schemeURL = `swiftget://add?${params.toString()}`;

    // Open via a new tab then close it immediately
    chrome.tabs.create({ url: schemeURL, active: false }, (tab) => {
      if (chrome.runtime.lastError) {
        // Fallback: try native messaging
        tryNativeMessaging(message).then(resolve);
        return;
      }
      setTimeout(() => {
        if (tab?.id) chrome.tabs.remove(tab.id).catch(() => {});
      }, 500);
      resolve(true);
    });
  });
}

function tryNativeMessaging(message) {
  return new Promise((resolve) => {
    try {
      const port = ensureNativePort();
      const listener = (response) => {
        port.onMessage.removeListener(listener);
        resolve(response?.success ?? false);
      };
      port.onMessage.addListener(listener);
      port.postMessage(message);
      // Timeout after 3 seconds
      setTimeout(() => resolve(false), 3000);
    } catch (e) {
      resolve(false);
    }
  });
}

async function pingNativeHost() {
  return tryNativeMessaging({ action: 'ping' });
}

// ─── Cookie Collection ───────────────────────────────────────────────────────

async function collectCookies(urlString) {
  try {
    const url = new URL(urlString);
    const cookies = await chrome.cookies.getAll({ domain: url.hostname });
    return cookies.map(c => `${c.name}=${c.value}`).join('; ');
  } catch (_) {
    return '';
  }
}
