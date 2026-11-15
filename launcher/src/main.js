import { invoke, windowAction, changelogText, docImage, inTauri } from "./bridge.js";
import { hydratePixelText, renderPixelNode } from "./pixelfont.js";
import { splitVersions, renderMarkdown, splitEmoji } from "./markdown.js";
import { Atmosphere, CastParade } from "./fx.js";

// ---------------------------------------------------------------- the game's own art
import logoBase from "../../assets/ui/logo/title_base.png?url";
import logoPlants from "../../assets/ui/logo/title_plants.png?url";
import logoGlow from "../../assets/ui/logo/title_glow.png?url";
import logoHaloVoid from "../../assets/ui/logo/title_halo_void.png?url";
import logoHaloLife from "../../assets/ui/logo/title_halo_life.png?url";
import orbVoid from "../../assets/ui/logo/title_orb_void.png?url";
import orbLife from "../../assets/ui/logo/title_orb_life.png?url";
import menuIcons from "../../assets/ui/menu_icons.png?url";
import menuIconsGlow from "../../assets/ui/menu_icons_glow.png?url";
import ellieSheet from "../../assets/ui/ellie_dialogue_v4.png?url";
import castSheet from "../../assets/ui/loading_cast.png?url";
import sceneGolden from "../../docs/img/daylight_golden.png?url";
import sceneWitch from "../../docs/img/witch_tower_site.png?url";
import sceneLake from "../../docs/img/lake_night.png?url";
import sceneRiver from "../../docs/img/river_night_glow.png?url";
import sceneSmithy from "../../docs/img/smithy_world.png?url";
import sceneNoon from "../../docs/img/daylight_noon.png?url";

const SCENES = [
  { src: sceneGolden, name: "Die Lichtung · Abendgold" },
  { src: sceneWitch, name: "Hexenwald · Turm der Nebelhexe" },
  { src: sceneLake, name: "Nachtsee · Glimmende Ufer" },
  { src: sceneSmithy, name: "Glimmrast · Torbens Schmiede", pos: "50% 60%", size: "300% auto" },
  { src: sceneRiver, name: "Flusstal · Leuchtende Strömung" },
  { src: sceneNoon, name: "Die Lichtung · Mittagssonne" },
];
const GITHUB = "https://github.com/acuteflower/shadowspore";
const ROLE_LABEL = { admin: "Admin", moderator: "Mod", tester: "Tester", player: "Spieler" };
const JOIN_LABEL = { friends: "Freunde", ask: "Auf Anfrage", closed: "Geschlossen", open: "Offen" };

const $ = (id) => document.getElementById(id);
const app = $("app");

const state = {
  page: "home",
  authMode: "login",
  session: null,
  friends: [],
  gameStatus: null,
  versions: [],
  selected: 0,
  slide: 0,
  launching: false,
  prefs: loadPrefs(),
};

function loadPrefs() {
  try {
    return { reduceMotion: false, autoSlides: true, ...JSON.parse(localStorage.getItem("launcher.prefs") || "{}") };
  } catch {
    return { reduceMotion: false, autoSlides: true };
  }
}
function savePrefs() {
  try {
    localStorage.setItem("launcher.prefs", JSON.stringify(state.prefs));
  } catch {
    /* private mode: preferences simply are not remembered */
  }
}

// ---------------------------------------------------------------- small helpers
function setStatus(node, text, isError = false) {
  if (!node) return;
  node.textContent = text;
  node.classList.toggle("is-error", isError);
}

let toastTimer = 0;
function toast(text, isError = false) {
  const t = $("toast");
  t.textContent = text;
  t.classList.toggle("is-error", isError);
  t.classList.add("is-shown");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("is-shown"), 3200);
}

