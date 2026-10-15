/**
 * Wireless ADB Manager - Interactive Client Logic
 * Real-time SSE synchronization, accessible tab navigation, QR code generation,
 * device inspection, shell runner, and screenshot viewer.
 */

let activeQrInstance = null;
let currentShellDevice = null;
let currentScreenshotDevice = null;
let eventSource = null;

// Sound feedback helper using Web Audio API (Accessible audible indicators)
function playFeedbackTone(type = 'success') {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);

    if (type === 'success') {
      osc.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
      osc.frequency.setValueAtTime(880, ctx.currentTime + 0.1); // A5
      gain.gain.setValueAtTime(0.1, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.35);
      osc.start();
      osc.stop(ctx.currentTime + 0.35);
    } else if (type === 'error') {
      osc.frequency.setValueAtTime(300, ctx.currentTime);
      osc.frequency.setValueAtTime(200, ctx.currentTime + 0.1);
      gain.gain.setValueAtTime(0.12, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.3);
      osc.start();
      osc.stop(ctx.currentTime + 0.3);
    }
  } catch (e) {
    // Audio might be blocked until user interaction
  }
}

// Toast Notifications
function showToast(message, type = 'info') {
  const container = document.getElementById('toastContainer');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.setAttribute('role', 'alert');
  toast.innerHTML = `
    <span class="toast-icon">${type === 'success' ? '✓' : type === 'error' ? '✕' : 'ℹ'}</span>
    <span class="toast-msg">${escapeHtml(message)}</span>
  `;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => toast.remove(), 250);
  }, 4000);
}

