// Renders kadron-intro.html frame by frame into an MP4.
//   node render.js [out.mp4] [--frames-dir dir]
// Needs puppeteer-core (NODE_PATH), Chrome (CHROME) and ffmpeg on PATH.
const path = require('path');
const { spawn } = require('child_process');
const puppeteer = require('puppeteer-core');
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';

const output = path.resolve(process.argv[2] || path.join(__dirname, 'kadron-intro.mp4'));
const page_url = 'file:///' + path.join(__dirname, 'kadron-intro.html').replace(/\\/g, '/');

(async () => {
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ['--force-device-scale-factor=1'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });
  await page.goto(page_url);
  await page.evaluate(async () => {
    await Promise.all([
      document.fonts.load('600 100px "Segoe UI"'),
      document.fonts.load('italic 400 40px Georgia'),
      document.fonts.load('700 16px Consolas'),
      document.fonts.load('400 16px Consolas'),
    ]);
  });
  const { FPS, DURATION } = await page.evaluate(() => ({ FPS: window.KADRON_INTRO.FPS, DURATION: window.KADRON_INTRO.DURATION }));
  const frames = Math.round(FPS * DURATION);

  const ffmpeg = spawn('ffmpeg', [
    '-v', 'error', '-y',
    '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart', output,
  ], { stdio: ['pipe', 'inherit', 'inherit'] });

  for (let i = 0; i < frames; i++) {
    const data = await page.evaluate(t => {
      window.KADRON_INTRO.renderFrame(t);
      return document.getElementById('c').toDataURL('image/png').split(',')[1];
    }, i / FPS);
    if (!ffmpeg.stdin.write(Buffer.from(data, 'base64')))
      await new Promise(r => ffmpeg.stdin.once('drain', r));
    if (i % 30 === 0) process.stdout.write(`frame ${i}/${frames}\r`);
  }
  ffmpeg.stdin.end();
  await new Promise(r => ffmpeg.on('close', r));
  await browser.close();
  console.log(`\nwrote ${output} (${frames} frames)`);
})();
