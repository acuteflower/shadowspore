import { invoke, listenEvent, windowAction, changelogText, docImage, inTauri } from "./bridge.js";
import { hydratePixelText, renderPixelNode } from "./pixelfont.js";
import { splitVersions, renderMarkdown, splitEmoji } from "./markdown.js";
import { Atmosphere, CastParade } from "./fx.js";
import { createAdminController } from "./admin.js";

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
import avatarLichtung from "./art/avatar_lichtung.png?url";
import avatarLeere from "./art/avatar_leere.png?url";
import castSheet from "../../assets/ui/loading_cast.png?url";
import sceneRiver from "../../docs/img/windkap_v0102_estuary.png?url";
import sceneShore from "../../docs/img/windkap_v0102_beach.png?url";
import sceneTerraces from "../../docs/img/windkap_v0102_suedkap.png?url";
import sceneLake from "../../docs/img/lake_night.png?url";
import sceneGlow from "../../docs/img/river_night_glow.png?url";

// Only landscapes: no buildings, characters or UI in the background.
const SCENES = [
  { src: sceneRiver, name: "Erlenbach-Mündung am Windkap" },
  { src: sceneShore, name: "Windstrand der Silberbucht" },
  { src: sceneTerraces, name: "Übergang ins Südkap" },
  { src: sceneLake, name: "Glimmende Ufer bei Nacht" },
  { src: sceneGlow, name: "Leuchtende Strömung" },
];
const GITHUB = "https://github.com/acuteflower/shadowspore";
const REGISTER_PORTAL_URL = "https://shadowspore.com/#register";
const ROLE_LABEL = { admin: "Admin", moderator: "Mod", tester: "Tester", player: "Spieler" };
const JOIN_LABEL = { private: "Privat", ask: "Auf Anfrage", open: "Offen" };

const $ = (id) => document.getElementById(id);
const app = $("app");

const state = {
  page: "home",
  session: null,
  friends: [],
  notifications: [],
  wsConnected: false,
  gameStatus: null,
  versions: [],
  selected: 0,
  slide: 0,
  launching: false,
  stepAsidePending: false,
  steppedAside: false,
  updating: false,
  running: false,
  prefs: loadPrefs(),
};

function normalizeJoinMode(mode) {
  const m = String(mode || "ask").toLowerCase();
  if (m === "friends" || m === "ask") return "ask";
  if (m === "closed" || m === "private") return "private";
  if (m === "open") return "open";
  return "ask";
}

