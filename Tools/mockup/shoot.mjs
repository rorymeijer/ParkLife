// Renders the ParkLife design mockup to PNG screenshots with headless Chromium.
import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = path.join(here, 'out', 'mockup.html');
const outDir = path.join(here, '..', '..', 'docs', 'screenshots');
fs.mkdirSync(outDir, { recursive: true });

const shots = [
  { screen: 'ipad-bookings',   file: '01-ipad-park-and-bookings.png', width: 1366, height: 1024 },
  { screen: 'ipad-park',       file: '02-ipad-overlay-and-objectives.png', width: 1366, height: 1024 },
  { screen: 'iphone-build',    file: '03-iphone-build-mode.png',      width: 402,  height: 874 },
  { screen: 'iphone-finances', file: '04-iphone-finances.png',        width: 402,  height: 874 },
  { screen: 'iphone-guest',    file: '05-iphone-guest-inspector.png', width: 402,  height: 874 }
];

// The container ships Chromium at a fixed path; point Playwright at it rather than downloading.
const executablePath = process.env.PARKLIFE_CHROMIUM
  || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const browser = await chromium.launch({
  executablePath: fs.existsSync(executablePath) ? executablePath : undefined,
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--force-color-profile=srgb']
});
for (const shot of shots) {
  const page = await browser.newPage({
    viewport: { width: shot.width, height: shot.height },
    deviceScaleFactor: 2
  });
  await page.goto('file://' + source + '?screen=' + shot.screen);
  await page.waitForFunction(() => document.body.dataset.ready === 'true', null, { timeout: 30000 });
  await page.waitForTimeout(350);
  await page.screenshot({ path: path.join(outDir, shot.file) });
  console.log('wrote', shot.file, `${shot.width}×${shot.height}`);
  await page.close();
}
await browser.close();
