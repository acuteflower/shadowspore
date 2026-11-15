// Talks to the Rust side. Outside Tauri (plain `npm run dev` in a browser) a small
// mock answers instead, so the UI can be designed and checked without the app shell.
import changelogBundled from "../../CHANGELOG.md?raw";

export const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

let tauriInvoke = null;
let tauriWindow = null;
let tauriListen = null;

async function core() {
  if (!tauriInvoke) tauriInvoke = (await import("@tauri-apps/api/core")).invoke;
  return tauriInvoke;
}

export async function invoke(cmd, args = {}) {
  if (inTauri) return (await core())(cmd, args);
  return mock(cmd, args);
}

export async function listenEvent(eventName, handler) {
  if (!inTauri) return () => {};
  if (!tauriListen) tauriListen = (await import("@tauri-apps/api/event")).listen;
  return tauriListen(eventName, (evt) => handler(evt.payload));
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
  session: { logged_in: false, server_url: "http://127.0.0.1:7350", cloud_save: {}, active_lobby: null },
  friends: [
    {
      user_id: "a",
      uid: "100231",
      username: "mooswanderer",
      display_name: "Mooswanderer",
      online: true,
      state: 0,
      world_join_mode: "open",
      role: "player",
      coop_active: true,
      coop_match_id: "mock-match-1",
      coop_world_name: "Lichtung",
      coop_join_mode: "open",
      coop_players: 1,
      coop_max_players: 4,
      avatar_url: "ellie_leere",
    },
    { user_id: "b", uid: "100877", username: "glutbeere", display_name: "Glutbeere", online: false, state: 0, world_join_mode: "ask", role: "player" },
    { user_id: "c", uid: "101004", username: "nebelfuchs", display_name: "Nebelfuchs", online: true, state: 2, world_join_mode: "ask", role: "tester" },
  ],
  notifications: [
    {
      id: "mock-n1",
      code: 101,
      subject: "Einladung",
      kind: "coop_invite",
      match_id: "mock-match-1",
      room_code: "AB12CD",
      world_name: "Lichtung",
      host_user_id: "a",
      host_uid: "100231",
      host_name: "Mooswanderer",
      join_mode: "open",
    },
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
      if (args.create) {
        throw new Error("Account-Erstellung nur mit Lizenzkey auf https://shadowspore.com moeglich.");
      }
      mockState.session = {
        logged_in: true,
        user_id: "me",
        username: "ellie",
        display_name: "Ellie",
        uid: "100002",
        role: "admin",
        world_join_mode: "ask",
        server_url: "http://127.0.0.1:7350",
        cloud_save: { has_save: true, day: 14, time: 0.62, level: 16, saved_at: Math.floor(Date.now() / 1000) - 5400 },
        active_lobby: null,
        license_active: true,
        license_edition: "founder",
        license_expires_at: 0,
        license_error: "",
        banned: false,
        ban_reason: "",
      };
      return mockState.session;
    case "admin_issue_license_key":
      return [
        {
          key: "SHADOW-MOCK-1234-ABCD",
          status: "unused",
          edition: args.edition || "standard",
          role_grant: args.roleGrant || "player",
          note: args.note || "",
          created_at: Math.floor(Date.now() / 1000),
          expires_at: args.expiresDays ? Math.floor(Date.now() / 1000) + args.expiresDays * 86400 : 0,
          claimed_by_uid: "",
          claimed_by_name: "",
          claimed_at: 0,
        },
      ];
    case "admin_list_license_keys":
      return [
        {
          key: "SHADOW-MOCK-1234-ABCD",
          status: "unused",
          edition: "founder",
          role_grant: "player",
          note: "Demo-Key",
          created_at: Math.floor(Date.now() / 1000),
          expires_at: 0,
          claimed_by_uid: "",
          claimed_by_name: "",
          claimed_at: 0,
        },
      ];
    case "admin_set_license":
    case "admin_set_ban":
    case "admin_kick_match_peer":
    case "admin_close_world":
      return null;
    case "admin_set_role":
      return mockState.session;
    case "admin_overview":
      return {
        total_accounts: 4,
        banned_accounts: 0,
        online_accounts: 2,
        active_worlds: 1,
        unused_keys: 1,
        claimed_keys: 3,
        revoked_keys: 0,
        security_events: 2,
        build_enforce: false,
        build_hash_count: 1,
      };
    case "admin_list_accounts":
      return [
        {
          user_id: "me",
          uid: "100000",
          username: "nxye",
          display_name: "nxye",
          email: "levinadamek@outlook.de",
          role: "admin",
          world_join_mode: "ask",
          license_active: true,
          license_edition: "founder",
          license_expires_at: 0,
          banned: false,
          ban_reason: "",
          created_at: Math.floor(Date.now() / 1000) - 86400,
          game_online: true,
          coop_active: false,
        },
        {
          user_id: "a",
          uid: "100231",
          username: "mooswanderer",
          display_name: "Mooswanderer",
          email: "moos@example.de",
          role: "player",
          world_join_mode: "private",
          license_active: true,
          license_edition: "standard",
          license_expires_at: 0,
          banned: false,
          ban_reason: "",
          created_at: Math.floor(Date.now() / 1000) - 43200,
          game_online: true,
          coop_active: true,
          coop_match_id: "mock-match-1",
          coop_world_name: "Lichtung",
          coop_room_code: "AB12CD",
          coop_join_mode: "private",
          coop_players: 2,
          coop_max_players: 4,
        },
      ];
    case "admin_list_active_worlds":
      return [
        {
          match_id: "mock-match-1",
          host_user_id: "a",
          host_uid: "100231",
          host_name: "Mooswanderer",
          world_name: "Lichtung",
          room_code: "AB12CD",
          join_mode: "private",
          player_count: 2,
          max_players: 4,
          updated_at: Math.floor(Date.now() / 1000),
          peers: [
            { peer_id: 1, user_id: "a", uid: "100231", role: "player", username: "mooswanderer", display_name: "Mooswanderer" },
            { peer_id: 2, user_id: "c", uid: "101004", role: "tester", username: "nebelfuchs", display_name: "Nebelfuchs" },
          ],
        },
      ];
    case "admin_force_join":
      return {
        ok: true,
        status: "approved",
        match_id: args.matchId || "mock-match-1",
        room_code: args.roomCode || "AB12CD",
        world_name: "Lichtung",
        join_mode: "private",
        host_user_id: "a",
        host_uid: "100231",
        host_name: "Mooswanderer",
      };
    case "admin_get_build_config":
    case "admin_register_build":
      return {
        enforce: Boolean(args.enforce),
        hash_list: [
          {
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            version: "0.1.0",
            added_at: Math.floor(Date.now() / 1000) - 3600,
          },
        ],
      };
    case "inspect_local_build":
      return {
        found: true,
        exe_path: "C:/Games/Shadowspore/Shadowspore.exe",
        version: "0.1.0",
        sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      };
    case "admin_list_security_events":
      return [
        {
          id: "mock-ev-1",
          kind: "ADMIN_FORCE_JOIN",
          severity: "warn",
          detail: "match=mock-match-1 host_uid=100231",
          user_id: "me",
          uid: "100000",
          username: "nxye",
          at: Math.floor(Date.now() / 1000),
        },
      ];
    case "logout":
      mockState.session = { logged_in: false, cloud_save: {}, active_lobby: null };
      return mockState.session;
    case "refresh_profile":
      return mockState.session;
    case "set_avatar":
      mockState.session = { ...mockState.session, avatar_url: args.avatar };
      return mockState.session;
    case "set_world_join_mode":
      mockState.session = { ...mockState.session, world_join_mode: args.mode };
      return mockState.session;
    case "list_friends":
      return mockState.friends;
    case "fetch_notifications":
      return mockState.notifications;
    case "dismiss_notification":
      mockState.notifications = mockState.notifications.filter((n) => n.id !== args.notificationId);
      return null;
    case "coop_invite_friend":
      return "mock-match-self";
    case "coop_request_join":
      return {
        ok: true,
        status: "approved",
        match_id: args.hostUserId === "a" ? "mock-match-1" : "mock-match-code",
        room_code: args.roomCode || "AB12CD",
        world_name: "Lichtung",
      };
    case "coop_respond_join_request":
      mockState.notifications = mockState.notifications.filter((n) => n.id !== args.notificationId);
      return null;
    case "coop_resolve_code":
      return {
        ok: true,
        match_id: "mock-match-1",
        room_code: String(args.roomCode || "AB12CD").toUpperCase(),
        world_name: "Lichtung",
        join_mode: "open",
        max_players: 4,
        player_count: 1,
        host_user_id: "a",
        host_uid: "100231",
        host_name: "Mooswanderer",
      };
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
        remote_version: params.has("update") ? "0.2.0" : "",
        update_available: params.has("update"),
        remote_changelog: "",
        remote_download_url: params.has("update") ? "https://shadowspore.com/updates/Shadowspore-0.2.0.zip" : "",
        remote_sha256: "",
        remote_size_bytes: 0,
        status_label: params.has("missing") ? "Spiel nicht gefunden" : "Dev-Modus bereit (Godot 4.7)",
      };
    case "install_game_update":
      await wait(600);
      return mock("get_game_status", {});
    case "get_settings":
      return { ...mockState.settings };
    case "get_server_presets":
      return {
        dev_url: "http://127.0.0.1:7350",
        dev_key: "shadowspore_dev_server_key",
        live_url: "https://s.shadowspore.com",
        live_key: "shadowspore_live_client_v1",
        live_manifest_url: "https://shadowspore.com/updates/manifest.json",
      };
    case "save_settings":
      mockState.settings = { ...args.settings };
      return mockState.settings;
    case "game_running":
      return Date.now() < (mockState.runningUntil || 0) || params.has("running");
    case "launch_game":
      mockState.runningUntil = Date.now() + 9000;
    // falls through
    case "launch_host_coop":
    case "launch_join_match":
    case "launch_join_code":
      await wait(600);
      return "Dev-Start via Godot";
    case "hide_while_playing":
    case "restore_launcher":
      return null;
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