function loadPrefs() {
  try {
    return { reduceMotion: false, autoSlides: true, trayWhilePlaying: false, ...JSON.parse(localStorage.getItem("launcher.prefs") || "{}") };
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

// ---------------------------------------------------------------- profile pictures
// Ids are stored in the Nakama account's avatar_url; unknown ids fall back to the first.
const AVATARS = [
  { id: "ellie_lichtung", src: avatarLichtung, name: "Lichtung", sub: "Abendgold über der Wiese" },
  { id: "ellie_leere", src: avatarLeere, name: "Leere", sub: "Mondlicht und Schatten" },
];
const avatarOf = (id) => AVATARS.find((a) => a.id === id) || AVATARS[0];

function currentAvatarId() {
  const s = state.session;
  if (s && s.avatar_url && AVATARS.some((a) => a.id === s.avatar_url)) return s.avatar_url;
  try {
    return localStorage.getItem("launcher.avatar") || AVATARS[0].id;
  } catch {
    return AVATARS[0].id;
  }
}

function renderAvatarOptions() {
  const box = $("avatar-options");
  const current = currentAvatarId();
  box.replaceChildren(
    ...AVATARS.map((a) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "avatar-option" + (a.id === current ? " is-active" : "");
      b.setAttribute("role", "radio");
      b.setAttribute("aria-checked", String(a.id === current));
      b.innerHTML = `<img alt="" src="${a.src}"><span class="avatar-option-text"><strong></strong><small></small></span>`;
      b.querySelector("strong").textContent = a.name;
      b.querySelector("small").textContent = a.sub;
      b.addEventListener("click", () => chooseAvatar(a.id));
      return b;
    }),
  );
}

async function chooseAvatar(id) {
  try {
    localStorage.setItem("launcher.avatar", id);
  } catch {}
  if (state.session) state.session.avatar_url = id;
  renderSession();
  renderAvatarOptions();
  const status = $("avatar-status");
  status.textContent = "Speichere …";
  status.className = "form-status";
  try {
    state.session = await invoke("set_avatar", { avatar: id });
    status.textContent = "Profilbild gespeichert.";
    status.classList.add("is-ok");
  } catch (e) {
    status.textContent = `Nur lokal gespeichert: ${e}`;
    status.classList.add("is-err");
  }
}

$("profile-avatar").addEventListener("click", () => {
  const picker = $("avatar-picker");
  picker.hidden = !picker.hidden;
  $("profile-avatar").setAttribute("aria-expanded", String(!picker.hidden));
  if (!picker.hidden) renderAvatarOptions();
});

// ---------------------------------------------------------------- navigation
let admin = null;

function go(page) {
  if (page === "admin" && !admin?.isAdmin()) page = state.session?.logged_in ? "home" : "social";
  if (state.page === page) return;
  state.page = page;
  app.dataset.page = page;
  for (const b of document.querySelectorAll(".rail-btn[data-nav]")) b.classList.toggle("is-active", b.dataset.nav === page);
  for (const p of document.querySelectorAll(".page")) p.classList.toggle("is-active", p.dataset.page === page);
  updateNight();
  if (page === "news") $("news-dot").hidden = true;
  if (page === "admin" && admin?.isAdmin()) admin.onEnterPage().catch(() => {});
}

for (const b of document.querySelectorAll("[data-nav]")) b.addEventListener("click", () => go(b.dataset.nav));
for (const b of document.querySelectorAll("[data-link]")) b.addEventListener("click", () => openLink(b.dataset.link));
for (const b of document.querySelectorAll("[data-win]")) b.addEventListener("click", () => windowAction(b.dataset.win));
$("account-chip").addEventListener("click", () => go("social"));
$("play-options").addEventListener("click", () => go("settings"));

window.addEventListener("keydown", (e) => {
  if (document.querySelector("dialog[open]")) return;
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
    card.querySelector(".banner-ver").textContent = `${v.version}, ${formatDate(v.date)}`;
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
function canPlayNow() {
  const s = state.session;
  const gs = state.gameStatus;
  return Boolean(
    !state.launching &&
      !state.updating &&
      !state.running &&
      gs?.ready &&
      s?.logged_in &&
      s?.license_active &&
      !s?.banned,
  );
}

function syncPlayButton() {
  const play = $("play-btn");
  const s = state.session;
  if (state.running) {
    play.disabled = true;
    $("play-sub").textContent = "Beende das Spiel, um neu zu starten";
    return;
  }
  play.disabled = !canPlayNow();
  if (!s || !s.logged_in) {
    $("play-sub").textContent = "Anmeldung auf Konto-Tab nötig";
  } else if (s.banned) {
    $("play-sub").textContent = "Konto gesperrt";
  } else if (!s.license_active) {
    $("play-sub").textContent = "Lizenzkey auf shadowspore.com nötig";
  } else if (!state.gameStatus?.ready) {
    $("play-sub").textContent = state.gameStatus?.update_available ? "Erst Spiel herunterladen" : "Spielpfad prüfen";
  } else if (s.cloud_save?.has_save) {
    renderProgress(s.cloud_save);
  } else {
    $("play-sub").textContent = "Eine neue Reise beginnen";
  }
}

/** The saved journey on the stone: the day under its sun or moon, the level as a star. */
function renderProgress(save) {
  const sub = $("play-sub");
  const t = Number(save.time) || 0;
  const night = t < 0.25 || t >= 0.8;
  const chip = (glyph, text) => {
    const c = document.createElement("span");
    c.className = `stone-chip is-${glyph}`;
    const g = document.createElement("i");
    g.setAttribute("aria-hidden", "true");
    c.append(g, text);
    return c;
  };
  const parts = [chip(night ? "moon" : "sun", `Tag ${save.day}`)];
  if (save.level > 0) parts.push(chip("star", `Stufe ${save.level}`));
  sub.replaceChildren(...parts);
  const clock = gameClock(save.time);
  sub.title = clock ? `Zuletzt gespeichert um ${clock} Uhr im Spiel` : "";
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
  pill.className = `presence is-${kind}`;
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
    $("chip-avatar-img").hidden = true;
    $("chip-avatar-letter").hidden = false;
    $("chip-name").textContent = "Anmelden";
    $("save-text").textContent = "Anmeldung für Cloud-Spielstand nötig";
    $("active-lobby-bar").hidden = true;
    $("coop-notifs").hidden = true;
    admin?.syncAccess();
    if (state.page === "admin") go("home");
    syncPlayButton();
    return;
  }
  const label = s.display_name || s.username || "Spieler";
  const role = roleKey(s.role);
  const pic = avatarOf(currentAvatarId());
  $("chip-avatar-img").src = pic.src;
  $("chip-avatar-img").hidden = false;
  $("chip-avatar-letter").hidden = true;
  $("chip-name").textContent = label;
  $("profile-avatar-img").src = pic.src;
  $("profile-name").textContent = label;
  $("profile-handle").textContent = "@" + (s.username || "spieler");
  $("profile-uid").textContent = s.uid || "------";
  const badge = $("profile-role-badge");
  badge.textContent = ROLE_LABEL[role];
  badge.className = `role-badge role-${role}`;
  admin?.syncAccess();
  if (state.page === "admin" && !admin?.isAdmin()) go("home");

  const licBar = $("license-bar");
  const licTitle = $("license-status-title");
  const licMeta = $("license-status-meta");
  const licBtn = $("license-portal-btn");
  if (s.banned) {
    licBar.className = "license-bar is-err";
    licTitle.textContent = "Konto gesperrt";
    licMeta.textContent = s.ban_reason || "Zugang dauerhaft deaktiviert";
    licBtn.hidden = true;
  } else if (s.license_active) {
    licBar.className = "license-bar";
    const ed = (s.license_edition || "standard").toUpperCase();
    licTitle.textContent = `Lizenz aktiv (${ed})`;
    licMeta.textContent = s.license_expires_at > 0 ? `Gültig bis ${formatUnix(s.license_expires_at)}` : "Unbegrenzt · Always-Online bereit";
    licBtn.hidden = true;
  } else {
    licBar.className = "license-bar is-err";
    licTitle.textContent = "Keine aktive Lizenz";
    licMeta.textContent = s.license_error || "Bitte Lizenzkey auf shadowspore.com aktivieren";
    licBtn.hidden = false;
  }

  renderJoinMode(normalizeJoinMode(s.world_join_mode));
  syncPlayButton();
  setServerPill(s.banned || !s.license_active ? "err" : "ok", s.banned ? "Gesperrt" : !s.license_active ? "Keine Lizenz" : state.wsConnected ? "Live verbunden" : "Verbunden");

  const lobby = s.active_lobby;
  if (lobby && lobby.match_id) {
    $("active-lobby-bar").hidden = false;
    $("active-lobby-title").textContent = `Welt „${lobby.world_name || "Koop"}“ aktiv`;
    $("active-lobby-meta").textContent = `${lobby.player_count || 1} von ${lobby.max_players || 4} Spielern, ${(JOIN_LABEL[normalizeJoinMode(lobby.join_mode)] || "Offen").toLowerCase()}`;
    $("active-lobby-code").textContent = lobby.room_code || "------";
  } else {
    $("active-lobby-bar").hidden = true;
  }

  const save = s.cloud_save || {};
  if (!s.license_active) {
    $("save-text").textContent = "Keine aktive Spiellizenz";
    $("profile-save").textContent = "Gesperrt";
    $("profile-save-when").textContent = "Lizenzkey nötig";
  } else if (save.has_save) {
    const when = formatUnix(save.saved_at);
    const clock = gameClock(save.time);
    $("save-text").textContent = `Cloud-Welt, Tag ${save.day}${clock ? `, ${clock} Uhr` : ""}`;
    $("save-text").title = when ? `Gespeichert am ${when}` : "";
    $("profile-save").textContent = `Tag ${save.day}`;
    $("profile-save-when").textContent = when ? `gespeichert ${when}` : "synchron";
  } else {
    $("save-text").textContent = "Cloud-Welt entsteht beim ersten Speichern";
    $("profile-save").textContent = "Neu";
    $("profile-save-when").textContent = "noch nicht gespeichert";
  }
}

function updateSocialBadge() {
  const incomingFriends = (state.friends || []).filter((f) => f.state === 2).length;
  const activeNotifs = (state.notifications || []).filter((n) => !n.expires_at || n.expires_at * 1000 > Date.now()).length;
  $("friends-dot").hidden = incomingFriends + activeNotifs === 0;
}

function friendRow(friend, group) {
  const item = document.createElement("div");
  item.className = `friend friend-${group}` + (friend.online ? " is-online" : "");
  const name = friend.display_name || friend.username || "Spieler";
  const avatar = document.createElement("span");
  avatar.className = "avatar avatar-sm";
  if (friend.avatar_url && AVATARS.some((a) => a.id === friend.avatar_url)) {
    const img = document.createElement("img");
    img.alt = "";
    img.src = avatarOf(friend.avatar_url).src;
    avatar.appendChild(img);
  } else {
    avatar.textContent = name.charAt(0).toUpperCase();
  }
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
  sub.textContent = status;
  sub.title = `Spieler-ID ${friend.uid || "?"}`;
  meta.append(top, sub);

  if (group === "friend" && friend.coop_active) {
    const coopLine = document.createElement("div");
    coopLine.className = "friend-coop";
    const jMode = normalizeJoinMode(friend.coop_join_mode);
    coopLine.textContent = `Spielt in „${friend.coop_world_name || "Koop"}“ (${friend.coop_players || 1}/${friend.coop_max_players || 4})`;
    meta.appendChild(coopLine);
  }

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
    if (friend.coop_active) {
      const jm = normalizeJoinMode(friend.coop_join_mode);
      if (jm === "open") {
        btn("Beitreten", "btn-primary", () => requestOrJoinFriend(friend));
      } else if (jm === "ask") {
        btn("Anfragen", "btn-secondary", () => requestOrJoinFriend(friend));
      }
    }
    if (friend.online && state.session?.active_lobby?.match_id) {
      btn("Einladen", "btn-secondary", () => inviteFriend(friend));
    }
    btn("Entfernen", "btn-danger", () => friendAction("remove_friend", friend.user_id, "Freund entfernt."));
  }
  item.append(avatar, meta, actions);
  return item;
}

function renderNotifications() {
  const box = $("coop-notifs");
  const now = Date.now();
  const list = (state.notifications || []).filter((n) => !n.expires_at || n.expires_at * 1000 > now);
  box.innerHTML = "";
  box.hidden = list.length === 0;
  updateSocialBadge();
  for (const n of list) {
    const row = document.createElement("div");
    row.className = "notif-item";
    const txt = document.createElement("div");
    txt.className = "notif-text";
    const title = document.createElement("strong");
    const sub = document.createElement("span");
    const acts = document.createElement("div");
    acts.className = "notif-actions";
    const addBtn = (label, cls, handler) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = `btn btn-sm ${cls}`;
      b.textContent = label;
      b.addEventListener("click", handler);
      acts.appendChild(b);
    };

    if (n.code === 101 || n.code === 103) {
      title.textContent = n.code === 103 ? "Beitritt genehmigt" : "Koop-Einladung";
      sub.textContent = `${n.host_name || "Ein Freund"} lädt dich nach „${n.world_name || "Koop"}“ ein`;
      addBtn("Beitreten", "btn-primary", async () => {
        try {
          if (n.id) await invoke("dismiss_notification", { notificationId: n.id }).catch(() => {});
          state.notifications = state.notifications.filter((x) => x.id !== n.id);
          renderNotifications();
          await startGame("launch_join_match", {
            matchId: n.match_id,
            roomCode: n.room_code || null,
            worldName: n.world_name || null,
          });
          toast(`Verbinde mit „${n.world_name || "Koop"}“…`);
        } catch (err) {
          setStatus($("friend-status"), String(err), true);
        }
      });
      addBtn("×", "btn-ghost", () => dismissNotif(n.id));
    } else if (n.code === 102) {
      title.textContent = "Beitrittsanfrage";
      sub.textContent = `${n.requester_name || "Spieler"} (UID ${n.requester_uid || "?"}) → „${n.world_name || "Koop"}“`;
      addBtn("Annehmen", "btn-primary", () => respondJoinReq(n, true));
      addBtn("Ablehnen", "btn-ghost", () => respondJoinReq(n, false));
    } else {
      title.textContent = "Anfrage abgelehnt";
      sub.textContent = `${n.host_name || "Host"} hat die Anfrage für „${n.world_name || "Koop"}“ abgelehnt.`;
      addBtn("×", "btn-ghost", () => dismissNotif(n.id));
    }
    txt.append(title, sub);
    row.append(txt, acts);
    box.appendChild(row);
  }
}