function formatUnix(sec) {
  if (!sec || sec <= 0) return "";
  return new Date(sec * 1000).toLocaleString("de-DE", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

function formatDate(iso) {
  const m = /(\d{4})-(\d{2})-(\d{2})/.exec(iso || "");
  return m ? `${m[3]}.${m[2]}.${m[1]}` : iso || "";
}

function gameClock(time) {
  if (typeof time !== "number" || !time) return "";
  const minutes = Math.round(time * 24 * 60) % (24 * 60);
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

function openLink(url) {
  invoke("open_external", { url }).catch((e) => toast(String(e), true));
}

// ---------------------------------------------------------------- art setup
function setupArt() {
  const logo = $("logo");
  logo.querySelector(".logo-base").src = logoBase;
  logo.querySelector(".logo-plants").src = logoPlants;
  logo.querySelector(".logo-glow").src = logoGlow;
  logo.querySelector(".logo-halo-void").src = logoHaloVoid;
  logo.querySelector(".logo-halo-life").src = logoHaloLife;
  const root = document.documentElement.style;
  root.setProperty("--orb-void", `url("${orbVoid}")`);
  root.setProperty("--orb-life", `url("${orbLife}")`);
  root.setProperty("--icons", `url("${menuIcons}")`);
  root.setProperty("--icons-glow", `url("${menuIconsGlow}")`);
  root.setProperty("--ellie", `url("${ellieSheet}")`);
  root.setProperty("--logo-mask", `url("${logoBase}")`);
  for (const node of document.querySelectorAll(".pix-icon")) node.style.setProperty("--i", node.dataset.icon || 0);

  const slides = $("slides");
  SCENES.forEach((scene, i) => {
    const s = document.createElement("div");
    s.className = "slide" + (i === 0 ? " is-active" : "");
    s.style.backgroundImage = `url("${scene.src}")`;
    if (scene.pos) s.style.backgroundPosition = scene.pos;
    if (scene.size) s.style.backgroundSize = scene.size;
    slides.appendChild(s);
  });
  $("scene-name").textContent = SCENES[0].name;
  fitLogo();
  window.addEventListener("resize", fitLogo);
}

function fitLogo() {
  // Integer scales only, so the pixel art stays crisp.
  const scale = window.innerWidth >= 1700 && window.innerHeight >= 950 ? 2 : 1;
  document.documentElement.style.setProperty("--logo-scale", scale);
}

function showSlide(i) {
  const slides = $("slides").children;
  state.slide = (i + SCENES.length) % SCENES.length;
  [...slides].forEach((s, n) => s.classList.toggle("is-active", n === state.slide));
  const chip = $("scene-chip");
  chip.classList.remove("is-swap");
  void chip.offsetWidth;
  chip.classList.add("is-swap");
  $("scene-name").textContent = SCENES[state.slide].name;
}

setInterval(() => {
  if (state.prefs.autoSlides && !document.hidden) showSlide(state.slide + 1);
}, 11000);
$("scene-chip").addEventListener("click", () => showSlide(state.slide + 1));

// Parallax: the scene and Ellie drift a little against the cursor.
window.addEventListener("pointermove", (e) => {
  if (state.prefs.reduceMotion) return;
  app.style.setProperty("--mx", (e.clientX / window.innerWidth - 0.5).toFixed(3));
  app.style.setProperty("--my", (e.clientY / window.innerHeight - 0.5).toFixed(3));
});

// Ellie blinks now and then (row 1 of the portrait sheet holds the closed eyes).
function blinkLoop() {
  const portrait = $("hero-portrait");
  setTimeout(() => {
    portrait.classList.add("is-blink");
    setTimeout(() => portrait.classList.remove("is-blink"), 130);
    blinkLoop();
  }, 2600 + Math.random() * 3800);
}

// ---------------------------------------------------------------- navigation
function go(page) {
  if (state.page === page) return;
  state.page = page;
  app.dataset.page = page;
  for (const b of document.querySelectorAll(".rail-btn[data-nav]")) b.classList.toggle("is-active", b.dataset.nav === page);
  for (const p of document.querySelectorAll(".page")) p.classList.toggle("is-active", p.dataset.page === page);
  if (atmosphere) atmosphere.dimTarget = page === "home" ? 1 : 0.5;
  if (page === "news") $("news-dot").hidden = true;
}

for (const b of document.querySelectorAll("[data-nav]")) b.addEventListener("click", () => go(b.dataset.nav));
for (const b of document.querySelectorAll("[data-link]")) b.addEventListener("click", () => openLink(b.dataset.link));
for (const b of document.querySelectorAll("[data-win]")) b.addEventListener("click", () => windowAction(b.dataset.win));
document.querySelector(".titlebar").addEventListener("dblclick", (e) => {
  if (e.target.closest("button")) return;
  windowAction("maximize");
});
$("account-chip").addEventListener("click", () => go("social"));
$("play-options").addEventListener("click", () => go("settings"));

window.addEventListener("keydown", (e) => {
  if (e.target.closest && e.target.closest("input, select, textarea")) return;
  if (e.key === "Escape" && !$("lightbox").hidden) return closeLightbox();
  if (e.key === "Escape" && state.page !== "home") return go("home");
  if (state.page === "home" && e.key === "ArrowRight") showSlide(state.slide + 1);
  if (state.page === "home" && e.key === "ArrowLeft") showSlide(state.slide - 1);
});

// ---------------------------------------------------------------- patch notes
async function loadChangelog() {
  const md = await changelogText();
  state.versions = splitVersions(md);
  if (!state.versions.length) {
    $("ribbon-title").textContent = "Keine Patchnotes gefunden";
    return;
  }
  const latest = state.versions[0];
  const short = latest.version.replace(/\s*Beta/i, "");
  renderPixelNode($("ribbon-version"), short);
  $("ribbon-title").textContent = splitEmoji(latest.title)[1] || latest.title;
  $("rail-version").textContent = short;
  try {
    if (localStorage.getItem("launcher.seenVersion") !== latest.version) $("news-dot").hidden = false;
  } catch {
    /* ignore */
  }
  renderNewsList();
  renderBanner();
  renderVersionList();
  selectVersion(0, false);
}

$("version-ribbon").addEventListener("click", () => {
  selectVersion(0, false);
  go("news");
});

function renderNewsList() {
  const list = $("news-list");
  list.innerHTML = "";
  for (const v of state.versions.slice(0, 4)) {
    const li = document.createElement("li");
    const b = document.createElement("button");
    b.type = "button";
    b.className = "news-row";
    const kind = document.createElement("span");
    kind.className = "news-kind";
    kind.textContent = v.version.replace(/\s*Beta/i, "");
    const title = document.createElement("span");
    title.className = "news-title";
    title.textContent = splitEmoji(v.title)[1] || v.title;
    const date = document.createElement("span");
    date.className = "news-date";
    date.textContent = formatDate(v.date).slice(0, 5);
    b.append(kind, title, date);
    b.addEventListener("click", () => {
      selectVersion(v.index, false);
      go("news");
    });
    li.appendChild(b);
    list.appendChild(li);
  }
}

for (const tab of document.querySelectorAll(".news-tab")) {
  tab.addEventListener("click", () => {
    for (const t of document.querySelectorAll(".news-tab")) t.classList.toggle("is-active", t === tab);
    $("news-list").hidden = tab.dataset.newsTab !== "updates";
    $("links-list").hidden = tab.dataset.newsTab !== "links";
  });
}

let bannerIndex = 0;
let bannerTimer = 0;
function renderBanner() {
  const items = state.versions.filter((v) => v.image).slice(0, 4);
  const track = $("banner-track");
  const dots = $("banner-dots");
  track.innerHTML = "";
  dots.innerHTML = "";
  items.forEach((v, i) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "banner-item" + (i === 0 ? " is-active" : "");
    card.innerHTML = `<span class="banner-img"></span><span class="banner-text"><span class="banner-ver"></span><span class="banner-title"></span></span>`;
    card.querySelector(".banner-ver").textContent = `${v.version} · ${formatDate(v.date)}`;
    card.querySelector(".banner-title").textContent = splitEmoji(v.title)[1] || v.title;
    docImage(v.image).then((url) => {
      if (url) card.querySelector(".banner-img").style.backgroundImage = `url("${url}")`;
    });
    card.addEventListener("click", () => {
      selectVersion(v.index, false);
      go("news");
    });
    track.appendChild(card);
    const dot = document.createElement("button");
    dot.type = "button";
    dot.className = "banner-dot" + (i === 0 ? " is-active" : "");
    dot.setAttribute("aria-label", `Neuigkeit ${i + 1}`);
    dot.addEventListener("click", () => showBanner(i));
    dots.appendChild(dot);
  });
  clearInterval(bannerTimer);
  bannerTimer = setInterval(() => {
    if (!document.hidden && state.page === "home" && !$("news-banner").matches(":hover")) showBanner(bannerIndex + 1);
  }, 6500);
}

function showBanner(i) {
  const cards = $("banner-track").children;
  if (!cards.length) return;
  bannerIndex = (i + cards.length) % cards.length;
  [...cards].forEach((c, n) => c.classList.toggle("is-active", n === bannerIndex));
  [...$("banner-dots").children].forEach((d, n) => d.classList.toggle("is-active", n === bannerIndex));
}

function renderVersionList(filter = "") {
  const list = $("version-list");
  list.innerHTML = "";
  const q = filter.trim().toLowerCase();
  for (const v of state.versions) {
    if (q && !`${v.version} ${v.title} ${v.body}`.toLowerCase().includes(q)) continue;
    const li = document.createElement("li");
    const b = document.createElement("button");
    b.type = "button";
    b.className = "version-item" + (v.index === state.selected ? " is-active" : "");
    b.dataset.index = v.index;
    const [emoji, title] = splitEmoji(v.title);
    b.innerHTML = `<span class="vi-node"></span><span class="vi-text"><span class="vi-head"><span class="vi-ver"></span><span class="vi-date"></span></span><span class="vi-title"></span></span>`;
    b.querySelector(".vi-ver").textContent = v.version;
    b.querySelector(".vi-date").textContent = formatDate(v.date);
    b.querySelector(".vi-title").textContent = `${emoji ? emoji + " " : ""}${title}`;
    b.addEventListener("click", () => selectVersion(v.index, true));
    li.appendChild(b);
    list.appendChild(li);
  }
  if (!list.children.length) {
    const li = document.createElement("li");
    li.className = "version-empty";
    li.textContent = "Nichts gefunden.";
    list.appendChild(li);
  }
}

$("version-filter").addEventListener("input", (e) => renderVersionList(e.target.value));

function selectVersion(index, focus = true) {
  const v = state.versions[index];
  if (!v) return;
  state.selected = index;
  for (const b of document.querySelectorAll(".version-item")) b.classList.toggle("is-active", Number(b.dataset.index) === index);
  renderPixelNode($("notes-version"), v.version);
  const [emoji, title] = splitEmoji(v.title);
  $("notes-title").textContent = title || v.title;
  $("notes-emoji").textContent = emoji;
  $("notes-date").textContent = formatDate(v.date);
  const hero = $("notes-hero-img");
  hero.style.backgroundImage = "";
  hero.classList.remove("is-loaded");
  if (v.image) {
    docImage(v.image).then((url) => {
      if (url && state.selected === index) {
        hero.style.backgroundImage = `url("${url}")`;
        hero.classList.add("is-loaded");
      }
    });
  }
  // The first heading and picture are shown in the header; the rest stays in the text.
  let body = v.body.replace(/^###\s+.*$/m, "");
  if (v.image) {
    const lines = body.split("\n");
    const at = lines.findIndex((l) => l.trim().startsWith("![") && l.includes(`(${v.image})`));
    if (at >= 0) lines.splice(at, 1);
    body = lines.join("\n");
  }
  const notes = $("notes-body");
  notes.innerHTML = renderMarkdown(body);
  notes.classList.remove("is-in");
  void notes.offsetWidth;
  notes.classList.add("is-in");
  hydrateImages(notes);
  for (const a of notes.querySelectorAll("a[data-link]")) {
    a.addEventListener("click", (e) => {
      e.preventDefault();
      const href = a.getAttribute("href");
      if (href.startsWith(GITHUB)) openLink(href);
    });
  }
  $("notes").scrollTop = 0;
  if (index === 0) {
    try {
      localStorage.setItem("launcher.seenVersion", v.version);
    } catch {
      /* ignore */
    }
  }
  if (focus) $("notes").focus({ preventScroll: true });
}

let imageObserver = null;
function hydrateImages(root) {
  imageObserver?.disconnect();
  imageObserver = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        imageObserver.unobserve(entry.target);
        const node = entry.target;
        docImage(node.dataset.src).then((url) => {
          if (!url) {
            node.classList.add("is-missing");
            node.textContent = "Bild nicht verfügbar";
            return;
          }
          const img = new Image();
          img.alt = node.dataset.alt || "";
          img.decoding = "async";
          img.onload = () => node.classList.add("is-loaded");
          img.src = url;
          node.appendChild(img);
          node.addEventListener("click", () => openLightbox(url, img.alt));
        });
      }
    },
    { root: $("notes"), rootMargin: "400px" },
  );
  for (const node of root.querySelectorAll(".md-img, .md-img-inline")) imageObserver.observe(node);
}

