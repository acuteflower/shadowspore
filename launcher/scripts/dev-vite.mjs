import { spawn } from "node:child_process";
import path from "node:path";
import {
  DEFAULT_DEV_PORT,
  findAvailablePort,
  getLauncherDir,
  isPortAvailable,
  parsePort,
  probeShadowsporeVite,
} from "./port-helpers.mjs";

const launcherDir = getLauncherDir();
const viteBin = path.resolve(launcherDir, "node_modules", "vite", "bin", "vite.js");
const args = process.argv.slice(2);
const standalone = args.includes("--standalone");
const passArgs = args.filter((a) => a !== "--standalone");

function runVite(port) {
  const child = spawn(
    process.execPath,
    [viteBin, "--port", String(port), "--strictPort", ...passArgs],
    {
      cwd: launcherDir,
      stdio: "inherit",
      env: {
        ...process.env,
        SHADOWSPORE_DEV_PORT: String(port),
      },
    }
  );

  const forwardSignal = (sig) => {
    if (!child.killed) {
      child.kill(sig);
    }
  };
  process.on("SIGINT", forwardSignal);
  process.on("SIGTERM", forwardSignal);
  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 0);
  });
}

function holdAliveForExistingServer() {
  const timer = setInterval(() => {}, 60000);
  const shutdown = () => {
    clearInterval(timer);
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

async function main() {
  const envPortRaw = process.env.SHADOWSPORE_DEV_PORT;
  const preferredPort = parsePort(envPortRaw, DEFAULT_DEV_PORT);

  if (standalone) {
    const { port, fallbackUsed } = await findAvailablePort(preferredPort);
    if (fallbackUsed) {
      console.log(`[dev] Port ${preferredPort} ist belegt -> weiche auf http://localhost:${port} aus.`);
    }
    runVite(port);
    return;
  }

  // Tauri mode (`npm run dev:tauri`): use the port coordinated by `tauri-cli.mjs`, or inspect 1420.
  if (envPortRaw) {
    runVite(preferredPort);
    return;
  }

  if (await isPortAvailable(preferredPort)) {
    runVite(preferredPort);
    return;
  }

  if (await probeShadowsporeVite(preferredPort)) {
    console.log(
      `[dev] Port ${preferredPort} dient bereits Shadowspore Launcher - nutze laufenden Vite-Server weiter.`
    );
    console.log(
      `[dev] Tipp: 'npm run tauri dev' weicht bei belegtem Port automatisch auf ${preferredPort + 1}+ aus.`
    );
    holdAliveForExistingServer();
    return;
  }

  console.error(
    `[dev] Port ${preferredPort} ist durch einen fremden Prozess belegt, aber Tauri erwartet http://localhost:${preferredPort}.`
  );
  console.error(
    `[dev] Bitte 'npm run tauri dev' ausfuehren (waehlt automatisch einen freien Ausweich-Port ab ${preferredPort + 1}).`
  );
  process.exit(1);
}

main().catch((err) => {
  console.error("[dev] Start fehlgeschlagen:", err instanceof Error ? err.message : err);
  process.exit(1);
});