function renderFriends() {
  const list = state.friends || [];
  const incoming = list.filter((f) => f.state === 2);
  const accepted = list.filter((f) => f.state === 0).sort((a, b) => Number(b.online) - Number(a.online));
  const outgoing = list.filter((f) => f.state === 1);
  const online = accepted.filter((f) => f.online).length;
  $("friends-count").textContent = accepted.length ? `${online} von ${accepted.length} online` : "";
  updateSocialBadge();
  const box = $("friends-list");
  box.innerHTML = "";
  $("friends-empty").hidden = incoming.length + accepted.length + outgoing.length > 0;
  const group = (title, entries, kind) => {
    if (!entries.length) return;
    const h = document.createElement("div");
    h.className = "friend-group";
    h.textContent = title;
    h.dataset.count = entries.length;
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
    const session = await invoke("refresh_profile");
    if (!session.logged_in) {
      state.session = session;
      state.friends = [];
      state.notifications = [];
      state.wsConnected = false;
      setServerPill("muted", "Nicht angemeldet");
      setStatus($("friend-status"), "");
      renderSession();
      renderNotifications();
      renderFriends();
      return;
    }
    const [friends, notifications] = await Promise.all([
      invoke("list_friends"),
      invoke("fetch_notifications").catch(() => []),
    ]);
    state.session = session;
    state.friends = friends;
    state.notifications = notifications;
    renderSession();
    renderNotifications();
    renderFriends();
    if (state.page === "admin" && admin.isAdmin()) admin.refreshAll().catch(() => {});
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  }
}