$("notes-github").addEventListener("click", () => openLink(`${GITHUB}/blob/main/CHANGELOG.md`));

function openLightbox(url, caption) {
  $("lightbox-img").src = url;
  $("lightbox-caption").textContent = caption;
  $("lightbox").hidden = false;
  requestAnimationFrame(() => $("lightbox").classList.add("is-open"));
}
function closeLightbox() {
  $("lightbox").classList.remove("is-open");
  setTimeout(() => ($("lightbox").hidden = true), 200);
}
$("lightbox").addEventListener("click", closeLightbox);

// ---------------------------------------------------------------- account
function setAuthMode(mode) {
  state.authMode = mode;
  const isRegister = mode === "register";
  $("tab-login").classList.toggle("is-active", !isRegister);
  $("tab-register").classList.toggle("is-active", isRegister);
  $("tab-login").setAttribute("aria-selected", String(!isRegister));
  $("tab-register").setAttribute("aria-selected", String(isRegister));
  document.querySelector(".segmented").dataset.mode = mode;
  $("username-field").hidden = !isRegister;
  $("auth-username").disabled = !isRegister;
  $("auth-password").setAttribute("autocomplete", isRegister ? "new-password" : "current-password");
  $("auth-submit-btn").textContent = isRegister ? "Konto erstellen" : "Anmelden";
  setStatus($("auth-status"), "");
}

