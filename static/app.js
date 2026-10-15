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
        ${d.is_wireless ? `
          <button class="btn btn-danger btn-sm" onclick="disconnectDevice('${escapeHtml(d.serial)}')">
            Disconnect
          </button>
        ` : ''}
        <button class="btn btn-secondary btn-sm" onclick="openScreenshotModal('${escapeHtml(d.serial)}')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>
          Screenshot
        </button>
        <button class="btn btn-secondary btn-sm" onclick="openShellModal('${escapeHtml(d.serial)}')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
          Shell
        </button>
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
});
