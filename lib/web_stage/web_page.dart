/// The page browsers open. Self-contained (no internet needed), and built
/// with textContent only, so nothing from a program is treated as HTML.
const webStagePage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0b1210">
<title>Church Service Timer</title>
<style>
:root { color-scheme: dark; --bg:#0b1210; --card:#141d1a; --line:#25322d; --text:#e8efe9; --muted:#9db0a6; --accent:#c8f56b; --warn:#ffb74d; --bad:#ff6b6b; }
* { box-sizing: border-box; }
html, body { margin:0; height:100%; background:var(--bg); color:var(--text); font: 16px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
button, input { font: inherit; }
.wrap { max-width: 640px; margin: 0 auto; padding: 20px 16px 48px; }
h1 { font-size: 22px; margin: 4px 0 2px; }
.muted { color: var(--muted); }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 16px; margin: 14px 0; }
input { width:100%; padding:14px; border-radius:12px; border:1px solid var(--line); background:#0f1714; color:var(--text); font-size:22px; letter-spacing:4px; text-align:center; }
.btn { width:100%; padding:14px; border-radius:12px; border:0; background:var(--accent); color:#10200a; font-weight:700; margin-top:10px; cursor:pointer; }
.btn.ghost { background:transparent; color:var(--accent); border:1px solid var(--line); }
.err { color: var(--bad); min-height: 1.4em; margin-top: 8px; }
.bar { display:flex; align-items:center; gap:10px; }
.bar .grow { flex:1; min-width:0; }
.chip { display:inline-block; padding:4px 10px; border-radius:999px; border:1px solid var(--line); font-size:13px; color:var(--muted); background:transparent; cursor:pointer; }
ol { list-style:none; padding:0; margin:0; }
li { display:flex; gap:12px; padding:12px 4px; border-bottom:1px solid var(--line); }
li:last-child { border-bottom:0; }
li .n { width: 1.8em; color: var(--muted); text-align:right; flex:none; }
li.past { color: var(--muted); }
li.now { background: #c8f56b; color: #10200a; font-weight: 700; border-radius: 12px; border-bottom-color: transparent; padding: 16px 12px; margin: 4px -8px; font-size: 19px; }
li.now .n, li.now .muted { color: #2d4a12; }
li.now .t { background: #10200a; color: #c8f56b; padding: 2px 10px; border-radius: 999px; font-size: 13px; letter-spacing: .06em; align-self: center; }
li.past { opacity: .55; }
li.next .t { color: var(--accent); }
li .t { margin-left:auto; color: var(--muted); font-variant-numeric: tabular-nums; flex:none; }
.tag { font-size:12px; font-weight:700; letter-spacing:.08em; text-transform:uppercase; color:var(--accent); }
.big { font-size: clamp(48px, 16vw, 120px); font-weight: 600; font-variant-numeric: tabular-nums; line-height:1.05; }
.over { color: var(--bad); }
#stage { position:fixed; inset:0; background:#000; display:none; align-items:center; justify-content:center; text-align:center; padding:4vw; }
#stage .text { color:#fff; font-weight:500; white-space:pre-wrap; word-break:break-word; line-height:1; margin:0 auto; font-variant-numeric: tabular-nums; }
#stage .note { position:absolute; bottom:3vh; left:0; right:0; color:#777; font-size:2.2vh; }
#stage .msg { width:100%; max-width:1280px; margin:0 auto; padding:0 4vw; box-sizing:border-box; }
#stage .msg h2 { font-size:8vh; font-weight:700; line-height:1.15; margin:0 0 3vh; }
#stage .msg p { font-size:6vh; line-height:1.2; margin:0; white-space:pre-wrap; word-break:break-word; }
#lost { position:fixed; left:0; right:0; top:0; z-index:8; display:none; align-items:center; justify-content:center; gap:10px; padding:12px 16px; background:#7a1f1f; color:#fff; font-weight:700; font-size:16px; text-align:center; }
#lost .dot { width:10px; height:10px; border-radius:50%; background:#ffb3b3; animation: pulse 1.2s infinite; }
@keyframes pulse { 50% { opacity:.25; } }
#stage.stale .text, #stage.stale .msg { opacity:.35; }
body.stale #app { opacity:.6; }
#tools { position:fixed; top:10px; right:10px; display:flex; gap:8px; z-index:5; transition:opacity .4s; }
#sheet { position:fixed; inset:0; background:rgba(0,0,0,.6); display:none; align-items:flex-end; justify-content:center; z-index:9; }
#sheet .card { width:100%; max-width:520px; margin:0; border-radius:18px 18px 0 0; }
.role { display:block; width:100%; text-align:left; padding:14px; margin:8px 0; border-radius:12px; border:1px solid var(--line); background:#0f1714; color:var(--text); cursor:pointer; }
.role b { display:block; }
.role.on { border-color: var(--accent); }
.foot { text-align:center; color:#5f7068; font-size:12px; margin-top:28px; font-style:italic; }
</style>
</head>
<body>
<div id="app" class="wrap"></div>
<div id="stage"><div class="text" id="stageText"></div><div class="note" id="stageNote"></div></div>
<div id="lost" role="alert"><span class="dot"></span><span id="lostText">Connection to the host device lost · reconnecting…</span></div>
<div id="tools"></div>
<div id="sheet"><div class="card" id="sheetCard"></div></div>
<script>
'use strict';
const $ = (id) => document.getElementById(id);
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
const ROLES = { order: ['Order of service', 'What is happening now and next. No times.'], stage: ['Stage display', 'The countdown and messages, full screen, for the stage.'], overview: ['Service overview', 'Rundown, time left, ahead or behind, and finish time.'] };
let token = null, role = null, team = false, info = { church: '', orderAccess: 'code' }, timer = null, lastState = null, hideTools = null;
try { token = localStorage.getItem('cst-token'); role = localStorage.getItem('cst-role'); team = localStorage.getItem('cst-team') === '1'; } catch (_) {}
function save() { try { if (token) { localStorage.setItem('cst-token', token); localStorage.setItem('cst-role', role); localStorage.setItem('cst-team', team ? '1' : '0'); } else { localStorage.removeItem('cst-token'); } } catch (_) {} }
// Every request gives up after a few seconds: when the host device leaves
// the network nothing answers and nothing fails, so without this a request
// would wait for minutes and the page would freeze on the last countdown.
async function api(path, body, timeoutMs = 4000) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), timeoutMs);
  let r;
  try { r = await fetch(path, Object.assign({ signal: ctl.signal, cache: 'no-store' }, body ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {})); }
  finally { clearTimeout(t); }
  let j = {}; try { j = await r.json(); } catch (_) {}
  return { status: r.status, body: j };
}
function clear(node) { while (node.firstChild) node.removeChild(node.firstChild); }

async function loadInfo() { try { info = (await api('/api/info')).body; } catch (_) {} }

function showJoin(message) {
  stop(); token = null; save(); setLost(false);
  $('stage').style.display = 'none'; clear($('tools'));
  const app = $('app'); clear(app); app.style.display = 'block';
  app.append(el('div', 'tag', 'Church Service Timer'), el('h1', '', info.church || 'Welcome'));
  const card = el('div', 'card');
  if (info.orderAccess === 'off') {
    card.append(el('p', '', 'Enter the team code from the host device.'));
  } else {
    card.append(el('p', '', 'Enter the guest code shown on the screen to follow the order of service.'));
  }
  const input = el('input'); input.inputMode = 'text'; input.autocomplete = 'off'; input.placeholder = 'Code'; input.maxLength = 8;
  const go = el('button', 'btn', 'Continue');
  const err = el('div', 'err', message || '');
  const join = async (code) => {
    go.disabled = true; err.textContent = '';
    try {
      const r = await api('/api/join', { code, role: role && role !== 'order' ? role : 'stage' });
      if (r.status === 200) { token = r.body.token; role = r.body.role; team = r.body.team; save(); start(); }
      else err.textContent = r.body.error || 'Could not join.';
    } catch (_) { err.textContent = 'The host device did not answer. Check you are on the same Wi-Fi.'; }
    go.disabled = false;
  };
  go.onclick = () => join(input.value.trim());
  input.onkeydown = (e) => { if (e.key === 'Enter') join(input.value.trim()); };
  card.append(input, go, err);
  if (info.orderAccess === 'open') {
    const open = el('button', 'btn ghost', 'Follow without a code');
    open.onclick = () => join('');
    card.append(open);
  }
  app.append(card, el('div', 'foot', 'Created by I-Proton'));
  input.focus();
}

function openSheet() {
  const card = $('sheetCard'); clear(card);
  card.append(el('h1', '', 'Show'));
  for (const key of Object.keys(ROLES)) {
    const b = el('button', 'role' + (key === role ? ' on' : ''));
    b.append(el('b', '', ROLES[key][0]), el('span', 'muted', ROLES[key][1] + (key !== 'order' && !team ? ' Needs the team code.' : '')));
    b.onclick = () => switchRole(key);
    card.append(b);
  }
  const err = el('div', 'err'); err.id = 'sheetErr'; card.append(err);
  const close = el('button', 'btn ghost', 'Close'); close.onclick = closeSheet; card.append(close);
  $('sheet').style.display = 'flex';
}
function closeSheet() { $('sheet').style.display = 'none'; }
$('sheet').onclick = (e) => { if (e.target === $('sheet')) closeSheet(); };

async function switchRole(next, code) {
  if (next !== 'order' && !team && code == null) {
    const card = $('sheetCard'); clear(card);
    card.append(el('h1', '', ROLES[next][0]), el('p', 'muted', 'Enter the team code from the host device.'));
    const input = el('input'); input.placeholder = 'Team code'; input.maxLength = 6; input.inputMode = 'numeric';
    const go = el('button', 'btn', 'Continue'); const err = el('div', 'err'); err.id = 'sheetErr';
    go.onclick = () => switchRole(next, input.value.trim());
    input.onkeydown = (e) => { if (e.key === 'Enter') switchRole(next, input.value.trim()); };
    const back = el('button', 'btn ghost', 'Back'); back.onclick = openSheet;
    card.append(input, go, err, back); input.focus();
    return;
  }
  try {
    const r = await api('/api/role', { token, role: next, code });
    if (r.status === 200) { role = r.body.role; team = r.body.team; save(); closeSheet(); start(); }
    else if (r.status === 401) { closeSheet(); showJoin('Please join again.'); }
    else { const e = $('sheetErr'); if (e) e.textContent = r.body.error || 'Could not switch.'; }
  } catch (_) { const e = $('sheetErr'); if (e) e.textContent = 'The host device did not answer.'; }
}

function tools(onStage) {
  const t = $('tools'); clear(t);
  const pick = el('button', 'chip', ROLES[role][0] + ' ▾'); pick.onclick = openSheet; t.append(pick);
  if (onStage && document.documentElement.requestFullscreen) {
    const fs = el('button', 'chip', 'Full screen');
    fs.onclick = () => { document.documentElement.requestFullscreen().catch(() => {}); };
    t.append(fs);
  }
  t.style.opacity = '1';
  clearTimeout(hideTools);
  if (onStage) hideTools = setTimeout(() => { t.style.opacity = '0'; }, 4000);
}
// Reveal the tools on a stage display without rebuilding them, so the tap
// that reveals them can also press the chip.
function revealTools() {
  const t = $('tools'); t.style.opacity = '1';
  clearTimeout(hideTools);
  hideTools = setTimeout(() => { t.style.opacity = '0'; }, 4000);
}
document.addEventListener('pointerdown', () => { if (role === 'stage') revealTools(); });

let wake = null;
async function keepAwake() { try { if ('wakeLock' in navigator && !wake) { wake = await navigator.wakeLock.request('screen'); wake.addEventListener('release', () => { wake = null; }); } } catch (_) {} }
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && role !== 'order') keepAwake(); });

function stop() { clearTimeout(timer); timer = null; }
function start() {
  stop(); lastState = null; lastOk = Date.now(); misses = 0;
  if (role !== 'order') keepAwake();
  tools(role === 'stage');
  poll();
}
let misses = 0, lastOk = Date.now();
function missed() { misses++; if (misses >= 3) setLost(true); }
// A watchdog besides the misses: if no answer has arrived for a while,
// whatever the requests are doing, say so.
setInterval(() => { if (timer && Date.now() - lastOk > (role === 'order' ? 12000 : 5000)) setLost(true); }, 1000);
async function poll() {
  try {
    const r = await api('/api/state?token=' + encodeURIComponent(token));
    if (r.status === 401) { showJoin('The codes changed or this device was removed. Please join again.'); return; }
    if (r.status === 200) { misses = 0; lastOk = Date.now(); setLost(false); role = r.body.role; team = r.body.team; render(r.body); }
    else missed();
  } catch (_) { missed(); }
  timer = setTimeout(poll, role === 'order' ? 3000 : 1000);
}

// A clear banner, and a faded screen, once the host device stops answering,
// so nobody trusts a frozen countdown.
function setLost(lost) {
  $('lost').style.display = lost ? 'flex' : 'none';
  document.body.classList.toggle('stale', lost);
  $('stage').classList.toggle('stale', lost);
  if (lost && navigator.vibrate) { try { if (!setLost.buzzed) navigator.vibrate(200); } catch (_) {} }
  setLost.buzzed = lost;
}

function fit(node, text) {
  const lines = text.split('\n'); const longest = Math.max(1, ...lines.map((l) => l.length));
  const byWidth = (window.innerWidth * 0.92) / (longest * 0.58);
  const byHeight = (window.innerHeight * 0.8) / (lines.length * 1.02);
  node.style.fontSize = Math.max(16, Math.min(byWidth, byHeight)) + 'px';
}

function render(s) {
  lastState = s;
  if (s.role === 'stage') return renderStage(s);
  $('stage').style.display = 'none';
  const app = $('app'); app.style.display = 'block'; clear(app);
  const head = el('div', 'bar');
  const titles = el('div', 'grow');
  titles.append(el('div', 'tag', s.church || 'Church Service Timer'), el('h1', '', s.service || (s.role === 'order' ? 'Order of service' : 'Service overview')));
  head.append(titles); app.append(head);
  if (s.phase === 'idle' || !(s.rundown || []).length) {
    app.append(el('div', 'card', 'The service hasn’t started yet.'));
    app.append(el('div', 'foot', 'Created by I-Proton'));
    return;
  }
  const live = s.phase === 'active', ended = s.phase === 'ended';
  if (s.role === 'overview') {
    const card = el('div', 'card');
    if (live) {
      card.append(el('div', 'tag', s.paused ? 'Paused' : 'Now'), el('div', '', s.segment));
      const t = el('div', 'big' + (s.overtime ? ' over' : ''), s.remaining); card.append(t);
      if (s.next) card.append(el('div', 'muted', 'Next · ' + s.next));
      const line = el('div', 'muted'); line.textContent = [s.variance, s.finish ? 'Finish ' + s.finish : ''].filter(Boolean).join(' · ');
      if (s.behind) line.style.color = 'var(--warn)';
      card.append(line);
    } else {
      card.append(el('div', 'tag', ended ? 'Service ended' : 'Coming up'));
    }
    app.append(card);
  } else if (s.phase === 'ready') {
    app.append(el('div', 'tag', 'Coming up'));
  }
  const list = el('ol'); const card = el('div', 'card'); card.append(list);
  s.rundown.forEach((item, i) => {
    const state = !live ? (ended ? 'past' : '') : i < s.index ? 'past' : i === s.index ? 'now' : i === s.index + 1 ? 'next' : '';
    const li = el('li', state);
    li.append(el('span', 'n', String(i + 1)));
    const body = el('div', '');
    body.append(el('div', '', item.name));
    if (item.speaker) body.append(el('div', 'muted', item.speaker));
    li.append(body);
    if (state === 'now') li.append(el('span', 't', 'NOW'));
    else if (state === 'next' && s.role === 'order') li.append(el('span', 't', 'Next'));
    else if (state === 'past' && s.role === 'order') li.append(el('span', 't', '✓'));
    else if (s.role === 'overview') li.append(el('span', 't', (item.minutes || 0) + ':' + String(item.seconds || 0).padStart(2, '0')));
    list.append(li);
  });
  app.append(card, el('div', 'foot', 'Created by I-Proton'));
  if (live && s.role === 'order') { const now = list.querySelector('.now'); if (now && s.index !== render.lastIndex) now.scrollIntoView({ block: 'center', behavior: 'smooth' }); }
  render.lastIndex = s.index;
}

function renderStage(s) {
  $('app').style.display = 'none';
  const stage = $('stage'); stage.style.display = 'flex';
  const text = $('stageText'); const note = $('stageNote');
  clear(text); note.textContent = ''; stage.style.background = '#000'; stage.style.textAlign = 'center'; text.style.width = '';
  if (!s.sharing) { text.textContent = 'Waiting for the host to share the stage'; text.style.fontSize = '4vh'; text.style.color = '#888'; return; }
  if (s.message) {
    renderMessage(stage, text, s.message); return;
  }
  if (s.blank) return;
  const value = s.displayText || '';
  text.textContent = value;
  text.style.color = s.overtime ? '#ff4d4d' : '#fff';
  text.style.fontWeight = s.bold ? '800' : '500';
  text.style.fontStyle = s.italic ? 'italic' : 'normal';
  fit(text, value || ' ');
  if (s.paused) note.textContent = 'PAUSED';
}
// The quick message's palette and style, as the paired screens show it.
const PALETTES = { white: ['#ffffff', '#10151c'], amber: ['#ffdc8b', '#261b09'], sky: ['#c4e6ff', '#071b2c'], mint: ['#bcf4da', '#08271c'] };
function renderMessage(stage, text, msg) {
  const [fg, bg] = PALETTES[msg.palette] || PALETTES.white;
  const scale = Math.min(2, Math.max(0.5, Number(msg.scale) || 1));
  const body = msg.body || '';
  stage.style.background = bg; text.style.width = '100%';
  text.style.fontSize = ''; text.style.color = fg; text.style.fontWeight = ''; text.style.fontStyle = '';
  const m = el('div', 'msg');
  m.style.textAlign = ['left', 'right'].includes(msg.align) ? msg.align : 'center';
  m.style.color = fg;
  if (msg.headline) { const h = el('h2', '', msg.headline); h.style.fontSize = (8 * scale) + 'vh'; m.append(h); }
  const p = el('p', '', body);
  p.style.fontSize = ((body.length > 100 ? 5 : 6.5) * scale) + 'vh';
  p.style.fontWeight = msg.bold ? '700' : '400';
  p.style.fontStyle = msg.italic ? 'italic' : 'normal';
  m.append(p); text.append(m);
  // Shrink evenly until it fits; never scroll or distort the text.
  for (let f = 0.95; f > 0.4 && m.scrollHeight > window.innerHeight * 0.9; f -= 0.05) {
    m.querySelectorAll('h2, p').forEach((n) => { n.style.fontSize = (parseFloat(n.style.fontSize) * 0.95) + 'vh'; });
  }
}
window.addEventListener('resize', () => { if (lastState && lastState.role === 'stage') renderStage(lastState); });

(async () => { await loadInfo(); if (token && role) start(); else showJoin(); })();
</script>
</body>
</html>
''';