function escapeHtml(text) {
  if (!text) return '';
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Initialize Real-time Server-Sent Events (SSE)
function initEventSource() {
  if (eventSource) eventSource.close();

  eventSource = new EventSource('/api/events');

  eventSource.addEventListener('init', (e) => {
    try {
      const data = JSON.parse(e.data);
      if (data.devices) renderDevices(data.devices);
      if (data.discovered) renderDiscovered(data.discovered);
      if (data.qr) updateQrUI(data.qr);
    } catch (err) {
      console.error('SSE init error:', err);
    }
  });

  eventSource.addEventListener('devices', (e) => {
    try {
      const devices = JSON.parse(e.data);
      renderDevices(devices);
    } catch (err) {
      console.error('SSE devices error:', err);
    }
  });

  eventSource.addEventListener('discovered', (e) => {
    try {
      const services = JSON.parse(e.data);
      renderDiscovered(services);
    } catch (err) {
      console.error('SSE discovered error:', err);
    }
  });

  eventSource.addEventListener('qr_status', (e) => {
    try {
      const session = JSON.parse(e.data);
      updateQrUI(session);
    } catch (err) {
      console.error('SSE qr_status error:', err);
    }
  });

  eventSource.onerror = () => {
    document.getElementById('adbStatusBadge').innerHTML = `
      <span class="indicator-dot" style="background: #f59e0b"></span>
      <span>Connecting...</span>
    `;
  };

  eventSource.onopen = () => {
    document.getElementById('adbStatusBadge').innerHTML = `
      <span class="indicator-dot green"></span>
      <span>ADB Ready</span>
    `;
  };
}

// QR Code Session Management
async function fetchOrNewQrSession(forceNew = false) {
  try {
    const res = await fetch('/api/qr_session', {
      method: forceNew ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json' }
    });
    const session = await res.json();
    if (session && session.qr_payload) {
      updateQrUI(session);
    } else if (!forceNew) {
      // Trigger new session
      fetchOrNewQrSession(true);
    }
  } catch (err) {
    showToast('Failed to load QR pairing session', 'error');
  }
}

function updateQrUI(session) {
  if (!session || !session.qr_payload) return;

  const targetBox = document.getElementById('qrCodeTarget');
  const codeEl = document.getElementById('qrPairingCode');
  const serviceEl = document.getElementById('qrServiceName');
  const statusBox = document.getElementById('qrStatusBox');
  const statusHeading = document.getElementById('qrStatusHeading');
  const statusDetail = document.getElementById('qrStatusDetail');
  const spinner = document.getElementById('qrSpinner');

  codeEl.textContent = session.pairing_code || '------';
  serviceEl.textContent = session.service_name || '...';

  // Render QR Code if changed
  if (targetBox.dataset.payload !== session.qr_payload) {
    targetBox.innerHTML = '';
    targetBox.dataset.payload = session.qr_payload;
    if (window.QRCode) {
      activeQrInstance = new window.QRCode(targetBox, {
        text: session.qr_payload,
        width: 220,
        height: 220,
        colorDark: '#090D16',
        colorLight: '#FFFFFF',
        correctLevel: window.QRCode.CorrectLevel.M
      });
    }
  }

  // Update Status styles & message
  const status = session.status || 'waiting';
  statusBox.className = `qr-status-box ${status}`;

  if (status === 'waiting') {
    spinner.style.display = 'block';
    statusHeading.textContent = 'Listening for Phone Scan...';
    statusDetail.textContent = session.message || 'Point your Android camera at the QR code';
  } else if (status === 'detected') {
    spinner.style.display = 'block';
    statusHeading.textContent = 'Phone Detected!';
    statusDetail.textContent = session.message || 'Exchanging TLS credentials...';
  } else if (status === 'paired') {
    spinner.style.display = 'block';
    statusHeading.textContent = 'Pairing Successful!';
    statusDetail.textContent = session.message || 'Establishing wireless connection...';
  } else if (status === 'connected') {
    spinner.style.display = 'none';
    statusHeading.textContent = 'Connected Wirelessly! 🎉';
    statusDetail.textContent = session.message || `Device connected at ${session.device}`;
    playFeedbackTone('success');
    showToast(`Device ${session.device || ''} connected wirelessly!`, 'success');
  } else if (status === 'error') {
    spinner.style.display = 'none';
    statusHeading.textContent = 'Pairing Issue';
    statusDetail.textContent = session.message || 'Check IP or retry pairing.';
    playFeedbackTone('error');
    showToast(session.message || 'Pairing error', 'error');
  }
}

// Render Active Devices
function renderDevices(devices = []) {
  const container = document.getElementById('deviceList');
  const countEl = document.getElementById('deviceCount');
  const usbSelect = document.getElementById('selectUsbDevice');

  countEl.textContent = devices.length;

  // Update USB selector
  const usbDevices = devices.filter(d => !d.is_wireless);
  usbSelect.innerHTML = usbDevices.length > 0
    ? usbDevices.map(d => `<option value="${escapeHtml(d.serial)}">${escapeHtml(d.model)} (${escapeHtml(d.serial)})</option>`).join('')
    : '<option value="">No USB devices detected</option>';

  if (devices.length === 0) {
    container.innerHTML = `
      <div class="empty-device-state">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/><path d="M1 1l22 22"/></svg>
        <p>No devices currently connected wirelessly</p>
        <span class="hint-text">Pair your phone using QR code or manual code below to start debugging.</span>
      </div>
    `;
    return;
  }

  container.innerHTML = devices.map(d => `
    <article class="device-card" aria-label="Device ${escapeHtml(d.model)}">
      <div class="device-card-header">
        <div>
          <h3 class="device-model">${escapeHtml(d.model)}</h3>
          <span class="device-serial">${escapeHtml(d.serial)}</span>
        </div>
        <div class="device-badges">
          <span class="badge ${d.is_wireless ? 'badge-wifi' : 'badge-usb'}">
            ${d.is_wireless ? 'Wi-Fi' : 'USB'}
          </span>
        </div>
      </div>

      <div class="device-details-grid">
        <div class="detail-item">
          <span class="detail-label">Status</span>
          <span class="detail-value" style="color: ${d.status === 'device' ? 'var(--accent-android)' : 'var(--accent-warning)'}">${escapeHtml(d.status)}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Wi-Fi IP</span>
          <span class="detail-value">${escapeHtml(d.ip || 'Unknown')}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Android OS</span>
          <span class="detail-value">${escapeHtml(d.version ? `v${d.version}` : 'N/A')}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Battery</span>
          <span class="detail-value">${escapeHtml(d.battery ? `${d.battery}%` : 'N/A')}</span>
        </div>
      </div>

      <div class="device-actions">
        <button class="btn btn-primary btn-sm" onclick="openScrcpyModal('${escapeHtml(d.serial)}', 'screen')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
          Mirror
        </button>
        <button class="btn btn-secondary btn-sm" onclick="openScrcpyModal('${escapeHtml(d.serial)}', 'camera')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>
          Camera
        </button>
        <button class="btn btn-secondary btn-sm" onclick="openFileExplorer('${escapeHtml(d.serial)}', '${escapeHtml(d.model)}')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
          Files
        </button>
        <button class="btn btn-secondary btn-sm" onclick="openScreenshotModal('${escapeHtml(d.serial)}')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
          Screenshot
        </button>
        <button class="btn btn-secondary btn-sm" onclick="openShellModal('${escapeHtml(d.serial)}')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
          Shell
        </button>
        ${d.is_wireless ? `
          <button class="btn btn-danger btn-sm" onclick="disconnectDevice('${escapeHtml(d.serial)}')">
            Disconnect
          </button>
        ` : ''}
      </div>
    </article>
  `).join('');
}

// Render Discovered mDNS Services
function renderDiscovered(services = []) {
  const tbody = document.getElementById('discoveredTableBody');
  const badge = document.getElementById('discoveredBadge');
  badge.textContent = services.length;

  if (services.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted" style="padding: 24px;">No active mDNS services broadcasting currently.</td></tr>`;
    return;
  }

  tbody.innerHTML = services.map(s => {
    const isPairing = s.type === '_adb-tls-pairing._tcp';
    return `
      <tr>
        <td><strong>${escapeHtml(s.name)}</strong></td>
        <td>
          <span class="badge ${isPairing ? 'badge-wifi' : 'badge-usb'}">
            ${escapeHtml(s.type)}
          </span>
        </td>
        <td><code>${escapeHtml(s.address)}</code></td>
        <td>
          ${isPairing ? `
            <button class="btn btn-secondary btn-sm" onclick="prefillManualPair('${escapeHtml(s.host)}', '${escapeHtml(s.port)}')">
              Pair with this
            </button>
          ` : `
            <button class="btn btn-primary btn-sm" onclick="directConnectTarget('${escapeHtml(s.host)}', '${escapeHtml(s.port)}')">
              Connect
            </button>
          `}
        </td>
      </tr>
    `;
  }).join('');
}

// Manual Pair Form Handler
async function handleManualPair(e) {
  e.preventDefault();
  const host = document.getElementById('inputHost').value.trim();
  const port = document.getElementById('inputPairPort').value.trim();
  const code = document.getElementById('inputPairCode').value.trim();
  const connectPort = document.getElementById('inputConnectPort').value.trim();
  const statusBox = document.getElementById('manualPairStatus');
  const btnSubmit = document.getElementById('btnSubmitPair');

  btnSubmit.disabled = true;
  btnSubmit.innerHTML = `<span class="spinner-small"></span> Pairing...`;
  statusBox.hidden = false;
  statusBox.className = 'result-banner';
  statusBox.textContent = `Pairing with ${host}:${port}...`;

  try {
    const res = await fetch('/api/pair_manual', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ host, port, code, connect_port: connectPort })
    });
    const data = await res.json();

    if (res.ok && data.ok) {
      statusBox.className = 'result-banner success';
      statusBox.innerHTML = `<strong>Success!</strong> ${escapeHtml(data.message)} ${data.connect_result ? `<br>Connect result: ${escapeHtml(data.connect_result)}` : ''}`;
      playFeedbackTone('success');
      showToast('Device successfully paired!', 'success');
      document.getElementById('formManualPair').reset();
    } else {
      statusBox.className = 'result-banner error';
      statusBox.innerHTML = `<strong>Pairing Failed:</strong> ${escapeHtml(data.error || 'Check IP, port, and code on phone screen')}`;
      playFeedbackTone('error');
    }
  } catch (err) {
    statusBox.className = 'result-banner error';
    statusBox.textContent = `Network error: ${err.message}`;
  } finally {
    btnSubmit.disabled = false;
    btnSubmit.innerHTML = `
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
      Pair & Connect Device
    `;
  }
}