async function dismissNotif(id) {
  state.notifications = state.notifications.filter((n) => n.id !== id);
  renderNotifications();
  if (id) await invoke("dismiss_notification", { notificationId: id }).catch(() => {});
}

async function respondJoinReq(notif, accept) {
  try {
    await invoke("coop_respond_join_request", {
      requesterUserId: notif.requester_user_id,
      accept,
      notificationId: notif.id || "",
    });
    state.notifications = state.notifications.filter((n) => n.id !== notif.id);
    renderNotifications();
    toast(accept ? `${notif.requester_name || "Spieler"} eingelassen.` : "Anfrage abgelehnt.");
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  }
}

async function requestOrJoinFriend(friend) {
  try {
    setStatus($("friend-status"), "Prüfe Beitritt…");
    const res = await invoke("coop_request_join", {
      hostUserId: friend.user_id,
      hostUid: friend.uid || "",
      roomCode: "",
    });
    if (res.status === "approved" && res.match_id) {
      setStatus($("friend-status"), "");
      await startGame("launch_join_match", {
        matchId: res.match_id,
        roomCode: res.room_code || null,
        worldName: res.world_name || friend.coop_world_name || null,
      });
      toast(`Verbinde mit ${friend.display_name || friend.username}…`);
    } else {
      setStatus($("friend-status"), "Beitrittsanfrage gesendet — warte auf Antwort.");
      toast("Beitrittsanfrage gesendet.");
    }
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  }
}

