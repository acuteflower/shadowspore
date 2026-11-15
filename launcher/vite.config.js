import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
// The launcher reuses the game's own art (assets/, docs/img/) and CHANGELOG.md.
const repoRoot = path.resolve(here, "..");

export default defineConfig({
  clearScreen: false,
  define: {
    __REPO_ROOT__: JSON.stringify(repoRoot.replace(/\\/g, "/")),
  },
  server: {
    port: 1420,
    strictPort: true,
    fs: {
      allow: [repoRoot],
    },
    watch: {
      ignored: ["**/src-tauri/**"],
    },
  },
  build: {
    assetsInlineLimit: 0,
    chunkSizeWarningLimit: 1200,
  },
});