function setFieldError(input, errorId, hasError) {
  const wrap = input.closest(".field");
  wrap.classList.toggle("has-error", hasError);
  if (hasError) {
    input.setAttribute("aria-invalid", "true");
    input.setAttribute("aria-describedby", errorId);
  } else {
    input.removeAttribute("aria-invalid");
    input.removeAttribute("aria-describedby");
  }
}

function setServerPill(kind, text) {
  const pill = $("server-pill");
  pill.className = `status-pill is-${kind}`;
  pill.querySelector(".status-text").textContent = text;
}

function roleKey(role) {
  const r = String(role || "player").toLowerCase();
  return ROLE_LABEL[r] ? r : "player";
}

function renderSession() {
  const s = state.session;
  const loggedIn = Boolean(s && s.logged_in);
  $("auth-view").hidden = loggedIn;
  $("social-view").hidden = !loggedIn;
  app.classList.toggle("is-logged-in", loggedIn);

  if (!loggedIn) {
    $("chip-avatar").textContent = "?";
    $("chip-name").textContent = "Anmelden";
    $("play-sub").textContent = "Als Gast starten";
    $("save-text").textContent = "Abgemeldet · lokaler Spielstand";
    $("admin-role-card").hidden = true;
    return;
  }
  const label = s.display_name || s.username || "Spieler";
  const role = roleKey(s.role);
  $("chip-avatar").textContent = label.charAt(0).toUpperCase();
  $("chip-name").textContent = label;
  $("profile-avatar").textContent = label.charAt(0).toUpperCase();
  $("profile-name").textContent = label;
  $("profile-handle").textContent = "@" + (s.username || "spieler");
  $("profile-uid").textContent = s.uid || "------";
  const badge = $("profile-role-badge");
  badge.textContent = ROLE_LABEL[role];
  badge.className = `role-badge role-${role}`;
  $("admin-role-card").hidden = role !== "admin";
  $("profile-join").textContent = JOIN_LABEL[s.world_join_mode] || s.world_join_mode || "—";
  $("play-sub").textContent = `Verbunden als ${label}${role === "admin" ? " · Admin" : ""}`;
  setServerPill("ok", "Verbunden");

  const save = s.cloud_save || {};
  if (save.has_save) {
    const when = formatUnix(save.saved_at);
    const clock = gameClock(save.time);
    $("save-text").textContent = `Cloud-Welt · Tag ${save.day}${clock ? ` · ${clock} Uhr` : ""}${when ? ` · gespeichert ${when}` : ""}`;
    $("profile-save").textContent = `Tag ${save.day}`;
    $("profile-save-when").textContent = when ? `gespeichert ${when}` : "synchron";
  } else {
    $("save-text").textContent = "Noch keine Cloud-Welt · wird beim ersten Speichern angelegt";
    $("profile-save").textContent = "Neu";
    $("profile-save-when").textContent = "noch nicht gespeichert";
  }
}

