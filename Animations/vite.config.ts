import path from 'path';
import fs from 'fs';
import { defineConfig, loadEnv, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

const tokenStockSavePlugin = (): Plugin => ({
  name: 'tokenstock-save',
  configureServer(server) {
    // List files in a kind/type folder, sorted by modification time desc
    server.middlewares.use('/api/list', (req, res) => {
      if (req.method !== 'GET') {
        res.statusCode = 405;
        res.end('Method Not Allowed');
        return;
      }
      const url = new URL(req.url || '', 'http://localhost');
      const kind = (url.searchParams.get('kind') || 'tokens').toLowerCase();
      const type = (url.searchParams.get('type') || '').toLowerCase();
      const kindFolderMap: Record<string, string> = { tokens: 'Tokens', dice: 'Dices' };
      const subfolderMap: Record<string, string> = { png: 'PNG', gif: 'GIF', webm: 'WEBM' };
      const kindFolder = kindFolderMap[kind];
      const sub = subfolderMap[type];
      if (!kindFolder || !sub) {
        res.statusCode = 400;
        res.end('Bad Request');
        return;
      }
      const dir = path.resolve(__dirname, 'AnimStock', kindFolder, sub);
      try {
        if (!fs.existsSync(dir)) {
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify({ files: [] }));
          return;
        }
        const files = fs.readdirSync(dir)
          .filter((name: string) => !name.startsWith('_') && !name.startsWith('.'))
          .map((name: string) => {
            const stat = fs.statSync(path.join(dir, name));
            return { name, mtime: stat.mtimeMs, size: stat.size };
          })
          .filter((f: any) => f.size > 0)
          .sort((a: any, b: any) => b.mtime - a.mtime);
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ files }));
      } catch (e: any) {
        res.statusCode = 500;
        res.end(String(e?.message || e));
      }
    });

    // Serve a single file from a kind/type folder
    server.middlewares.use('/api/file', (req, res) => {
      if (req.method !== 'GET') {
        res.statusCode = 405;
        res.end('Method Not Allowed');
        return;
      }
      const url = new URL(req.url || '', 'http://localhost');
      const kind = (url.searchParams.get('kind') || 'tokens').toLowerCase();
      const type = (url.searchParams.get('type') || '').toLowerCase();
      const name = url.searchParams.get('name') || '';
      const kindFolderMap: Record<string, string> = { tokens: 'Tokens', dice: 'Dices' };
      const subfolderMap: Record<string, string> = { png: 'PNG', gif: 'GIF', webm: 'WEBM' };
      const kindFolder = kindFolderMap[kind];
      const sub = subfolderMap[type];
      if (!kindFolder || !sub || !name || /[\\/]/.test(name) || !/^[\w. -]+$/.test(name)) {
        res.statusCode = 400;
        res.end('Bad Request');
        return;
      }
      const filePath = path.resolve(__dirname, 'AnimStock', kindFolder, sub, name);
      if (!fs.existsSync(filePath)) {
        res.statusCode = 404;
        res.end('Not Found');
        return;
      }
      const contentType = type === 'png' ? 'image/png' : type === 'gif' ? 'image/gif' : 'video/webm';
      res.setHeader('Content-Type', contentType);
      fs.createReadStream(filePath).pipe(res);
    });

    // Trigger asset generation by driving the live studio in a headless browser.
    // POST /api/generate  body: GenerateSpec (see App.tsx).
    // Returns once all files have been written to disk via /api/save.
    server.middlewares.use('/api/generate', (req, res) => {
      if (req.method !== 'POST') {
        res.statusCode = 405;
        res.end('Method Not Allowed');
        return;
      }
      const chunks: Buffer[] = [];
      req.on('data', (c: Buffer) => chunks.push(c));
      req.on('end', async () => {
        let spec: any;
        try {
          spec = JSON.parse(Buffer.concat(chunks).toString('utf-8'));
        } catch (e: any) {
          res.statusCode = 400;
          res.end(`Bad JSON: ${e?.message || e}`);
          return;
        }
        const chromePath = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
        try {
          // Lazy-load puppeteer-core so the plugin still loads when it's not installed.
          const puppeteer = (await import('puppeteer-core')).default;
          const browser = await puppeteer.launch({
            executablePath: chromePath,
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox'],
            defaultViewport: { width: 1600, height: 900 },
          });
          try {
            const page = await browser.newPage();
            page.on('console', (msg: any) => console.log('[studio]', msg.text()));
            await page.goto('http://localhost:3000/', { waitUntil: 'networkidle2', timeout: 30000 });
            await page.waitForFunction('typeof window.studioGenerate === "function"', { timeout: 10000 });
            const result = await page.evaluate((s: any) => (window as any).studioGenerate(s), spec);
            await new Promise((r) => setTimeout(r, 1500)); // flush save round-trips
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ ok: true, result }));
          } finally {
            await browser.close();
          }
        } catch (e: any) {
          res.statusCode = 500;
          res.end(String(e?.message || e));
        }
      });
    });

    server.middlewares.use('/api/save', (req, res) => {
      if (req.method !== 'POST') {
        res.statusCode = 405;
        res.end('Method Not Allowed');
        return;
      }
      const url = new URL(req.url || '', 'http://localhost');
      const ext = (url.searchParams.get('ext') || '').toLowerCase();
      const filename = url.searchParams.get('filename') || '';
      const kind = (url.searchParams.get('kind') || 'tokens').toLowerCase();
      const subfolderMap: Record<string, string> = { png: 'PNG', gif: 'GIF', webm: 'WEBM' };
      const kindFolderMap: Record<string, string> = { tokens: 'Tokens', dice: 'Dices' };
      const sub = subfolderMap[ext];
      const kindFolder = kindFolderMap[kind];
      if (!sub || !filename || !kindFolder || /[\\/]/.test(filename)) {
        res.statusCode = 400;
        res.end('Bad Request');
        return;
      }
      const targetDir = path.resolve(__dirname, 'AnimStock', kindFolder, sub);
      fs.mkdirSync(targetDir, { recursive: true });
      const targetPath = path.join(targetDir, filename);

      const chunks: Buffer[] = [];
      req.on('data', (c: Buffer) => chunks.push(c));
      req.on('end', () => {
        try {
          fs.writeFileSync(targetPath, Buffer.concat(chunks));
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify({ ok: true, path: targetPath }));
        } catch (e: any) {
          res.statusCode = 500;
          res.end(String(e?.message || e));
        }
      });
    });
  },
});

export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, '.', '');
    return {
      server: {
        port: 3000,
        strictPort: true,
        host: '0.0.0.0',
        open: false,
      },
      plugins: [react(), tokenStockSavePlugin()],
      define: {
        'process.env.API_KEY': JSON.stringify(env.GEMINI_API_KEY),
        'process.env.GEMINI_API_KEY': JSON.stringify(env.GEMINI_API_KEY)
      },
      resolve: {
        alias: {
          '@': path.resolve(__dirname, '.'),
        }
      }
    };
});
