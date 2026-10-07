/* TimeOut web demo — core helpers: storage, demo clock, hashing, formatting, odds math, icons. */
window.TO = window.TO || {};
(function (TO) {
  'use strict';

  // ---------- Storage (localStorage with in-memory fallback) ----------
  const mem = {};
  TO.store = {
    get(key, fallback) {
      try {
        const raw = localStorage.getItem(key);
        if (raw != null) return JSON.parse(raw);
      } catch (e) { /* private mode or blocked */ }
      return key in mem ? mem[key] : fallback;
    },
    set(key, value) {
      mem[key] = value;
      try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* ignore */ }
    },
    del(key) {
      delete mem[key];
      try { localStorage.removeItem(key); } catch (e) { /* ignore */ }
    },
  };

  // ---------- Demo clock ----------
  // Testers can move time forward (to see games end, midnight resets, etc). Everything reads TO.now().
  let clockOffset = TO.store.get('timeout.clockOffset', 0);
  TO.now = () => Date.now() + clockOffset;
  TO.clock = {
    get offset() { return clockOffset; },
    add(ms) { clockOffset += ms; TO.store.set('timeout.clockOffset', clockOffset); },
    set(ts) { clockOffset = ts - Date.now(); TO.store.set('timeout.clockOffset', clockOffset); },
    reset() { clockOffset = 0; TO.store.set('timeout.clockOffset', 0); },
  };

  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const DAY = 24 * HOUR;
  TO.MIN = MIN; TO.HOUR = HOUR; TO.DAY = DAY;

  const pad = (n) => String(n).padStart(2, '0');
  TO.dayKey = (ts = TO.now()) => {
    const d = new Date(ts);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  };
  TO.dayStart = (key) => {
    const [y, m, d] = key.split('-').map(Number);
    return new Date(y, m - 1, d).getTime();
  };
  TO.addDays = (key, n) => {
    const [y, m, d] = key.split('-').map(Number);
    return TO.dayKey(new Date(y, m - 1, d + n, 12).getTime());
  };
  TO.nextMidnight = (ts = TO.now()) => {
    const d = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime();
  };
  TO.weekKey = (ts = TO.now()) => {
    const d = new Date(ts);
    const day = (d.getDay() + 6) % 7; // Monday = 0
    return TO.dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() - day, 12).getTime());
  };

  // ---------- Hashing / seeded randomness ----------
  TO.hash = (str) => {
    let h = 0x811c9dc5;
    for (let i = 0; i < str.length; i++) {
      h ^= str.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
    return h >>> 0;
  };
  /** Stable value in [-1, 1] for a string. */
  TO.unit = (str) => (TO.hash(str) % 20001) / 10000 - 1;
  /** Stable value in [0, 1). */
  TO.u01 = (str) => (TO.hash(str) % 100000) / 100000;
  TO.rng = (seed) => {
    let a = typeof seed === 'string' ? TO.hash(seed) : seed >>> 0;
    return () => {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };
  TO.shuffle = (arr, rand) => {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(rand() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  };
  TO.uid = (prefix = 'id') => `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

  // Password hashing for the demo only (accounts live in this browser; this is not real security).
  TO.pwHash = (password, salt) => {
    let h1 = 0xdeadbeef ^ 7, h2 = 0x41c6ce57 ^ 7;
    const str = `${salt}:${password}:timeout`;
    for (let i = 0; i < str.length; i++) {
      const ch = str.charCodeAt(i);
      h1 = Math.imul(h1 ^ ch, 2654435761);
      h2 = Math.imul(h2 ^ ch, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    return (h2 >>> 0).toString(16).padStart(8, '0') + (h1 >>> 0).toString(16).padStart(8, '0');
  };

  // ---------- Math ----------
  /** Standard normal CDF (Abramowitz–Stegun erf approximation). */
  TO.phi = (x) => {
    const z = Math.abs(x) / Math.SQRT2;
    const t = 1 / (1 + 0.3275911 * z);
    const y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-z * z);
    return 0.5 * (1 + (x >= 0 ? y : -y));
  };
  /** Rounds down to the nearest hook (x.5) so lines never land on a whole number. */
  TO.hook = (x) => Math.floor(x) + 0.5;
  TO.clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

  TO.odds = {
    decimal(american) { return american > 0 ? 1 + american / 100 : 1 + 100 / Math.abs(american); },
    fromDecimal(dec) {
      if (dec <= 1) return -10000;
      return dec >= 2 ? Math.round((dec - 1) * 100) : Math.round(-100 / (dec - 1));
    },
    /** Fair (no house edge) American price, rounded to sportsbook-looking steps. */
    fromProb(raw) {
      const p = TO.clamp(raw, 0.038, 0.962);
      const val = p >= 0.5 ? (-100 * p) / (1 - p) : (100 * (1 - p)) / p;
      const step = Math.abs(val) >= 300 ? 25 : 5;
      let r = Math.round(val / step) * step;
      if (r > -100 && r < 100) r = r < 0 ? -100 : 100;
      return r;
    },
    fmt(price) { return price > 0 ? `+${price}` : `${price}`; },
    fmtLine(line, signed = true) {
      const body = Number.isInteger(line) ? String(line) : line.toFixed(1);
      if (!signed) return body;
      return line > 0 ? `+${body}` : body;
    },
  };

  // ---------- Formatting ----------
  TO.esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  TO.signedMin = (n) => (n > 0 ? `+${n} min` : n < 0 ? `−${Math.abs(n)} min` : '0 min');
  TO.signed = (n) => (n > 0 ? `+${n}` : n < 0 ? `−${Math.abs(n)}` : '0');
  TO.countdown = (ms) => {
    const s = Math.max(0, Math.floor(ms / 1000));
    return `${pad(Math.floor(s / 3600))}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}`;
  };
  TO.fmtTime = (ts) => new Date(ts).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  TO.fmtDate = (ts) => new Date(ts).toLocaleDateString([], { month: 'short', day: 'numeric' });
  TO.fmtDay = (ts) => {
    const key = TO.dayKey(ts);
    const today = TO.dayKey();
    if (key === today) return 'Today';
    if (key === TO.addDays(today, 1)) return 'Tomorrow';
    if (key === TO.addDays(today, -1)) return 'Yesterday';
    return new Date(ts).toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
  };
  TO.fmtIn = (ms) => {
    const m = Math.max(0, Math.round(ms / MIN));
    if (m < 1) return 'under a minute';
    if (m < 60) return `${m} min`;
    const h = Math.floor(m / 60);
    return `${h} hr${m % 60 ? ` ${m % 60} min` : ''}`;
  };
  TO.ago = (ts) => {
    const m = Math.round((TO.now() - ts) / MIN);
    if (m < 1) return 'just now';
    if (m < 60) return `${m} min ago`;
    const h = Math.round(m / 60);
    if (h < 24) return `${h} hr ago`;
    return TO.fmtDay(ts);
  };
  TO.plural = (n, word, plural) => `${n} ${n === 1 ? word : plural || word + 's'}`;
  TO.ordinal = (n) => {
    const s = ['th', 'st', 'nd', 'rd'];
    const v = n % 100;
    return n + (s[(v - 20) % 10] || s[v] || s[0]);
  };

  // ---------- Avatars ----------
  TO.initialsAvatar = (name, color) => {
    const initials = String(name || '?').replace(/[^a-zA-Z0-9]/g, ' ').trim().split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase() || '?';
    const c = color || `hsl(${TO.hash(name || '') % 360} 55% 42%)`;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><rect width="96" height="96" fill="${c}"/><text x="48" y="60" font-family="Arial, sans-serif" font-size="38" font-weight="700" fill="#fff" text-anchor="middle">${initials}</text></svg>`;
    return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
  };

  // ---------- Icons (24px stroke icons) ----------
  const P = {
    home: '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/><path d="M9.5 21v-6h5v6"/>',
    ticket: '<path d="M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v2.5a2.5 2.5 0 0 0 0 5V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-2.5a2.5 2.5 0 0 0 0-5Z"/><path d="M14 5v2M14 11v2M14 17v2"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8"/><path d="M18 14.2a6.5 6.5 0 0 1 3.5 5.8"/>',
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    hourglass: '<path d="M6 3h12M6 21h12"/><path d="M7 3v3.5a5 5 0 0 0 2.4 4.3L12 12l2.6-1.2A5 5 0 0 0 17 6.5V3"/><path d="M7 21v-3.5a5 5 0 0 1 2.4-4.3L12 12l2.6 1.2a5 5 0 0 1 2.4 4.3V21"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    unlock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.8-1.3"/>',
    flame: '<path d="M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3 0-3-1-5.5 1-8.5Z"/>',
    bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"/>',
    share: '<path d="M12 3v12"/><path d="m7 8 5-5 5 5"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>',
    send: '<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7Z"/>',
    chevR: '<path d="m9 6 6 6-6 6"/>',
    chevL: '<path d="m15 6-6 6 6 6"/>',
    chevD: '<path d="m6 9 6 6 6-6"/>',
    x: '<path d="M18 6 6 18M6 6l12 12"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
    trophy: '<path d="M8 21h8M12 17v4"/><path d="M7 4h10v5a5 5 0 0 1-10 0V4Z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>',
    star: '<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9Z"/>',
    crown: '<path d="m3 7 4.5 4L12 4l4.5 7L21 7l-2 12H5L3 7Z"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    userPlus: '<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0M19 8v6M16 11h6"/>',
    alert: '<path d="M12 3 2 20h20L12 3Z"/><path d="M12 10v4M12 17v.5"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
    bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10 21a2 2 0 0 0 4 0"/>',
    shield: '<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6l-8-3Z"/>',
    sliders: '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>',
    camera: '<path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13" r="4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    todo: '<path d="M11 6h10M11 12h10M11 18h10"/><path d="m3 6 1.5 1.5L7 5M3 12l1.5 1.5L7 11"/><rect x="3" y="16" width="4" height="4" rx="1"/>',
    chart: '<path d="M4 20V11M10 20V5M16 20v-6M2 20h20"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
    phone: '<rect x="6" y="2" width="12" height="20" rx="2.5"/><path d="M11 18h2"/>',
    copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16v4Z"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
    target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
    flask: '<path d="M9 3h6M10 3v6L4 19a1.5 1.5 0 0 0 1.3 2h13.4A1.5 1.5 0 0 0 20 19l-6-10V3"/><path d="M7 15h10"/>',
    ff: '<path d="m4 6 8 6-8 6V6ZM12 6l8 6-8 6V6Z"/>',
    moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5Z"/>',
    trend: '<path d="m3 17 6-6 4 4 8-8M15 7h6v6"/>',
    refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
    eyeOff: '<path d="M3 3l18 18M10.6 5.1A9.8 9.8 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.1 4M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
    help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6M12 17v.5"/>',
    swap: '<path d="M7 4 3 8l4 4M3 8h14M17 20l4-4-4-4M21 16H7"/>',
    dot: '<circle cx="12" cy="12" r="4" fill="currentColor"/>',
    grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
    radio: '<circle cx="12" cy="12" r="2"/><path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8"/>',
    gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M5 12v9h14v-9M12 8v13M12 8S10.5 3.5 8 4.5 9 8 12 8Zm0 0s1.5-4.5 4-3.5S15 8 12 8Z"/>',
  };
  TO.icon = (name, size = 20, extra = '') =>
    `<svg class="ic ${extra}" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || ''}</svg>`;
})(window.TO);
