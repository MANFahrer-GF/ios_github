const path = require('path');
const { chromium } = require(process.env.PW);
const jobs = require('./jobs.json');
const only = process.argv[2];
(async () => {
  const browser = await chromium.launch();
  for (const j of jobs) {
    if (only && !j.name.includes(only)) continue;
    const ctx = await browser.newContext({ viewport: { width: Math.round(j.w), height: Math.round(j.h) }, deviceScaleFactor: j.scale });
    const page = await ctx.newPage();
    await page.goto('file://' + path.join(__dirname, 'html', j.name + '.html'));
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    require('fs').mkdirSync(path.join(__dirname, 'png', j.dev), { recursive: true });
    await page.screenshot({ path: path.join(__dirname, 'png', j.dev, j.name + '.png'), omitBackground: false });
    await ctx.close();
  }
  await browser.close();
})();