// Prefill Manual Pair from Discovered Table
function prefillManualPair(host, port) {
  switchTab('tabBtnCode', 'tabPanelCode');
  document.getElementById('inputHost').value = host;
  document.getElementById('inputPairPort').value = port;
  document.getElementById('inputPairCode').focus();
  showToast(`Pre-filled IP and pairing port for ${host}`, 'info');
}

// Direct Connect Target
async function directConnectTarget(host, port) {
  showToast(`Connecting to ${host}:${port}...`, 'info');
  try {
    const res = await fetch('/api/connect', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ host, port })
    });
    const data = await res.json();
    const isSuccess = res.ok && data.ok && !/failed|cannot|unable|refused|error|fault|timed out/i.test(data.message || '');
    if (isSuccess) {
      showToast(data.message || `Connected to ${host}:${port}`, 'success');
      playFeedbackTone('success');
      loadDevices();
    } else {
      const errMsg = data.error || data.message || `Failed to connect to ${host}:${port}`;
      showToast(errMsg, 'error');
      playFeedbackTone('error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
    playFeedbackTone('error');
  }
}

// Disconnect Device
async function disconnectDevice(device) {
  if (!confirm(`Disconnect wireless device ${device}?`)) return;
  try {
    const res = await fetch('/api/disconnect', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device })
    });
    const data = await res.json();
    showToast(data.message || `Disconnected ${device}`, 'info');
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

