import path from 'path';
import fs from 'fs';
import { defineConfig, loadEnv, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

const tokenStockSavePlugin = (): Plugin => ({
  name: 'tokenstock-save',
  configureServer(server) {
    server.middlewares.use('/api/save', (req, res) => {
      if (req.method !== 'POST') {
        res.statusCode = 405;
        res.end('Method Not Allowed');
        return;
      }
      const url = new URL(req.url || '', 'http://localhost');
      const ext = (url.searchParams.get('ext') || '').toLowerCase();
      const filename = url.searchParams.get('filename') || '';
      const subfolderMap: Record<string, string> = { png: 'PNG', gif: 'GIF', webm: 'WEBM' };
      const sub = subfolderMap[ext];
      if (!sub || !filename || /[\\/]/.test(filename)) {
        res.statusCode = 400;
        res.end('Bad Request');
        return;
      }
      const targetDir = path.resolve(__dirname, 'AnimStock', 'Tokens', sub);
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
