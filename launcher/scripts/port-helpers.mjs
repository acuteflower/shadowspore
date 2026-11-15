import http from "node:http";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const DEFAULT_DEV_PORT = 1420;
export const MAX_PORT_TRIES = 30;

export function getLauncherDir() {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
}

export function parsePort(raw, fallback = DEFAULT_DEV_PORT) {
  const n = Number(raw);
  return Number.isInteger(n) && n >= 1024 && n <= 65535 ? n : fallback;
}

function canBindHost(port, host) {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.unref();
    srv.once("error", (err) => {
      if (err && (err.code === "EADDRNOTAVAIL" || err.code === "EAFNOSUPPORT")) {
        resolve(true);
        return;
      }
      resolve(false);
    });
    srv.listen({ port, host, exclusive: true }, () => {
      srv.close(() => resolve(true));
    });
  });
}

/**
 * Checks both IPv4 and IPv6 loopback interfaces because Vite's `localhost`
 * listener on Windows commonly binds `::1` while leaving `127.0.0.1` unbound.
 */
export async function isPortAvailable(port) {
  const ipv4Ok = await canBindHost(port, "127.0.0.1");
  if (!ipv4Ok) {
    return false;
  }
  return canBindHost(port, "::1");
}

export async function findAvailablePort(startPort = DEFAULT_DEV_PORT, maxTries = MAX_PORT_TRIES) {
  for (let offset = 0; offset < maxTries; offset += 1) {
    const candidate = startPort + offset;
    if (candidate > 65535) {
      break;
    }
    if (await isPortAvailable(candidate)) {
      return { port: candidate, fallbackUsed: offset > 0 };
    }
  }
  throw new Error(
    `Kein freier Dev-Port zwischen ${startPort} und ${Math.min(65535, startPort + maxTries - 1)} gefunden.`
  );
}

function probeUrlForShadowspore(url) {
  return new Promise((resolve) => {
    const req = http.get(url, { timeout: 1200 }, (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        resolve(false);
        return;
      }
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => {
        if (body.length < 16384) {
          body += chunk;
        }
      });
      res.on("end", () => {
        resolve(body.includes("<title>Shadowspore</title>") && body.includes("/@vite/client"));
      });
    });
    req.on("timeout", () => {
      req.destroy();
      resolve(false);
    });
    req.on("error", () => resolve(false));
  });
}

export async function probeShadowsporeVite(port) {
  const candidates = [
    `http://localhost:${port}/`,
    `http://[::1]:${port}/`,
    `http://127.0.0.1:${port}/`,
  ];
  for (const url of candidates) {
    if (await probeUrlForShadowspore(url)) {
      return true;
    }
  }
  return false;
}