// Disconnect All Devices
async function disconnectAllDevices() {
  if (!confirm('Disconnect all wireless ADB devices?')) return;
  try {
    const res = await fetch('/api/disconnect_all', { method: 'POST' });
    const data = await res.json();
    showToast(data.message || 'All devices disconnected', 'info');
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
}

// Restart ADB Server
async function restartAdbServer() {
  const btn = document.getElementById('btnRestartAdb');
  btn.disabled = true;
  showToast('Restarting ADB server...', 'info');
  try {
    await fetch('/api/restart_adb', { method: 'POST' });
    showToast('ADB server restarted successfully', 'success');
    playFeedbackTone('success');
  } catch (err) {
    showToast('Failed to restart ADB', 'error');
  } finally {
    btn.disabled = false;
  }
}

// Switch USB to Wireless
async function handleSwitchUsbToWifi() {
  const select = document.getElementById('selectUsbDevice');
  const serial = select.value;
  if (!serial) {
    showToast('Please select a connected USB device', 'error');
    return;
  }

  const btn = document.getElementById('btnSwitchUsbToWifi');
  btn.disabled = true;
  btn.innerHTML = `<span class="spinner-small"></span> Switching to wireless...`;
  showToast('Enabling TCP/IP 5555 and retrieving Wi-Fi IP...', 'info');

  try {
    const res = await fetch('/api/usb_to_wireless', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ serial })
    });
    const data = await res.json();
    if (res.ok && data.ok) {
      showToast(data.message || 'Switched to wireless! You can unplug USB cable now.', 'success');
      playFeedbackTone('success');
    } else {
      showToast(data.error || 'Failed to switch to wireless', 'error');
      playFeedbackTone('error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = `
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12.55a11 11 0 0 1 14.08 0M1.42 9a16 16 0 0 1 21.16 0M8.53 16.11a6 6 0 0 1 6.95 0M12 20h.01"/></svg>
      Switch to Wireless Mode
    `;
  }
}

// Accessible Tab Navigation
function setupTabs() {
  const tabBtns = document.querySelectorAll('.tab-btn');
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetPanelId = btn.getAttribute('aria-controls');
      switchTab(btn.id, targetPanelId);
    });

    btn.addEventListener('keydown', (e) => {
      let targetBtn = null;
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
        targetBtn = btn.nextElementSibling || tabBtns[0];
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
        targetBtn = btn.previousElementSibling || tabBtns[tabBtns.length - 1];
      }
      if (targetBtn) {
        targetBtn.focus();
        switchTab(targetBtn.id, targetBtn.getAttribute('aria-controls'));
      }
    });
  });
}

function switchTab(btnId, panelId) {
  document.querySelectorAll('.tab-btn').forEach(b => {
    const isActive = b.id === btnId;
    b.classList.toggle('active', isActive);
    b.setAttribute('aria-selected', isActive ? 'true' : 'false');
    b.setAttribute('tabindex', isActive ? '0' : '-1');
  });

  document.querySelectorAll('.tab-panel').forEach(p => {
    const isTarget = p.id === panelId;
    p.classList.toggle('active', isTarget);
    p.hidden = !isTarget;
  });
}

// Shell Modal
function openShellModal(device) {
  currentShellDevice = device;
  const modal = document.getElementById('modalShell');
  document.getElementById('shellDeviceName').textContent = device;
  document.getElementById('shellOutput').textContent = `Connected to ${device}.\nEnter command below or click quick commands.\n`;
  modal.showModal();
  document.getElementById('inputShellCmd').focus();
}

async function runShellCommand(cmd) {
  if (!currentShellDevice || !cmd) return;
  const outputEl = document.getElementById('shellOutput');
  outputEl.textContent += `\n$ ${cmd}\n`;
  outputEl.scrollTop = outputEl.scrollHeight;

  try {
    const res = await fetch('/api/shell', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device: currentShellDevice, command: cmd })
    });
    const data = await res.json();
    outputEl.textContent += data.output || data.error || '(no output)\n';
    outputEl.scrollTop = outputEl.scrollHeight;
  } catch (err) {
    outputEl.textContent += `Error: ${err.message}\n`;
  }
}

// Screenshot Modal
function openScreenshotModal(device) {
  currentScreenshotDevice = device;
  const modal = document.getElementById('modalScreenshot');
  const img = document.getElementById('imgScreenshot');
  const loading = document.getElementById('screenshotLoading');
  const downloadBtn = document.getElementById('btnDownloadScreenshot');

  img.style.display = 'none';
  loading.hidden = false;
  modal.showModal();

  const src = `/api/screenshot?device=${encodeURIComponent(device)}&_t=${Date.now()}`;
  img.onload = () => {
    loading.hidden = true;
    img.style.display = 'block';
  };
  img.onerror = () => {
    loading.hidden = true;
    showToast('Failed to capture screenshot', 'error');
  };
  img.src = src;
  downloadBtn.href = src;
}

// Keyboard shortcuts (Alt+1, Alt+2, Alt+3, Alt+4, Alt+R, Alt+S)
function setupKeyboardShortcuts() {
  window.addEventListener('keydown', (e) => {
    if (e.altKey && !e.ctrlKey && !e.metaKey) {
      if (e.key === '1') {
        e.preventDefault();
        switchTab('tabBtnQr', 'tabPanelQr');
      } else if (e.key === '2') {
        e.preventDefault();
        switchTab('tabBtnCode', 'tabPanelCode');
      } else if (e.key === '3') {
        e.preventDefault();
        switchTab('tabBtnDiscovered', 'tabPanelDiscovered');
      } else if (e.key === '4') {
        e.preventDefault();
        switchTab('tabBtnUsb', 'tabPanelUsb');
      } else if (e.key.toLowerCase() === 'r') {
        e.preventDefault();
        fetch('/api/devices').then(r => r.json()).then(d => renderDevices(d.devices));
        showToast('Refreshing devices...', 'info');
      } else if (e.key.toLowerCase() === 's') {
        e.preventDefault();
        restartAdbServer();
      }
    }
  });
}

// DOM Setup
document.addEventListener('DOMContentLoaded', () => {
  setupTabs();
  setupKeyboardShortcuts();
  initEventSource();
  fetchOrNewQrSession(false);

  // Form Handlers
  document.getElementById('formManualPair').addEventListener('submit', handleManualPair);
  document.getElementById('formDirectConnect').addEventListener('submit', (e) => {
    e.preventDefault();
    const host = document.getElementById('directHost').value.trim();
    const port = document.getElementById('directPort').value.trim() || '5555';
    directConnectTarget(host, port);
  });

  // Buttons
  document.getElementById('btnRegenerateQr').addEventListener('click', () => fetchOrNewQrSession(true));
  document.getElementById('btnCopyCode').addEventListener('click', () => {
    const code = document.getElementById('qrPairingCode').textContent;
    if (code && code !== '------') {
      navigator.clipboard.writeText(code);
      showToast(`Copied code ${code} to clipboard!`, 'success');
    }
  });
  document.getElementById('btnRefreshDevices').addEventListener('click', () => {
    fetch('/api/devices').then(r => r.json()).then(d => renderDevices(d.devices));
    fetch('/api/discovered').then(r => r.json()).then(d => renderDiscovered(d.services));
    showToast('Refreshing active & discovered devices...', 'info');
  });
  document.getElementById('btnRestartAdb').addEventListener('click', restartAdbServer);
  document.getElementById('btnDisconnectAll').addEventListener('click', disconnectAllDevices);
  document.getElementById('btnSwitchUsbToWifi').addEventListener('click', handleSwitchUsbToWifi);

  // Shell Dialog
  document.getElementById('btnCloseShell').addEventListener('click', () => document.getElementById('modalShell').close());
  document.getElementById('formShellCmd').addEventListener('submit', (e) => {
    e.preventDefault();
    const input = document.getElementById('inputShellCmd');
    const cmd = input.value.trim();
    if (cmd) {
      runShellCommand(cmd);
      input.value = '';
    }
  });
  document.querySelectorAll('.chip-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const cmd = btn.dataset.cmd;
      document.getElementById('inputShellCmd').value = cmd;
      runShellCommand(cmd);
    });
  });

  // Screenshot Dialog
  document.getElementById('btnCloseScreenshot').addEventListener('click', () => document.getElementById('modalScreenshot').close());
  document.getElementById('btnRefreshScreenshot').addEventListener('click', () => {
    if (currentScreenshotDevice) openScreenshotModal(currentScreenshotDevice);
  });

  // Scrcpy & File Explorer Modal Closers
  document.getElementById('btnCloseScrcpy').addEventListener('click', () => document.getElementById('modalScrcpy').close());
  document.getElementById('btnCloseFileExplorer').addEventListener('click', () => document.getElementById('modalFileExplorer').close());
  document.getElementById('btnStopScrcpy').addEventListener('click', () => {
    const dev = document.getElementById('scrcpyTargetDevice').value;
    if (dev) stopScrcpy(dev);
  });

  // Confirm delete button
  document.getElementById('btnConfirmDeleteAction').addEventListener('click', confirmDeleteFileAction);

  // Setup Drag and Drop
  setupFileExplorerDragAndDrop();
});

// ==========================================
// SCRCPY SCREEN & CAMERA INTEGRATION
// ==========================================

async function openScrcpyModal(device, defaultMode = 'screen') {
  document.getElementById('scrcpyDeviceSerial').textContent = device;
  document.getElementById('scrcpyTargetDevice').value = device;

  switchScrcpyMode(defaultMode);

  // Check if mirroring is already running
  try {
    const res = await fetch(`/api/scrcpy/status?device=${encodeURIComponent(device)}`);
    const data = await res.json();
    const activeBanner = document.getElementById('scrcpyActiveBanner');
    if (data.running) {
      activeBanner.style.display = 'flex';
      document.getElementById('scrcpyStatusText').textContent = `Mirroring session active for ${device}`;
    } else {
      activeBanner.style.display = 'none';
    }
  } catch (e) {
    console.error('Error fetching scrcpy status:', e);
  }

  // Load cameras if camera mode
  if (defaultMode === 'camera') {
    loadDeviceCameras(device);
  }

  document.getElementById('modalScrcpy').showModal();
}

function switchScrcpyMode(mode) {
  document.getElementById('scrcpyMode').value = mode;
  const btnScreen = document.getElementById('btnModeScreen');
  const btnCamera = document.getElementById('btnModeCamera');
  const screenOpt = document.getElementById('scrcpyScreenOptions');
  const cameraOpt = document.getElementById('scrcpyCameraOptions');

  if (mode === 'camera') {
    btnCamera.classList.add('active');
    btnScreen.classList.remove('active');
    cameraOpt.style.display = 'block';
    screenOpt.style.display = 'none';

    const device = document.getElementById('scrcpyTargetDevice').value;
    if (device) loadDeviceCameras(device);
  } else {
    btnScreen.classList.add('active');
    btnCamera.classList.remove('active');
    screenOpt.style.display = 'block';
    cameraOpt.style.display = 'none';
  }
}

async function loadDeviceCameras(device) {
  const select = document.getElementById('selectScrcpyCamera');
  select.innerHTML = '<option value="">Querying device cameras via scrcpy...</option>';
  try {
    const res = await fetch(`/api/scrcpy/cameras?device=${encodeURIComponent(device)}`);
    const data = await res.json();
    if (data.cameras && data.cameras.length > 0) {
      select.innerHTML = `
        <option value="">Auto Select (First Available)</option>
        ${data.cameras.map(c => `
          <option value="${escapeHtml(c.id)}">Camera ${escapeHtml(c.id)} (${escapeHtml(c.description)})</option>
        `).join('')}
      `;
    } else {
      select.innerHTML = `
        <option value="">Auto Select (Front/Back)</option>
        <option value="0">Camera 0 (Default Camera)</option>
        <option value="1">Camera 1 (Secondary Camera)</option>
      `;
    }
  } catch (err) {
    select.innerHTML = '<option value="">Auto Select (Default)</option>';
  }
}

async function handleLaunchScrcpy(e) {
  e.preventDefault();
  const device = document.getElementById('scrcpyTargetDevice').value;
  const mode = document.getElementById('scrcpyMode').value;
  const cameraId = document.getElementById('selectScrcpyCamera').value;
  const cameraFacing = document.getElementById('selectCameraFacing').value;
  const stayAwake = document.getElementById('scrcpyStayAwake').checked;
  const turnOffScreen = document.getElementById('scrcpyTurnOffScreen').checked;
  const noAudio = document.getElementById('scrcpyNoAudio').checked;

  showToast(`Launching Scrcpy (${mode === 'camera' ? 'Camera' : 'Screen'})...`, 'info');

  try {
    const res = await fetch('/api/scrcpy/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        device,
        mode,
        camera_id: cameraId || null,
        camera_facing: cameraFacing || null,
        stay_awake: stayAwake,
        turn_off_screen: turnOffScreen,
        no_audio: noAudio
      })
    });
    const data = await res.json();
    if (res.ok && data.ok) {
      showToast(data.message, 'success');
      playFeedbackTone('success');
      document.getElementById('scrcpyActiveBanner').style.display = 'flex';
      document.getElementById('scrcpyStatusText').textContent = `Mirroring session active for ${device}`;
      setTimeout(() => {
        document.getElementById('modalScrcpy').close();
      }, 500);
    } else {
      showToast(data.error || 'Failed to start scrcpy', 'error');
      playFeedbackTone('error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
    playFeedbackTone('error');
  }
}

async function stopScrcpy(device) {
  try {
    const res = await fetch('/api/scrcpy/stop', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device })
    });
    const data = await res.json();
    if (data.ok) {
      showToast(`Mirroring stopped for ${device}`, 'info');
      document.getElementById('scrcpyActiveBanner').style.display = 'none';
    }
  } catch (err) {
    showToast(`Error stopping scrcpy: ${err.message}`, 'error');
  }
}

// ==========================================
// FILE EXPLORER INTEGRATION
// ==========================================

let feDevice = '';
let feCurrentPath = '/sdcard';
let feParentPath = null;
let feFiles = [];
let feFilterQuery = '';
let feSortCol = 'name';
let feSortAsc = true;
let feDeleteTarget = null; // { path, name, isDir }

function openFileExplorer(device, model, initialPath = '/sdcard') {
  feDevice = device;
  feCurrentPath = initialPath;
  feFilterQuery = '';

  document.getElementById('fileExplorerDevice').textContent = `${model} (${device})`;
  document.getElementById('fileSearchInput').value = '';
  document.getElementById('modalFileExplorer').showModal();

  loadFiles(device, initialPath);
}

async function loadFiles(device, path) {
  const tbody = document.getElementById('fileTableBody');
  tbody.innerHTML = `
    <tr>
      <td colspan="4" class="text-center text-muted" style="padding: 40px;">
        <div class="spinner-small" style="margin: 0 auto 10px;"></div>
        Loading directory contents...
      </td>
    </tr>
  `;

  try {
    const res = await fetch(`/api/files/list?device=${encodeURIComponent(device)}&path=${encodeURIComponent(path)}`);
    const data = await res.json();

    if (res.ok && data.ok) {
      feCurrentPath = data.path;
      feParentPath = data.parent;
      feFiles = data.files || [];

      // Update Parent Folder button state
      document.getElementById('btnParentFolder').disabled = !feParentPath;

      // Update Breadcrumbs
      renderBreadcrumbs(feCurrentPath);

      // Update Storage pill
      const storagePill = document.getElementById('fileStoragePill');
      if (data.storage) {
        storagePill.innerHTML = `<strong>${escapeHtml(data.storage.avail)}</strong> free / ${escapeHtml(data.storage.size)} (${escapeHtml(data.storage.percent)} used)`;
        storagePill.style.display = 'inline-flex';
      } else {
        storagePill.style.display = 'none';
      }

      // Render file list
      renderFileTable();
    } else {
      tbody.innerHTML = `
        <tr>
          <td colspan="4" class="text-center text-danger" style="padding: 30px;">
            Failed to list directory: ${escapeHtml(data.error || 'Unknown error')}
          </td>
        </tr>
      `;
    }
  } catch (err) {
    tbody.innerHTML = `
      <tr>
        <td colspan="4" class="text-center text-danger" style="padding: 30px;">
          Network error: ${escapeHtml(err.message)}
        </td>
      </tr>
    `;
  }
}

function renderBreadcrumbs(path) {
  const container = document.getElementById('fileBreadcrumbs');
  const parts = path.split('/').filter(Boolean);

  let html = `<button class="breadcrumb-item ${path === '/' ? 'active' : ''}" onclick="navigateFolder('/')">Root</button>`;
  let cumulative = '';

  parts.forEach((p, idx) => {
    cumulative += '/' + p;
    const isLast = idx === parts.length - 1;
    const currentTarget = cumulative;
    html += `
      <span class="breadcrumb-sep">/</span>
      <button class="breadcrumb-item ${isLast ? 'active' : ''}" onclick="navigateFolder('${escapeHtml(currentTarget)}')">
        ${escapeHtml(p)}
      </button>
    `;
  });

  container.innerHTML = html;
}

function renderFileTable() {
  const tbody = document.getElementById('fileTableBody');
  const countIndicator = document.getElementById('fileCountIndicator');

  let list = [...feFiles];

  // Apply search query filter
  if (feFilterQuery) {
    const q = feFilterQuery.toLowerCase();
    list = list.filter(f => f.name.toLowerCase().includes(q));
  }

  // Sort list
  list.sort((a, b) => {
    // Directories always first unless sorting explicitly by size
    if (a.is_dir !== b.is_dir && feSortCol !== 'size') {
      return a.is_dir ? -1 : 1;
    }

    let valA = a[feSortCol];
    let valB = b[feSortCol];

    if (feSortCol === 'name') {
      valA = (valA || '').toLowerCase();
      valB = (valB || '').toLowerCase();
    }

    if (valA < valB) return feSortAsc ? -1 : 1;
    if (valA > valB) return feSortAsc ? 1 : -1;
    return 0;
  });

  countIndicator.textContent = `${list.length} item${list.length === 1 ? '' : 's'}`;

  if (list.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="4" class="text-center text-muted" style="padding: 50px 20px;">
          ${feFilterQuery ? `No files match filter "<strong>${escapeHtml(feFilterQuery)}</strong>"` : 'Directory is empty'}
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = list.map(f => {
    const iconSvg = getFileIconSvg(f);
    const sizeStr = f.is_dir ? '—' : formatFileSize(f.size);
    const dateStr = f.date || '—';

    return `
      <tr class="file-row ${f.is_dir ? 'is-dir' : 'is-file'}">
        <td class="col-name">
          <div class="file-name-cell" onclick="${f.is_dir ? `navigateFolder('${escapeHtml(f.path)}')` : `downloadFile('${escapeHtml(f.path)}', false, '${escapeHtml(f.name)}')`}">
            <span class="file-icon">${iconSvg}</span>
            <span class="file-title" title="${escapeHtml(f.name)}">${escapeHtml(f.name)}</span>
            ${f.is_symlink ? `<span class="symlink-badge" title="Points to: ${escapeHtml(f.link_target || '')}">&rarr; ${escapeHtml(f.link_target || '')}</span>` : ''}
          </div>
        </td>
        <td class="col-size">${escapeHtml(sizeStr)}</td>
        <td class="col-date">${escapeHtml(dateStr)}</td>
        <td class="col-actions">
          <div class="file-row-actions">
            <button class="btn-action-icon" title="Download ${f.is_dir ? 'Folder (Zip)' : 'File'}" onclick="downloadFile('${escapeHtml(f.path)}', ${f.is_dir}, '${escapeHtml(f.name)}')">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            </button>
            <button class="btn-action-icon text-danger" title="Delete" onclick="promptDeleteFile('${escapeHtml(f.path)}', '${escapeHtml(f.name)}', ${f.is_dir})">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </div>
        </td>
      </tr>
    `;
  }).join('');
}

function getFileIconSvg(file) {
  if (file.is_dir) {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="#facc15" stroke="#ca8a04" stroke-width="1.5"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>`;
  }
  const ext = (file.ext || '').toLowerCase();
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].includes(ext)) {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`;
  }
  if (['mp4', 'mkv', 'webm', 'mov', 'avi', '3gp'].includes(ext)) {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#f43f5e" stroke-width="2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>`;
  }
  if (['mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac'].includes(ext)) {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#a855f7" stroke-width="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>`;
  }
  if (ext === 'pdf') {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>`;
  }
  if (ext === 'apk') {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#3ddc84" stroke-width="2"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>`;
  }
  if (['zip', 'rar', '7z', 'tar', 'gz'].includes(ext)) {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#eab308" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg>`;
  }
  if (['docx', 'doc', 'pptx', 'ppt', 'xlsx', 'xls', 'txt', 'md', 'json', 'xml'].includes(ext)) {
    return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#60a5fa" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>`;
  }
  return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#94a3b8" stroke-width="2"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><polyline points="13 2 13 9 20 9"/></svg>`;
}