function friendRow(friend, group) {
  const item = document.createElement("div");
  item.className = `friend friend-${group}` + (friend.online ? " is-online" : "");
  const name = friend.display_name || friend.username || "Spieler";
  const avatar = document.createElement("span");
  avatar.className = "avatar avatar-sm";
  avatar.textContent = name.charAt(0).toUpperCase();
  const meta = document.createElement("div");
  meta.className = "friend-meta";
  const top = document.createElement("div");
  top.className = "friend-top";
  const nameEl = document.createElement("span");
  nameEl.className = "friend-name";
  nameEl.textContent = name;
  top.appendChild(nameEl);
  const role = roleKey(friend.role);
  if (role !== "player") {
    const badge = document.createElement("span");
    badge.className = `role-badge role-${role}`;
    badge.textContent = ROLE_LABEL[role];
    top.appendChild(badge);
  }
  const sub = document.createElement("div");
  sub.className = "friend-sub";
  const status = group === "incoming" ? "möchte dein Freund sein" : group === "outgoing" ? "Anfrage gesendet" : friend.online ? "online" : "offline";
  sub.textContent = `UID ${friend.uid || "?"} · ${status}`;
  meta.append(top, sub);

  const actions = document.createElement("div");
  actions.className = "friend-actions";
  const btn = (text, cls, fn) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = `btn btn-sm ${cls}`;
    b.textContent = text;
    b.addEventListener("click", fn);
    actions.appendChild(b);
  };
  if (group === "incoming") {
    btn("Annehmen", "btn-primary", () => friendAction("accept_friend", friend.user_id, "Freundschaft angenommen."));
    btn("Ablehnen", "btn-ghost", () => friendAction("remove_friend", friend.user_id, "Anfrage abgelehnt."));
  } else if (group === "outgoing") {
    btn("Zurückziehen", "btn-ghost", () => friendAction("remove_friend", friend.user_id, "Anfrage zurückgezogen."));
  } else {
    btn("Entfernen", "btn-danger", () => friendAction("remove_friend", friend.user_id, "Freund entfernt."));
  }
  item.append(avatar, meta, actions);
  return item;
}

