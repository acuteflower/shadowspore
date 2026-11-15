// Talks to the Rust side. Outside Tauri (plain `npm run dev` in a browser) a small
// mock answers instead, so the UI can be designed and checked without the app shell.
import changelogBundled from "../../CHANGELOG.md?raw";

export const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

let tauriInvoke = null;
let tauriWindow = null;

async function core() {
  if (!tauriInvoke) tauriInvoke = (await import("@tauri-apps/api/core")).invoke;
  return tauriInvoke;
}

export async function invoke(cmd, args = {}) {
  if (inTauri) return (await core())(cmd, args);
  return mock(cmd, args);
}

export async function windowAction(action) {
  if (!inTauri) return;
  if (!tauriWindow) tauriWindow = (await import("@tauri-apps/api/window")).getCurrentWindow();
  if (action === "minimize") return tauriWindow.minimize();
  if (action === "maximize") return tauriWindow.toggleMaximize();
  if (action === "close") return tauriWindow.close();
}

export async function changelogText() {
  try {
    const live = await invoke("get_changelog");
    if (live && live.trim()) return live;
  } catch {
    /* fall back to the bundled copy */
  }
  return changelogBundled;
}

const imageCache = new Map();
export function docImage(rel) {
  if (!imageCache.has(rel)) {
    imageCache.set(
      rel,
      invoke("read_doc_image", { rel }).catch(() => ""),
    );
  }
  return imageCache.get(rel);
}

// ---------------------------------------------------------------- browser mock
const mockState = {
  session: { logged_in: false, server_url: "http://127.0.0.1:7350", cloud_save: {} },
  friends: [
    { user_id: "a", uid: "100231", username: "mooswanderer", display_name: "Mooswanderer", online: true, state: 0 },
    { user_id: "b", uid: "100877", username: "glutbeere", display_name: "Glutbeere", online: false, state: 0 },
    { user_id: "c", uid: "101004", username: "nebelfuchs", display_name: "Nebelfuchs", online: true, state: 2 },
  ],
  settings: {
    server_url: "http://127.0.0.1:7350",
    server_key: "shadowspore_dev_server_key",
    game_exe_path: "",
    godot_exe_path: "",
    manifest_url: "",
  },
};

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function mock(cmd, args) {
  await wait(120);
  const params = new URLSearchParams(location.search);
  switch (cmd) {
    case "restore_session":
      if (params.has("login")) return mock("login_email", { email: "ellie@lichtung.de" });
      return mockState.session;
    case "login_email":
      mockState.session = {
        logged_in: true,
        user_id: "me",
        username: "ellie",
        display_name: "Ellie",
        uid: "100002",
        world_join_mode: "friends",
        server_url: "http://127.0.0.1:7350",
        cloud_save: { has_save: true, day: 14, time: 0.62, saved_at: Math.floor(Date.now() / 1000) - 5400 },
      };
      return mockState.session;
    case "logout":
      mockState.session = { logged_in: false, cloud_save: {} };
      return mockState.session;
    case "refresh_profile":
      return mockState.session;
    case "list_friends":
      return mockState.friends;
    case "add_friend":
    case "accept_friend":
    case "remove_friend":
      return null;
    case "get_game_status":
      return {
        mode: params.has("missing") ? "missing" : "dev",
        ready: !params.has("missing"),
        resolved_exe: "C:/Godot/Godot_v4.7-stable_win64.exe",
        resolved_project_dir: __REPO_ROOT__,
        local_version: "dev",
        remote_version: "",
        update_available: params.has("update"),
        status_label: params.has("missing") ? "Spiel nicht gefunden" : "Dev-Modus bereit (Godot 4.7)",
      };
    case "get_settings":
      return { ...mockState.settings };
    case "save_settings":
      mockState.settings = { ...args.settings };
      return mockState.settings;
    case "launch_game":
      await wait(900);
      return "Dev-Start via Godot";
    case "get_changelog":
      return "";
    case "read_doc_image":
      return `/@fs/${__REPO_ROOT__}/${args.rel}`;
    case "open_external":
      window.open(args.url, "_blank");
      return null;
    default:
      throw new Error(`Unbekannter Befehl: ${cmd}`);
  }
}