function formatFileSize(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function navigateFolder(path) {
  if (!feDevice) return;
  loadFiles(feDevice, path);
}

function navigateParentFolder() {
  if (feParentPath) navigateFolder(feParentPath);
}

function refreshCurrentFolder() {
  if (feDevice && feCurrentPath) loadFiles(feDevice, feCurrentPath);
}

function handleFileSearch(query) {
  feFilterQuery = query.trim();
  renderFileTable();
}

function sortFiles(col) {
  if (feSortCol === col) {
    feSortAsc = !feSortAsc;
  } else {
    feSortCol = col;
    feSortAsc = true;
  }

  document.getElementById('sortIndicatorName').textContent = feSortCol === 'name' ? (feSortAsc ? '▲' : '▼') : '';
  document.getElementById('sortIndicatorSize').textContent = feSortCol === 'size' ? (feSortAsc ? '▲' : '▼') : '';
  document.getElementById('sortIndicatorDate').textContent = feSortCol === 'date' ? (feSortAsc ? '▲' : '▼') : '';

  renderFileTable();
}

function downloadFile(remotePath, isDir, name) {
  showToast(`Preparing download: ${name}...`, 'info');
  const url = `/api/files/download?device=${encodeURIComponent(feDevice)}&path=${encodeURIComponent(remotePath)}&is_dir=${isDir ? '1' : '0'}`;
  const a = document.createElement('a');
  a.href = url;
  a.download = isDir ? `${name}.zip` : name;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

function promptDeleteFile(remotePath, name, isDir) {
  feDeleteTarget = { path: remotePath, name, isDir };
  document.getElementById('deleteTargetName').innerHTML = `
    <strong>${escapeHtml(name)}</strong>
    <span class="text-dim text-sm block">(${escapeHtml(remotePath)})</span>
  `;
  document.getElementById('modalConfirmDelete').showModal();
}

async function confirmDeleteFileAction() {
  if (!feDeleteTarget || !feDevice) return;
  document.getElementById('modalConfirmDelete').close();

  const { path, name } = feDeleteTarget;
  showToast(`Deleting ${name}...`, 'info');

  try {
    const res = await fetch('/api/files/delete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device: feDevice, path })
    });
    const data = await res.json();
    if (res.ok && data.ok) {
      showToast(data.message || `Deleted ${name}`, 'success');
      playFeedbackTone('success');
      refreshCurrentFolder();
    } else {
      showToast(data.error || 'Failed to delete file', 'error');
      playFeedbackTone('error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
    playFeedbackTone('error');
  } finally {
    feDeleteTarget = null;
  }
}

function openNewFolderModal() {
  document.getElementById('inputNewFolderName').value = '';
  document.getElementById('modalNewFolder').showModal();
}

async function handleCreateFolder(e) {
  e.preventDefault();
  const folderName = document.getElementById('inputNewFolderName').value.trim();
  if (!folderName || !feDevice) return;

  document.getElementById('modalNewFolder').close();
  showToast(`Creating folder ${folderName}...`, 'info');

  try {
    const res = await fetch('/api/files/mkdir', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device: feDevice, path: feCurrentPath, name: folderName })
    });
    const data = await res.json();
    if (res.ok && data.ok) {
      showToast(data.message || `Created folder ${folderName}`, 'success');
      playFeedbackTone('success');
      refreshCurrentFolder();
    } else {
      showToast(data.error || 'Failed to create folder', 'error');
      playFeedbackTone('error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
    playFeedbackTone('error');
  }
}

function triggerFileUpload() {
  document.getElementById('fileUploadInput').click();
}

function triggerFolderUpload() {
  document.getElementById('folderUploadInput').click();
}

async function handleFilesSelected(files) {
  if (!files || files.length === 0 || !feDevice) return;

  const totalFiles = files.length;
  const progressBanner = document.getElementById('uploadProgressBanner');
  const progressText = document.getElementById('uploadProgressText');
  const progressBar = document.getElementById('uploadProgressBar');

  progressBanner.style.display = 'block';

  let successCount = 0;
  let errorCount = 0;

  for (let i = 0; i < totalFiles; i++) {
    const file = files[i];
    const percent = Math.round(((i) / totalFiles) * 100);
    progressBar.style.width = `${percent}%`;
    progressText.textContent = `Uploading (${i + 1}/${totalFiles}): ${file.name}`;

    try {
      const url = `/api/files/upload?device=${encodeURIComponent(feDevice)}&path=${encodeURIComponent(feCurrentPath)}&filename=${encodeURIComponent(file.name)}`;
      const res = await fetch(url, {
        method: 'POST',
        body: file
      });
      const data = await res.json();
      if (res.ok && data.ok) {
        successCount++;
      } else {
        errorCount++;
        showToast(data.error || `Failed to upload ${file.name}`, 'error');
      }
    } catch (err) {
      errorCount++;
      showToast(`Upload error: ${err.message}`, 'error');
    }
  }

  progressBar.style.width = '100%';
  setTimeout(() => {
    progressBanner.style.display = 'none';
  }, 400);

  if (successCount > 0) {
    showToast(`Successfully uploaded ${successCount} file(s)`, 'success');
    playFeedbackTone('success');
    refreshCurrentFolder();
  }
}

function setupFileExplorerDragAndDrop() {
  const dropZone = document.getElementById('fileDropZone');
  if (!dropZone) return;

  ['dragenter', 'dragover'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      e.stopPropagation();
      dropZone.classList.add('drag-active');
    }, false);
  });

  ['dragleave', 'drop'].forEach(eventName => {
    dropZone.addEventListener(eventName, (e) => {
      e.preventDefault();
      e.stopPropagation();
      dropZone.classList.remove('drag-active');
    }, false);
  });

  dropZone.addEventListener('drop', (e) => {
    const dt = e.dataTransfer;
    const files = dt.files;
    if (files && files.length > 0) {
      handleFilesSelected(files);
    }
  });
}