function renderFriends() {
  const list = state.friends || [];
  const incoming = list.filter((f) => f.state === 2);
  const accepted = list.filter((f) => f.state === 0).sort((a, b) => Number(b.online) - Number(a.online));
  const outgoing = list.filter((f) => f.state === 1);
  const online = accepted.filter((f) => f.online).length;
  $("friends-count").textContent = `${online} online · ${accepted.length} Freunde`;
  $("friends-dot").hidden = incoming.length === 0;
  const box = $("friends-list");
  box.innerHTML = "";
  $("friends-empty").hidden = incoming.length + accepted.length + outgoing.length > 0;
  const group = (title, entries, kind) => {
    if (!entries.length) return;
    const h = document.createElement("div");
    h.className = "friend-group";
    h.textContent = `${title} · ${entries.length}`;
    box.appendChild(h);
    entries.forEach((f, i) => {
      const row = friendRow(f, kind);
      row.style.setProperty("--d", `${i * 45}ms`);
      box.appendChild(row);
    });
  };
  group("Anfragen", incoming, "incoming");
  group("Freunde", accepted, "friend");
  group("Gesendet", outgoing, "outgoing");
}

async function refreshSocial() {
  if (!state.session || !state.session.logged_in) return;
  try {
    state.session = await invoke("refresh_profile");
    state.friends = await invoke("list_friends");
    renderSession();
    renderFriends();
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  }
}

async function friendAction(cmd, userId, done) {
  try {
    await invoke(cmd, { userId });
    toast(done);
    await refreshSocial();
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  }
}

$("tab-login").addEventListener("click", () => setAuthMode("login"));
$("tab-register").addEventListener("click", () => setAuthMode("register"));
$("toggle-password-btn").addEventListener("click", () => {
  const input = $("auth-password");
  const show = input.type === "password";
  input.type = show ? "text" : "password";
  $("toggle-password-btn").setAttribute("aria-pressed", String(show));
  $("toggle-password-btn").textContent = show ? "Verbergen" : "Zeigen";
});
$("auth-email").addEventListener("input", () => setFieldError($("auth-email"), "email-error", false));
$("auth-password").addEventListener("input", () => setFieldError($("auth-password"), "password-error", false));

