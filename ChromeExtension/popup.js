// Popup script for SwiftGet Chrome Extension

document.addEventListener('DOMContentLoaded', async () => {
  const urlInput = document.getElementById('urlInput');
  const addBtn = document.getElementById('addBtn');
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const videoList = document.getElementById('videoList');
  const interceptToggle = document.getElementById('interceptToggle');
  const openAppBtn = document.getElementById('openAppBtn');
  
  // Auto-paste from clipboard
  try {
    const text = await navigator.clipboard.readText();
    if (text.startsWith('http')) urlInput.value = text;
  } catch (e) { /* clipboard not available */ }
  
  // Check native host connection
  chrome.runtime.sendMessage({ type: 'PING_NATIVE' }, (result) => {
    if (result?.connected) {
      statusDot.classList.add('connected');
      statusText.textContent = `Connected · SwiftGet v${result.version || '1.0'}`;
    } else {
      statusDot.classList.add('disconnected');
      statusText.textContent = 'SwiftGet app not running';
    }
  });
  
  // Load settings
  chrome.storage.sync.get({ interceptEnabled: true }, (settings) => {
    interceptToggle.checked = settings.interceptEnabled;
  });
  
  // Toggle intercept
  interceptToggle.addEventListener('change', () => {
    chrome.storage.sync.set({ interceptEnabled: interceptToggle.checked });
  });
  
  // Add download
  addBtn.addEventListener('click', () => {
    const url = urlInput.value.trim();
    if (!url || !url.startsWith('http')) return;
    chrome.runtime.sendMessage({ type: 'DOWNLOAD_URL', url, filename: '' });
    addBtn.textContent = 'Added! ✓';
    addBtn.disabled = true;
    setTimeout(() => window.close(), 1000);
  });
  
  urlInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') addBtn.click();
  });
  
  // Get detected videos from content script
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (!tabs[0]) return;
    chrome.tabs.sendMessage(tabs[0].id, { type: 'GET_VIDEO_DATA' }, (response) => {
      if (chrome.runtime.lastError || !response) return;
      
      const streams = response.streams || [];
      if (streams.length > 0) {
        videoList.innerHTML = streams.map(url => {
          const shortUrl = url.length > 60 ? url.substring(0, 57) + '...' : url;
          return `
            <div class="video-item">
              <button class="video-download-btn" onclick="downloadVideo('${url.replace(/'/g, "\\'")}')">↓</button>
              <div class="url">${shortUrl}</div>
            </div>
          `;
        }).join('');
      }
    });
  });
  
  // Open app
  openAppBtn.addEventListener('click', () => {
    chrome.tabs.create({ url: 'swiftget://open' });
  });
});

function downloadVideo(url) {
  chrome.runtime.sendMessage({ type: 'DOWNLOAD_URL', url, filename: 'video' });
  const btn = event.target;
  btn.textContent = '✓';
  btn.disabled = true;
}
