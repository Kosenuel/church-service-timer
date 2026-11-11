// Renders the Google Play store graphics into play/graphics/ from the app's
// golden screenshots (test/goldens) and launcher icon. Test data only.
//
//   node scripts/play_assets.js
//
// Needs Playwright with Chromium (`npm i -g playwright && npx playwright
// install chromium`, or any environment where require('playwright') works).
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '..');
const out = path.join(root, 'play', 'graphics');
// Embedded as data URLs: a page set from a string can't read local files.
const dataUrl = (file, type) =>
  `data:${type};base64,${fs.readFileSync(file).toString('base64')}`;
const golden = (n) => dataUrl(path.join(root, 'test', 'goldens', n + '.png'), 'image/png');
const font = (f) => dataUrl(path.join(root, 'assets', 'fonts', f), 'font/ttf');

const bg = '#0a1210', panel = '#131d1a', lime = '#c9f96c', text = '#e4e7de', muted = '#9caaa5';

// The launcher icon's line art (android/app/src/main/res/drawable/
// ic_church_timer_foreground.xml), cropped to the mark.
const mark = (size, viewBox = '14 13 80 80') =>
  `<svg width="${size}" height="${size}" viewBox="${viewBox}" xmlns="http://www.w3.org/2000/svg"><path fill="none" stroke="${lime}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" d="M54,23v13M48,28h12M39,49v-2l15,-11l15,11v2l12,9v25h-54v-25zM39,49v34M69,49v34M48,83v-16q0,-8 6,-8q6,0 6,8v16M32,63v7M76,63v7M51,49h6"/></svg>`;

const page = (w, h, body) => `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:R;src:url(${font('Roboto-Regular.ttf')})}
@font-face{font-family:R;font-weight:700;src:url(${font('Roboto-Bold.ttf')})}
*{box-sizing:border-box;margin:0}
html,body{width:${w}px;height:${h}px;overflow:hidden;background:${bg};color:${text};font-family:R,sans-serif}
.glow{position:absolute;inset:0;background:radial-gradient(ellipse at 50% 0%,#1d3a24 0%,${bg} 60%)}
</style></head><body><div class="glow"></div>${body}</body></html>`;

const phone = [
  ['phone-1-live', 'theme-midnight_lime', 'Run the service with confidence', 'A clear countdown for every segment, with warnings before time runs out'],
  ['phone-2-program', 'program-detail', 'Plan once, use every week', 'Segments, speakers and private notes, ready to load in seconds'],
  ['phone-3-standing-by', 'welcome-sharing-020', 'Start a service or a quick timer', 'Share to stage screens and web screens on the same Wi-Fi'],
  ['phone-4-report', 'report-detail-phone', 'See how each service really ran', 'On time, over or under, segment by segment, ready to print'],
  ['phone-5-warnings', 'warnings-settings-phone', 'Warnings that reach the stage', 'Stage cues and phone alerts at the times you choose'],
  ['phone-6-themes', 'appearance-phone', 'Make it yours', '13 themes in light and dark, your church logo and banner'],
  ['phone-7-royal-navy', 'theme-royal_navy', 'Your colours on Live', 'Royal Navy, one of 13 themes, during a running service'],
];
const tablet = [
  ['tablet-1-live', 'tablet-live', 'Made for tablets too', 'The countdown, rundown and stage preview side by side'],
  ['tablet-2-programs', 'programs-tablet-021', 'Your programs at a glance', 'Pin, search and edit the plans you run every week'],
  ['tablet-3-stage', 'stage-next-segment', 'A big, calm stage screen', 'Any phone or tablet becomes a countdown for the speaker'],
  ['tablet-4-message', 'stage-rich-message', 'Quiet messages to the stage', 'Send a short note to one screen or all of them'],
];

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const shot = async (name, w, h, html) => {
    const p = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    await p.setContent(html, { waitUntil: 'load' });
    await p.evaluate(() => document.fonts.ready);
    await p.screenshot({ path: path.join(out, name + '.png') });
    await p.close();
    console.log('wrote', name + '.png', `${w}x${h}`);
  };

  // App icon: 512 × 512, full-bleed (Play rounds the corners itself).
  await shot('icon-512', 512, 512, page(512, 512,
    `<div style="position:absolute;inset:0;background:${bg};display:grid;place-items:center">${mark(512)}</div>`));

  // Feature graphic: 1024 × 500.
  await shot('feature-graphic', 1024, 500, page(1024, 500, `
    <div style="position:absolute;left:64px;top:0;bottom:0;width:560px;display:flex;flex-direction:column;justify-content:center;gap:18px">
      <div style="width:96px;height:96px;border-radius:24px;background:${panel};display:grid;place-items:center">${mark(84)}</div>
      <div style="font-size:52px;font-weight:700;line-height:1.05">Church Service Timer</div>
      <div style="font-size:26px;color:${muted};line-height:1.3">Calm, clear timing for every service, on your phone, the stage and the LED sign.</div>
    </div>
    <img src="${golden('theme-midnight_lime')}" style="position:absolute;right:70px;top:40px;width:300px;border-radius:28px;border:6px solid #24322d;box-shadow:0 20px 60px #000a">`));

  const card = (w, h, file, title, sub, landscape) => {
    const pad = landscape ? 120 : 80;
    const titleSize = landscape ? 84 : 76, subSize = landscape ? 44 : 40;
    const imgBox = landscape
      ? `left:${pad}px;right:${pad}px;top:420px;bottom:90px`
      : `left:${pad + 40}px;right:${pad + 40}px;top:470px;bottom:0;overflow:hidden`;
    return page(w, h, `
      <div style="position:absolute;left:${pad}px;right:${pad}px;top:${landscape ? 110 : 130}px">
        <div style="font-size:${titleSize}px;font-weight:700;line-height:1.1">${title}</div>
        <div style="font-size:${subSize}px;color:${muted};line-height:1.35;margin-top:22px">${sub}</div>
      </div>
      <div style="position:absolute;${imgBox};display:flex;justify-content:center;align-items:${landscape ? 'center' : 'flex-start'}">
        <img src="${golden(file)}" style="${landscape ? 'height:100%;max-width:100%;object-fit:contain' : 'width:100%'};border-radius:${landscape ? 28 : 44}px ${landscape ? 28 : 44}px ${landscape ? 28 : 0}px ${landscape ? 28 : 0}px;border:8px solid #24322d;${landscape ? '' : 'border-bottom:0;'}box-shadow:0 30px 80px #000c">
      </div>`);
  };
  for (const [name, file, title, sub] of phone) await shot(name, 1080, 1920, card(1080, 1920, file, title, sub, false));
  for (const [name, file, title, sub] of tablet) await shot(name, 2560, 1600, card(2560, 1600, file, title, sub, true));
  await browser.close();
})();
