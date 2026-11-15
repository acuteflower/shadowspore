import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  DEFAULT_DEV_PORT,
  findAvailablePort,
  getLauncherDir,
  parsePort,
} from "./port-helpers.mjs";

const launcherDir = getLauncherDir();
const tauriBin = path.resolve(launcherDir, "node_modules", "@tauri-apps", "cli", "tauri.js");
const rawArgs = process.argv.slice(2);

function runTauri(cliArgs, extraEnv, onCleanup) {
  const child = spawn(process.execPath, [tauriBin, ...cliArgs], {
    cwd: launcherDir,
    stdio: "inherit",
    env: {
      ...process.env,
      ...extraEnv,
    },
  });

  const forwardSignal = (sig) => {
    if (!child.killed) {
      child.kill(sig);
    }
  };
  process.on("SIGINT", forwardSignal);
  process.on("SIGTERM", forwardSignal);
  child.on("exit", (code, signal) => {
    onCleanup?.();
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 0);
  });
}

async function main() {
  const isDev = rawArgs[0] === "dev";
  const isMetaFlag =
    rawArgs.includes("-h") ||
    rawArgs.includes("--help") ||
    rawArgs.includes("-V") ||
    rawArgs.includes("--version");
  const skipsDevServer = rawArgs.includes("--no-dev-server");

  if (!isDev || isMetaFlag || skipsDevServer) {
    runTauri(rawArgs, {});
    return;
  }

  const preferredPort = parsePort(process.env.SHADOWSPORE_DEV_PORT, DEFAULT_DEV_PORT);
  const { port, fallbackUsed } = await findAvailablePort(preferredPort);

  let finalArgs = rawArgs;
  let cleanup = null;

  if (fallbackUsed || process.env.SHADOWSPORE_DEV_PORT) {
    if (fallbackUsed) {
      console.log(
        `[tauri-dev] Port ${preferredPort} ist belegt -> Ausweich-Port http://localhost:${port} aktiviert.`
      );
    }
    const tmpCfgPath = path.join(os.tmpdir(), `shadowspore-tauri-dev-${process.pid}.json`);
    fs.writeFileSync(
      tmpCfgPath,
      JSON.stringify({ build: { devUrl: `http://localhost:${port}` } }),
      "utf8"
    );
    finalArgs = ["dev", "-c", tmpCfgPath, ...rawArgs.slice(1)];
    cleanup = () => {
      try {
        fs.rmSync(tmpCfgPath, { force: true });
      } catch {
        // ignore temp cleanup errors on exit
      }
    };
  }

  runTauri(finalArgs, { SHADOWSPORE_DEV_PORT: String(port) }, cleanup);
}

main().catch((err) => {
  console.error("[tauri-dev] Start fehlgeschlagen:", err instanceof Error ? err.message : err);
  process.exit(1);
});
