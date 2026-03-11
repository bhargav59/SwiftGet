/**
 * SwiftGet Chrome Extension — Content Script (content.js)
 *
 * Responsibilities:
 * 1. Monitor XHR / Fetch network activity to detect video stream URLs
 * 2. Inject a floating "Download with SwiftGet" button on supported video pages
 * 3. Present a quality-selection UI overlay when multiple streams are found
 */

'use strict';

// ─── Constants ───────────────────────────────────────────────────────────────

const VIDEO_URL_PATTERNS = [
  /\.(mp4|m4v|mov|webm|avi|flv|ts|mkv)(\?|$)/i,
  /\.m3u8(\?|$)/i,
  /\.mpd(\?|$)/i,
  /\/videoplayback\?/,
  /\/manifest\//,
  /googlevideo\.com\/videoplayback/,
  /akamaized\.net\/.*\.(m3u8|mp4)/i,
  /cloudfront\.net\/.*\.(m3u8|mp4)/i,
];

const SUPPORTED_HOSTS = [
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
];

// ─── State ───────────────────────────────────────────────────────────────────

let detectedStreams = new Map(); // url → {quality, ext, mimeType}
let floatingButton = null;
let settingsCache = null;

// ─── Initialization ──────────────────────────────────────────────────────────

(async () => {
  settingsCache = await chrome.runtime.sendMessage({ type: 'GET_SETTINGS' });
  if (!settingsCache?.enabled) return;

  if (isVideoPage()) {
    interceptNetworkRequests();
    setTimeout(injectFloatingButton, 1500);
  }
})();

function isVideoPage() {
  return SUPPORTED_HOSTS.some(host => location.hostname.endsWith(host));
}

// ─── Network Interception ────────────────────────────────────────────────────

/**
 * Monkey-patch XHR and Fetch to observe URLs being requested by the page.
 * This lets us capture video stream URLs as the page loads them.
 */
function interceptNetworkRequests() {
  // ── XHR ──
  const OrigXHR = window.XMLHttpRequest;
  class HookedXHR extends OrigXHR {
    open(method, url, ...args) {
      if (typeof url === 'string' && isVideoURL(url)) {
        registerStream(url, null);
      }
      super.open(method, url, ...args);
    }
  }
  window.XMLHttpRequest = HookedXHR;

  // ── Fetch ──
  const origFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input?.url;
    if (url && isVideoURL(url)) {
      registerStream(url, null);
    }
    return origFetch(input, init);
  };

  // ── Service Worker / postMessage ──
  // Listen for messages the page sends to itself (e.g., YouTube player)
  window.addEventListener('message', (e) => {
    if (!e.data) return;
    const data = typeof e.data === 'string' ? e.data : JSON.stringify(e.data);
    extractVideoURLsFromText(data);
  });
}

function isVideoURL(url) {
  return VIDEO_URL_PATTERNS.some(re => re.test(url));
}

