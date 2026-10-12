// Render the video covers: cover-4x3.png (1440x1080) and cover-3x4.png (1080x1440), at 2x for sharpness.
// Usage: node cover.js
const puppeteer = require('puppeteer-core');
const path = require('path');

const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SIZES = { '43': [1440, 1080, 'cover-4x3.png'], '34': [1080, 1440, 'cover-3x4.png'] };

(async () => {
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--allow-file-access-from-files', '--hide-scrollbars'] });
  const page = await browser.newPage();
  for (const [r, [w, h, out]] of Object.entries(SIZES)) {
    await page.setViewport({ width: w, height: h, deviceScaleFactor: 2 });
    await page.goto('file://' + path.join(__dirname, 'cover.html') + '?r=' + r, { waitUntil: 'load' });
    await page.evaluate(() => Promise.all([document.fonts.ready, ...[...document.images].map(i => i.decode())]));
    await page.screenshot({ path: path.join(__dirname, out), clip: { x: 0, y: 0, width: w, height: h } });
    console.log('wrote', out);
  }
  await browser.close();
})();
