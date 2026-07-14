(function () {
  'use strict';

  const API = '/cgi/ThirdParty/App.Native.UGreenLED/api.cgi';

  const ROUTES = {
    overview: { title: '概览', description: '查看灯控服务、实时网速与硬盘活动。' },
    lighting: { title: '灯光设置', description: '配置硬盘、网络和电源灯的状态颜色。' },
    activity: { title: '活动提示', description: '控制磁盘读写和网络流量的速度闪动。' },
    devices: { title: '设备与高级', description: '管理盘位映射、监测频率、后台服务与诊断状态。' },
  };

  const DISK_STATES = [
    { key: 'active', label: '活动', def: '0 255 0', br: 128 },
    { key: 'idle', label: '空闲', def: '255 255 0', br: 64 },
    { key: 'standby', label: '休眠', def: '0 100 255', br: 40 },
    { key: 'deep_sleep', label: '深度睡眠', def: '40 0 80', br: 24 },
    { key: 'offline', label: '离线 / 拔出', def: 'off', br: 0, isOff: true },
  ];

  const NET_STATES = [
    { key: 'disconnected', label: '断网', def: '255 0 0', br: 64 },
    { key: 'connected', label: '联网', def: '0 80 255', br: 48 },
    { key: 'vpn', label: '外网', def: '160 0 255', br: 64 },
  ];

  const POWER_FIELDS = [
    { key: 'smart_color', label: '智能模式', def: '100 100 100', type: 'color' },
    { key: 'all_on_color', label: '全部开启', def: '180 180 180', type: 'color' },
    { key: 'brightness', label: '亮度', def: '40', type: 'number' },
  ];

  const DISK_STATE_LABELS = {
    active: '活动', idle: '空闲', standby: '休眠', deep_sleep: '深度睡眠',
    offline: '离线', unknown: '未知', error: '异常', '?': '未知',
  };
  const NET_LABELS = { disconnected: '断网', connected: '联网', vpn: '外网' };
  const MODE_LABELS = { off: '关闭全部', on: '开启全部', smart: '智能模式' };

  const ACTIVITY_DEFAULTS = {
    disk_blink: false,
    network_blink: false,
    disk_threshold_kbps: 128,
    network_threshold_kbps: 32,
  };

  const DAEMON_DEFAULTS = {
    disk_power_probe_interval: 60,
    hotplug_check_interval: 30,
  };

  const COLOR_PRESETS = {
    classic: {
      name: '经典',
      ini: {
        disk_colors: { active: '0 255 0', idle: '255 255 0', standby: '0 100 255', deep_sleep: '40 0 80', offline: 'off' },
        disk_brightness: { active: '128', idle: '64', standby: '40', deep_sleep: '24', offline: '0' },
        netdev_colors: { disconnected: '255 0 0', connected: '0 80 255', vpn: '160 0 255' },
        netdev_brightness: { disconnected: '64', connected: '48', vpn: '64' },
        power: { smart_color: '100 100 100', all_on_color: '180 180 180', brightness: '40' },
      },
    },
    minimal: {
      name: '极简蓝灰',
      ini: {
        disk_colors: { active: '80 160 255', idle: '60 60 80', standby: '30 50 90', deep_sleep: '20 30 50', offline: 'off' },
        disk_brightness: { active: '96', idle: '32', standby: '24', deep_sleep: '16', offline: '0' },
        netdev_colors: { disconnected: '80 40 40', connected: '0 120 200', vpn: '100 80 220' },
        netdev_brightness: { disconnected: '48', connected: '40', vpn: '48' },
        power: { smart_color: '70 75 85', all_on_color: '140 145 155', brightness: '32' },
      },
    },
    vivid: {
      name: '醒目警示',
      ini: {
        disk_colors: { active: '0 255 0', idle: '255 200 0', standby: '255 80 0', deep_sleep: '128 0 128', offline: 'off' },
        disk_brightness: { active: '160', idle: '96', standby: '64', deep_sleep: '32', offline: '0' },
        netdev_colors: { disconnected: '255 0 0', connected: '0 255 128', vpn: '255 0 255' },
        netdev_brightness: { disconnected: '128', connected: '80', vpn: '96' },
        power: { smart_color: '255 255 255', all_on_color: '255 220 120', brightness: '64' },
      },
    },
    soft: {
      name: '柔和护眼',
      ini: {
        disk_colors: { active: '100 200 120', idle: '200 180 80', standby: '100 140 180', deep_sleep: '80 60 100', offline: 'off' },
        disk_brightness: { active: '64', idle: '40', standby: '28', deep_sleep: '20', offline: '0' },
        netdev_colors: { disconnected: '180 80 80', connected: '80 140 180', vpn: '140 100 180' },
        netdev_brightness: { disconnected: '40', connected: '36', vpn: '40' },
        power: { smart_color: '90 90 95', all_on_color: '150 150 140', brightness: '28' },
      },
    },
    white: {
      name: '白色系',
      ini: {
        disk_colors: { active: '255 255 255', idle: '220 220 220', standby: '160 160 160', deep_sleep: '90 90 90', offline: 'off' },
        disk_brightness: { active: '72', idle: '48', standby: '32', deep_sleep: '18', offline: '0' },
        netdev_colors: { disconnected: '120 120 120', connected: '255 255 255', vpn: '255 255 255' },
        netdev_brightness: { disconnected: '32', connected: '48', vpn: '64' },
        power: { smart_color: '200 200 200', all_on_color: '255 255 255', brightness: '40' },
      },
    },
  };

  let currentMode = 'smart';
  let currentRoute = 'overview';
  let currentLightingPanel = 'disk';
  let refreshPromise = null;
  let toastTimer = null;
  let currentIni = {};

  function $(id) { return document.getElementById(id); }

  function api(path, opts) {
    const options = opts || {};
    const url = API + path + (options.query ? '?' + options.query : '');
    return fetch(url, {
      method: options.method || 'GET',
      headers: options.body ? { 'Content-Type': 'text/plain' } : {},
      body: options.body,
      credentials: 'same-origin',
      cache: 'no-store',
    }).then(async (response) => {
      const text = await response.text();
      let data;
      try { data = JSON.parse(text); } catch (_) { throw new Error(text.slice(0, 160) || `HTTP ${response.status}`); }
      if (data && data.ok === false) throw new Error(data.error || '请求失败');
      return data;
    });
  }

  function showMessage(message, type) {
    const el = $('actionMsg');
    clearTimeout(toastTimer);
    el.textContent = message;
    el.className = `action-message visible ${type || 'ok'}`;
    toastTimer = setTimeout(() => { el.className = 'action-message'; }, 3200);
  }

  function showError(error) {
    const message = error && error.message ? error.message : String(error);
    showMessage(message, 'err');
    console.error('[UGreenLED]', error);
  }

  function setBusy(button, busy) {
    if (!button) return;
    button.classList.toggle('busy', busy);
    button.disabled = busy;
  }

  function parseIni(raw) {
    const data = {};
    let section = '';
    String(raw || '').split('\n').forEach((sourceLine) => {
      const line = sourceLine.trim();
      if (!line || line.startsWith('#')) return;
      const sectionMatch = line.match(/^\[([^\]]+)\]/);
      if (sectionMatch) {
        section = sectionMatch[1];
        data[section] = data[section] || {};
        return;
      }
      const index = line.indexOf('=');
      if (index > 0 && section) data[section][line.slice(0, index).trim()] = line.slice(index + 1).trim();
    });
    return data;
  }

  function mergeIni(base, patch) {
    const result = JSON.parse(JSON.stringify(base || {}));
    Object.keys(patch || {}).forEach((section) => {
      result[section] = Object.assign({}, result[section] || {}, patch[section]);
    });
    return result;
  }

  function settingBool(value, fallback) {
    if (value === 'true') return true;
    if (value === 'false') return false;
    return fallback;
  }

  function positiveInt(value, fallback) {
    const number = Number.parseInt(value, 10);
    return Number.isFinite(number) && number > 0 ? number : fallback;
  }

  function boundedInt(value, min, max, fallback) {
    const number = Number.parseInt(value, 10);
    if (!Number.isFinite(number)) return fallback;
    return Math.max(min, Math.min(max, number));
  }

  function rgbToHex(r, g, b) {
    return '#' + [r, g, b].map((value) => Math.max(0, Math.min(255, Number(value) || 0)).toString(16).padStart(2, '0')).join('');
  }

  function hexToRgb(hex) {
    const match = String(hex).match(/^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i);
    return match ? [parseInt(match[1], 16), parseInt(match[2], 16), parseInt(match[3], 16)] : [128, 128, 128];
  }

  function formatRate(kbps) {
    const value = Number(kbps) || 0;
    if (value >= 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} GB/s`;
    if (value >= 1024) return `${(value / 1024).toFixed(1)} MB/s`;
    return `${Math.round(value)} KB/s`;
  }

  function setRoute(route, updateHash) {
    const next = ROUTES[route] ? route : 'overview';
    currentRoute = next;
    document.querySelectorAll('.app-view').forEach((view) => {
      const active = view.dataset.view === next;
      view.hidden = !active;
      view.classList.toggle('active', active);
    });
    document.querySelectorAll('.nav-item').forEach((button) => {
      const active = button.dataset.route === next;
      button.classList.toggle('active', active);
      if (active) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
    });
    $('pageTitle').textContent = ROUTES[next].title;
    $('pageDescription').textContent = ROUTES[next].description;
    if (updateHash !== false && location.hash !== `#${next}`) history.replaceState(null, '', `#${next}`);
    $('appMain').scrollTo({ top: 0, behavior: 'smooth' });
  }

  function setLightingPanel(panel) {
    const next = ['disk', 'network', 'power'].includes(panel) ? panel : 'disk';
    currentLightingPanel = next;
    document.querySelectorAll('[data-lighting-panel]').forEach((surface) => {
      surface.hidden = surface.dataset.lightingPanel !== next;
    });
    document.querySelectorAll('[data-lighting-tab]').forEach((button) => {
      const active = button.dataset.lightingTab === next;
      button.classList.toggle('active', active);
      button.setAttribute('aria-selected', active ? 'true' : 'false');
      button.tabIndex = active ? 0 : -1;
    });
  }

  function buildColorGrid(containerId, items, colorSection, brightnessSection) {
    const grid = $(containerId);
    grid.innerHTML = '';
    items.forEach((item) => {
      const row = document.createElement('div');
      row.className = 'color-row';
      row.dataset.colorSection = colorSection;
      row.dataset.brightnessSection = brightnessSection;
      row.dataset.key = item.key;

      const label = document.createElement('label');
      label.textContent = item.label;
      row.appendChild(label);

      if (item.isOff) {
        const off = document.createElement('span');
        off.className = 'off-tag';
        off.textContent = '自动关灯';
        row.appendChild(off);
      } else {
        const raw = currentIni[colorSection]?.[item.key] || item.def;
        const rgb = raw === 'off' ? [0, 0, 0] : raw.split(/\s+/).map(Number);
        const brightness = currentIni[brightnessSection]?.[item.key] ?? item.br ?? 64;
        const color = document.createElement('input');
        color.type = 'color';
        color.className = 'color-input';
        color.value = rgbToHex(rgb[0], rgb[1], rgb[2]);
        color.setAttribute('aria-label', `${item.label}颜色`);
        const number = document.createElement('input');
        number.type = 'number';
        number.className = 'brightness-input';
        number.min = '0';
        number.max = '255';
        number.value = brightness;
        number.setAttribute('aria-label', `${item.label}亮度`);
        row.append(color, number);
      }
      grid.appendChild(row);
    });
  }

  function buildPowerGrid() {
    const grid = $('powerGrid');
    grid.innerHTML = '';
    POWER_FIELDS.forEach((item) => {
      const row = document.createElement('div');
      row.className = 'color-row';
      row.dataset.powerKey = item.key;
      const label = document.createElement('label');
      label.textContent = item.label;
      row.appendChild(label);
      const raw = currentIni.power?.[item.key] || item.def;
      if (item.type === 'color') {
        const rgb = raw.split(/\s+/).map(Number);
        const color = document.createElement('input');
        color.type = 'color';
        color.className = 'color-input';
        color.value = rgbToHex(rgb[0], rgb[1], rgb[2]);
        color.setAttribute('aria-label', `${item.label}颜色`);
        row.appendChild(color);
      } else {
        const number = document.createElement('input');
        number.type = 'number';
        number.className = 'brightness-input';
        number.min = '0';
        number.max = '255';
        number.value = raw;
        number.setAttribute('aria-label', '电源灯亮度');
        row.appendChild(number);
      }
      grid.appendChild(row);
    });
  }

  function loadUiFromSettings(ini) {
    currentIni = ini || {};
    buildColorGrid('diskGrid', DISK_STATES, 'disk_colors', 'disk_brightness');
    buildColorGrid('netGrid', NET_STATES, 'netdev_colors', 'netdev_brightness');
    buildPowerGrid();
    currentMode = currentIni.mode?.global || 'smart';
    $('diskBlink').checked = settingBool(currentIni.activity?.disk_blink, ACTIVITY_DEFAULTS.disk_blink);
    $('networkBlink').checked = settingBool(currentIni.activity?.network_blink, ACTIVITY_DEFAULTS.network_blink);
    $('diskBlinkThreshold').value = positiveInt(currentIni.activity?.disk_threshold_kbps, ACTIVITY_DEFAULTS.disk_threshold_kbps);
    $('networkBlinkThreshold').value = positiveInt(currentIni.activity?.network_threshold_kbps, ACTIVITY_DEFAULTS.network_threshold_kbps);
    $('diskPowerProbeInterval').value = boundedInt(currentIni.daemon?.disk_power_probe_interval, 10, 3600, DAEMON_DEFAULTS.disk_power_probe_interval);
    $('hotplugCheckInterval').value = boundedInt(currentIni.daemon?.hotplug_check_interval, 5, 3600, DAEMON_DEFAULTS.hotplug_check_interval);
    syncActivityControls();
    updateModeUi();
  }

  function updateModeUi() {
    document.querySelectorAll('.mode-button').forEach((button) => {
      const active = button.dataset.mode === currentMode;
      button.classList.toggle('active', active);
      button.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    $('overviewMode').textContent = MODE_LABELS[currentMode] || currentMode;
  }

  function syncActivityControls() {
    $('diskBlinkThreshold').disabled = !$('diskBlink').checked;
    $('networkBlinkThreshold').disabled = !$('networkBlink').checked;
  }

  function collectLightingLines() {
    const lines = [];
    document.querySelectorAll('#diskGrid .color-row, #netGrid .color-row').forEach((row) => {
      const key = row.dataset.key;
      if (row.querySelector('.off-tag')) {
        lines.push(`${row.dataset.colorSection}.${key}=off`);
        lines.push(`${row.dataset.brightnessSection}.${key}=0`);
        return;
      }
      const color = row.querySelector('.color-input');
      const brightness = row.querySelector('.brightness-input');
      const [r, g, b] = hexToRgb(color.value);
      lines.push(`${row.dataset.colorSection}.${key}=${r} ${g} ${b}`);
      lines.push(`${row.dataset.brightnessSection}.${key}=${boundedInt(brightness.value, 0, 255, 64)}`);
    });
    document.querySelectorAll('#powerGrid .color-row').forEach((row) => {
      const key = row.dataset.powerKey;
      const color = row.querySelector('.color-input');
      const number = row.querySelector('.brightness-input');
      if (color) {
        const [r, g, b] = hexToRgb(color.value);
        lines.push(`power.${key}=${r} ${g} ${b}`);
      } else if (number) {
        lines.push(`power.${key}=${boundedInt(number.value, 0, 255, 40)}`);
      }
    });
    return lines;
  }

  function collectActivityLines() {
    return [
      `activity.disk_blink=${$('diskBlink').checked}`,
      `activity.network_blink=${$('networkBlink').checked}`,
      `activity.disk_threshold_kbps=${positiveInt($('diskBlinkThreshold').value, ACTIVITY_DEFAULTS.disk_threshold_kbps)}`,
      `activity.network_threshold_kbps=${positiveInt($('networkBlinkThreshold').value, ACTIVITY_DEFAULTS.network_threshold_kbps)}`,
    ];
  }

  function collectMonitoringLines() {
    return [
      `daemon.disk_power_probe_interval=${boundedInt($('diskPowerProbeInterval').value, 10, 3600, DAEMON_DEFAULTS.disk_power_probe_interval)}`,
      `daemon.hotplug_check_interval=${boundedInt($('hotplugCheckInterval').value, 5, 3600, DAEMON_DEFAULTS.hotplug_check_interval)}`,
    ];
  }

  function saveSettings(button, lines, successMessage) {
    setBusy(button, true);
    return api('/settings', { method: 'POST', body: lines.join('\n') })
      .then(() => api('/daemon/start'))
      .then(() => {
        showMessage(successMessage, 'ok');
        return loadSettings();
      })
      .then(refresh)
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  function applyPreset(id) {
    const preset = COLOR_PRESETS[id];
    if (!preset) return;
    currentIni = mergeIni(currentIni, preset.ini);
    loadUiFromSettings(currentIni);
    showMessage(`已套用“${preset.name}”，保存后生效`, 'ok');
  }

  function setMode(mode) {
    if (!MODE_LABELS[mode]) return;
    showMessage(`正在切换到${MODE_LABELS[mode]}…`, 'ok');
    return api('/mode', { query: `mode=${encodeURIComponent(mode)}` })
      .then((data) => {
        currentMode = data.mode || mode;
        updateModeUi();
        showMessage(`已切换到${MODE_LABELS[currentMode] || currentMode}`, 'ok');
        return refresh();
      })
      .catch(showError);
  }

  function stateChip(state) {
    const chip = document.createElement('span');
    chip.className = `state-chip ${state || 'unknown'}`;
    chip.textContent = DISK_STATE_LABELS[state] || state || '未知';
    return chip;
  }

  function fillDiskTable(tableId, mapping) {
    const tbody = document.querySelector(`#${tableId} tbody`);
    tbody.innerHTML = '';
    if (!mapping.length) {
      const row = document.createElement('tr');
      const cell = document.createElement('td');
      cell.colSpan = 5;
      cell.className = 'empty-row';
      cell.textContent = '暂未检测到硬盘映射';
      row.appendChild(cell);
      tbody.appendChild(row);
      return;
    }
    mapping.forEach((item) => {
      const row = document.createElement('tr');
      const device = document.createElement('td');
      const led = document.createElement('td');
      const state = document.createElement('td');
      const read = document.createElement('td');
      const write = document.createElement('td');
      device.textContent = item.device || '—';
      led.textContent = item.led || '—';
      state.appendChild(stateChip(String(item.state || '').trim()));
      read.textContent = formatRate(item.read_kbps);
      write.textContent = formatRate(item.write_kbps);
      row.append(device, led, state, read, write);
      tbody.appendChild(row);
    });
  }

  function renderStatus(data) {
    const running = data.daemon === 'running';
    currentMode = data.mode || currentMode;
    updateModeUi();
    $('overviewServiceState').textContent = running ? '应用运行中' : '后台已停止';
    $('overviewNetwork').textContent = data.network_label || NET_LABELS[data.network] || data.network || '未知';
    $('networkBadge').textContent = data.network_label || NET_LABELS[data.network] || '未知';
    $('downloadSpeed').textContent = formatRate(data.net_rx_kbps);
    $('uploadSpeed').textContent = formatRate(data.net_tx_kbps);
    $('networkDebug').textContent = `国内 ${data.net_domestic ? '可达' : '不可达'} · 海外 ${data.net_overseas ? '可达' : '不可达'}`;
    $('daemonBadgeText').textContent = running ? '后台运行中' : '后台已停止';
    $('railStatusText').textContent = running ? '服务在线' : '服务离线';
    document.querySelectorAll('#daemonBadge .status-dot, #railStatusDot').forEach((dot) => {
      dot.classList.toggle('online', running);
      dot.classList.toggle('offline', !running);
    });
    $('statusBar').textContent = (data.led_status || '暂无 LED 原始状态').slice(0, 1400);
  }

  function renderMapping(data) {
    const mapping = Array.isArray(data.mapping) ? data.mapping : [];
    $('overviewDiskCount').textContent = `${mapping.length} 块`;
    fillDiskTable('overviewDiskTable', mapping);
    fillDiskTable('deviceMapTable', mapping);
  }

  function refresh() {
    if (refreshPromise) return refreshPromise;
    const button = $('btnRefresh');
    setBusy(button, true);
    const statusRequest = api('/status').then(renderStatus);
    const mappingRequest = api('/mapping').then(renderMapping);
    refreshPromise = Promise.all([statusRequest, mappingRequest])
      .catch(showError)
      .finally(() => {
        refreshPromise = null;
        setBusy(button, false);
      });
    return refreshPromise;
  }

  function loadSettings() {
    return api('/settings')
      .then((data) => loadUiFromSettings(parseIni(data.raw || '')))
      .catch(showError);
  }

  function runAction(button, promise, successMessage) {
    setBusy(button, true);
    return promise
      .then((data) => {
        showMessage(data.message || successMessage, 'ok');
        return refresh();
      })
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  document.querySelectorAll('[data-route]').forEach((button) => {
    button.addEventListener('click', () => setRoute(button.dataset.route));
  });
  document.querySelectorAll('.mode-button').forEach((button) => {
    button.addEventListener('click', () => setMode(button.dataset.mode));
  });
  document.querySelectorAll('[data-preset]').forEach((button) => {
    button.addEventListener('click', () => applyPreset(button.dataset.preset));
  });
  document.querySelectorAll('[data-lighting-tab]').forEach((button) => {
    button.addEventListener('click', () => setLightingPanel(button.dataset.lightingTab));
    button.addEventListener('keydown', (event) => {
      if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
      event.preventDefault();
      const tabs = Array.from(document.querySelectorAll('[data-lighting-tab]'));
      const index = tabs.indexOf(button);
      const offset = event.key === 'ArrowRight' ? 1 : -1;
      const next = tabs[(index + offset + tabs.length) % tabs.length];
      setLightingPanel(next.dataset.lightingTab);
      next.focus();
    });
  });

  $('btnRefresh').addEventListener('click', refresh);
  $('diskBlink').addEventListener('change', syncActivityControls);
  $('networkBlink').addEventListener('change', syncActivityControls);
  $('btnSaveLighting').addEventListener('click', function () {
    saveSettings(this, collectLightingLines(), '灯光设置已保存');
  });
  $('btnSaveActivity').addEventListener('click', function () {
    saveSettings(this, collectActivityLines(), '活动提示已保存');
  });
  $('btnSaveMonitoring').addEventListener('click', function () {
    saveSettings(this, collectMonitoringLines(), '监测频率已保存');
  });
  $('btnRemap').addEventListener('click', function () {
    runAction(this, api('/remap'), '硬盘映射已更新');
  });
  $('btnDaemonStart').addEventListener('click', function () {
    runAction(this, api('/daemon/start'), '后台服务已启动');
  });
  $('btnDaemonStop').addEventListener('click', function () {
    runAction(this, api('/daemon/stop'), '后台服务已停止');
  });

  window.addEventListener('hashchange', () => setRoute(location.hash.slice(1), false));

  setLightingPanel(currentLightingPanel);
  setRoute(location.hash.slice(1) || 'overview', false);
  Promise.all([loadSettings(), refresh()]);
  setInterval(() => {
    if (!document.hidden) refresh();
  }, 10000);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refresh();
  });
})();