async function inviteFriend(friend) {
  try {
    await invoke("coop_invite_friend", { targetUserId: friend.user_id });
    toast(`Einladung an ${friend.display_name || friend.username} gesendet.`);
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

$("open-website-register-btn").addEventListener("click", () => invoke("open_external", { url: REGISTER_PORTAL_URL }));
$("license-portal-btn").addEventListener("click", () => invoke("open_external", { url: REGISTER_PORTAL_URL }));
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
    state.session = await invoke("login_email", { email, password, username: "", create: false });
    $("auth-password").value = "";
    state.friends = await invoke("list_friends");
    state.notifications = await invoke("fetch_notifications").catch(() => []);
    renderSession();
    renderNotifications();
    renderFriends();
    if (admin.isAdmin()) admin.refreshAll().catch(() => {});
    setStatus($("auth-status"), "");
    setStatus($("friend-status"), "");
    setStatus($("launch-feedback"), "");
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
  state.notifications = [];
  state.wsConnected = false;
  renderSession();
  renderNotifications();
  renderFriends();
  setStatus($("friend-status"), "");
  setStatus($("launch-feedback"), "");
  setServerPill("muted", "Nicht angemeldet");
  toast("Abgemeldet.");
});

const JOIN_HINT = {
  private: "Niemand kann deiner Welt beitreten.",
  ask: "Freunde fragen an, du entscheidest.",
  open: "Freunde treten direkt bei.",
};