$("auth-form").addEventListener("submit", async (evt) => {
  evt.preventDefault();
  const email = $("auth-email").value.trim();
  const password = $("auth-password").value;
  const username = $("auth-username").value.trim();
  const emailOk = email.includes("@") && $("auth-email").checkValidity();
  const passOk = password.length >= 8;
  setFieldError($("auth-email"), "email-error", !emailOk);
  setFieldError($("auth-password"), "password-error", !passOk);
  if (!emailOk || !passOk) return;
  const submit = $("auth-submit-btn");
  submit.disabled = true;
  submit.classList.add("is-busy");
  setStatus($("auth-status"), "Verbinde mit Nakama…");
  try {
    state.session = await invoke("login_email", { email, password, username, create: state.authMode === "register" });
    $("auth-password").value = "";
    state.friends = await invoke("list_friends");
    renderSession();
    renderFriends();
    setStatus($("auth-status"), "");
    toast(`Willkommen, ${state.session.display_name || state.session.username || "Wanderer"}.`);
  } catch (err) {
    setStatus($("auth-status"), String(err), true);
  } finally {
    submit.disabled = false;
    submit.classList.remove("is-busy");
  }
});

$("logout-btn").addEventListener("click", async () => {
  state.session = await invoke("logout");
  state.friends = [];
  renderSession();
  renderFriends();
  setServerPill("muted", "Nicht angemeldet");
  toast("Abgemeldet.");
});

$("copy-uid-btn").addEventListener("click", async () => {
  const uid = $("profile-uid").textContent.trim();
  if (!uid || uid === "------") return;
  try {
    await navigator.clipboard.writeText(uid);
    $("uid-copy-feedback").textContent = "Kopiert!";
    $("copy-uid-btn").classList.add("is-copied");
  } catch {
    $("uid-copy-feedback").textContent = "Kopieren fehlgeschlagen";
  }
  setTimeout(() => {
    $("uid-copy-feedback").textContent = "Klicken zum Kopieren";
    $("copy-uid-btn").classList.remove("is-copied");
  }, 1800);
});

$("refresh-social-btn").addEventListener("click", async () => {
  const b = $("refresh-social-btn");
  b.classList.add("is-spinning");
  await refreshSocial();
  setTimeout(() => b.classList.remove("is-spinning"), 500);
});

$("add-friend-form").addEventListener("submit", async (evt) => {
  evt.preventDefault();
  const query = $("friend-query").value.trim();
  if (!query) return setStatus($("friend-status"), "Bitte eine UID eingeben.", true);
  $("add-friend-btn").disabled = true;
  setStatus($("friend-status"), "Suche Spieler…");
  try {
    await invoke("add_friend", { query });
    $("friend-query").value = "";
    setStatus($("friend-status"), "");
    toast("Freundesanfrage gesendet.");
    await refreshSocial();
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  } finally {
    $("add-friend-btn").disabled = false;
  }
});

$("admin-role-form").addEventListener("submit", async (evt) => {
  evt.preventDefault();
  const target = $("admin-target-uid").value.trim();
  const role = $("admin-role-select").value;
  if (!target) return setStatus($("admin-role-status"), "Bitte UID oder Namen angeben.", true);
  $("admin-role-submit").disabled = true;
  setStatus($("admin-role-status"), "Aktualisiere Rolle…");
  try {
    state.session = await invoke("admin_set_role", { target, role });
    setStatus($("admin-role-status"), `Rolle von ${target} ist jetzt ${ROLE_LABEL[roleKey(role)]}.`);
    $("admin-target-uid").value = "";
    renderSession();
    await refreshSocial();
  } catch (err) {
    setStatus($("admin-role-status"), String(err), true);
  } finally {
    $("admin-role-submit").disabled = false;
  }
});

// ---------------------------------------------------------------- game status and launch
function renderGameStatus() {
  const gs = state.gameStatus;
  if (!gs) return;
  const dot = $("game-dot");
  const label = $("game-label");
  const play = $("play-btn");
  const version = gs.update_available ? `Update ${gs.remote_version} verfügbar` : gs.mode === "dev" ? "Dev-Build" : `v${gs.local_version}`;
  if (gs.ready) {
    dot.className = "status-dot is-ok";
    label.textContent = `${gs.status_label} · ${version}`;
    label.title = gs.resolved_exe;
    play.disabled = state.launching;
    play.classList.toggle("is-update", Boolean(gs.update_available));
  } else {
    dot.className = "status-dot is-err";
    label.textContent = "Spiel nicht gefunden – Pfad in den Optionen setzen";
    play.disabled = true;
  }
  const resolved = $("resolved-path");
  resolved.innerHTML = "";
  const line = (k, v) => {
    if (!v) return;
    const row = document.createElement("div");
    const key = document.createElement("span");
    const val = document.createElement("code");
    key.textContent = k;
    val.textContent = v;
    row.append(key, val);
    resolved.appendChild(row);
  };
  line("Gefunden", gs.resolved_exe || "nichts");
  line("Projekt", gs.resolved_project_dir);
  line("Modus", gs.mode === "release" ? "Build" : gs.mode === "dev" ? "Dev (Godot)" : "fehlt");
}

