(function () {
  'use strict';

  const API = '/cgi/ThirdParty/App.Native.UGreenLED/api.cgi';

  const ROUTES = {
    overview: { title: '概览', description: '查看灯控服务、实时网速与硬盘活动。' },
    lighting: { title: '灯光设置', description: '配置硬盘、网络和电源灯的状态颜色。' },
    activity: { title: '活动提示', description: '控制磁盘读写和网络流量的速度闪动。' },
    devices: { title: '设备与高级', description: '管理盘位映射、监测频率、后台服务与诊断状态。' },
    bios: { title: 'BIOS 控制', description: 'DXP4800 Plus / Pro、DXP4800S 与 DXP480T Plus 的 IT8613 风扇、系统信息与来电启动控制。' },
    lab: { title: '实验室', description: '未经验证的高级硬件功能，请确认风险后谨慎使用。' },
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
  const POWER26_EFFECT_LABELS = { steady: '常亮', fast: '快闪', slow: '慢闪', breath: '呼吸', network: '网络活动' };

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
  let hardwareState = {};
  let biosState = { loaded: false, supported: false, available: false };
  const biosFanWrites = {
    cpu: { timer: null, statusTimer: null, queue: Promise.resolve(), revision: 0, busy: false },
    sys: { timer: null, statusTimer: null, queue: Promise.resolve(), revision: 0, busy: false },
  };
  let labState = { active: false, mode: 'auto', slots: [], disks: [] };
  let labMethod = 'position';
  let labDraft = {};
  let labIdentifying = '';
  let labStatusPromise = null;
  let logsLoaded = false;
  let logContent = '';
  let clientErrorTimestamps = [];

  function $(id) { return document.getElementById(id); }

  function createRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
    return `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function requestError(message, context) {
    const error = new Error(message);
    Object.assign(error, context || {});
    return error;
  }

  function reportClientError(kind, error, extra) {
    const now = Date.now();
    clientErrorTimestamps = clientErrorTimestamps.filter((timestamp) => now - timestamp < 60000);
    if (clientErrorTimestamps.length >= 10) return;
    clientErrorTimestamps.push(now);
    const sourceError = error instanceof Error ? error : new Error(String(error || 'unknown client error'));
    const payload = JSON.stringify({
      kind: String(kind || 'runtime').slice(0, 40),
      route: currentRoute,
      message: String(sourceError.message || sourceError).slice(0, 600),
      stack: String(sourceError.stack || '').slice(0, 2400),
      related_request_id: String(sourceError.requestId || extra?.requestId || '').slice(0, 64),
      source: String(extra?.source || '').split('/').pop().split('?')[0].slice(0, 120),
      line: Number(extra?.line) || 0,
      column: Number(extra?.column) || 0,
      browser_time: new Date(now).toISOString(),
    });
    fetch(`${API}/logs/client`, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain', 'X-Request-ID': createRequestId() },
      body: payload,
      credentials: 'same-origin',
      cache: 'no-store',
      keepalive: true,
    }).catch(() => {});
  }

  window.addEventListener('error', (event) => {
    reportClientError('window.error', event.error || event.message, {
      source: event.filename,
      line: event.lineno,
      column: event.colno,
    });
  });
  window.addEventListener('unhandledrejection', (event) => {
    reportClientError('unhandledrejection', event.reason);
  });

  function api(path, opts) {
    const options = opts || {};
    const url = API + path + (options.query ? '?' + options.query : '');
    const method = options.method || 'GET';
    const clientRequestId = createRequestId();
    const startedAt = performance.now();
    const headers = { 'X-Request-ID': clientRequestId };
    if (options.body !== undefined) headers['Content-Type'] = 'text/plain';
    return fetch(url, {
      method,
      headers,
      body: options.body,
      credentials: 'same-origin',
      cache: 'no-store',
    }).then(async (response) => {
      const text = await response.text();
      const requestId = response.headers.get('X-Request-ID') || clientRequestId;
      const durationMs = Math.round(performance.now() - startedAt);
      let data;
      try {
        data = JSON.parse(text);
      } catch (_) {
        console.error('[UGreenLED] API returned non-JSON', {
          method, path, status: response.status, requestId, durationMs,
          responsePreview: text.replace(/[\r\n\t]+/g, ' ').slice(0, 240),
        });
        throw requestError(`服务器返回异常响应（HTTP ${response.status}）`, {
          method, path, status: response.status, requestId, durationMs, code: 'INVALID_RESPONSE',
        });
      }
      if (!response.ok || (data && data.ok === false)) {
        throw requestError(data?.error || `请求失败（HTTP ${response.status}）`, {
          method, path, status: response.status, requestId, durationMs, code: data?.code || 'API_ERROR',
        });
      }
      if (data && typeof data === 'object') data.requestId = requestId;
      return data;
    }).catch((error) => {
      if (!error.requestId) {
        error.requestId = clientRequestId;
        error.method = method;
        error.path = path;
        error.durationMs = Math.round(performance.now() - startedAt);
        error.code = error.code || 'NETWORK_ERROR';
      }
      throw error;
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
    const base = error && error.message ? error.message : String(error);
    const message = error?.requestId ? `${base}（请求 ID：${error.requestId}）` : base;
    if (!error?.requestId || ['NETWORK_ERROR', 'INVALID_RESPONSE'].includes(error?.code)) {
      reportClientError(error?.code ? 'handled.transport_error' : 'handled.runtime_error', error, {
        requestId: error?.requestId,
      });
    }
    showMessage(message, 'err');
    console.error('[UGreenLED]', {
      message: base,
      requestId: error?.requestId,
      method: error?.method,
      path: error?.path,
      status: error?.status,
      code: error?.code,
      durationMs: error?.durationMs,
      error,
    });
  }

  function setBusy(button, busy) {
    if (!button) return;
    button.classList.toggle('busy', busy);
    button.disabled = busy;
    button.setAttribute('aria-busy', busy ? 'true' : 'false');
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

  function isPower26Profile() {
    return hardwareState.profile === 'dxp480t_plus';
  }

  function applyHardwareRouting() {
    if (!hardwareState.backend_active) return;
    const power26 = isPower26Profile();
    $('power26LightingContent').hidden = !power26;
    $('standardLightingContent').hidden = power26;
    if (currentRoute === 'lighting') setRoute('lighting', false);
  }

  function applyBiosRouting() {
    const supported = Boolean(biosState.supported);
    $('navBios').hidden = !supported;
    if (biosState.loaded && !supported && currentRoute === 'bios') setRoute('overview');
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

  function compareVersions(left, right) {
    const normalize = (value) => String(value || '')
      .replace(/^v/i, '')
      .split(/[.+-]/)
      .map((part) => Number.parseInt(part, 10))
      .filter((part) => Number.isFinite(part));
    const a = normalize(left);
    const b = normalize(right);
    const length = Math.max(a.length, b.length);
    for (let index = 0; index < length; index += 1) {
      const difference = (a[index] || 0) - (b[index] || 0);
      if (difference !== 0) return difference > 0 ? 1 : -1;
    }
    return 0;
  }

  function formatCheckedAt(timestamp) {
    const value = Number(timestamp);
    if (!Number.isFinite(value) || value <= 0) return '刚刚完成检查';
    try {
      return `检查时间：${new Date(value * 1000).toLocaleString('zh-CN', { hour12: false })}`;
    } catch (_) {
      return '刚刚完成检查';
    }
  }

  function renderUpdate(data) {
    const badge = $('updateBadge');
    const download = $('btnDownloadUpdate');
    const notes = $('btnReleaseNotes');
    const current = data.current_version || 'unknown';
    $('currentAppVersion').textContent = current === 'unknown' ? '未知' : `v${String(current).replace(/^v/i, '')}`;
    $('updateCheckedAt').textContent = formatCheckedAt(data.checked_at);
    download.hidden = true;
    notes.hidden = true;

    if (!data.reachable) {
      badge.textContent = '检查失败';
      $('updateTitle').textContent = '暂时无法连接 GitHub Release';
      $('updateDescription').textContent = data.error || '请检查 NAS 网络连接，稍后可再次手动检查。';
      return;
    }

    const latest = data.latest_version || current;
    notes.href = data.release_url || 'https://github.com/BearHero520/LLLED_FPK/releases/latest';
    notes.hidden = false;
    const comparison = compareVersions(latest, current);
    if (comparison > 0) {
      badge.textContent = '发现新版本';
      $('updateTitle').textContent = `v${latest} 可以升级`;
      $('updateDescription').textContent = '下载安装包后，请在 fnOS 应用中心使用手动安装完成升级，现有配置会保留。';
      download.href = data.download_url || 'https://github.com/BearHero520/LLLED_FPK/releases/latest';
      download.hidden = false;
      return;
    }

    if (comparison < 0) {
      badge.textContent = '开发版本';
      $('updateTitle').textContent = `当前 v${current} 高于公开版本 v${latest}`;
      $('updateDescription').textContent = '当前安装包可能来自开发构建；正式发布同版本或更高版本后会恢复正常提示。';
    } else {
      badge.textContent = '已是最新';
      $('updateTitle').textContent = `当前已是最新版本 v${latest}`;
      $('updateDescription').textContent = '应用会在打开管理页时自动检查，也可以随时手动重新检查。';
    }
  }

  function checkForUpdates(force, button) {
    setBusy(button, true);
    return api('/update/check', { query: force ? 'force=1' : '' })
      .then((data) => {
        renderUpdate(data);
        if (force) showMessage(data.reachable ? '更新检查完成' : '暂时无法连接 GitHub Release', data.reachable ? 'ok' : 'err');
        return data;
      })
      .catch((error) => {
        if (force) showError(error); else console.error('[UGreenLED] update check failed', error);
      })
      .finally(() => setBusy(button, false));
  }

  function labDiskLabel(disk) {
    const details = [disk.size, disk.model, disk.serial ? `S/N ${disk.serial}` : ''].filter(Boolean).join(' · ');
    return `${disk.device}${details ? ` · ${details}` : ''}`;
  }

  function updateLabMethodUi() {
    document.querySelectorAll('[data-lab-method]').forEach((button) => {
      const active = button.dataset.labMethod === labMethod;
      button.classList.toggle('active', active);
      button.setAttribute('aria-selected', active ? 'true' : 'false');
      button.disabled = labState.active;
    });
    const positionMode = labMethod === 'position';
    $('labMethodHelp').textContent = positionMode
      ? '将 HCTL 代表的硬盘位置绑定到实际 LED 通道，适合 6/8 盘位灯光乱序的机型。换硬盘后规则仍然有效。'
      : '将具体硬盘的序列号绑定到 LED 通道。硬盘移动或设备名变化后，映射仍会跟随这块硬盘。';
    $('labStep2Title').textContent = positionMode ? '逐位置选择 LED' : '逐灯选择硬盘';
    $('labStep2Copy').textContent = positionMode
      ? '为每个硬盘位置选择 LED 通道并闪烁验证'
      : '让一个 LED 通道闪烁，再选择要跟随的硬盘';
    $('labSessionHelp').textContent = positionMode
      ? '先确认全部硬盘灯已亮，再为每个硬盘位置选择对应的 LED 通道。当前硬盘信息仅用于帮助识别位置。'
      : '先确认全部硬盘灯已亮，再为每个 LED 通道选择要绑定的具体硬盘。此方式依赖硬盘序列号。';
    $('labProgressHint').textContent = positionMode
      ? '请选择每个硬盘位置对应的 LED 通道'
      : '请选择每个 LED 通道对应的具体硬盘';
    $('labPrimaryTitle').textContent = positionMode ? '硬盘位置与 LED' : 'LED 与硬盘';
    $('labPrimaryHint').textContent = positionMode ? '选择后点击“闪烁所选灯”验证' : '点击“闪烁此灯”确认 LED 通道';
    $('labInventoryTitle').textContent = positionMode ? 'LED 通道分配' : '检测到的硬盘';
    $('labSecondaryHint').textContent = positionMode ? '每个 LED 只能分配一次' : '通过型号、容量或序列号核对';
    $('btnSaveLabMapping').innerHTML = positionMode
      ? '<i class="bi bi-floppy" aria-hidden="true"></i>保存位置绑定'
      : '<i class="bi bi-floppy" aria-hidden="true"></i>保存硬盘绑定';
  }

  function buildLabDraft(data, previousDraft, preserveDraft) {
    const next = {};
    if (labMethod === 'position') {
      const validLeds = new Set((data.slots || []).map((slot) => slot.led));
      (data.disks || []).filter((disk) => disk.position_supported).forEach((disk) => {
        const hasPrevious = preserveDraft && Object.prototype.hasOwnProperty.call(previousDraft, disk.hctl);
        const previous = hasPrevious ? previousDraft[disk.hctl] : disk.position_led;
        next[disk.hctl] = validLeds.has(previous) ? previous : '';
      });
    } else {
      const validDevices = new Set((data.disks || []).filter((disk) => disk.identity_supported).map((disk) => disk.device));
      (data.slots || []).forEach((slot) => {
        const savedDisk = (data.disks || []).find((disk) => disk.identity_led === slot.led);
        const hasPrevious = preserveDraft && Object.prototype.hasOwnProperty.call(previousDraft, slot.led);
        const previous = hasPrevious ? previousDraft[slot.led] : savedDisk?.device;
        next[slot.led] = validDevices.has(previous) ? previous : '';
      });
    }
    return next;
  }

  function updateLabValidation() {
    const disks = Array.isArray(labState.disks) ? labState.disks : [];
    const positionMode = labMethod === 'position';
    const supported = disks.filter((disk) => positionMode ? disk.position_supported : disk.identity_supported);
    const assigned = Object.values(labDraft).filter(Boolean);
    const unique = new Set(assigned);
    const validation = $('labValidation');
    const save = $('btnSaveLabMapping');
    const valid = assigned.length > 0 && assigned.length === unique.size;
    save.disabled = !labState.active || !valid;
    $('labProgressText').textContent = positionMode ? `已绑定 ${unique.size} 个位置` : `已绑定 ${unique.size} 块硬盘`;

    if (!disks.length) {
      validation.textContent = '未检测到硬盘，请确认硬盘已被系统识别。';
      validation.className = 'lab-validation';
    } else if (!supported.length) {
      validation.textContent = positionMode
        ? '检测到的设备没有可用于位置绑定的 HCTL，暂时无法保存。'
        : '检测到的硬盘没有序列号，暂时无法按硬盘绑定。';
      validation.className = 'lab-validation';
    } else if (!assigned.length) {
      validation.textContent = positionMode ? '请至少为一个硬盘位置选择 LED。' : '请至少为一个 LED 选择硬盘。';
      validation.className = 'lab-validation';
    } else if (assigned.length !== unique.size) {
      validation.textContent = positionMode ? '同一个 LED 不能绑定到多个位置。' : '同一块硬盘不能绑定到多个 LED。';
      validation.className = 'lab-validation';
    } else {
      const remaining = supported.length - unique.size;
      validation.textContent = remaining > 0
        ? positionMode
          ? `映射有效；另有 ${remaining} 个硬盘位置未绑定，保存后对应 LED 将保持未分配。`
          : `映射有效；另有 ${remaining} 块带序列号的硬盘未绑定。`
        : '映射检查通过，可以保存。';
      validation.className = 'lab-validation ok';
    }
  }

  function renderLabInventory() {
    const container = $('labDiskInventory');
    const disks = Array.isArray(labState.disks) ? labState.disks : [];
    container.innerHTML = '';
    if (labMethod === 'position') {
      const positionByLed = {};
      Object.entries(labDraft).forEach(([hctl, led]) => {
        const disk = disks.find((item) => item.hctl === hctl);
        if (led && disk) positionByLed[led] = disk.position;
      });
      (labState.slots || []).forEach((slot) => {
        const card = document.createElement('div');
        const position = positionByLed[slot.led];
        card.className = `lab-disk-card${position ? ' bound' : ''}`;
        const head = document.createElement('div');
        head.className = 'lab-disk-card-head';
        const title = document.createElement('strong');
        title.textContent = slot.led;
        const chip = document.createElement('span');
        chip.className = `state-chip ${position ? 'active' : 'unknown'}`;
        chip.textContent = position ? `位置 ${position}` : '未分配';
        head.append(title, chip);
        const details = document.createElement('p');
        details.textContent = `硬盘灯通道 ${slot.position}`;
        card.append(head, details);
        container.appendChild(card);
      });
      if (!(labState.slots || []).length) {
        const empty = document.createElement('div');
        empty.className = 'lab-empty';
        empty.textContent = '未读取到 LED 通道';
        container.appendChild(empty);
      }
      return;
    }

    const slotByDevice = {};
    Object.entries(labDraft).forEach(([slot, device]) => { if (device) slotByDevice[device] = slot; });
    if (!disks.length) {
      const empty = document.createElement('div');
      empty.className = 'lab-empty';
      empty.textContent = '未检测到硬盘';
      container.appendChild(empty);
      return;
    }

    disks.forEach((disk) => {
      const card = document.createElement('div');
      const boundSlot = slotByDevice[disk.device];
      card.className = `lab-disk-card${boundSlot ? ' bound' : ''}${disk.identity_supported ? '' : ' unsupported'}`;
      const head = document.createElement('div');
      head.className = 'lab-disk-card-head';
      const title = document.createElement('strong');
      title.textContent = disk.device || '未知设备';
      title.title = disk.device || '';
      const chip = document.createElement('span');
      chip.className = `state-chip ${boundSlot ? 'active' : 'unknown'}`;
      chip.textContent = !disk.identity_supported ? '无序列号' : boundSlot ? `LED ${boundSlot.replace('disk', '')}` : '未绑定';
      head.append(title, chip);
      const details = document.createElement('p');
      const identity = [disk.model || '未知型号', disk.size || '未知容量', disk.serial ? `S/N ${disk.serial}` : '无序列号'].join(' · ');
      details.append(document.createTextNode(`${identity} · `));
      const hctl = document.createElement('code');
      hctl.textContent = disk.hctl ? `HCTL ${disk.hctl}` : '无 HCTL';
      details.appendChild(hctl);
      card.append(head, details);
      container.appendChild(card);
    });
  }

  function renderLabWorkspace() {
    const container = $('labSlotList');
    const slots = Array.isArray(labState.slots) ? labState.slots : [];
    const disks = Array.isArray(labState.disks) ? labState.disks : [];
    const selected = new Set(Object.values(labDraft).filter(Boolean));
    container.innerHTML = '';

    if (labMethod === 'position') {
      const positions = disks.filter((disk) => disk.position_supported);
      if (!positions.length) {
        const empty = document.createElement('div');
        empty.className = 'lab-empty';
        empty.textContent = '未读取到带 HCTL 的硬盘位置';
        container.appendChild(empty);
      }
      positions.forEach((disk) => {
        const assignedLed = labDraft[disk.hctl] || '';
        const row = document.createElement('div');
        row.className = `lab-slot-row${labIdentifying === assignedLed ? ' identifying' : ''}`;
        const label = document.createElement('div');
        label.className = 'lab-slot-label';
        const title = document.createElement('strong');
        title.textContent = `硬盘位置 ${disk.position}`;
        const code = document.createElement('small');
        code.textContent = `HCTL ${disk.hctl}`;
        const occupant = document.createElement('span');
        occupant.className = 'lab-position-occupant';
        occupant.textContent = [disk.device, disk.size, disk.model].filter(Boolean).join(' · ');
        label.append(title, code, occupant);

        const select = document.createElement('select');
        select.className = 'lab-disk-select';
        select.setAttribute('aria-label', `硬盘位置 ${disk.position} 对应 LED 通道`);
        const emptyOption = document.createElement('option');
        emptyOption.value = '';
        emptyOption.textContent = '未绑定 LED';
        select.appendChild(emptyOption);
        slots.forEach((slot) => {
          const option = document.createElement('option');
          option.value = slot.led;
          option.textContent = `${slot.led} · LED 通道 ${slot.position}`;
          option.disabled = selected.has(slot.led) && assignedLed !== slot.led;
          select.appendChild(option);
        });
        select.value = assignedLed;
        select.addEventListener('change', () => {
          labDraft[disk.hctl] = select.value;
          renderLabWorkspace();
        });

        const identify = document.createElement('button');
        identify.type = 'button';
        identify.className = 'secondary-button';
        identify.disabled = !assignedLed;
        identify.innerHTML = '<i class="bi bi-lightning-charge" aria-hidden="true"></i>闪烁所选灯';
        identify.addEventListener('click', () => {
          const led = labDraft[disk.hctl];
          if (!led) return;
          setBusy(identify, true);
          api('/lab/mapping/highlight', { method: 'POST', query: `led=${encodeURIComponent(led)}` })
            .then((data) => {
              labIdentifying = led;
              renderLabStatus(data, true);
              showMessage(`硬盘位置 ${disk.position} 选择的 ${led} 正在闪烁`, 'ok');
            })
            .catch(showError)
            .finally(() => setBusy(identify, false));
        });
        row.append(label, select, identify);
        container.appendChild(row);
      });
      renderLabInventory();
      updateLabValidation();
      return;
    }

    const identityDisks = disks.filter((disk) => disk.identity_supported);
    if (!slots.length) {
      const empty = document.createElement('div');
      empty.className = 'lab-empty';
      empty.textContent = '未读取到硬盘灯盘位';
      container.appendChild(empty);
    }

    slots.forEach((slot) => {
      const row = document.createElement('div');
      row.className = `lab-slot-row${labIdentifying === slot.led ? ' identifying' : ''}`;
      const label = document.createElement('div');
      label.className = 'lab-slot-label';
      const title = document.createElement('strong');
      title.textContent = `LED 通道 ${slot.position}`;
      const code = document.createElement('small');
      code.textContent = slot.led;
      label.append(title, code);

      const select = document.createElement('select');
      select.className = 'lab-disk-select';
      select.setAttribute('aria-label', `LED 通道 ${slot.position} 对应硬盘`);
      const emptyOption = document.createElement('option');
      emptyOption.value = '';
      emptyOption.textContent = '未绑定 / 空盘位';
      select.appendChild(emptyOption);
      identityDisks.forEach((disk) => {
        const option = document.createElement('option');
        option.value = disk.device;
        option.textContent = labDiskLabel(disk);
        option.disabled = selected.has(disk.device) && labDraft[slot.led] !== disk.device;
        select.appendChild(option);
      });
      select.value = labDraft[slot.led] || '';
      select.addEventListener('change', () => {
        labDraft[slot.led] = select.value;
        renderLabWorkspace();
      });

      const identify = document.createElement('button');
      identify.type = 'button';
      identify.className = 'secondary-button';
      identify.innerHTML = '<i class="bi bi-lightning-charge" aria-hidden="true"></i>闪烁此灯';
      identify.addEventListener('click', () => {
        setBusy(identify, true);
        api('/lab/mapping/highlight', { method: 'POST', query: `led=${encodeURIComponent(slot.led)}` })
          .then((data) => {
            labIdentifying = slot.led;
            renderLabStatus(data, true);
            showMessage(`${slot.led} 正在闪烁`, 'ok');
          })
          .catch(showError)
          .finally(() => setBusy(identify, false));
      });
      row.append(label, select, identify);
      container.appendChild(row);
    });
    renderLabInventory();
    updateLabValidation();
  }

  function renderLabStatus(data, preserveDraft) {
    const previousDraft = labDraft;
    const mode = ['position', 'disk'].includes(data.mode) ? data.mode : 'auto';
    labState = {
      active: Boolean(data.active),
      mode,
      productName: data.product_name || '',
      profile: data.profile || 'unknown',
      slots: Array.isArray(data.slots) ? data.slots : [],
      disks: Array.isArray(data.disks) ? data.disks : [],
    };
    if (!labState.active && ['position', 'disk'].includes(labState.mode)) labMethod = labState.mode;
    document.body.classList.toggle('lab-session-active', labState.active);
    $('labModeBadge').textContent = labState.mode === 'position'
      ? '当前：位置绑定'
      : labState.mode === 'disk' ? '当前：硬盘绑定' : '当前：自动映射';
    const autoSummary = labState.profile === 'dxp6800'
      ? `已识别 ${labState.productName || 'DXP6800 系列'}，自动使用六盘位专用顺序：HCTL 0/1 → disk5/6，HCTL 2–5 → disk1–4。`
      : `已识别 ${labState.productName || '未知机型'}，自动使用标准 HCTL 顺序。`;
    $('labSummary').textContent = labState.mode === 'position'
      ? '当前使用 HCTL 位置规则：更换硬盘不会改变 LED 对应关系。'
      : labState.mode === 'disk'
        ? '当前使用硬盘序列号规则：设备名变化后，LED 映射仍会跟随具体硬盘。'
        : `${autoSummary} 如果实际机箱灯位乱序，可选择位置绑定手动修正。`;
    $('labSession').hidden = !labState.active;
    $('btnStartLabMapping').disabled = labState.active;
    $('btnStartLabMapping').innerHTML = labState.active
      ? '<i class="bi bi-check2-circle" aria-hidden="true"></i>检测模式已启动'
      : '<i class="bi bi-lightbulb" aria-hidden="true"></i>开始检测并点亮全部硬盘灯';

    updateLabMethodUi();
    if (labState.active) {
      labDraft = buildLabDraft(labState, previousDraft, Boolean(preserveDraft));
      renderLabWorkspace();
    } else {
      labDraft = {};
      labIdentifying = '';
    }
    return data;
  }

  function loadLabMappingStatus() {
    if (labStatusPromise) return labStatusPromise;
    labStatusPromise = api('/lab/mapping/status')
      .then((data) => renderLabStatus(data, labState.active))
      .catch(showError)
      .finally(() => { labStatusPromise = null; });
    return labStatusPromise;
  }

  function startLabMapping(button, preserveDraft) {
    setBusy(button, true);
    return api('/lab/mapping/start', { method: 'POST' })
      .then((data) => {
        labIdentifying = '';
        renderLabStatus(data, Boolean(preserveDraft));
        showMessage(data.message || '检测模式已启动', 'ok');
        return data;
      })
      .catch(showError)
      .finally(() => {
        setBusy(button, false);
        if (button && button.id === 'btnStartLabMapping') button.disabled = labState.active;
      });
  }

  function finishLabMapping(path, button, body, successMessage) {
    setBusy(button, true);
    return api(path, { method: 'POST', body })
      .then((data) => {
        renderLabStatus(data, false);
        showMessage(data.message || successMessage, 'ok');
        return refresh();
      })
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  function setRoute(route, updateHash) {
    let next = ROUTES[route] ? route : 'overview';
    if (next === 'bios' && biosState.loaded && !biosState.supported) next = 'overview';
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
    $('pageDescription').textContent = next === 'lighting' && isPower26Profile()
      ? '控制 DXP480T / Plus 的红白电源灯与硬件灯效。'
      : ROUTES[next].description;
    document.body.classList.toggle('lab-route', next === 'lab');
    document.body.classList.toggle('bios-route', next === 'bios');
    if (updateHash !== false && location.hash !== `#${next}`) history.replaceState(null, '', `#${next}`);
    $('appMain').scrollTo({ top: 0, behavior: 'smooth' });
    if (next === 'lab') loadLabMappingStatus();
    if (next === 'bios') loadBiosStatus();
    if (next === 'devices' && !logsLoaded) loadLogs();
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

  function selectedPower26Value(name, fallback) {
    return document.querySelector(`input[name="${name}"]:checked`)?.value || fallback;
  }

  function setPower26Value(name, value, fallback) {
    const target = document.querySelector(`input[name="${name}"][value="${value}"]`)
      || document.querySelector(`input[name="${name}"][value="${fallback}"]`);
    if (target) target.checked = true;
  }

  function updatePower26Preview(forceOff) {
    const color = selectedPower26Value('power26Color', 'white');
    const effect = selectedPower26Value('power26Effect', 'steady');
    const off = forceOff === undefined ? currentMode === 'off' : forceOff;
    const lamp = $('power26LampPreview');
    lamp.dataset.color = color;
    lamp.dataset.effect = off ? 'off' : effect;
    $('power26PreviewText').textContent = off
      ? '灯光已关闭'
      : `${color === 'red' ? '红色' : '白色'} · ${POWER26_EFFECT_LABELS[effect] || '常亮'}`;
  }

  function syncPower26NetworkOptions() {
    $('power26NetworkOptions').hidden = selectedPower26Value('power26Effect', 'steady') !== 'network';
  }

  function loadPower26Controls(ini) {
    const color = ini.power26?.color === 'red' ? 'red' : 'white';
    const effect = POWER26_EFFECT_LABELS[ini.power26?.effect] ? ini.power26.effect : 'steady';
    setPower26Value('power26Color', color, 'white');
    setPower26Value('power26Effect', effect, 'steady');
    $('power26NetworkThreshold').value = positiveInt(ini.power26?.network_threshold_kbps, 32);
    syncPower26NetworkOptions();
    updatePower26Preview();
  }

  function applyPower26(button, turnOff) {
    if (!isPower26Profile()) {
      showMessage('当前机型未使用 480T 专用电源灯后端', 'err');
      return Promise.resolve();
    }
    const color = selectedPower26Value('power26Color', 'white');
    const effect = turnOff ? 'off' : selectedPower26Value('power26Effect', 'steady');
    const threshold = positiveInt($('power26NetworkThreshold').value, 32);
    setBusy(button, true);
    return api('/power26/apply', { method: 'POST', query: `color=${encodeURIComponent(color)}&effect=${encodeURIComponent(effect)}&threshold=${threshold}` })
      .then((data) => {
        currentMode = data.mode || (turnOff ? 'off' : 'on');
        currentIni.power26 = Object.assign({}, currentIni.power26 || {}, { color });
        if (!turnOff) {
          currentIni.power26.effect = effect;
          currentIni.power26.network_threshold_kbps = String(threshold);
        }
        updateModeUi();
        updatePower26Preview(turnOff);
        showMessage(data.message || (turnOff ? '电源灯已关闭' : '480T 电源灯设置已应用'), 'ok');
        return refresh();
      })
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  function loadUiFromSettings(ini) {
    currentIni = ini || {};
    buildColorGrid('diskGrid', DISK_STATES, 'disk_colors', 'disk_brightness');
    buildColorGrid('netGrid', NET_STATES, 'netdev_colors', 'netdev_brightness');
    buildPowerGrid();
    currentMode = currentIni.mode?.global || 'smart';
    loadPower26Controls(currentIni);
    $('diskBlink').checked = settingBool(currentIni.activity?.disk_blink, ACTIVITY_DEFAULTS.disk_blink);
    $('networkBlink').checked = settingBool(currentIni.activity?.network_blink, ACTIVITY_DEFAULTS.network_blink);
    $('diskBlinkThreshold').value = positiveInt(currentIni.activity?.disk_threshold_kbps, ACTIVITY_DEFAULTS.disk_threshold_kbps);
    $('networkBlinkThreshold').value = positiveInt(currentIni.activity?.network_threshold_kbps, ACTIVITY_DEFAULTS.network_threshold_kbps);
    $('diskPowerProbeInterval').value = boundedInt(currentIni.daemon?.disk_power_probe_interval, 10, 3600, DAEMON_DEFAULTS.disk_power_probe_interval);
    $('hotplugCheckInterval').value = boundedInt(currentIni.daemon?.hotplug_check_interval, 5, 3600, DAEMON_DEFAULTS.hotplug_check_interval);
    $('hardwareBackend').value = ['auto', 'cli'].includes(currentIni.hardware?.backend) ? currentIni.hardware.backend : 'cli';
    $('hardwareWriteProtocol').value = ['auto', 'legacy', 'smbus-block'].includes(currentIni.hardware?.write_protocol) ? currentIni.hardware.write_protocol : 'auto';
    const selectedProfile = currentIni.hardware?.profile || 'auto';
    $('hardwareProfile').value = Array.from($('hardwareProfile').options).some((option) => option.value === selectedProfile) ? selectedProfile : 'auto';
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

  function collectHardwareLines() {
    return [
      `hardware.backend=${$('hardwareBackend').value}`,
      `hardware.profile=${$('hardwareProfile').value}`,
      `hardware.write_protocol=${$('hardwareWriteProtocol').value}`,
    ];
  }

  function saveSettings(button, lines, successMessage) {
    setBusy(button, true);
    return api('/settings', { method: 'POST', body: lines.join('\n') })
      .then(() => api('/daemon/start', { method: 'POST', body: '' }))
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
    return api('/mode', { method: 'POST', query: `mode=${encodeURIComponent(mode)}`, body: '' })
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
    updatePower26Preview();
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
    if (Boolean(data.lab_mapping_active) !== Boolean(labState.active)) loadLabMappingStatus();
  }

  function renderMapping(data) {
    const mapping = Array.isArray(data.mapping) ? data.mapping : [];
    $('overviewDiskCount').textContent = `${mapping.length} 块`;
    fillDiskTable('overviewDiskTable', mapping);
    fillDiskTable('deviceMapTable', mapping);
  }

  function formatBytes(value) {
    const bytes = Math.max(0, Number(value) || 0);
    if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MiB`;
    if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
    return `${bytes} B`;
  }

  function renderLogs(data) {
    logContent = String(data.content || '');
    logsLoaded = true;
    $('logConsole').textContent = logContent || '当前筛选条件下暂无日志。';
    const writeLevel = String(data.write_level || 'info').toLowerCase();
    if (Array.from($('logWriteLevel').options).some((option) => option.value === writeLevel)) {
      $('logWriteLevel').value = writeLevel;
    }
    $('logStatusBadge').textContent = `${writeLevel.toUpperCase()} · ${data.requested_lines || 0} 行上限`;
    const updated = Number(data.updated_at) > 0 ? new Date(Number(data.updated_at) * 1000).toLocaleString() : '尚无日志';
    $('logMeta').textContent = `app.log · ${formatBytes(data.size_bytes)} · 更新于 ${updated}${data.clipped ? ' · 输出已截断' : ''}`;
  }

  function loadLogs(button) {
    if (button) setBusy(button, true);
    const level = $('logFilterLevel')?.value || 'all';
    const lines = $('logLineCount')?.value || '500';
    return api('/logs', { query: `source=application&level=${encodeURIComponent(level)}&lines=${encodeURIComponent(lines)}` })
      .then(renderLogs)
      .catch(showError)
      .finally(() => { if (button) setBusy(button, false); });
  }

  function saveLogLevel(button) {
    const level = $('logWriteLevel').value;
    setBusy(button, true);
    return api('/logs/config', { method: 'POST', query: `level=${encodeURIComponent(level)}`, body: '' })
      .then((data) => {
        showMessage(data.message || `日志级别已切换为 ${level.toUpperCase()}`, 'ok');
        logsLoaded = false;
        return loadLogs();
      })
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  async function copyLogs() {
    if (!logContent) {
      showMessage('当前没有可复制的日志', 'err');
      return;
    }
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(logContent);
      } else {
        const area = document.createElement('textarea');
        area.value = logContent;
        area.style.position = 'fixed';
        area.style.opacity = '0';
        document.body.appendChild(area);
        area.select();
        document.execCommand('copy');
        area.remove();
      }
      showMessage('日志已复制到剪贴板', 'ok');
    } catch (error) {
      showError(error);
    }
  }

  function triggerTextDownload(content, filename) {
    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function downloadLogs() {
    if (!logContent) {
      showMessage('当前没有可下载的日志', 'err');
      return;
    }
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    triggerTextDownload(logContent + '\n', `ugreen-led-application-${stamp}.log`);
  }

  function downloadHardwareDiagnostics(button) {
    setBusy(button, true);
    return api('/hardware/diagnostics')
      .then((data) => {
        if (!data.content) throw new Error('诊断包内容为空');
        triggerTextDownload(data.content + '\n', data.filename || 'ugreen-led-diagnostics.txt');
        showMessage('硬件诊断包已生成并开始下载', 'ok');
      })
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  function clearLogs(button) {
    if (!window.confirm('确定清空 app.log 及其轮转历史吗？此操作无法撤销。')) return;
    setBusy(button, true);
    return api('/logs/clear', { method: 'POST', query: 'confirm=clear-logs', body: '' })
      .then((data) => {
        showMessage(data.message || '应用诊断日志已清空', 'ok');
        logsLoaded = false;
        return loadLogs();
      })
      .catch(showError)
      .finally(() => setBusy(button, false));
  }

  function biosBackendLabel(backend) {
    return {
      port: '/dev/port 直连',
      proc: '原厂 /proc/it86',
      ugreenctl: 'UGREEN-NAS-Hardware',
      unavailable: '不可用',
    }[backend] || backend || '不可用';
  }

  function biosStartupLabel(policy) {
    return { on: '自动开机', off: '保持关机', last: '恢复断电前状态', unknown: '未知' }[policy] || '未知';
  }

  function formatSystemUptime(value) {
    const total = Math.max(0, Math.floor(Number(value) || 0));
    const days = Math.floor(total / 86400);
    const hours = Math.floor((total % 86400) / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    if (days > 0) return `${days} 天 ${hours} 小时 ${minutes} 分钟`;
    if (hours > 0) return `${hours} 小时 ${minutes} 分钟`;
    return `${minutes} 分钟`;
  }

  function formatMemoryMb(value) {
    const mb = Math.max(0, Number(value) || 0);
    return mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : `${Math.round(mb)} MB`;
  }

  function renderBiosSystemInfo(data) {
    const info = data || {};
    const available = Boolean(info.system_hostname || info.system_os || info.system_cpu_model);
    $('biosSystemBadge').textContent = available ? '实时只读' : '信息不可用';
    $('biosSystemHostname').textContent = info.system_hostname || '未读取到';
    $('biosSystemOs').textContent = info.system_os || '未读取到';
    $('biosSystemKernel').textContent = info.kernel || '未读取到';
    $('biosSystemUptime').textContent = formatSystemUptime(info.system_uptime_seconds);
    $('biosSystemCpu').textContent = info.system_cpu_model || '未读取到';
    $('biosSystemThreads').textContent = Number(info.system_cpu_threads) > 0 ? `${info.system_cpu_threads} 线程` : '未读取到';
    const hasTemperature = info.system_cpu_temp_c !== null && info.system_cpu_temp_c !== '' && Number.isFinite(Number(info.system_cpu_temp_c));
    $('biosSystemTemperature').textContent = hasTemperature
      ? `${Number(info.system_cpu_temp_c).toFixed(1)} °C`
      : '传感器未提供';
    const totalMb = Number(info.system_memory_total_mb) || 0;
    const usedMb = Number(info.system_memory_used_mb) || 0;
    $('biosSystemMemory').textContent = totalMb > 0
      ? `${formatMemoryMb(usedMb)} / ${formatMemoryMb(totalMb)} · ${Number(info.system_memory_percent) || 0}%`
      : '未读取到';
    const loads = [info.system_load_1, info.system_load_5, info.system_load_15]
      .map((value) => Number(value))
      .map((value) => Number.isFinite(value) ? value.toFixed(2) : '—');
    $('biosSystemLoad').textContent = loads.join(' / ');
  }

  function setBiosPwmControl(prefix, value) {
    const current = $(`${prefix}FanCurrentPwm`);
    if (Number.isFinite(Number(value)) && Number(value) >= 0) {
      const bounded = boundedInt(value, 0, 255, 0);
      current.textContent = String(bounded);
      setBiosPwmEditor(prefix, bounded);
    } else {
      current.textContent = '未提供';
    }
  }

  function setBiosPwmEditor(prefix, value) {
    if (!Number.isFinite(Number(value)) || Number(value) < 0) return;
    const bounded = boundedInt(value, 0, 255, 0);
    $(`${prefix}FanPwmRange`).value = String(bounded);
  }

  function biosPwmValue(value) {
    const number = Number(value);
    return Number.isInteger(number) && number >= 0 && number <= 255 ? number : null;
  }

  function biosPwmText(value) {
    const pwm = biosPwmValue(value);
    return pwm === null ? '—' : String(pwm);
  }

  function biosFanTarget(prefix) {
    if (prefix === 'cpu') return 'cpu';
    return biosState.fan_write_target === 'all' ? 'all' : 'sys';
  }

  function biosWriteConfirmed() {
    return !biosState.write_confirmation_required || Boolean($('biosExperimentalConfirmInput').checked);
  }

  function biosWriteQuery(query) {
    return biosState.write_confirmation_required && biosWriteConfirmed()
      ? `${query}&confirm=${biosState.direct_fan_fallback && !['dxp4800s', 'dxp6800pro'].includes(biosState.model) ? 'direct-superio' : 'firmware-reversed'}`
      : query;
  }

  function setBiosFanWriteStatus(prefix, state, message) {
    const writeState = biosFanWrites[prefix];
    const status = $(`${prefix}FanWriteStatus`);
    const icon = status.querySelector('i');
    const label = status.querySelector('span');
    clearTimeout(writeState.statusTimer);
    writeState.statusTimer = null;
    status.className = `bios-fan-write-status${state ? ` is-${state}` : ''}`;
    icon.className = state === 'saving'
      ? 'bi bi-arrow-repeat'
      : state === 'saved'
        ? 'bi bi-check2-circle'
        : state === 'error' ? 'bi bi-exclamation-circle' : 'bi bi-lightning-charge';
    label.textContent = message;
  }

  function resetBiosFanWriteStatus(prefix) {
    if (!biosState.available) {
      setBiosFanWriteStatus(prefix, '', '当前不可写入');
    } else if (!biosWriteConfirmed()) {
      setBiosFanWriteStatus(prefix, '', '请先确认固件逆向写入风险');
    } else {
      setBiosFanWriteStatus(prefix, '', '调整后写入手动 PWM，并由 hwmon 回读校验');
    }
  }

  function updateBiosFanEditorState(prefix) {
    const available = Boolean(biosState.available);
    const writeState = biosFanWrites[prefix];
    const fanPresent = prefix !== 'cpu' || biosState.cpu_fan_present !== false;
    const writable = available && fanPresent && biosWriteConfirmed() && !writeState.busy;
    $(`${prefix}FanPwmRange`).disabled = !writable;
  }

  function updateBiosWriteAvailability() {
    const startupAvailable = Boolean(biosState.startup_available) && biosWriteConfirmed();
    updateBiosFanEditorState('cpu');
    updateBiosFanEditorState('sys');
    $('btnApplyBiosStartup').disabled = !startupAvailable;
    document.querySelectorAll('input[name="biosStartupPolicy"]').forEach((input) => {
      input.disabled = !startupAvailable;
    });
  }

  function renderBios(data) {
    biosState = Object.assign({ loaded: true, supported: false, available: false }, data || {}, { loaded: true });
    applyBiosRouting();
    const available = Boolean(biosState.available);
    const startupAvailable = Boolean(biosState.startup_available);
    const is480t = biosState.model === 'dxp480t_plus';
    const is4800s = biosState.model === 'dxp4800s';
    const is6800 = biosState.model === 'dxp6800pro';
    const directFallback = Boolean(biosState.direct_fan_fallback);
    const is4800Pro = biosState.model === 'dxp4800_pro';
    const minPwm = Math.max(0, Number(biosState.min_pwm) || 0);
    $('biosAvailabilityBadge').textContent = !biosState.supported
      ? '非适用机型'
      : available ? '风扇 hwmon 就绪' : startupAvailable ? '仅来电启动就绪' : '控制器不可用';
    $('biosAvailabilityText').textContent = !biosState.supported
      ? '此入口仅对 DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro 开放。'
      : available
        ? directFallback
          ? is480t
            ? `it87 已卸载，风扇通过 DXP480T Plus 原厂共享 Super I/O PWM 路径读取和写入；sys2 仅报告转速。来电启动${startupAvailable ? '也可用' : `独立不可用：${biosState.startup_error || '读取失败'}`}。`
            : is6800
              ? `it87 已卸载，风扇通过 DXP6800 Pro 固件证明的直控路径读取和写入；CPU 可单独设置，sys 会同步系统风扇 1/2。来电启动${startupAvailable ? '也可用' : `独立不可用：${biosState.startup_error || '读取失败'}`}。`
              : `it87 已卸载，风扇通过受保护的 IT8613 直控路径读取和写入；来电启动${startupAvailable ? '也可用' : `独立不可用：${biosState.startup_error || '读取失败'}`}。`
          : `已动态找到 name=it8613 的 hwmon 节点，风扇通过现有 it87 驱动读取和写入；来电启动${startupAvailable ? '也可用' : `独立不可用：${biosState.startup_error || '读取失败'}`}。`
        : startupAvailable
          ? `来电启动可用，但风扇 hwmon 不可用：${biosState.fan_error || biosState.error || '未找到 name=it8613 的节点'}。`
          : biosState.fan_error || biosState.error || '没有找到可用的 BIOS 控制接口。';
    $('biosModelKicker').textContent = is6800
      ? 'DXP6800 PRO · IT8613 · FIRMWARE-REVERSED'
      : is4800s
      ? 'DXP4800S · IT8613 · FIRMWARE-REVERSED'
      : is480t ? 'DXP480T PLUS · IT8613 · VERIFIED' : `DXP4800 ${is4800Pro ? 'PRO' : 'PLUS'} · IT8613`;
    $('biosPwmRangeBadge').textContent = `${minPwm}–255`;
    $('biosFanSafetyText').textContent = is480t
      ? directFallback
        ? '当前未使用 it87。直控会复现 480T Plus 原厂的共享 PWM 路径；sys2 仅测速，不会单独写入。PWM 最低为 40。'
        : '只开放手动 PWM。全部风扇通过现有 it87 hwmon 节点写入并回读；PWM 最低为 40。'
      : is6800
        ? '只开放手动 PWM。CPU 可单独设置；系统风扇 1/2 会按原厂成对路径同步写入并回读。该固件逆向映射尚待实机验证，PWM 最低为 40。'
      : '只开放手动 PWM，写入后会回读校验，PWM 最低为 40。原厂自动调速是软件温控曲线，不会用 pwm*_enable=2 冒充。';
    $('biosProductName').textContent = biosState.product_name || '未读取到';
    $('biosChipId').textContent = biosState.chip_id
      ? `${biosState.chip_id} · Rev ${biosState.revision ?? 0}`
      : '未读取';
    $('biosBackendName').textContent = biosBackendLabel(biosState.backend);
    $('biosStartupSummary').textContent = startupAvailable ? biosStartupLabel(biosState.startup) : '不可用';
    $('biosStartupBadge').textContent = startupAvailable ? biosStartupLabel(biosState.startup) : '独立不可用';
    $('biosStartupHelp').textContent = startupAvailable
      ? '来电启动与风扇控制独立读取和写入。该设置使用 UGREEN-NAS-Hardware 的受保护 Super I/O 路径。'
      : `来电启动当前不可用，但不会影响风扇控制：${biosState.startup_error || '读取失败'}。`;
    $('cpuFanRpm').textContent = available ? String(biosState.cpu_rpm ?? 0) : '—';
    $('sysFanRpm').textContent = available ? String(biosState.sys_rpm ?? 0) : '—';
    $('sys2FanRpm').textContent = available ? String(biosState.sys2_rpm ?? 0) : '—';
    $('biosSys2RpmRow').hidden = !(is480t || is6800);
    $('cpuFanCard').hidden = biosState.cpu_fan_present === false;
    $('cpuFanTitle').textContent = is480t && directFallback ? 'CPU / 共享输出' : 'CPU 风扇';
    $('sysFanEyebrow').textContent = is480t && directFallback ? 'SHARED FAN PWM' : is480t ? 'ALL FANS' : is6800 ? 'SYSTEM FAN PAIR' : 'SYSTEM FAN';
    $('sysFanTitle').textContent = is480t && directFallback ? '共享风扇 PWM' : is480t ? '全部风扇' : is6800 ? '系统风扇（成对）' : is4800s ? '系统风扇 sysfan1' : '系统风扇';
    $('sysFanRpmLabel').textContent = is480t || is6800 ? 'SYS 1 RPM' : 'RPM';
    setBiosPwmControl('cpu', biosState.cpu_pwm);
    if (is480t && directFallback) {
      const sharedPwm = biosPwmValue(biosState.sys_pwm) ?? biosPwmValue(biosState.cpu_pwm);
      $('biosAllFanPwmRow').hidden = false;
      $('allCpuFanPwm').textContent = biosPwmText(sharedPwm);
      $('allSys1FanPwm').textContent = biosPwmText(sharedPwm);
      $('allSys2FanPwm').textContent = '仅测速';
      $('sysFanCurrentPwm').textContent = biosPwmText(sharedPwm);
      if (sharedPwm !== null) setBiosPwmEditor('sys', sharedPwm);
      $('sysFanMode').textContent = '原厂共享 PWM · sys2 不单独写入';
    } else if (is480t) {
      const allPwmValues = [biosState.cpu_pwm, biosState.sys_pwm, biosState.sys2_pwm].map(biosPwmValue);
      const knownPwmValues = allPwmValues.filter((value) => value !== null);
      const allKnown = knownPwmValues.length === 3;
      const allSame = allKnown && knownPwmValues.every((value) => value === knownPwmValues[0]);
      $('biosAllFanPwmRow').hidden = false;
      $('allCpuFanPwm').textContent = biosPwmText(biosState.cpu_pwm);
      $('allSys1FanPwm').textContent = biosPwmText(biosState.sys_pwm);
      $('allSys2FanPwm').textContent = biosPwmText(biosState.sys2_pwm);
      $('sysFanCurrentPwm').textContent = allSame ? String(knownPwmValues[0]) : allKnown ? '多值' : '未提供';
      if (knownPwmValues.length > 0) setBiosPwmEditor('sys', Math.max(...knownPwmValues));
      const pwmText = allSame
        ? 'PWM 一致'
        : allKnown ? 'PWM 不同，手动应用后将统一' : 'PWM 读取不完整';
      $('sysFanMode').textContent = `仅开放手动 PWM · ${pwmText}`;
    } else if (is6800) {
      const systemPwmValues = [biosState.sys_pwm, biosState.sys2_pwm].map(biosPwmValue);
      const knownPwmValues = systemPwmValues.filter((value) => value !== null);
      const allKnown = knownPwmValues.length === 2;
      const allSame = allKnown && knownPwmValues.every((value) => value === knownPwmValues[0]);
      $('biosAllFanPwmRow').hidden = false;
      $('allCpuFanPwm').textContent = biosPwmText(biosState.cpu_pwm);
      $('allSys1FanPwm').textContent = biosPwmText(biosState.sys_pwm);
      $('allSys2FanPwm').textContent = biosPwmText(biosState.sys2_pwm);
      $('sysFanCurrentPwm').textContent = allSame ? String(knownPwmValues[0]) : allKnown ? '多值' : '未提供';
      if (knownPwmValues.length > 0) setBiosPwmEditor('sys', Math.max(...knownPwmValues));
      $('sysFanMode').textContent = allSame
        ? '原厂成对系统 PWM · 写入 sys 会同步两路'
        : allKnown ? '两路 PWM 不同；写入 sys 会同步两路' : '系统 PWM 读取不完整';
    } else {
      $('biosAllFanPwmRow').hidden = true;
      setBiosPwmControl('sys', biosState.sys_pwm);
    }
    ['cpuFanPwmRange', 'sysFanPwmRange'].forEach((id) => {
      $(id).min = String(minPwm);
      if (Number($(id).value) < minPwm) $(id).value = String(minPwm);
    });
    $('cpuFanMode').textContent = is480t && directFallback ? '原厂共享 PWM 输出' : '仅开放手动 PWM';
    if (!is480t && !is6800) $('sysFanMode').textContent = '仅开放手动 PWM；原厂自动由软件温控曲线实现';
    $('biosGuardTitle').textContent = directFallback && is480t ? '480T Plus 原厂共享直控保护' : directFallback ? 'IT8613 直控保护' : is6800 ? 'DXP6800 Pro 固件逆向保护' : is4800s ? '4800S 固件逆向保护' : is480t ? '480T Plus 已验证保护' : '4800 系列专属保护';
    $('biosGuardText').textContent = directFallback
      ? is480t
        ? '检测到 it87 已卸载：DXP480T Plus 只会复现原厂共享 PWM 输出，不会猜测 sys2 寄存器。无原厂控制器占用、IT8613 芯片 ID 匹配并取得进程锁后才允许写入；写入附加 --force --apply、最低 PWM 40 并回读。'
        : '检测到 it87 已卸载：将仅在无原厂控制器占用、IT8613 芯片 ID 匹配并取得进程锁后使用直控兜底。写入附加 --force --apply、最低 PWM 40 并逐项回读；请先确认风险。'
      : is6800
      ? '仅精确 DMI 为 DXP6800 Pro 且动态 hwmon 名称为 it8613 时开放。CPU 可单独写入；sys 会按固件证明同步系统风扇 1/2。所有写入附加 --force --apply、最低 PWM 40，并执行进程锁和回读校验。'
      : is4800s
      ? '仅精确 DMI 为 DXP4800S 且动态 hwmon 名称为 it8613 时开放。写入附加 --force --apply，最低 PWM 40，并执行进程锁和回读校验。'
      : is480t
        ? '仅精确 DMI 识别为 DXP480T Plus 且动态 hwmon 名称为 it8613 时开放；保留 it87，不卸载模块，PWM 低于 40 会被拒绝。'
        : '页面和写入接口只在 DMI 精确匹配且找到 name=it8613 的 hwmon 节点时启用；保留现有 it87 驱动。';
    $('biosExperimentalConfirm').hidden = !biosState.write_confirmation_required;
    $('biosExperimentalConfirmTitle').textContent = directFallback
      ? '我已了解 IT8613 直控写入风险'
      : '我已了解固件逆向写入风险';
    $('biosExperimentalConfirmText').textContent = directFallback
      ? is480t
        ? '我已确认 it87 已主动卸载，已准备独立温度监控与恢复原控制方式，并接受 DXP480T Plus 仅使用原厂共享 PWM 直控、sys2 不单独写入。'
        : '我已确认 it87 已主动卸载，已准备独立温度监控与恢复原控制方式，并接受该机型直控写入尚待实机记录。'
      : is6800
        ? '已准备独立温度监控与恢复原厂控制的方案，并接受当前尚无 DXP6800 Pro 实机写入验证。'
        : '已准备独立温度监控与恢复原厂控制的方案，并接受当前尚无 DXP4800S 实机写入验证。';
    if (currentRoute === 'bios') $('pageDescription').textContent = is6800
      ? 'DXP6800 Pro 的三路风扇状态、固件逆向 CPU/成对系统 PWM 与来电启动控制；写入前必须确认风险。'
      : is4800s
      ? 'DXP4800S 的单路系统风扇、固件逆向 PWM 与来电启动控制；写入前必须确认风险。'
      : is480t
        ? directFallback
          ? 'DXP480T Plus 的三路转速与原厂共享 PWM 直控；sys2 仅测速。'
          : 'DXP480T Plus 的 IT8613 三风扇状态、已验证 PWM 与来电启动控制。'
        : ROUTES.bios.description;
    document.querySelectorAll('input[name="biosStartupPolicy"]').forEach((input) => {
      input.checked = input.value === biosState.startup;
      input.closest('.bios-policy-choice')?.classList.toggle('active', input.checked);
    });
    updateBiosWriteAvailability();
    ['cpu', 'sys'].forEach((prefix) => {
      if (!biosFanWrites[prefix].busy) resetBiosFanWriteStatus(prefix);
    });
  }

  function loadBiosStatus() {
    return api('/bios/status')
      .then(renderBios)
      .catch((error) => {
        biosState = { loaded: true, supported: false, available: false, error: error.message };
        applyBiosRouting();
        console.error('[UGreenLED] BIOS status failed', error);
      });
  }

  function runBiosAction(button, promise) {
    const icon = button?.querySelector('i');
    const iconClass = icon?.className || '';
    if (icon) icon.className = 'bi bi-arrow-repeat';
    setBusy(button, true);
    return promise
      .then((data) => {
        renderBios(data);
        showMessage(data.message || 'BIOS 设置已应用', 'ok');
      })
      .catch(showError)
      .finally(() => {
        if (icon) icon.className = iconClass;
        setBusy(button, false);
        updateBiosWriteAvailability();
      });
  }

  function queueBiosFanWrite(prefix, requestFactory, successMessage) {
    const writeState = biosFanWrites[prefix];
    const revision = ++writeState.revision;
    writeState.busy = true;
    setBiosFanWriteStatus(prefix, 'saving', '正在写入硬件…');
    updateBiosFanEditorState(prefix);

    const request = writeState.queue.catch(() => {}).then(requestFactory);
    writeState.queue = request.catch(() => {});
    return request
      .then((data) => {
        if (revision !== writeState.revision) return data;
        renderBios(data);
        setBiosFanWriteStatus(prefix, 'saved', successMessage);
        writeState.statusTimer = setTimeout(() => {
          if (!writeState.busy && revision === writeState.revision) resetBiosFanWriteStatus(prefix);
        }, 1600);
        return data;
      })
      .catch((error) => {
        if (revision === writeState.revision) {
          renderBios(biosState);
          setBiosFanWriteStatus(prefix, 'error', error?.message || '写入失败，请重试');
          showError(error);
        }
        throw error;
      })
      .finally(() => {
        if (revision === writeState.revision) {
          writeState.busy = false;
          updateBiosFanEditorState(prefix);
        }
      });
  }

  function scheduleBiosFanPwm(prefix, delay, strict) {
    const writeState = biosFanWrites[prefix];
    const input = $(`${prefix}FanPwmRange`);
    const minimum = Math.max(0, Number(biosState.min_pwm) || 0);
    const pwm = Number(input.value);
    clearTimeout(writeState.timer);
    writeState.timer = null;
    if (!Number.isInteger(pwm) || pwm < minimum || pwm > 255) {
      setBiosFanWriteStatus(
        prefix,
        strict ? 'error' : '',
        strict ? `请输入 ${minimum}–255 的整数 PWM` : `继续输入 ${minimum}–255 的 PWM`,
      );
      return;
    }
    setBiosFanWriteStatus(prefix, '', `PWM ${pwm} 即将自动应用`);
    writeState.timer = setTimeout(() => {
      writeState.timer = null;
      const channel = biosFanTarget(prefix);
      queueBiosFanWrite(
        prefix,
        () => api('/bios/fan', { method: 'POST', query: biosWriteQuery(`channel=${channel}&pwm=${pwm}`) }),
        `PWM ${pwm} 已应用`,
      ).catch(() => {});
    }, Math.max(0, delay));
  }

  function renderHardware(data) {
    hardwareState = data || {};
    renderBiosSystemInfo(data);
    const supportLabels = { stable: '已验证', experimental: '实验性', unverified: '待验证', limited: '受限支持', unsupported: '暂不支持', unknown: '未知机型' };
    $('hardwareSupportBadge').textContent = supportLabels[data.support] || data.support || '未知';
    $('hardwareDetectedModel').textContent = `DMI：${data.product_name || '未读取到'} · 当前档案：${data.profile_name || data.profile || '未知'} · CLI ${data.cli_version || '未知'} · 内核 ${data.kernel || '未知'}`;
    $('hardwareActiveBackend').textContent = data.backend_active === 'sysfs'
      ? '内核驱动 / sysfs'
      : data.backend_active === 'cli'
        ? '内置 CLI'
        : data.backend_active === 'power-0x26' ? 'N76E003 电源灯控制' : '不可用';
    $('hardwareProtocol').textContent = data.write_protocol || 'legacy';
    $('hardwareLayout').textContent = `${data.netdev_count ?? 1} 网络灯 · ${data.disk_count ?? 0} 硬盘灯`;
    $('hardwareKernelState').textContent = data.backend_active === 'power-0x26'
      ? '独立电源灯控制器'
      : data.driver_loaded
      ? '驱动已加载'
      : data.dkms_ready && data.headers_ready ? '可安装驱动' : 'CLI 模式';
    const messages = [];
    if (data.it87_loaded) messages.push('检测到 it87：这是 BIOS 风扇控制的正常依赖，会保留且不会被本应用卸载。若另装第三方灯光插件后出现灯光或部分功能不可用，请先停用该插件，避免同时占用 LED 控制器。');
    if (data.led_plugin_conflict) messages.push(`检测到可能占用 LED 控制器的内核模块：${data.led_plugin_modules || '未知模块'}。灯光仅由 bundled ugreen_leds_cli 控制；请停用该插件后重启灯光服务。`);
    if (data.driver_conflict) messages.push('检测到厂商 LED 内核模块，实验驱动安装已禁用。');
    if (data.driver_loaded && data.driver_managed) messages.push('修改机型档案或写入协议后，请点击“安装 / 重建实验驱动”让模块参数生效。');
    if (!data.headers_ready) messages.push('当前内核 headers 不可用，不能编译 DKMS；内置 CLI 不受影响。');
    if (data.support === 'experimental' || data.support === 'unverified') messages.push('此机型需要实机验证，请先在实验室逐灯确认。');
    if (data.support === 'limited') messages.push('此机型使用独立 N76E003 控制器，仅支持红/白电源灯；没有硬盘灯和网络灯。');
    if (data.backend_active === 'unavailable') messages.push('所选后端不可用或 CLI 与内核驱动发生冲突。');
    $('hardwareMessage').textContent = messages.join(' ');
    const sysfsOption = Array.from($('hardwareBackend').options).find((option) => option.value === 'sysfs');
    if (sysfsOption) sysfsOption.disabled = true;
    document.querySelectorAll('[data-backend-guide]').forEach((item) => {
      const active = item.dataset.backendGuide === data.backend_active;
      item.classList.toggle('is-active', active);
      const currentTag = item.querySelector('.hardware-current-tag');
      if (currentTag) currentTag.hidden = !active;
    });
    $('btnInstallDriver').disabled = data.driver_supported === false || data.support === 'unsupported' || Boolean(data.driver_conflict) || !data.dkms_ready || !data.headers_ready || Boolean(data.dkms_registered && !data.driver_managed);
    $('btnUnloadDriver').disabled = !data.driver_loaded || !data.driver_managed;
    applyHardwareRouting();
  }

  function refresh() {
    if (refreshPromise) return refreshPromise;
    const button = $('btnRefresh');
    setBusy(button, true);
    const statusRequest = api('/status').then(renderStatus);
    const mappingRequest = api('/mapping').then(renderMapping);
    const hardwareRequest = api('/hardware/status').then(renderHardware);
    const biosRequest = loadBiosStatus();
    refreshPromise = Promise.all([statusRequest, mappingRequest, hardwareRequest, biosRequest])
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
  document.querySelectorAll('input[name="power26Color"], input[name="power26Effect"]').forEach((input) => {
    input.addEventListener('change', () => {
      syncPower26NetworkOptions();
      updatePower26Preview(false);
    });
  });
  $('btnPower26Apply').addEventListener('click', function () {
    applyPower26(this, false);
  });
  $('btnPower26Off').addEventListener('click', function () {
    applyPower26(this, true);
  });
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
  $('btnSaveHardware').addEventListener('click', function () {
    if ($('hardwareBackend').value === 'cli' && hardwareState.driver_loaded) {
      showMessage('内核驱动仍在占用 MCU，请先点击“卸载驱动并切回 CLI”', 'err');
      return;
    }
    if ($('hardwareBackend').value === 'sysfs' && !hardwareState.sysfs_ready) {
      showMessage('sysfs 后端尚未就绪，请先安装并成功探测实验驱动', 'err');
      return;
    }
    saveSettings(this, collectHardwareLines(), '硬件设置已保存');
  });
  $('btnInstallDriver').addEventListener('click', function () {
    if (!window.confirm('实验驱动会针对当前 fnOS 内核编译模块，并暂时停止 LED 后台服务。确认继续吗？')) return;
    runAction(this, api('/driver/install', { method: 'POST', query: 'confirm=install-driver', body: '' }), '内核驱动已安装');
  });
  $('btnUnloadDriver').addEventListener('click', function () {
    if (!window.confirm('将卸载本应用管理的 led-ugreen 模块并切回内置 CLI。确认继续吗？')) return;
    runAction(this, api('/driver/unload', { method: 'POST', query: 'confirm=unload-driver', body: '' }), '已切回 CLI 后端');
  });
  $('btnRemap').addEventListener('click', function () {
    runAction(this, api('/remap', { method: 'POST', body: '' }), '硬盘映射已更新');
  });
  $('btnDaemonStart').addEventListener('click', function () {
    runAction(this, api('/daemon/start', { method: 'POST', body: '' }), '后台服务已启动');
  });
  $('btnDaemonStop').addEventListener('click', function () {
    runAction(this, api('/daemon/stop', { method: 'POST', body: '' }), '后台服务已停止');
  });
  $('btnRefreshLogs').addEventListener('click', function () { loadLogs(this); });
  $('btnSaveLogLevel').addEventListener('click', function () { saveLogLevel(this); });
  $('btnCopyLogs').addEventListener('click', copyLogs);
  $('btnDownloadLogs').addEventListener('click', downloadLogs);
  $('btnDownloadDiagnostics').addEventListener('click', function () { downloadHardwareDiagnostics(this); });
  $('btnClearLogs').addEventListener('click', function () { clearLogs(this); });
  $('logFilterLevel').addEventListener('change', () => loadLogs());
  $('logLineCount').addEventListener('change', () => loadLogs());
  $('btnCheckUpdate').addEventListener('click', function () {
    checkForUpdates(true, this);
  });
  [
    ['cpu', 'cpuFanPwmRange'],
    ['sys', 'sysFanPwmRange'],
  ].forEach(([prefix, rangeId]) => {
    $(rangeId).addEventListener('input', function () {
      clearTimeout(biosFanWrites[prefix].timer);
      biosFanWrites[prefix].timer = null;
      setBiosFanWriteStatus(prefix, '', `PWM ${this.value}，松开后自动应用`);
    });
    $(rangeId).addEventListener('change', function () {
      scheduleBiosFanPwm(prefix, 0, true);
    });
  });
  $('btnApplyBiosStartup').addEventListener('click', function () {
    const selected = document.querySelector('input[name="biosStartupPolicy"]:checked');
    if (!selected) {
      showMessage('请选择来电启动策略', 'err');
      return;
    }
    runBiosAction(this, api('/bios/startup', { method: 'POST', query: biosWriteQuery(`policy=${selected.value}`) }));
  });
  $('biosExperimentalConfirmInput').addEventListener('change', () => {
    updateBiosWriteAvailability();
    ['cpu', 'sys'].forEach((prefix) => {
      if (!biosFanWrites[prefix].busy) resetBiosFanWriteStatus(prefix);
    });
  });
  document.querySelectorAll('input[name="biosStartupPolicy"]').forEach((input) => {
    input.addEventListener('change', () => {
      document.querySelectorAll('input[name="biosStartupPolicy"]').forEach((candidate) => {
        candidate.closest('.bios-policy-choice')?.classList.toggle('active', candidate.checked);
      });
    });
  });
  document.querySelectorAll('[data-lab-method]').forEach((button) => {
    button.addEventListener('click', () => {
      if (labState.active) return;
      labMethod = button.dataset.labMethod === 'disk' ? 'disk' : 'position';
      labDraft = {};
      updateLabMethodUi();
    });
  });
  $('btnStartLabMapping').addEventListener('click', function () {
    startLabMapping(this, false);
  });
  $('btnShowAllLabLeds').addEventListener('click', function () {
    startLabMapping(this, true);
  });
  $('btnCancelLabMapping').addEventListener('click', function () {
    if (!window.confirm('确定取消本次检测吗？尚未保存的盘位选择会丢失。')) return;
    finishLabMapping('/lab/mapping/cancel', this, '', '已退出检测模式');
  });
  $('btnResetLabMapping').addEventListener('click', function () {
    if (!window.confirm('确定恢复自动 HCTL 映射吗？已保存的自定义盘位规则将停用。')) return;
    finishLabMapping('/lab/mapping/reset', this, '', '已恢复自动映射');
  });
  $('btnSaveLabMapping').addEventListener('click', function () {
    let path;
    let message;
    let lines;
    if (labMethod === 'position') {
      path = '/lab/position/save';
      message = '灯光与硬盘位置绑定已保存';
      lines = labState.disks.map((disk) => {
        const led = labDraft[disk.hctl];
        return led && disk.position_supported ? `${led}|${disk.device}|${disk.hctl}` : '';
      }).filter(Boolean);
    } else {
      path = '/lab/mapping/save';
      message = '按硬盘绑定已保存';
      const diskByDevice = new Map(labState.disks.map((disk) => [disk.device, disk]));
      lines = labState.slots.map((slot) => {
        const device = labDraft[slot.led];
        const disk = diskByDevice.get(device);
        return device && disk && disk.identity_supported ? `${slot.led}|${device}|${disk.serial}` : '';
      }).filter(Boolean);
    }
    if (!lines.length) {
      updateLabValidation();
      return;
    }
    finishLabMapping(path, this, lines.join('\n'), message);
  });

  window.addEventListener('hashchange', () => setRoute(location.hash.slice(1), false));

  setLightingPanel(currentLightingPanel);
  setRoute(location.hash.slice(1) || 'overview', false);
  Promise.all([loadSettings(), refresh(), checkForUpdates(false)]);
  setInterval(() => {
    if (!document.hidden) refresh();
  }, 10000);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refresh();
  });
})();