function extractVideoURLsFromText(text) {
  // Quick scan for .m3u8 and videoplayback URLs in arbitrary JSON/text blobs
  const m3u8Matches = text.match(/https?:\/\/[^\s"']+\.m3u8[^\s"']*/g) ?? [];
  const vbMatches = text.match(/https?:\/\/[^\s"']*videoplayback[^\s"']*/g) ?? [];
  [...m3u8Matches, ...vbMatches].forEach(url => registerStream(url, null));
}

function registerStream(url, quality) {
  if (detectedStreams.has(url)) return;
  const cleanURL = url.split('?')[0];
  const ext = cleanURL.split('.').pop()?.toLowerCase() ?? 'mp4';
  detectedStreams.set(url, { quality: quality ?? inferQuality(url), ext });

  // Update floating button badge
  updateFloatingButtonBadge();

  // Notify background
  chrome.runtime.sendMessage({ type: 'VIDEO_DETECTED', url, quality, ext });
}

function inferQuality(url) {
  const lower = url.toLowerCase();
  if (lower.includes('1080') || lower.includes('fhd')) return '1080p';
  if (lower.includes('720') || lower.includes('hd')) return '720p';
  if (lower.includes('480')) return '480p';
  if (lower.includes('360')) return '360p';
  if (lower.includes('240')) return '240p';
  if (lower.includes('.m3u8') || lower.includes('.mpd')) return 'HLS/DASH';
  return 'Video';
}

// ─── Floating Download Button ─────────────────────────────────────────────────

function injectFloatingButton() {
  if (!settingsCache?.showFloatingButton) return;
  if (floatingButton) return;

  floatingButton = document.createElement('div');
  floatingButton.id = 'swiftget-fab';
  floatingButton.innerHTML = `
    <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
      <path d="M10 2a1 1 0 011 1v9.586l2.293-2.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V3a1 1 0 011-1z"/>
      <path d="M3 16a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z"/>
    </svg>
    <span id="swiftget-fab-label">SwiftGet</span>
    <span id="swiftget-fab-badge" style="display:none">0</span>
  `;

  const style = document.createElement('style');
  style.textContent = `
    #swiftget-fab {
      position: fixed;
      bottom: 80px;
      right: 20px;
      z-index: 2147483647;
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 10px 16px;
      background: linear-gradient(135deg, #0066ff, #0044cc);
      color: white;
      border-radius: 50px;
      cursor: pointer;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 13px;
      font-weight: 600;
      box-shadow: 0 4px 16px rgba(0, 102, 255, 0.4);
      transition: transform 0.15s ease, box-shadow 0.15s ease, opacity 0.2s ease;
      user-select: none;
    }
    #swiftget-fab:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0, 102, 255, 0.5);
    }
    #swiftget-fab:active {
      transform: scale(0.97);
    }
    #swiftget-fab-badge {
      background: #ff3b30;
      color: white;
      border-radius: 50%;
      width: 18px;
      height: 18px;
      display: flex !important;
      align-items: center;
      justify-content: center;
      font-size: 10px;
      font-weight: 700;
      margin-left: 2px;
    }
    #swiftget-quality-panel {
      position: fixed;
      bottom: 140px;
      right: 20px;
      z-index: 2147483647;
      background: white;
      border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.18);
      padding: 12px;
      min-width: 220px;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 13px;
      border: 1px solid rgba(0,0,0,0.08);
    }
    #swiftget-quality-panel h4 {
      margin: 0 0 10px;
      font-size: 14px;
      font-weight: 600;
      color: #1a1a1a;
    }
    .swiftget-format-btn {
      display: block;
      width: 100%;
      padding: 8px 12px;
      margin-bottom: 6px;
      background: #f5f5f7;
      border: none;
      border-radius: 8px;
      cursor: pointer;
      text-align: left;
      font-size: 13px;
      transition: background 0.1s;
    }
    .swiftget-format-btn:hover { background: #e8e8ed; }
    .swiftget-format-btn:last-child { margin-bottom: 0; }
  `;
  document.head.appendChild(style);

  floatingButton.addEventListener('click', () => {
    if (detectedStreams.size === 0) {
      // No streams yet — use page URL and let yt-dlp handle it
      downloadCurrentPage('best');
    } else if (detectedStreams.size === 1) {
      const [url, info] = [...detectedStreams.entries()][0];
      downloadStream(url, info);
    } else {
      showQualityPanel();
    }
  });

  document.body.appendChild(floatingButton);
}

function updateFloatingButtonBadge() {
  if (!floatingButton) return;
  const badge = floatingButton.querySelector('#swiftget-fab-badge');
  if (!badge) return;
  const count = detectedStreams.size;
  badge.textContent = String(count);
  badge.style.display = count > 0 ? 'flex' : 'none';
}

function showQualityPanel() {
  // Remove existing panel
  document.getElementById('swiftget-quality-panel')?.remove();

  const panel = document.createElement('div');
  panel.id = 'swiftget-quality-panel';
  panel.innerHTML = `<h4>Select Quality</h4>`;

  // Add "Best (auto)" option
  const autoBtn = document.createElement('button');
  autoBtn.className = 'swiftget-format-btn';
  autoBtn.textContent = '▶ Best Quality (auto)';
  autoBtn.addEventListener('click', () => {
    downloadCurrentPage('best');
    panel.remove();
  });
  panel.appendChild(autoBtn);

  // Add each detected stream
  [...detectedStreams.entries()].forEach(([url, info]) => {
    const btn = document.createElement('button');
    btn.className = 'swiftget-format-btn';
    btn.textContent = `${info.quality} · ${info.ext.toUpperCase()}`;
    btn.addEventListener('click', () => {
      downloadStream(url, info);
      panel.remove();
    });
    panel.appendChild(btn);
  });

  document.body.appendChild(panel);

  // Close on outside click
  setTimeout(() => {
    document.addEventListener('click', (e) => {
      if (!panel.contains(e.target) && e.target !== floatingButton) {
        panel.remove();
      }
    }, { once: true });
  }, 0);
}

function downloadCurrentPage(quality) {
  const title = document.title ?? '';
  const filename = sanitizeFilename(title) + '.mp4';
  chrome.runtime.sendMessage({
    type: 'DOWNLOAD_VIDEO',
    url: location.href,
    filename,
    quality,
    format: 'mp4',
  });
}

function downloadStream(url, info) {
  const title = document.title ?? '';
  const filename = sanitizeFilename(title) + '.' + info.ext;
  chrome.runtime.sendMessage({
    type: 'DOWNLOAD_VIDEO',
    url: location.href,
    videoURL: url,
    filename,
    quality: info.quality,
    format: info.ext,
  });
}

function sanitizeFilename(name) {
  return name.replace(/[<>:"/\\|?*\x00-\x1f]/g, '').trim().slice(0, 128) || 'video';
}
