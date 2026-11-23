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
#stage { position:fixed; inset:0; overflow:hidden; background:#000; display:none; align-items:center; justify-content:center; text-align:center; padding:4vw; }
#stage .text { color:#fff; font-weight:500; white-space:pre-wrap; word-break:break-word; line-height:1; margin:0 auto; font-variant-numeric: tabular-nums; }
#stage .lane { position:absolute; inset:0; overflow:hidden; }
#stage .run { position:absolute; left:0; top:50%; white-space:pre; line-height:1.1; will-change:transform; }
#stage .text.wrapped { white-space:normal; word-break:normal; overflow-wrap:normal; line-height:1.1; width:92vw; }
#stage .colon { transition: opacity .1s; }
#stage .colon.dim { opacity: .2; }
#stage .dg { display:inline-block; text-align:center; width:var(--dg, .6em); }
#stage .ap { display:inline-block; text-align:center; width:var(--ap, .7em); }
#stage .band { position:absolute; left:0; right:0; height:20vh; display:none; align-items:center; justify-content:center; overflow:hidden; padding:0 6vh; white-space:nowrap; line-height:1; font-size:14vh; z-index:2; }
#stage .band.top { top:0; border-bottom:.7vh solid currentColor; }
#stage .band.bottom { bottom:0; border-top:.7vh solid currentColor; }
#stage .band .run { top:50%; }
#stage .band.wrapped { white-space:normal; line-height:1.1; text-align:center; }
#stage.stale .band { opacity:.35; }
/* The newer cue effects. Each starts again when a new cue arrives. */
@keyframes fx-pulse { 0%, 100% { opacity:1; } 50% { opacity:.55; } }
@keyframes fx-flash3 { 0% { opacity:1; } 16.667% { opacity:0; } 33.333% { opacity:1; } 50% { opacity:0; } 66.667% { opacity:1; } 83.333% { opacity:0; } 100% { opacity:1; } }
@keyframes fx-up { from { transform:translateY(100vh); } to { transform:none; } }
@keyframes fx-down { from { transform:translateY(-100vh); } to { transform:none; } }
@keyframes fx-screen { from, to { background:var(--fx-tint); } }
@keyframes fx-ink { from, to { color:#fff4dc; } }
#stage .fx-pulse { animation:fx-pulse 2s ease-in-out infinite; }
#stage .fx-flashHold { animation:fx-flash3 3s step-end 1; }
#stage .fx-slideIn { animation:fx-up .3s ease-out 1; }
#stage .band.top .fx-slideIn { animation-name:fx-down; }
#stage.fx-screenFlash, #stage .band.fx-screenFlash { animation:fx-screen .6s step-end 1; }
/* Words in the cue's colour are warm white while the flash lights it. */
#stage.fx-screenFlash.coloured .text { animation:fx-ink .6s step-end 1; }
/* A countdown bar: placed just under the words by placeBar. */
#stage .cuebar { position:absolute; left:0; top:0; width:0; height:0; display:none; overflow:hidden; background:rgba(255,255,255,.14); }
#stage .cuebar i { display:block; height:100%; width:100%; background:currentColor; border-radius:inherit; }
#stage .band .cuebar { display:block; }
@media (prefers-reduced-motion: reduce) {
  #stage .fx-slideIn { animation:none; }
  #stage.fx-screenFlash, #stage .band.fx-screenFlash, #stage.fx-screenFlash.coloured .text { animation:none; }
  #stage.fx-screenFlash, #stage .band.fx-screenFlash { box-shadow:inset 0 0 0 1.2vh var(--fx); }
}
#stage .rule { position:absolute; left:0; right:0; bottom:0; height:max(4px, 1.667vh); display:none; }
#stage .note { position:absolute; bottom:3vh; left:0; right:0; color:#777; font-size:2.2vh; }
/* The countdown's bands, tag and progress line, in the theme's colours. */
#cd { position:absolute; inset:0; display:none; pointer-events:none; font-family:Roboto, system-ui, "Segoe UI", sans-serif; }
#stage.stale #cd { opacity:.35; }
#cd .cdband { position:absolute; display:none; align-items:baseline; justify-content:center; gap:2vw; background:var(--c-band); border:1px solid var(--c-line); text-align:center; min-width:0; overflow:hidden; }
#cd .cdband.up { flex-direction:column; align-items:center; gap:1.5vw; }
#cd .cdeye { color:var(--c-eye); font-weight:700; text-transform:uppercase; white-space:nowrap; align-self:center; }
#cd .cdnm { color:var(--c-name); font-weight:500; line-height:1.1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; min-width:0; }
#cd .cdsub { color:var(--c-sub); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; min-width:0; }
#cd .cdband.up .cdnm, #cd .cdband.up .cdsub { white-space:normal; overflow-wrap:anywhere; }
#cd #cdOnly { position:absolute; display:none; flex-direction:column; align-items:center; justify-content:center; text-align:center; }
#cd #cdOnly .cdnm { white-space:normal; overflow-wrap:anywhere; line-height:1.02; max-width:100%; }
#cd #cdTag { position:absolute; left:0; right:0; display:none; align-items:center; justify-content:center; }
#cd #cdTag b { font-weight:700; text-transform:uppercase; border-radius:999px; white-space:nowrap; }
#cd #cdProg { position:absolute; left:0; right:0; bottom:0; background:var(--c-track); }
#cd #cdProg i { display:block; height:100%; width:0; background:var(--c-fill); transition:width 1s linear, background .3s; }
#stage.cdpulse { animation:cdpulse 2s ease-in-out infinite; }
@keyframes cdpulse { 0%, 100% { background:#e5333a; } 50% { background:#ff5b61; } }
@media (prefers-reduced-motion: reduce) { #stage.cdpulse { animation:none; } #cd #cdProg i { transition:none; } }
#stage .msg { width:100%; max-width:1280px; margin:0 auto; padding:0 4vw; box-sizing:border-box; }
#stage .msg h2 { font-size:8vh; font-weight:700; line-height:1.15; margin:0 0 3vh; }
#stage .msg p { font-size:6vh; line-height:1.2; margin:0; white-space:pre-wrap; word-break:break-word; }
#lost { position:fixed; left:0; right:0; top:0; z-index:8; display:none; align-items:center; justify-content:center; gap:10px; padding:12px 16px; background:#7a1f1f; color:#fff; font-weight:700; font-size:16px; text-align:center; }
#lost .dot { width:10px; height:10px; border-radius:50%; background:#ffb3b3; animation: pulse 1.2s infinite; }
@keyframes pulse { 50% { opacity:.25; } }
#stage.stale .text, #stage.stale .msg { opacity:.35; }
body.stale #app { opacity:.6; }
#tools { position:fixed; top:10px; right:10px; display:flex; gap:8px; z-index:5; transition:opacity .4s; }
#req { position:fixed; left:10px; bottom:10px; z-index:5; display:none; align-items:center; gap:8px; }
#reqNote { color:#bbb; font-size:13px; }
#req .chip { opacity:.75; }
#sheet { position:fixed; inset:0; background:rgba(0,0,0,.6); display:none; align-items:flex-end; justify-content:center; z-index:9; }
#sheet .card { width:100%; max-width:520px; margin:0; border-radius:18px 18px 0 0; }
.role { display:block; width:100%; text-align:left; padding:14px; margin:8px 0; border-radius:12px; border:1px solid var(--line); background:#0f1714; color:var(--text); cursor:pointer; }
.role b { display:block; }
.role.on { border-color: var(--accent); }
.foot { text-align:center; color:#5f7068; font-size:12px; margin-top:28px; font-style:italic; }

/* The flip clock: every size is a multiple of --H, the height of a card. */
#flip { display:none; flex-direction:column; align-items:center; justify-content:center; font-family:Roboto, system-ui, "Segoe UI", sans-serif; text-align:center; }
#flip .fmain { display:flex; align-items:center; justify-content:center; }
#flip .fpair { display:flex; gap:calc(var(--H) * .05); }
#flip .fcolon { display:grid; gap:calc(var(--H) * .2); width:calc(var(--H) * .2); justify-items:center; margin:0 calc(var(--H) * .06); }
#flip .fcolon i { display:block; width:calc(var(--H) * .075); height:calc(var(--H) * .075); border-radius:50%; background:var(--f-accent); }
#flip .fd { position:relative; width:calc(var(--H) * .72); height:var(--H); perspective:calc(var(--H) * 4); font-size:calc(var(--H) * .86); line-height:1; font-weight:500; color:var(--f-text); font-variant-numeric:tabular-nums; }
#flip .fh, #flip .fl { position:absolute; left:0; width:100%; height:50%; overflow:hidden; backface-visibility:hidden; }
#flip .fh span, #flip .fl span { position:absolute; left:0; width:100%; height:200%; display:grid; place-items:center; }
#flip .ft { top:0; border-radius:calc(var(--H) * .07) calc(var(--H) * .07) 0 0; background:linear-gradient(var(--f-top), var(--f-mid)); }
#flip .fb { bottom:0; border-radius:0 0 calc(var(--H) * .07) calc(var(--H) * .07); background:linear-gradient(var(--f-mid), var(--f-bottom)); }
#flip .ft span { top:0; } #flip .fb span { top:-100%; }
#flip .fl.ft { transform-origin:bottom; z-index:3; }
#flip .fl.fb { transform-origin:top; transform:rotateX(90deg); z-index:3; }
#flip .fd.flipping .fl.ft { animation:fliptop .32s ease-in forwards; }
#flip .fd.flipping .fl.fb { animation:flipbottom .32s .32s ease-out forwards; }
@keyframes fliptop { to { transform:rotateX(-90deg); } }
@keyframes flipbottom { to { transform:rotateX(0deg); } }
#flip .fd::after { content:""; position:absolute; left:0; right:0; top:calc(50% - 1px); height:2px; background:var(--f-hinge); z-index:5; }
#flip .fd::before { content:""; position:absolute; inset:0; border-radius:calc(var(--H) * .07); box-shadow:0 calc(var(--H) * .04) calc(var(--H) * .1) rgba(0,0,0,.35); pointer-events:none; }
#flip .ftiles { display:none; }
#flip .ftiles.on { display:grid; }
#flip .ftiles.side { gap:calc(var(--H) * .06); height:var(--H); width:calc(var(--H) * .62); margin-left:calc(var(--H) * .14); }
#flip .ftiles.below { grid-auto-flow:column; gap:calc(var(--H) * .1); margin-top:calc(var(--H) * .22); height:calc(var(--H) * .27); }
#flip .ftiles.below b { width:calc(var(--H) * .5); }
#flip .ftiles b { display:grid; place-items:center; font-weight:700; font-size:calc(var(--H) * .17); letter-spacing:.06em; border-radius:calc(var(--H) * .05); color:var(--f-muted); background:var(--f-off); border:1px solid var(--f-line); }
#flip .ftiles b.lit { color:var(--f-on); background:var(--f-accent); border-color:var(--f-accent); }
#flip .fdate { margin-top:calc(var(--H) * .2); }
#flip .fdow { font-size:calc(var(--H) * .13); letter-spacing:.32em; text-transform:uppercase; color:var(--f-accent); font-weight:500; line-height:1.25; white-space:nowrap; }
#flip .fdmy { font-size:calc(var(--H) * .115); letter-spacing:.04em; color:var(--f-muted); font-weight:300; line-height:1.25; margin-top:calc(var(--H) * .05); white-space:nowrap; }
@media (prefers-reduced-motion: reduce) { #flip .fd.flipping .fl.ft, #flip .fd.flipping .fl.fb { animation:none; } }
</style>
</head>
<body>
<div id="app" class="wrap"></div>
<div id="stage"><div id="flip"></div><div class="text" id="stageText"></div><div class="band" id="stageBand"></div><div class="cuebar" id="stageBar"><i></i></div><div class="rule" id="stageRule"></div><div id="cd"><div class="cdband" id="cdNow"></div><div class="cdband" id="cdNext"></div><div id="cdOnly"></div><div id="cdTag"></div><div id="cdProg"><i></i></div></div><div class="note" id="stageNote"></div></div>
<div id="lost" role="alert"><span class="dot"></span><span id="lostText">Connection to the host device lost · reconnecting…</span></div>
<div id="tools"></div>
<div id="req"><span id="reqNote"></span><button class="chip" id="reqBtn">Request</button></div>
<div id="sheet"><div class="card" id="sheetCard"></div></div>
<script>
'use strict';
const $ = (id) => document.getElementById(id);
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
const span = (total) => { const h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60; return [h ? h + ' h' : '', m ? m + ' min' : '', s ? s + ' s' : ''].filter(Boolean).join(' ') || '0 s'; };
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
  stop(); stopMotion(); token = null; save(); setLost(false); $('req').style.display = 'none';
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

// Requests to the operator, for team Stage displays while the host allows
// them. Three fixed choices; the note shows Sent, then Seen by operator.
const REQUESTS = { time: 'Need 2 minutes', finish: 'Ready to finish', mic: 'Microphone issue' };
function openRequests() {
  const card = $('sheetCard'); clear(card);
  card.append(el('h1', '', 'Ask the operator'));
  for (const [kind, text] of Object.entries(REQUESTS)) {
    const b = el('button', 'role'); b.append(el('b', '', text));
    b.onclick = () => sendRequest(kind);
    card.append(b);
  }
  const err = el('div', 'err'); err.id = 'sheetErr'; card.append(err);
  const close = el('button', 'btn ghost', 'Close'); close.onclick = closeSheet; card.append(close);
  $('sheet').style.display = 'flex';
}
async function sendRequest(kind) {
  try {
    const r = await api('/api/request', { token, kind });
    if (r.status === 200) { closeSheet(); $('reqNote').textContent = 'Sent · ' + REQUESTS[kind]; return; }
    $('sheetErr').textContent = 'Not sent. Wait a few seconds and try again.';
  } catch (_) { $('sheetErr').textContent = 'Not sent. Check the connection and try again.'; }
}
$('reqBtn').onclick = openRequests;
function showRequests(s) {
  const on = s.role === 'stage' && s.requests === true;
  $('req').style.display = on ? 'flex' : 'none';
  if (!on) return;
  const r = s.request;
  $('reqNote').textContent = !r ? '' : r.state === 'sent' ? 'Sent · ' + (REQUESTS[r.kind] || '') : r.state === 'seen' ? 'Seen by operator' : r.state === 'added' ? '2 minutes added' : '';
}
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
    const fs = el('button', 'chip'); fs.id = 'fs';
    fs.onclick = () => {
      if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
      else document.documentElement.requestFullscreen().catch(() => {});
    };
    t.append(fs); fullscreenLabel();
  }
  t.style.opacity = '1';
  clearTimeout(hideTools);
  if (onStage) hideTools = setTimeout(() => { t.style.opacity = '0'; }, 4000);
}
// The chip follows the real state, including when the browser leaves full
// screen by itself (Esc, a swipe, or the system back gesture).
function fullscreenLabel() { const fs = $('fs'); if (fs) fs.textContent = document.fullscreenElement ? 'Exit full screen' : 'Full screen'; }
document.addEventListener('fullscreenchange', fullscreenLabel);
// Reveal the tools on a stage display without rebuilding them, so the tap
// that reveals them can also press the chip.
function revealTools() {
  const t = $('tools'); t.style.opacity = '1';
  clearTimeout(hideTools);
  hideTools = setTimeout(() => { t.style.opacity = '0'; }, 4000);
}
document.addEventListener('pointerdown', () => { if (role === 'stage') revealTools(); });

// Wake lock: held only while this page is a stage screen or a service is
// running, and let go otherwise so an idle screen can sleep. A browser may
// refuse or drop the lock, so failure is quiet and the next change retries.
let wake = null;
function wantAwake() {
  if (document.visibilityState !== 'visible' || role === 'order') return false;
  return role === 'stage' || (!!lastState && lastState.phase === 'active');
}
async function keepAwake() {
  try {
    if (!('wakeLock' in navigator) || wake) return;
    const lock = await navigator.wakeLock.request('screen');
    // The need may have ended while the browser was answering.
    if (!wantAwake() || wake) { lock.release().catch(() => {}); return; }
    wake = lock;
    lock.addEventListener('release', () => { if (wake === lock) wake = null; });
  } catch (_) {}
}
function letSleep() {
  const lock = wake; wake = null;
  try { if (lock) lock.release().catch(() => {}); } catch (_) {}
}
function syncAwake() { if (wantAwake()) keepAwake(); else letSleep(); }
document.addEventListener('visibilitychange', syncAwake);

function stop() { clearTimeout(timer); timer = null; }
function start() {
  stop(); lastState = null; lastOk = Date.now(); misses = 0;
  syncAwake();
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

// [room] is the share of the screen's height the text may use: less while
// a banner cue takes a band at the top or bottom.
function fit(node, text, room) {
  const lines = text.split('\n'); const longest = Math.max(1, ...lines.map((l) => l.length));
  const byWidth = (window.innerWidth * 0.92) / (longest * 0.58);
  const byHeight = (window.innerHeight * 0.8 * (room || 1)) / (lines.length * 1.02);
  node.style.fontSize = Math.max(16, Math.min(byWidth, byHeight)) + 'px';
}

// "Wrap long text": sets [node], already holding the text and its style,
// to the largest size from [least] to [most] px at which it fits on at most
// [lines] lines and [height] px with no word split, and returns that size.
// 0 when it would have to be smaller: it then scrolls instead, so nothing
// is cut off or too small to read. Measured on the node itself, so the
// size is exactly what is drawn.
function wrapSize(node, lines, height, least, most) {
  const fits = (size) => { node.style.fontSize = size + 'px'; return node.scrollWidth <= node.clientWidth + 1 && node.offsetHeight <= Math.min(height, lines * size * 1.1) + 1; };
  let best = 0;
  if (most >= least && fits(least)) {
    if (fits(most)) best = most;
    else { let lo = least, hi = most; for (let i = 0; i < 14; i++) { const mid = (lo + hi) / 2; if (fits(mid)) lo = mid; else hi = mid; } best = Math.floor(lo); }
  }
  if (best) node.style.fontSize = best + 'px';
  return best;
}

function render(s) {
  lastState = s;
  syncAwake();
  showRequests(s);
  if (s.role === 'stage') return renderStage(s);
  stopMotion(); renderBand(null);
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
    else if (s.role === 'overview') li.append(el('span', 't', span((item.minutes || 0) * 60 + (item.seconds || 0))));
    list.append(li);
  });
  app.append(card, el('div', 'foot', 'Created by I-Proton'));
  if (live && s.role === 'order') { const now = list.querySelector('.now'); if (now && s.index !== render.lastIndex) now.scrollIntoView({ block: 'center', behavior: 'smooth' }); }
  render.lastIndex = s.index;
}

// Scrolling and flashing text, as on the display preview: one line at
// screen height moving right to left at the cue's speed, or blinking twice
// a second. It keeps running across polls and pauses while the host is lost.
let motion = null;
// With [keep], scrolling text started again carries on where it was.
function stopMotion(keep) { if (motion) cancelAnimationFrame(motion.raf); motion = null; stopScroll('stage', !keep); }

// One line of text moving right to left across the screen, over and over.
// It moves on every frame by the time since the last frame, at [speed]
// pixels a second, so polls and slow frames never change its pace, and
// only its transform changes, so the browser just moves it. The same text
// carries on from where it was when the lane is started again (a new
// size, speed, colour or style); different text starts at the right-hand
// edge. It holds still while the host is lost.
const lanes = {};
function startScroll(name, run, text, w, speed) {
  const old = lanes[name];
  if (old) cancelAnimationFrame(old.raf);
  const travel = w + run.offsetWidth;
  const lane = { text, w, travel, travelled: 0, last: null, raf: 0 };
  // The same text stays where it is on the screen, and on time.
  if (old && old.text === text && old.w > 0) {
    const x = (old.w - old.travelled) * w / old.w;
    lane.travelled = (((w - x) % travel) + travel) % travel; lane.last = old.last;
  }
  const place = () => { run.style.transform = 'translate3d(' + (w - lane.travelled) + 'px, -50%, 0)'; };
  const frame = (now) => {
    if (lane.last !== null && now > lane.last && !$('stage').classList.contains('stale')) {
      lane.travelled = (lane.travelled + (now - lane.last) / 1000 * speed) % travel;
    }
    lane.last = now; place(); lane.raf = requestAnimationFrame(frame);
  };
  lanes[name] = lane; place(); lane.raf = requestAnimationFrame(frame);
}
// Stops the lane; with [forget], the next text starts at the edge again.
function stopScroll(name, forget) { const l = lanes[name]; if (l) cancelAnimationFrame(l.raf); if (forget) delete lanes[name]; }
function startMotion(text, value, s, key) {
  const stage = $('stage');
  const h = window.innerHeight, w = window.innerWidth;
  const m = { key, elapsed: 0, last: performance.now(), raf: 0 };
  if (s.effect === 'scroll') {
    const lane = el('div', 'lane'); const run = el('span', 'run', value.replace(/\n/g, ' '));
    const size = h * 0.9;
    run.style.fontSize = size + 'px';
    lane.append(run); text.append(lane);
    // The preview's speed: the cue's speed scaled by text size.
    const speed = (Number(s.speed) || 12) * 6 * (size / Math.min(260, Math.max(42, w / 7)));
    motion = m; startScroll('stage', run, value.replace(/\n/g, ' '), w, speed);
    return;
  } else if (s.group) {
    const longest = s.group.words.reduce((a, b) => (b.length > a.length ? b : a));
    fit(text, longest);
    fitWords(text, s.group.words, parseFloat(text.style.fontSize), w * 0.92);
    stepWords(m, text, s.group);
  } else {
    text.textContent = value;
    if (s.wrapAt) text.style.fontSize = s.wrapAt + 'px'; else fit(text, value || ' ');
    m.step = () => { text.style.visibility = Math.floor(m.elapsed * 2) % 2 === 1 ? 'hidden' : 'visible'; };
  }
  const frame = (now) => {
    if (!stage.classList.contains('stale')) m.elapsed += (now - m.last) / 1000;
    m.last = now; m.step(); m.raf = requestAnimationFrame(frame);
  };
  motion = m; m.step(); m.raf = requestAnimationFrame(frame);
}

// The newer effects, as classes the styles above animate. A class is put
// back only for a new cue, so a poll never restarts an animation.
const FX = ['pulse', 'flashHold', 'slideIn', 'bar', 'screenFlash'];
function setFx(node, fx, key) {
  const k = fx ? fx + '|' + key : '';
  if (node.dataset.fx === k) return;
  node.dataset.fx = k;
  for (const f of FX) node.classList.remove('fx-' + f);
  if (fx) { void node.offsetWidth; node.classList.add('fx-' + fx); }
}
// Flash or Pulse text too wide for the LED sign, a few words at a time as
// the sign shows it: which of [count] groups shows [ms] after the cue
// appears, and how brightly. The same timing as the app's screens.
function wordAt(kind, count, ms) {
  const cycle = count * 2000 + (kind === 'flash' ? 300 : 0);
  const t = ((Math.floor(ms) % cycle) + cycle) % cycle;
  const index = Math.min(Math.floor(t / 2000), count - 1), within = t - index * 2000;
  if (kind === 'flash') return { index, opacity: within < 500 || (within >= 1000 && within < 1500) ? 1 : 0 };
  const v = Math.sin(Math.PI * within / 2000);
  return { index, opacity: v * v };
}
// The groups of words [s] steps through, and with which effect, or null
// when it shows its text whole (wrapped text flashes or pulses whole).
function wordsOf(s, wrap) {
  const ok = Array.isArray(s.words) && s.words.length > 0 && s.words.every((w) => typeof w === 'string');
  if (!ok || wrap) return null;
  const kind = s.effect === 'flash' ? 'flash' : s.screenEffect === 'pulse' ? 'pulse' : null;
  return kind ? { kind, words: s.words } : null;
}
// Sets [node] to the size at which the widest of [words] fits [room] px
// across, from [size] px at most, so every group is the same size.
function fitWords(node, words, size, room) {
  node.style.whiteSpace = 'nowrap'; node.style.fontSize = size + 'px';
  for (const w of words) { node.textContent = w; if (node.offsetWidth > room) { size = size * room / node.offsetWidth; node.style.fontSize = size + 'px'; } }
}
// Steps [node] through the groups as time passes in motion [m].
function stepWords(m, node, g) {
  m.step = () => {
    const at = wordAt(g.kind, g.words.length, m.elapsed * 1000);
    if (node.textContent !== g.words[at.index]) node.textContent = g.words[at.index];
    node.style.opacity = String(at.opacity);
  };
}
// A coloured full-screen cue's words: warm white for amber, otherwise the
// cue's own colour (the host lightens a dark theme colour before sending).
const cardInk = (c) => c.toLowerCase() === '#ffa833' ? '#fff4dc' : c;
// A screen flash is in the cue's colour, or red for a white cue.
const flashColour = (c) => !c || c.toLowerCase() === '#ffffff' ? '#ff4d4d' : c;
// The flash's background: a deep tint of its colour, so the cue stays
// in its own colour over it.
const flashTint = (c) => {
  const n = parseInt(flashColour(c).slice(1), 16);
  return 'rgb(' + [16, 8, 0].map((s) => Math.round(((n >> s) & 255) * .32)).join(',') + ')';
};
// A countdown bar: set to the time left at each poll, then running down
// smoothly until the next.
function setBar(bar, time) {
  if (!time || !(time.total > 0)) { bar.style.display = 'none'; return; }
  bar.style.display = 'block';
  const fill = bar.firstChild;
  fill.style.transition = 'none';
  fill.style.width = (100 * Math.min(1, Math.max(0, time.left / time.total))) + '%';
  void fill.offsetWidth;
  fill.style.transition = 'width ' + Math.max(0, time.left) + 'ms linear';
  fill.style.width = '0%';
}

// A countdown bar just under [node]'s words and as wide as them (nine
// tenths of their width, at least 80 px), about 2% of the screen's height
// thick with a gap of one and a half times that. The words move up by
// half of the bar and gap, so the two stay centred together. Measured on
// the words as drawn, so the bar matches them, wrapped or not.
function placeBar(bar, node) {
  node.style.position = ''; node.style.top = '';
  if (bar.style.display === 'none' || !node.textContent.trim() || !bar.offsetParent) return;
  const h = window.innerHeight;
  const thick = Math.min(10, Math.max(4, h * 0.02)), gap = thick * 1.5;
  node.style.position = 'relative'; node.style.top = (-(gap + thick) / 2) + 'px';
  const range = document.createRange(); range.selectNodeContents(node);
  // Across, the words themselves; down, the lines they sit on.
  const r = range.getBoundingClientRect(), lines = node.getBoundingClientRect(), box = bar.offsetParent.getBoundingClientRect();
  const width = Math.min(box.width, Math.max(80, r.width * 0.9));
  bar.style.height = thick + 'px'; bar.style.borderRadius = thick + 'px';
  bar.style.width = width + 'px';
  bar.style.left = (r.left + r.width / 2 - width / 2 - box.left) + 'px';
  // With nothing below the line (as in capitals), from the line the last
  // words stand on; otherwise below the room kept for letters such as g.
  let bottom = lines.bottom;
  const last = node.textContent.trimEnd().split('\n').pop();
  if (!/[gjpqyQ,;()\[\]{}|@_$]/.test(last)) {
    const mark = el('span'); mark.style.display = 'inline-block'; mark.style.height = '0'; mark.style.verticalAlign = 'baseline';
    node.append(mark); bottom = Math.min(bottom, mark.getBoundingClientRect().bottom); mark.remove();
  }
  bar.style.top = (bottom + gap - box.top) + 'px';
}

// A banner cue: the cue in a band across the top or bottom of the screen,
// in its colour, while the countdown or clock stays in view behind it.
let bandMotion = null;
function renderBand(s) {
  const band = $('stageBand');
  const b = s && s.sharing && !s.message && !s.blank ? s.banner : null;
  const stop = () => { if (bandMotion) cancelAnimationFrame(bandMotion.raf); bandMotion = null; stopScroll('band'); };
  if (!b) { stop(); stopScroll('band', true); band.style.display = 'none'; band.dataset.key = ''; setFx(band, null, ''); clear(band); return; }
  const h = window.innerHeight, w = window.innerWidth;
  const fx = b.screenEffect || '';
  const bandGroup = wordsOf(b, b.wrap === true);
  const key = [b.text, b.position, b.color, b.bold, b.italic, b.effect, b.wrap, fx, bandGroup ? bandGroup.words.join('\n') : '', s.speed, w, h].join('|');
  // The same banner as the last poll: leave it running.
  if (band.dataset.key === key) { const bar = band.querySelector('.cuebar'); if (bar) setBar(bar, b.cueTime); return; }
  stop(); clear(band); band.dataset.key = key;
  const value = (b.text || '').replace(/\n/g, ' ');
  const size = h * 0.14;
  const room = w - h * 0.12;
  band.className = 'band ' + (b.position === 'top' ? 'top' : 'bottom');
  band.style.display = 'flex';
  // The cue's colour, on a dark tint of the same colour.
  band.style.color = b.color; band.style.background = b.color + '29';
  band.style.fontWeight = b.bold ? '800' : '500';
  band.style.fontStyle = b.italic ? 'italic' : 'normal';
  band.style.fontSize = size + 'px';
  // Wrapped, on up to 2 lines in the band; too long for that, it scrolls.
  let effect = b.effect, label = null;
  if (b.wrap) {
    band.classList.add('wrapped');
    label = el('span', '', value); label.style.display = 'block'; label.style.width = room + 'px'; band.append(label);
    // Clear of the countdown bar, when there is one.
    if (wrapSize(label, 2, h * (fx === 'bar' ? 0.14 : 0.168), h * 0.03, size)) effect = effect === 'flash' ? 'flash' : 'static';
    else { band.classList.remove('wrapped'); clear(band); label = null; effect = 'scroll'; }
  }
  // Too long to wrap, it scrolls without its own effect or bar, as the
  // app's screens do; a screen flash still plays.
  const scrollsInstead = b.wrap && effect === 'scroll';
  const m = { elapsed: 0, last: performance.now(), raf: 0, step: null };
  if (effect === 'scroll') {
    const run = el('span', 'run', value); band.append(run);
    const speed = (Number(s.speed) || 12) * 6 * (size / Math.min(260, Math.max(42, w / 7)));
    run.style.left = '0';
    startScroll('band', run, value, w, speed);
  } else {
    const wrapped = !!label;
    if (!label) { label = el('span', '', value); band.append(label); }
    if (bandGroup && !wrapped) {
      // A few words at a time, every group the same size.
      label.style.fontSize = size + 'px';
      fitWords(label, bandGroup.words, size, room);
      stepWords(m, label, bandGroup);
    } else {
      // A long cue is made smaller until it fits the band's width.
      if (!wrapped && label.offsetWidth > room) band.style.fontSize = Math.max(12, size * room / label.offsetWidth) + 'px';
      if (effect === 'flash') m.step = () => { label.style.visibility = Math.floor(m.elapsed * 2) % 2 === 1 ? 'hidden' : 'visible'; };
      // The band's text pulses, flashes three times or slides in from its
      // edge; wrapped text does so as one block.
      if (['pulse', 'flashHold', 'slideIn'].includes(fx)) label.classList.add('fx-' + fx);
    }
  }
  // A screen flash lights the band only; the countdown stays as it is.
  band.style.setProperty('--fx', flashColour(b.color));
  band.style.setProperty('--fx-tint', flashTint(b.color));
  setFx(band, fx === 'screenFlash' ? fx : null, key);
  if (fx === 'bar' && !scrollsInstead) { const bar = el('div', 'cuebar'); bar.append(el('i')); band.append(bar); setBar(bar, b.cueTime); placeBar(bar, label); }
  if (!m.step) return;
  const frame = (now) => {
    if (!$('stage').classList.contains('stale')) m.elapsed += (now - m.last) / 1000;
    m.last = now; m.step(); m.raf = requestAnimationFrame(frame);
  };
  bandMotion = m; m.step(); m.raf = requestAnimationFrame(frame);
}

// A time as the host sends it: "48:03", "+01:10" or "9:30 AM".
const TIME = /^[+-]?\d{1,3}(:\d\d){1,2}( [AP]M)?$/;
// The widest of [chars] in [node]'s font, weight and style, in em.
const placeWidths = {};
function placeWidth(node, chars, otherwise) {
  const cs = getComputedStyle(node);
  const font = cs.fontStyle + ' ' + cs.fontWeight + ' 100px ' + cs.fontFamily;
  const k = font + '|' + chars;
  if (!(k in placeWidths)) {
    const ctx = document.createElement('canvas').getContext('2d');
    ctx.font = font;
    let most = 0;
    for (const c of chars) most = Math.max(most, ctx.measureText(c).width);
    placeWidths[k] = most > 0 ? most / 100 : otherwise;
  }
  return placeWidths[k];
}

// The blinking colon: lit as each new second arrives, dimmed for the second
// half, steady while paused or lost. The new second is the moment the time
// text changes, so screens follow the host's seconds.
const colon = { text: '', at: 0 };
setInterval(() => {
  const lit = $('stage').classList.contains('stale') || (performance.now() - colon.at) % 1000 < 500;
  document.querySelectorAll('#stage .colon').forEach((c) => c.classList.toggle('dim', !lit));
}, 50);


// The flip clock, wherever the screen is filled with the time of day.
// Four cards (the hours' first is hidden on a 12 hour clock's single
// digit) turn over when their digit changes; the colours are mixed from
// the host's theme, and nothing is drawn from the host as HTML.
const flipDigits = []; let flipCur = ['', '', '', ''];
const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const rgbHex = (c) => '#' + c.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
const mixHex = (a, b, t) => { const x = hexRgb(a), y = hexRgb(b); return rgbHex(x.map((v, i) => v + (y[i] - v) * t)); };
const lumOf = (h) => { const [r, g, b] = hexRgb(h).map((v) => { v /= 255; return v <= .03928 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); }); return .2126 * r + .7152 * g + .0722 * b; };
const ratioOf = (a, b) => { const x = lumOf(a), y = lumOf(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };
const CLASSIC = { background: '#000000', surface: '#141414', accent: '#ffffff', muted: '#b3b3b3', text: '#ffffff' };
function flipCard() {
  const d = el('div', 'fd');
  for (const cls of ['fh ft', 'fh fb', 'fl ft', 'fl fb']) { const half = el('div', cls); half.append(el('span')); d.append(half); }
  return d;
}
const flipSet = (d, sel, t) => { d.querySelector(sel + ' span').textContent = t; };
const flipShow = (d, v) => { ['.fh.ft', '.fh.fb', '.fl.ft', '.fl.fb'].forEach((q) => flipSet(d, q, v)); };
function flipTurn(d, from, to) {
  d.classList.remove('flipping'); void d.offsetWidth;
  flipSet(d, '.fh.ft', to); flipSet(d, '.fh.fb', from); flipSet(d, '.fl.ft', from); flipSet(d, '.fl.fb', to);
  d.classList.add('flipping');
  const done = () => { d.removeEventListener('animationend', handler); flipShow(d, to); d.classList.remove('flipping'); };
  const handler = (e) => { if (e.animationName === 'flipbottom') done(); };
  d.addEventListener('animationend', handler);
  setTimeout(() => { if (d.classList.contains('flipping')) done(); }, 900);
}
function renderFlip(s, w, h) {
  const c = s.clock, root = $('flip');
  if (!flipDigits.length) {
    const pairs = [el('div', 'fpair'), el('div', 'fpair')];
    const tiles = (cls) => { const t = el('div', 'ftiles ' + cls); t.append(el('b', '', 'AM'), el('b', '', 'PM')); return t; };
    const colon = el('div', 'fcolon'); colon.append(el('i'), el('i'));
    const main = el('div', 'fmain'); main.append(pairs[0], colon, pairs[1], tiles('side'));
    const date = el('div', 'fdate'); date.append(el('div', 'fdow'), el('div', 'fdmy'));
    root.append(main, tiles('below'), date);
    for (let i = 0; i < 4; i++) { const d = flipCard(); flipShow(d, '0'); flipDigits.push(d); pairs[i < 2 ? 0 : 1].append(d); }
  }
  const t = Object.assign({}, CLASSIC, s.theme || {});
  const light = lumOf(t.background) > .179;
  const vars = {
    '--f-text': t.text, '--f-accent': t.accent, '--f-muted': t.muted,
    '--f-top': mixHex(t.surface, t.text, .06), '--f-bottom': mixHex(t.surface, t.background, .35),
    '--f-mid': mixHex(mixHex(t.surface, t.text, .06), mixHex(t.surface, t.background, .35), .5),
    '--f-hinge': light ? mixHex(t.background, t.text, .3) : mixHex(t.background, '#000000', .3),
    '--f-off': mixHex(t.background, t.text, .06), '--f-line': mixHex(t.background, t.text, .14),
    '--f-on': ratioOf('#10150a', t.accent) >= ratioOf('#ffffff', t.accent) ? '#10150a' : '#ffffff'
  };
  for (const k in vars) root.style.setProperty(k, vars[k]);
  const twelve = typeof c.pm === 'boolean', upright = h > w;
  // The largest card that fits, sized for two hour digits so the clock
  // keeps its size as 9:59 becomes 10:00.
  const m = Math.min(w, h) * .04;
  const wf = 2 * (2 * .72 + .05) + .12 + .2 + .12 + (!upright && twelve ? .76 : 0);
  const hf = 1 + (upright && twelve ? .49 : 0) + .2 + .13 * 1.25 + .05 + .115 * 1.25;
  root.style.setProperty('--H', Math.max(10, Math.min((w - 2 * m) / wf, (h - 2 * m) / hf)) + 'px');
  root.style.display = 'flex';
  const hs = c.hours.length === 1 ? ' ' + c.hours : c.hours, next = [hs[0], hs[1], c.minutes[0], c.minutes[1]];
  const calm = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const animate = !calm && !$('stage').classList.contains('stale');
  flipDigits.forEach((d, i) => {
    d.style.display = next[i] === ' ' ? 'none' : '';
    if (flipCur[i] === next[i]) return;
    if (animate && flipCur[i] !== '' && flipCur[i] !== ' ' && next[i] !== ' ') flipTurn(d, flipCur[i], next[i]);
    else flipShow(d, next[i] === ' ' ? '0' : next[i]);
    flipCur[i] = next[i];
  });
  root.querySelectorAll('.ftiles').forEach((box) => {
    box.classList.toggle('on', twelve && box.classList.contains(upright ? 'below' : 'side'));
    if (twelve) { box.children[0].classList.toggle('lit', !c.pm); box.children[1].classList.toggle('lit', c.pm); }
  });
  root.querySelector('.fdow').textContent = c.weekday || '';
  root.querySelector('.fdmy').textContent = c.date || '';
  return t;
}

// The countdown's chrome: the band for the segment now or what is next
// (or the next item alone), the PAUSED and OVER TIME tag, and the progress
// line, in the host's theme and the colour of the moment. It returns the
// share of the screen's height left for the digits, and their colour. All
// text is set with textContent.
function renderCountdown(s, cd, w, h, high, low) {
  const stage = $('stage'), root = $('cd');
  const t = Object.assign({}, CLASSIC, s.theme || {});
  const light = lumOf(t.background) > .179;
  const upright = h > w;
  const only = s.layout === 'only' && !!cd.next;
  // 'Up next only' shows no time, so overtime does not change it.
  const moment = only && cd.moment === 'overtime' ? 'normal' : cd.moment;
  const over = moment === 'overtime', solid = over && cd.alert !== 'gentle';
  const redInk = light ? '#ad2835' : '#ff6b6b', warn = light ? '#875100' : '#f3ba61', dark = '#1a0000';
  const ink = over ? (solid ? dark : redInk) : moment === 'warning' ? warn : t.text;
  stage.style.background = solid ? '#e5333a' : t.background;
  stage.classList.toggle('cdpulse', solid && cd.alert === 'strongest');
  if (over && !solid) stage.style.boxShadow = 'inset 0 0 0 ' + Math.max(6, Math.min(w, h) * 0.035) + 'px ' + redInk;
  const vars = {
    '--c-band': solid ? 'rgba(0,0,0,.12)' : mixHex(t.surface, t.text, .05),
    '--c-line': solid ? 'rgba(0,0,0,.3)' : mixHex(t.surface, t.text, .16),
    '--c-eye': solid ? dark : t.accent, '--c-name': solid ? dark : t.text, '--c-sub': solid ? 'rgba(26,0,0,.8)' : t.muted,
    '--c-track': solid ? 'rgba(0,0,0,.22)' : mixHex(t.background, t.text, .12),
    '--c-fill': over ? (solid ? dark : redInk) : moment === 'warning' ? warn : t.accent
  };
  for (const k in vars) root.style.setProperty(k, vars[k]);
  root.style.display = 'block';
  const topM = upright ? w * .08 : w * .03, botM = upright ? w * .10 : w * .044, side = upright ? w * .06 : w * .03, gap = upright ? w * .05 : w * .02;
  const prog = $('cdProg'); prog.style.height = Math.max(4, upright ? w * .024 : w * .013) + 'px';
  $('cdProg').firstChild.style.width = (Math.max(0, Math.min(1, cd.progress || 0)) * 100) + '%';
  const bandTop = high ? h * .2 : 0, bandBottom = low ? h * .2 : 0;
  const fs = (a, b) => (upright ? b : a) * w + 'px';
  const fill = (node, label, name, detail) => {
    clear(node);
    const e = el('span', 'cdeye', label); e.style.fontSize = fs(.019, .042); e.style.letterSpacing = '.16em';
    const n = el('span', 'cdnm', name); n.style.fontSize = fs(.044, .09);
    node.append(e, n);
    if (detail) { const d = el('span', 'cdsub', detail); d.style.fontSize = fs(.03, .054); node.append(d); }
    node.classList.toggle('up', upright);
    node.style.left = side + 'px'; node.style.right = side + 'px';
    node.style.borderRadius = (upright ? w * .04 : w * .016) + 'px';
    node.style.padding = upright ? (w * .05) + 'px ' + (w * .04) + 'px' : (w * .015) + 'px ' + (w * .03) + 'px';
    node.style.display = 'flex'; node.style.maxHeight = h * (upright ? .34 : .3) + 'px';
  };
  const nowBand = $('cdNow'), nextBand = $('cdNext'), onlyBox = $('cdOnly'), tag = $('cdTag');
  nowBand.style.display = nextBand.style.display = onlyBox.style.display = tag.style.display = 'none';
  let padTop = bandTop + topM, padBottom = bandBottom + botM, nextH = 0;
  if (only) {
    clear(onlyBox);
    const e = el('span', 'cdeye', 'UP NEXT'); e.style.fontSize = fs(.03, .054); e.style.letterSpacing = '.16em';
    const n = el('span', 'cdnm', cd.next.name); n.style.fontSize = fs(.12, .17); n.style.marginTop = (upright ? w * .05 : w * .022) + 'px';
    onlyBox.append(e, n);
    if (cd.next.detail) { const d = el('span', 'cdsub', cd.next.detail); d.style.fontSize = fs(.046, .07); d.style.marginTop = (upright ? w * .05 : w * .022) + 'px'; d.style.whiteSpace = 'normal'; onlyBox.append(d); }
    onlyBox.style.left = side + 'px'; onlyBox.style.right = side + 'px'; onlyBox.style.top = bandTop + 'px'; onlyBox.style.bottom = bandBottom + 'px';
    onlyBox.style.display = 'flex';
    return { only: true, room: 1, ink };
  }
  if (s.layout === 'current' && cd.now.name.trim()) {
    fill(nowBand, 'Now', cd.now.name, cd.now.by);
    nowBand.style.top = bandTop + topM + 'px';
    padTop += nowBand.offsetHeight + gap;
  }
  if (s.layout === 'next' && cd.next) {
    fill(nextBand, 'Up next', cd.next.name, cd.next.detail);
    nextBand.style.bottom = bandBottom + botM + 'px';
    nextH = nextBand.offsetHeight; padBottom += nextH + gap;
  }
  // The tag has its room always, so the digits keep their size.
  const tagH = upright ? w * .085 : h * .075;
  const paused = cd.moment === 'paused' || (cd.moment === 'overtime' && s.paused);
  const words = paused ? (over ? 'PAUSED · OVER TIME' : 'PAUSED') : over ? 'OVER TIME' : '';
  if (words) {
    clear(tag);
    const b = el('b', '', words);
    const pill = over && !paused;
    b.style.fontSize = tagH * .5 + 'px'; b.style.letterSpacing = '.18em'; b.style.padding = (tagH * .12) + 'px ' + (tagH * .5) + 'px';
    b.style.background = pill ? (solid ? dark : redInk) : vars['--c-band'];
    b.style.color = pill ? (solid ? '#e5333a' : t.background) : t.text;
    b.style.border = pill ? '0' : '1px solid ' + vars['--c-line'];
    tag.append(b); tag.style.display = 'flex';
  }
  tag.style.height = tagH + 'px'; tag.style.bottom = bandBottom + botM + (nextH ? nextH + gap : 0) + 'px';
  padBottom += tagH;
  stage.style.paddingTop = padTop + 'px'; stage.style.paddingBottom = padBottom + 'px';
  return { only: false, room: Math.max(.2, (h - padTop - padBottom) / h), ink, dim: moment === 'paused' };
}

function renderStage(s) {
  $('app').style.display = 'none';
  $('flip').style.display = 'none'; $('stageText').style.display = '';
  const stage = $('stage'); stage.style.display = 'flex';
  const text = $('stageText'); const note = $('stageNote');
  renderBand(s);
  // With a banner, the countdown keeps to the middle of the screen and is
  // a little smaller at most, so its digits stay clear of the band.
  const low = s.banner && s.banner.position !== 'top', high = s.banner && s.banner.position === 'top';
  stage.style.paddingTop = ''; stage.style.paddingBottom = '';
  let room = s.banner ? 0.88 : 1;
  note.style.bottom = low ? '23vh' : '';
  $('cd').style.display = 'none'; stage.classList.remove('cdpulse'); stage.style.boxShadow = '';
  const value = s.displayText || '';
  const h = window.innerHeight, w = window.innerWidth;
  // "Wrap long text": wrapped onto up to 3 lines, as large as fits.
  const wrap = s.wrap === true && value.trim() !== '';
  // A few words at a time, when the text is too wide for the LED sign.
  const group = s.sharing && !s.message && !s.blank && value ? wordsOf(s, wrap) : null;
  // Wrapped text too long for 3 lines scrolls, so it may be moving too.
  const moving = s.sharing && !s.message && !s.blank && value && (s.effect === 'scroll' || s.effect === 'flash' || wrap || !!group);
  const key = moving ? [s.effect, s.screenEffect, wrap, value, group ? group.words.join('\n') : '', s.speed, s.bold, s.italic, s.overtime, s.color, w, h].join('|') : '';
  // The same moving text as the last poll: leave it running.
  if (moving && motion && motion.key === key) { note.textContent = s.paused ? 'PAUSED' : ''; return; }
  // Scrolling text started again carries on where it was.
  stopMotion(moving && (s.effect === 'scroll' || wrap)); text.style.visibility = 'visible';
  // A full-screen cue's newer effect, if it has one; nothing otherwise.
  const fx = s.sharing && !s.message && !s.blank && !s.banner && value ? (s.screenEffect || null) : null;
  const fxKey = [value, s.color, s.bold, s.italic].join('|');
  setFx(text, ['pulse', 'flashHold', 'slideIn'].includes(fx) && !group ? fx : null, fxKey);
  stage.style.setProperty('--fx', flashColour(s.color));
  stage.style.setProperty('--fx-tint', flashTint(s.color));
  setFx(stage, fx === 'screenFlash' ? fx : null, fxKey);
  const bar = $('stageBar'); bar.style.color = s.color || '#fff';
  setBar(bar, fx === 'bar' ? s.cueTime : null);
  // A full-screen cue in a colour: its words in that colour (warm white
  // for amber) on warm charcoal, with a rule in its colour along the
  // bottom edge. White cues stay as they are.
  const card = s.sharing && !s.message && !s.blank && !s.banner && value.trim() !== '' && !!s.color && s.color.toLowerCase() !== '#ffffff';
  stage.classList.toggle('coloured', card);
  const rule = $('stageRule'); rule.style.display = card ? 'block' : 'none'; rule.style.background = card ? s.color : '';
  clear(text); note.textContent = ''; stage.style.background = card ? '#1a1712' : '#000'; stage.style.textAlign = 'center'; text.style.width = ''; text.style.position = ''; text.style.top = ''; text.style.opacity = ''; text.style.whiteSpace = ''; text.classList.remove('wrapped');
  if (!s.sharing) { text.textContent = 'Waiting for the host. On the host, tap Show on stage screens on Live.'; text.style.fontSize = '4vh'; text.style.color = '#888'; return; }
  if (s.message) {
    renderMessage(stage, text, s.message); return;
  }
  if (s.blank) return;
  // The time of day fills the screen as a flip clock in the host's theme;
  // a banner keeps its band and the clock the room that is left.
  if (s.clock && !s.message && !card) {
    const bandH = s.banner ? 20 : 0;
    stage.style.paddingTop = s.banner && s.banner.position === 'top' ? bandH + 'vh' : '';
    stage.style.paddingBottom = s.banner && s.banner.position !== 'top' ? bandH + 'vh' : '';
    const theme = renderFlip(s, w, h * (1 - bandH / 100));
    stage.style.background = theme.background;
    clear(text); note.textContent = ''; text.style.display = 'none';
    return;
  }
  // The countdown in the theme's colours with its bands and progress line.
  let cdLook = null;
  if (s.countdown && !card) {
    cdLook = renderCountdown(s, s.countdown, w, h, high, low);
    if (cdLook.only) { clear(text); text.style.display = 'none'; return; }
    room = cdLook.room;
  }
  // A coloured full-screen cue in its colour, amber's in warm white, with
  // its colour in the rule too; otherwise white, or red in overtime.
  text.style.color = cdLook ? cdLook.ink : card ? cardInk(s.color) : s.color || (s.overtime ? '#ff4d4d' : '#fff');
  if (cdLook && cdLook.dim) text.style.opacity = '.45';
  text.style.fontWeight = s.bold ? '800' : '500';
  text.style.fontStyle = s.italic ? 'italic' : 'normal';
  if (s.paused && !cdLook) note.textContent = 'PAUSED';
  let effect = s.effect, wrapAt = 0;
  if (wrap) {
    text.textContent = value; text.classList.add('wrapped');
    // Clear of the countdown bar near the bottom, when there is one.
    wrapAt = wrapSize(text, 3, fx === 'bar' ? h * 0.74 : Math.min(h * 0.9, h - w * 0.08), h * 0.12, h * 0.9);
    // Wrapped text holds still (or flashes), and a newer effect plays on
    // the whole block; too long for that, it scrolls.
    // A scrolling fallback drops its own effect and bar, as the app's
    // screens do; a screen flash still plays.
    if (wrapAt) { if (effect !== 'flash') { placeBar(bar, text); return; } } else { text.classList.remove('wrapped'); clear(text); effect = 'scroll'; setFx(text, null, ''); setBar(bar, null); }
  }
  if (group) { startMotion(text, value, Object.assign({}, s, { effect: 'words', group }), key); return; }
  if (moving && (effect === 'scroll' || effect === 'flash')) { startMotion(text, value, Object.assign({}, s, { effect, wrapAt }), key); return; }
  const time = TIME.test(value);
  if (time) {
    // A time: each digit in a place as wide as the widest digit (and A
    // and P in one place as wide as either), so the time keeps its size
    // and every digit its place as it counts, whatever the browser's font.
    // Each colon is its own span, so only its brightness changes when it
    // blinks. It stays on one line.
    text.style.whiteSpace = 'nowrap';
    text.style.setProperty('--dg', placeWidth(text, '0123456789', 0.6) + 'em');
    text.style.setProperty('--ap', placeWidth(text, 'AP', 0.7) + 'em');
    for (const char of value) text.append(/[0-9]/.test(char) ? el('span', 'dg', char) : /[AP]/.test(char) ? el('span', 'ap', char) : char === ':' && s.ticking ? el('span', 'colon', ':') : document.createTextNode(char));
    if (s.ticking && value !== colon.text) { colon.text = value; colon.at = performance.now(); }
  } else {
    text.style.removeProperty('--dg'); text.style.removeProperty('--ap');
    text.textContent = value;
  }
  fit(text, value || ' ', room);
  if (time) {
    // Narrower if its places are wider than the screen allows. They are
    // set in em, so this depends only on the characters' kinds, not on
    // which digits are showing.
    const most = w * 0.92, wide = text.getBoundingClientRect().width;
    if (wide > most) text.style.fontSize = parseFloat(text.style.fontSize) * most / wide + 'px';
  }
  placeBar(bar, text);
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