function renderJoinMode(mode) {
  const seg = $("join-mode");
  const buttons = [...seg.querySelectorAll("button[data-mode]")];
  const index = Math.max(0, buttons.findIndex((b) => b.dataset.mode === mode));
  buttons.forEach((b, i) => {
    b.classList.toggle("is-active", i === index);
    b.setAttribute("aria-checked", String(i === index));
  });
  seg.style.setProperty("--k", index);
  seg.dataset.mode = buttons[index].dataset.mode;
  $("join-mode-hint").textContent = JOIN_HINT[buttons[index].dataset.mode] || "";
}

$("join-mode").addEventListener("click", async (evt) => {
  const btn = evt.target.closest("button[data-mode]");
  if (!btn || btn.classList.contains("is-active")) return;
  const mode = btn.dataset.mode;
  renderJoinMode(mode);
  try {
    state.session = await invoke("set_world_join_mode", { mode });
    renderSession();
    toast(`Welt-Beitritt: ${JOIN_LABEL[mode] || mode}`);
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
    renderSession();
  }
});

$("copy-code-btn").addEventListener("click", async () => {
  const code = $("active-lobby-code").textContent.trim();
  if (!code || code === "------") return;
  await navigator.clipboard.writeText(code).catch(() => {});
  toast(`Raumcode ${code} kopiert.`);
});