let parade = null;
$("play-btn").addEventListener("click", async () => {
  if (state.launching) return;
  state.launching = true;
  const play = $("play-btn");
  play.disabled = true;
  play.classList.add("is-launching");
  app.classList.add("is-launching");
  parade?.start();
  renderPixelNode($("play-word"), "Startet…");
  setStatus($("launch-feedback"), "");
  try {
    const msg = await invoke("launch_game");
    await new Promise((r) => setTimeout(r, 1400));
    setStatus($("launch-feedback"), msg);
    toast("Shadowspore startet. Gute Reise!");
  } catch (err) {
    setStatus($("launch-feedback"), String(err), true);
  } finally {
    setTimeout(() => {
      state.launching = false;
      play.classList.remove("is-launching");
      app.classList.remove("is-launching");
      parade?.stop();
      renderPixelNode($("play-word"), "Spielen");
      renderGameStatus();
    }, 2400);
  }
});

// ---------------------------------------------------------------- settings
async function fillSettings() {
  const cfg = await invoke("get_settings");
  $("cfg-server-url").value = cfg.server_url;
  $("cfg-server-key").value = cfg.server_key;
  $("cfg-game-exe").value = cfg.game_exe_path;
  $("cfg-godot-exe").value = cfg.godot_exe_path;
  $("cfg-manifest-url").value = cfg.manifest_url;
  $("opt-motion").checked = state.prefs.reduceMotion;
  $("opt-slides").checked = state.prefs.autoSlides;
  setStatus($("settings-status"), "");
}

$("cancel-settings-btn").addEventListener("click", fillSettings);
$("opt-motion").addEventListener("change", (e) => {
  state.prefs.reduceMotion = e.target.checked;
  applyPrefs();
  savePrefs();
});
$("opt-slides").addEventListener("change", (e) => {
  state.prefs.autoSlides = e.target.checked;
  savePrefs();
});

function applyPrefs() {
  document.documentElement.classList.toggle("reduce-motion", state.prefs.reduceMotion);
  if (atmosphere) atmosphere.paused = state.prefs.reduceMotion;
  if (state.prefs.reduceMotion) {
    app.style.setProperty("--mx", 0);
    app.style.setProperty("--my", 0);
  }
}

$("settings-form").addEventListener("submit", async (evt) => {
  evt.preventDefault();
  try {
    await invoke("save_settings", {
      settings: {
        server_url: $("cfg-server-url").value,
        server_key: $("cfg-server-key").value,
        game_exe_path: $("cfg-game-exe").value,
        godot_exe_path: $("cfg-godot-exe").value,
        manifest_url: $("cfg-manifest-url").value,
      },
    });
    state.gameStatus = await invoke("get_game_status");
    renderGameStatus();
    setStatus($("settings-status"), "Gespeichert.");
    toast("Einstellungen gespeichert.");
  } catch (err) {
    setStatus($("settings-status"), String(err), true);
  }
});

// ---------------------------------------------------------------- boot
let atmosphere = null;
async function init() {
  setupArt();
  hydratePixelText();
  setAuthMode("login");
  atmosphere = new Atmosphere($("atmosphere"));
  applyPrefs();
  parade = new CastParade($("parade"), castSheet);
  blinkLoop();
  if (!inTauri) document.documentElement.classList.add("is-browser");
  requestAnimationFrame(() => requestAnimationFrame(() => app.classList.remove("is-booting")));

  const params = new URLSearchParams(location.search);
  if (params.get("page")) go(params.get("page"));

  loadChangelog();
  fillSettings().catch(() => {});

  try {
    state.gameStatus = await invoke("get_game_status");
    renderGameStatus();
  } catch (err) {
    $("game-label").textContent = String(err);
  }

  try {
    state.session = await invoke("restore_session");
    renderSession();
    if (state.session.logged_in) {
      state.friends = await invoke("list_friends");
      renderFriends();
    } else {
      setServerPill("muted", "Nicht angemeldet");
    }
  } catch (err) {
    setServerPill("err", "Server nicht erreichbar");
    setStatus($("auth-status"), String(err), true);
  }
}

init();
