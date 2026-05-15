// Kill any process listening on port 3000 before launching Vite.
// Cross-shell, no PowerShell, no interactive prompts.
const { exec } = require('child_process');

const isWin = process.platform === 'win32';
const cmd = isWin
  ? 'netstat -ano | findstr :3000 | findstr LISTENING'
  : "lsof -i :3000 -t";

exec(cmd, { windowsHide: true }, (err, out) => {
  if (err || !out) {
    // Nothing on port 3000 — silent exit.
    return;
  }
  const pids = new Set();
  out.split(/\r?\n/).forEach((line) => {
    const t = line.trim();
    if (!t) return;
    const parts = t.split(/\s+/);
    const pid = isWin ? parts[parts.length - 1] : t;
    if (/^\d+$/.test(pid)) pids.add(pid);
  });
  if (pids.size === 0) return;
  const kill = isWin ? (p) => `taskkill /F /PID ${p}` : (p) => `kill -9 ${p}`;
  pids.forEach((pid) => {
    exec(kill(pid), { windowsHide: true }, () => {});
  });
});
