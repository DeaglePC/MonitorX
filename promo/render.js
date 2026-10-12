// Render video.html frame by frame with headless Chrome, then encode with ffmpeg.
// Usage: node render.js            -> full render to MonitorX-promo.mp4
//        node render.js 3 8.2 12   -> stills at those times into frames/still-*.png
const puppeteer = require('puppeteer-core');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const FPS = 30;
// Homebrew ffmpeg can break on dylib upgrades; prefer the bundled static build.
const FFMPEG = process.env.FFMPEG || require('ffmpeg-static');
const OUT = path.join(__dirname, 'frames');

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--allow-file-access-from-files', '--hide-scrollbars'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(__dirname, 'video.html'), { waitUntil: 'load' });
  await page.evaluate(() => Promise.all([document.fonts.ready, ...[...document.images].map(i => i.decode())]));

  const stills = process.argv.slice(2).map(Number);
  if (stills.length) {
    for (const t of stills) {
      await page.evaluate(t => render(t), t);
      await page.screenshot({ path: path.join(OUT, `still-${t}.png`) });
    }
    await browser.close();
    return;
  }

  const dur = await page.evaluate(() => DUR);
  const n = Math.round(dur * FPS);
  for (let i = 0; i < n; i++) {
    await page.evaluate(t => render(t), i / FPS);
    await page.screenshot({ path: path.join(OUT, `f${String(i).padStart(4, '0')}.png`) });
    if (i % 90 === 0) console.log(`frame ${i}/${n}`);
  }
  await browser.close();

  const wav = path.join(__dirname, 'music.wav');
  if (!fs.existsSync(wav)) execFileSync('python3', [path.join(__dirname, 'music.py'), wav], { stdio: 'inherit' });
  execFileSync(FFMPEG, ['-y', '-hide_banner', '-loglevel', 'error',
    '-framerate', String(FPS), '-i', path.join(OUT, 'f%04d.png'), '-i', wav,
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
    '-c:a', 'aac', '-b:a', '192k', '-shortest', path.join(__dirname, 'MonitorX-promo.mp4')], { stdio: 'inherit' });
  console.log('done -> MonitorX-promo.mp4');
})();
