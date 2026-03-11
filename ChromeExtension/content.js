// SwiftGet Content Script
// Detects video streams on supported platforms

(function() {
  'use strict';
  
  const VIDEO_PLATFORMS = {
    youtube: ['youtube.com', 'youtu.be'],
    vimeo: ['vimeo.com'],
    twitter: ['twitter.com', 'x.com'],
    instagram: ['instagram.com'],
    facebook: ['facebook.com', 'fb.com'],
    tiktok: ['tiktok.com'],
    dailymotion: ['dailymotion.com'],
    twitch: ['twitch.tv'],
    reddit: ['reddit.com'],
    vimeo2: ['vimeo.com'],
    rumble: ['rumble.com']
  };
  
  const hostname = window.location.hostname;
  let detectedStreams = new Set();
  let floatingButton = null;
  let lastVideoData = null;
  
  // Intercept XHR requests for video streams
  const originalXHROpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...args) {
    monitorURL(url);
    return originalXHROpen.apply(this, [method, url, ...args]);
  };
  
  // Intercept Fetch requests
  const originalFetch = window.fetch;
  window.fetch = function(input, init) {
    const url = typeof input === 'string' ? input : input.url;
    monitorURL(url);
    return originalFetch.apply(this, [input, init]);
  };
  
  function monitorURL(url) {
    if (!url || typeof url !== 'string') return;
    
    const isVideoStream = 
      url.includes('.m3u8') || 
      url.includes('.mpd') || 
      url.includes('manifest') ||
      url.includes('video') && (url.includes('.mp4') || url.includes('.webm')) ||
      url.includes('googlevideo.com') || // YouTube
      url.includes('fbcdn.net') ||       // Facebook
      url.includes('cdninstagram.com');   // Instagram
    
    if (isVideoStream && !detectedStreams.has(url)) {
      detectedStreams.add(url);
      notifyVideoDetected(url);
    }
  }
  
  function notifyVideoDetected(streamURL) {
    // Get page title and cookies
    const title = document.title;
    const cookies = document.cookie;
    
    lastVideoData = { url: streamURL, title, cookies };
    
    chrome.runtime.sendMessage({
      type: 'VIDEO_DETECTED',
      data: { url: streamURL, title, cookies, hostname }
    });
    
    showFloatingButton();
  }
  
  function showFloatingButton() {
    if (floatingButton) return; // Already shown
    
    floatingButton = document.createElement('div');
    floatingButton.id = 'swiftget-download-btn';
    floatingButton.innerHTML = `
      <div style="
        position: fixed;
        bottom: 20px;
        right: 20px;
        z-index: 2147483647;
        background: #0070F3;
        color: white;
        border-radius: 24px;
        padding: 10px 18px;
        font-family: -apple-system, sans-serif;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        box-shadow: 0 4px 20px rgba(0,112,243,0.4);
        display: flex;
        align-items: center;
        gap: 8px;
        user-select: none;
        transition: transform 0.2s, box-shadow 0.2s;
      " onmouseover="this.style.transform='scale(1.05)';this.style.boxShadow='0 6px 24px rgba(0,112,243,0.5)'"
         onmouseout="this.style.transform='scale(1)';this.style.boxShadow='0 4px 20px rgba(0,112,243,0.4)'"
         id="swiftget-btn-inner">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <path d="M12 2v14M6 10l6 6 6-6"/><path d="M4 20h16"/>
        </svg>
        Download with SwiftGet
        <span id="swiftget-close" style="margin-left:4px;opacity:0.7;font-size:16px">×</span>
      </div>
    `;
    
    document.body.appendChild(floatingButton);
    
    document.getElementById('swiftget-btn-inner').addEventListener('click', (e) => {
      if (e.target.id === 'swiftget-close') {
        floatingButton.remove();
        floatingButton = null;
        return;
      }
      if (lastVideoData) {
        chrome.runtime.sendMessage({
          type: 'DOWNLOAD_URL',
          url: lastVideoData.url,
          filename: lastVideoData.title || 'video'
        });
      }
    });
    
    // Auto-dismiss after 8 seconds
    setTimeout(() => {
      if (floatingButton) {
        floatingButton.style.opacity = '0';
        floatingButton.style.transition = 'opacity 0.5s';
        setTimeout(() => { floatingButton?.remove(); floatingButton = null; }, 500);
      }
    }, 8000);
  }
  
  // Also watch for video elements added to the page
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeName === 'VIDEO' || (node.querySelectorAll && node.querySelectorAll('video').length)) {
          const videos = node.nodeName === 'VIDEO' ? [node] : [...node.querySelectorAll('video')];
          for (const video of videos) {
            if (video.src && !detectedStreams.has(video.src)) {
              detectedStreams.add(video.src);
              notifyVideoDetected(video.src);
            }
          }
        }
      }
    }
  });
  
  observer.observe(document.documentElement, { childList: true, subtree: true });
  
  // Listen for messages from popup
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'GET_VIDEO_DATA') {
      sendResponse({ streams: [...detectedStreams], lastVideo: lastVideoData });
    }
    if (message.type === 'DOWNLOAD_CURRENT_VIDEO') {
      if (lastVideoData) {
        chrome.runtime.sendMessage({
          type: 'DOWNLOAD_URL',
          url: lastVideoData.url,
          filename: lastVideoData.title || 'video'
        });
        sendResponse({ success: true });
      } else {
        sendResponse({ success: false, error: 'No video detected' });
      }
    }
  });
})();
