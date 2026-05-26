(function () {
  const API = '/cgi/ThirdParty/App.Native.UGreenLED/api.cgi';

  const DISK_STATES = [
    { key: 'active', label: '活动', def: '0 255 0', br: 128 },
    { key: 'idle', label: '空闲', def: '255 255 0', br: 64 },
    { key: 'standby', label: '休眠', def: '0 100 255', br: 40 },
    { key: 'deep_sleep', label: '深度睡眠', def: '40 0 80', br: 24 },
    { key: 'offline', label: '离线/拔出', def: 'off', br: 0, isOff: true },
  ];

  const NET_STATES = [
    { key: 'disconnected', label: '断网', def: '255 0 0', br: 64 },
    { key: 'connected', label: '联网', def: '0 80 255', br: 48 },
    { key: 'vpn', label: '外网', def: '160 0 255', br: 64 },
  ];

  const NET_LABELS = { disconnected: '断网', connected: '联网', vpn: '外网' };
  const DISK_STATE_LABELS = {
    active: '活动',
    idle: '空闲',
    standby: '休眠',
    deep_sleep: '深度睡眠',
    offline: '离线/拔出',
    unknown: '未知',
    error: '异常',
    '?': '未知',
  };

  /** 一键配色方案（套用后需点保存） */
  const COLOR_PRESETS = {
    classic: {
      name: '经典（默认）',
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
      name: '白色系（清爽）',
      ini: {
        disk_colors: { active: '255 255 255', idle: '220 220 220', standby: '160 160 160', deep_sleep: '90 90 90', offline: 'off' },
        disk_brightness: { active: '72', idle: '48', standby: '32', deep_sleep: '18', offline: '0' },
        netdev_colors: { disconnected: '120 120 120', connected: '255 255 255', vpn: '255 255 255' },
        netdev_brightness: { disconnected: '32', connected: '48', vpn: '64' },
        power: { smart_color: '200 200 200', all_on_color: '255 255 255', brightness: '40' },
      },
    },
  };

  const POWER_FIELDS = [
    { key: 'smart_color', label: '智能模式', def: '100 100 100' },
    { key: 'all_on_color', label: '全开模式', def: '180 180 180' },
    { key: 'brightness', label: '亮度', def: '40', isBright: true },
  ];

  let currentMode = 'smart';

  function showErr(e) {
    const msg = (e && e.message) ? e.message : String(e);
    const bar = document.getElementById('statusBar');
    if (bar) bar.textContent = 'API 请求失败: ' + msg;
    const am = document.getElementById('actionMsg');
    if (am) {
      am.textContent = msg;
      am.className = 'action-msg err';
      am.style.display = 'block';
    }
    console.error('[UGreenLED]', e);
  }

  function showOk(msg) {
    const am = document.getElementById('actionMsg');
    if (am) {
      am.textContent = msg;
      am.className = 'action-msg ok';
      am.style.display = 'block';
    }
  }

  function runAction(btn, label, req) {
    if (btn) btn.classList.add('busy');
    showOk(label + '…');
    const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error(label + '超时，请稍后重试。')), 10000));
    return Promise.race([req, timeout])
      .then((d) => {
        showOk(d.message || label + '完成');
        return refresh();
      })
      .catch(showErr)
      .finally(() => {
        if (btn) btn.classList.remove('busy');
      });
  }

  function api(path, opts) {
    const url = API + path + (opts && opts.query ? '?' + opts.query : '');
    return fetch(url, {
      method: (opts && opts.method) || 'GET',
      headers: opts && opts.body ? { 'Content-Type': 'text/plain' } : {},
      body: opts && opts.body,
      credentials: 'same-origin',
      cache: 'no-store',
    }).then(async (r) => {
      const text = await r.text();
      let data;
      try {
        data = JSON.parse(text);
      } catch (err) {
        throw new Error(text.slice(0, 120) || 'HTTP ' + r.status);
      }
      if (data && data.ok === false) {
        const hint = data.path ? ` [${data.path}]` : '';
        throw new Error((data.error || 'unknown') + hint);
      }
      return data;
    });
  }

  function rgbToHex(r, g, b) {
    return '#' + [r, g, b].map((x) => Number(x).toString(16).padStart(2, '0')).join('');
  }

  function hexToRgb(hex) {
    const m = hex.match(/^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i);
    return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : [128, 128, 128];
  }

  function parseIni(raw) {
    const data = {};
    let sec = '';
    if (!raw) return data;
    raw.split('\n').forEach((line) => {
      line = line.trim();
      if (!line || line.startsWith('#')) return;
      const sm = line.match(/^\[([^\]]+)\]/);
      if (sm) {
        sec = sm[1];
        data[sec] = data[sec] || {};
        return;
      }
      const eq = line.indexOf('=');
      if (eq > 0 && sec) {
        data[sec][line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
      }
    });
    return data;
  }

  function buildGrid(containerId, items, sectionColors, sectionBright) {
    const grid = document.getElementById(containerId);
    grid.innerHTML = '';
    items.forEach((s) => {
      const row = document.createElement('div');
      row.className = 'color-row';
      row.dataset.section = sectionColors.replace('_colors', '');
      row.dataset.key = s.key;
      if (s.isOff) {
        row.innerHTML = `<label>${s.label}</label><span class="off-tag">自动关灯</span>`;
        grid.appendChild(row);
        return;
      }
      const raw = (sectionColors && window._ini?.[sectionColors]?.[s.key]) || s.def;
      const rgb = raw === 'off' ? [0, 0, 0] : raw.split(/\s+/).map(Number);
      const br =
        (sectionBright && window._ini?.[sectionBright]?.[s.key]) ?? s.br ?? 64;
      const hex = rgbToHex(rgb[0] || 0, rgb[1] || 0, rgb[2] || 0);
      if (s.isBright) {
        row.innerHTML = `<label>${s.label}</label><input type="number" class="c-br" min="0" max="255" value="${br}">`;
      } else {
        row.innerHTML = `
          <label>${s.label}</label>
          <input type="color" class="c-pick" value="${hex}">
          <input type="number" class="c-br" min="0" max="255" value="${br}">
        `;
      }
      grid.appendChild(row);
    });
  }

  function mergeIni(base, patch) {
    const out = JSON.parse(JSON.stringify(base || {}));
    Object.keys(patch || {}).forEach((sec) => {
      out[sec] = Object.assign({}, out[sec] || {}, patch[sec]);
    });
    return out;
  }

  function applyPreset(presetId) {
    const p = COLOR_PRESETS[presetId];
    if (!p) return;
    window._ini = mergeIni(window._ini || parseIni(''), p.ini);
    loadUiFromSettings(window._ini);
    showOk('已套用「' + p.name + '」，请点击下方「保存智能配色」写入设备');
  }

  function loadUiFromSettings(ini) {
    window._ini = ini;
    buildGrid('diskGrid', DISK_STATES, 'disk_colors', 'disk_brightness');
    buildGrid('netGrid', NET_STATES, 'netdev_colors', 'netdev_brightness');
    const pg = document.getElementById('powerGrid');
    pg.innerHTML = '';
    POWER_FIELDS.forEach((s) => {
      const row = document.createElement('div');
      row.className = 'color-row';
      row.dataset.section = 'power';
      row.dataset.key = s.key;
      const raw = ini.power?.[s.key] || s.def;
      if (s.isBright) {
        row.innerHTML = `<label>${s.label}</label><input type="number" class="c-br" min="0" max="255" value="${raw}">`;
      } else {
        const rgb = raw.split(/\s+/).map(Number);
        row.innerHTML = `<label>${s.label}</label><input type="color" class="c-pick" value="${rgbToHex(rgb[0], rgb[1], rgb[2])}">`;
      }
      pg.appendChild(row);
    });
    currentMode = ini.mode?.global || 'smart';
    updateModeUi();
  }

  function updateModeUi() {
    const labels = { off: '关闭全部灯光', on: '开启全部灯光', smart: '智能模式' };
    document.querySelectorAll('.mode-btn').forEach((b) => {
      const on = b.dataset.mode === currentMode;
      b.classList.toggle('active', on);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
    document.getElementById('modeHint').textContent =
      '当前模式：' + (labels[currentMode] || currentMode);
    document.getElementById('smartPanel').style.display =
      currentMode === 'smart' ? 'block' : 'none';
  }

  function setMode(mode) {
    const labels = { off: '关闭全部灯光', on: '开启全部灯光', smart: '智能模式' };
    showOk('正在切换为「' + (labels[mode] || mode) + '」…');
    return api('/mode', { query: 'mode=' + mode })
      .then((d) => {
        currentMode = d.mode || mode;
        updateModeUi();
        showOk('已切换：' + (labels[currentMode] || currentMode));
        return refresh();
      })
      .catch(showErr);
  }

  function collectSaveLines() {
    const lines = ['mode.global=' + currentMode];
    document.querySelectorAll('#diskGrid .color-row, #netGrid .color-row').forEach((row) => {
      const sec = row.dataset.section;
      const key = row.dataset.key;
      if (row.querySelector('.off-tag')) {
        lines.push(`${sec}_colors.${key}=off`);
        lines.push(`${sec}_brightness.${key}=0`);
        return;
      }
      const pick = row.querySelector('.c-pick');
      const br = row.querySelector('.c-br');
      if (pick && br) {
        const [r, g, b] = hexToRgb(pick.value);
        lines.push(`${sec}_colors.${key}=${r} ${g} ${b}`);
        lines.push(`${sec}_brightness.${key}=${br.value}`);
      }
    });
    document.querySelectorAll('#powerGrid .color-row').forEach((row) => {
      const key = row.dataset.key;
      const pick = row.querySelector('.c-pick');
      const br = row.querySelector('.c-br');
      if (pick) {
        const [r, g, b] = hexToRgb(pick.value);
        lines.push(`power.${key}=${r} ${g} ${b}`);
      } else if (br) {
        lines.push(`power.${key}=${br.value}`);
      }
    });
    return lines.join('\n');
  }

  function refresh() {
    api('/status').then((d) => {
      const netLabel = d.network_label || NET_LABELS[d.network] || d.network || '—';
      let netDbg = '';
      if (d.net_domestic !== undefined) {
        netDbg = ` | 国内:${d.net_domestic ? '通' : '×'} 海外:${d.net_overseas ? '通' : '×'}`;
      }
      document.getElementById('statusBar').textContent =
        `后台: ${d.daemon} | 模式: ${d.mode} | 网络: ${netLabel}${netDbg}\n\n${(d.led_status || '').slice(0, 600)}`;
      if (d.mode) {
        currentMode = d.mode;
        updateModeUi();
      }
    }).catch(showErr);
    api('/mapping').then((d) => {
      const tb = document.querySelector('#mapTable tbody');
      tb.innerHTML = '';
      (d.mapping || []).forEach((m) => {
        const st = (m.state || '').trim();
        const stZh = DISK_STATE_LABELS[st] || st || '—';
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${m.device}</td><td>${m.led}</td><td>${stZh}</td>`;
        tb.appendChild(tr);
      });
    }).catch(showErr);
  }

  document.querySelectorAll('.mode-btn').forEach((btn) => {
    btn.addEventListener('click', () => setMode(btn.dataset.mode));
  });
  document.getElementById('btnSave').onclick = () =>
    api('/settings', { method: 'POST', body: collectSaveLines() })
      .then(() => {
        showOk('已保存，正在应用智能模式…');
        currentMode = 'smart';
        updateModeUi();
        return api('/mode', { query: 'mode=smart' });
      })
      .then(() => api('/daemon/start'))
      .then(refresh)
      .catch(showErr);
  document.getElementById('btnRemap').onclick = function () {
    runAction(this, '重新检测硬盘', api('/remap'));
  };

  document.querySelectorAll('[data-preset]').forEach((btn) => {
    btn.addEventListener('click', () => applyPreset(btn.dataset.preset));
  });

  api('/settings')
    .then((d) => loadUiFromSettings(parseIni(d.raw || '')))
    .catch(showErr);
  refresh();
  setInterval(refresh, 10000);
})();