$("join-code-form").addEventListener("submit", async (evt) => {
  evt.preventDefault();
  const code = $("join-code-input").value.trim().toUpperCase();
  if (!code) return;
  $("join-code-btn").disabled = true;
  setStatus($("friend-status"), "Prüfe Raumcode…");
  try {
    const info = await invoke("coop_resolve_code", { roomCode: code });
    const res = await invoke("coop_request_join", {
      hostUserId: info.host_user_id || "",
      hostUid: info.host_uid || "",
      roomCode: info.room_code || code,
    });
    $("join-code-input").value = "";
    if (res.status === "approved" && res.match_id) {
      setStatus($("friend-status"), "");
      await startGame("launch_join_match", {
        matchId: res.match_id,
        roomCode: res.room_code || code,
        worldName: res.world_name || info.world_name || null,
      });
      toast(`Verbinde mit „${info.world_name || "Koop"}“…`);
    } else {
      setStatus($("friend-status"), `Beitrittsanfrage an ${info.host_name || "Host"} gesendet.`);
      toast("Beitrittsanfrage gesendet.");
    }
  } catch (err) {
    setStatus($("friend-status"), String(err), true);
  } finally {
    $("join-code-btn").disabled = false;
  }
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

// ---------------------------------------------------------------- game status and launch
function renderGameStatus() {
  const gs = state.gameStatus;
  if (!gs) return;
  const dot = $("game-dot");
  const label = $("game-label");
  const play = $("play-btn");
  const updBtn = $("update-btn");
  const version = gs.update_available ? `Update ${gs.remote_version} verfügbar` : gs.mode === "dev" ? "Dev-Build" : `v${gs.local_version}`;
  if (gs.ready) {
    dot.className = "status-dot is-ok";
    label.textContent = `${gs.status_label}, ${version}`;
    label.title = gs.resolved_exe;
    play.classList.toggle("is-update", Boolean(gs.update_available));
  } else if (gs.update_available && gs.remote_download_url) {
    dot.className = "status-dot is-warn";
    label.textContent = `Noch nicht installiert, v${gs.remote_version} steht bereit`;
    label.title = "";
    play.classList.remove("is-update");
  } else {
    dot.className = "status-dot is-err";
    label.textContent = "Spiel nicht gefunden. Pfad in den Optionen setzen.";
    label.title = "";
    play.classList.remove("is-update");
  }
  syncPlayButton();
  const canUpdate = Boolean(gs.update_available && gs.remote_download_url);
  updBtn.hidden = !canUpdate;
  updBtn.disabled = state.updating;
  if (canUpdate) {
    if (state.updating) {
      updBtn.textContent = gs.mode === "missing" ? "Download läuft…" : "Update läuft…";
    } else {
      updBtn.textContent =
        gs.mode === "missing"
          ? `Spiel v${gs.remote_version} herunterladen`
          : `Update v${gs.remote_version} installieren`;
    }
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
  if (state.launching || state.updating) return;
  state.launching = true;
  const play = $("play-btn");
  play.disabled = true;
  play.classList.add("is-launching");
  app.classList.add("is-launching");
  parade?.start();
  if (atmosphere) atmosphere.flareTarget = 1;
  renderPixelNode($("play-word"), "Startet");
  setStatus($("launch-feedback"), "");
  try {
    const msg = await startGame("launch_game");
    await new Promise((r) => setTimeout(r, 1400));
    setStatus($("launch-feedback"), msg);
    pollRunning();
  } catch (err) {
    setStatus($("launch-feedback"), String(err), true);
  } finally {
    setTimeout(() => {
      state.launching = false;
      play.classList.remove("is-launching");
      app.classList.remove("is-launching");
      parade?.stop();
      if (atmosphere) atmosphere.flareTarget = 0;
      applyRunning(true);
      pollRunning();
    }, 2400);
  }
});

// ---------------------------------------------------------------- the game is running
// The launcher asks the backend (child process or the game's IPC ping) every two seconds;
// while the game runs the stone is grey and cannot be pressed.
async function pollRunning() {
  let on = false;
  try {
    on = Boolean(await invoke("game_running"));
  } catch {
    on = false;
  }
  if (on !== state.running) {
    state.running = on;
    applyRunning(true);
  }
  // The launcher steps aside once a game it started is up, and comes back when it ends.
  if (on && state.stepAsidePending) {
    state.stepAsidePending = false;
    state.steppedAside = true;
    invoke("hide_while_playing", { tray: state.prefs.trayWhilePlaying }).catch(() => {});
  } else if (!on && state.steppedAside) {
    state.steppedAside = false;
    invoke("restore_launcher").catch(() => {});
  }
}

/** Every game start goes through here, so the launcher knows to step aside afterwards. */
async function startGame(cmd, args) {
  const result = await invoke(cmd, args);
  state.stepAsidePending = true;
  return result;
}

function applyRunning(force = false) {
  if (state.launching) return;
  const on = state.running;
  app.classList.toggle("is-running", on);
  const play = $("play-btn");
  renderPixelNode($("play-word"), on ? "Spiel läuft" : "Spielen");
  if (on) {
    play.disabled = true;
    $("play-sub").textContent = "Beende das Spiel, um neu zu starten";
    setStatus($("launch-feedback"), "");
  } else {
    renderSession();
    renderGameStatus();
  }
  updateNight();
}

function updateNight() {
  if (!atmosphere) return;
  atmosphere.dimTarget = state.page !== "home" ? 0.72 : state.running ? 0.66 : 0.46;
}

setInterval(() => {
  if (!document.hidden) pollRunning();
}, 2000);

$("update-btn").addEventListener("click", async () => {
  if (state.updating || state.launching) return;
  state.updating = true;
  $("update-progress-wrap").hidden = false;
  $("update-progress-bar").style.width = "4%";
  renderGameStatus();
  try {
    state.gameStatus = await invoke("install_game_update");
    $("update-progress-bar").style.width = "100%";
    setStatus($("launch-feedback"), `Shadowspore v${state.gameStatus.local_version} installiert!`);
    toast(`Shadowspore v${state.gameStatus.local_version} bereit!`);
    setTimeout(() => { $("update-progress-wrap").hidden = true; }, 2200);
  } catch (err) {
    setStatus($("launch-feedback"), String(err), true);
    $("update-progress-wrap").hidden = true;
  } finally {
    state.updating = false;
    renderGameStatus();
  }
});

// ---------------------------------------------------------------- settings
let serverCfg = { server_url: "", server_key: "" };
async function fillSettings() {
  const cfg = await invoke("get_settings");
  serverCfg = { server_url: cfg.server_url, server_key: cfg.server_key };
  $("cfg-game-exe").value = cfg.game_exe_path;
  $("cfg-godot-exe").value = cfg.godot_exe_path;
  $("cfg-manifest-url").value = cfg.manifest_url;
  $("opt-motion").checked = state.prefs.reduceMotion;
  $("opt-slides").checked = state.prefs.autoSlides;
  $("opt-tray").checked = state.prefs.trayWhilePlaying;
  setStatus($("settings-status"), "");
}

$("cancel-settings-btn").addEventListener("click", fillSettings);
$("opt-motion").addEventListener("change", (e) => {
  state.prefs.reduceMotion = e.target.checked;
  applyPrefs();
  savePrefs();
});
$("opt-tray").checked = state.prefs.trayWhilePlaying;
$("opt-tray").addEventListener("change", (e) => {
  state.prefs.trayWhilePlaying = e.target.checked;
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
        server_url: serverCfg.server_url,
        server_key: serverCfg.server_key,
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
admin = createAdminController({
  invoke,
  state,
  ROLE_LABEL,
  JOIN_LABEL,
  roleKey,
  normalizeJoinMode,
  setStatus,
  toast,
  formatUnix,
  startGame,
  refreshSocial: () => refreshSocial(),
  renderSession,
});

let atmosphere = null;
async function init() {
  setupArt();
  hydratePixelText();
  syncPlayButton();
  atmosphere = new Atmosphere($("atmosphere"));
  updateNight();
  applyPrefs();
  parade = new CastParade($("parade"), castSheet);
  if (!inTauri) document.documentElement.classList.add("is-browser");
  requestAnimationFrame(() => requestAnimationFrame(() => app.classList.remove("is-booting")));

  loadChangelog();
  fillSettings().catch(() => {});
  pollRunning();

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
      const [friends, notifications] = await Promise.all([
        invoke("list_friends"),
        invoke("fetch_notifications").catch(() => []),
      ]);
      state.friends = friends;
      state.notifications = notifications;
      renderNotifications();
      renderFriends();
      if (admin.isAdmin()) admin.refreshAll().catch(() => {});
    } else {
      setServerPill("muted", "Nicht angemeldet");
    }
  } catch (err) {
    setServerPill("err", "Server nicht erreichbar");
    setStatus($("auth-status"), String(err), true);
  }

  const params = new URLSearchParams(location.search);
  if (params.get("page")) go(params.get("page"));

  let presenceTimer = null;
  await listenEvent("coop://ws-status", (payload) => {
    state.wsConnected = Boolean(payload?.connected);
    if (state.session?.logged_in) {
      setServerPill("ok", state.wsConnected ? "Live verbunden" : "Verbunden");
    }
  });
  await listenEvent("coop://notification", (notif) => {
    if (!notif || !notif.id) return;
    if (!state.notifications.some((n) => n.id === notif.id)) {
      state.notifications = [notif, ...state.notifications];
      renderNotifications();
      if (notif.subject) toast(notif.subject);
    }
  });
  await listenEvent("coop://presence", () => {
    clearTimeout(presenceTimer);
    presenceTimer = setTimeout(() => refreshSocial(), 500);
  });
  await listenEvent("updater://progress", (p) => {
    if (!p) return;
    $("update-progress-wrap").hidden = false;
    $("update-progress-bar").style.width = `${Math.max(4, Number(p.percent || 0))}%`;
    if (p.message) setStatus($("launch-feedback"), p.message, p.stage === "error");
  });

  setInterval(() => {
    if (!state.session?.logged_in) return;
    if (state.page === "social") refreshSocial();
    if (state.page === "admin" && admin.isAdmin()) admin.refreshAll().catch(() => {});
  }, 20000);
}

init();
