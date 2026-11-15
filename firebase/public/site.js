import { createAccountApi, tokenExpiry, normalizeLicenseKey } from './account.mjs';
import { hydratePixelText } from './pixelfont.mjs';
import { Atmosphere, CastParade } from './fx.mjs';
import { WorldMapEngine } from './map.mjs';
import { AdminController } from './admin.mjs';
import { splitVersions, renderMarkdown, splitEmoji } from './markdown.mjs';
import { START_TILE, SUPERS } from './map-data.mjs';

const $ = (id) => document.getElementById(id);

const SESSION_KEY = 'shadowspore.web.session.v2';
const LEGACY_SESSION_KEY = 'shadowspore.web.session.v1';
const BANNER_DISMISS_KEY = 'shadowspore.web.banner.dismissed.v1';

let chronicleVersions = [];
let selectedVersionIdx = 0;

const api = createAccountApi();
const reduceMql = window.matchMedia('(prefers-reduced-motion: reduce)');

let token = '';
let refreshToken = '';
let profile = null;
let authMode = 'login';
let busy = false;
let epoch = 0;
let expiryTimer = 0;
let activePage = 'home';
let userPaused = false;
let currentMood = 'night';
let currentWorldMeta = null;
let siteConfigCache = { banner_enabled: false, banner_text: '', banner_tone: 'teal', pins: [] };

const avatarSrc = (id) => (id === 'ellie_leere' ? './img/avatar_leere.png' : './img/avatar_lichtung.png');

function el(tag, className = '', text = '') {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== '') node.textContent = text;
  return node;
}

// ---------------------------------------------------------------- Toast notifications
function toast(message, tone = '') {
  const region = $('toast-region');
  if (!region || !message) return;
  while (region.children.length >= 4) region.firstElementChild?.remove();
  const item = el('div', `toast stair${tone ? ` is-${tone}` : ''}`, message);
  region.append(item);
  setTimeout(() => item.remove(), 4200);
}

// ---------------------------------------------------------------- Top-layer dialogs & exit animations
let supportsDisplayTransition;
function canTransitionDisplay() {
  if (supportsDisplayTransition !== undefined) return supportsDisplayTransition;
  if (!window.CSS?.supports?.('transition-behavior', 'allow-discrete') || !document.body) {
    supportsDisplayTransition = false;
    return false;
  }
  const probe = document.createElement('div');
  probe.style.cssText = 'transition: display 1s allow-discrete !important; display: block;';
  document.body.appendChild(probe);
  getComputedStyle(probe).display;
  probe.style.display = 'none';
  supportsDisplayTransition = getComputedStyle(probe).display === 'block';
  probe.remove();
  return supportsDisplayTransition;
}

function supportsTopLayerExit() {
  return Boolean(window.CSS?.supports?.('overlay', 'auto') && canTransitionDisplay());
}

async function closeTopLayer(dialog, returnValue) {
  if (!dialog || !dialog.open) return;
  if (!supportsTopLayerExit()) {
    dialog.setAttribute('data-closing', '');
    const animations = dialog.getAnimations({ subtree: true });
    if (animations.length > 0) {
      await Promise.race([
        Promise.allSettled(animations.map((a) => a.finished)),
        new Promise((r) => setTimeout(r, 400)),
      ]);
    }
    if (!dialog.hasAttribute('data-closing')) return;
    dialog.removeAttribute('data-closing');
  }
  dialog.close(returnValue);
}

const outsideRect = (e, dialog) => {
  const r = dialog.getBoundingClientRect();
  return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom;
};

document.querySelectorAll('dialog.bark-dialog').forEach((dialog) => {
  dialog.addEventListener('cancel', (event) => {
    event.preventDefault();
    closeTopLayer(dialog, 'cancel');
  });

  dialog.addEventListener('close', () => {
    dialog.removeAttribute('data-closing');
  });

  // Safari fallback for <dialog closedby="any">
  if (!('closedBy' in HTMLDialogElement.prototype)) {
    let pressedOutside = false;
    dialog.addEventListener('pointerdown', (e) => {
      pressedOutside = outsideRect(e, dialog);
    });
    dialog.addEventListener('pointerup', (e) => {
      if (pressedOutside && outsideRect(e, dialog)) closeTopLayer(dialog, 'cancel');
      pressedOutside = false;
    });
  }
});

document.querySelectorAll('[data-close-dialog]').forEach((btn) => {
  btn.addEventListener('click', () => closeTopLayer($(btn.dataset.closeDialog), 'cancel'));
});

function confirmAction({ title = 'Aktion bestätigen', body = '', okText = 'Bestätigen' } = {}) {
  const dialog = $('confirm-dialog');
  if (!dialog) return Promise.resolve(false);
  $('confirm-title').textContent = title;
  $('confirm-body').textContent = body;
  $('confirm-ok-btn').textContent = okText;

  return new Promise((resolve) => {
    let settled = false;
    const done = (val) => {
      if (settled) return;
      settled = true;
      dialog.removeEventListener('close', onClose);
      resolve(val);
    };
    const onClose = () => {
      const accepted = dialog.returnValue === 'confirm';
      dialog.returnValue = '';
      done(accepted);
    };
    dialog.returnValue = '';
    dialog.addEventListener('close', onClose);
    dialog.showModal();
  });
}

// Intercept form submit inside #confirm-dialog when browser lacks discrete top-layer exit animation
const confirmForm = $('confirm-dialog')?.querySelector('form[method="dialog"]');
confirmForm?.addEventListener('submit', (e) => {
  if (!supportsTopLayerExit()) {
    e.preventDefault();
    const rv = e.submitter?.value || 'cancel';
    closeTopLayer($('confirm-dialog'), rv);
  }
});

// ---------------------------------------------------------------- Pixel Typography & Atmosphere
hydratePixelText(document);

const atmosphereCanvas = $('global-atmosphere');
const atmosphere = atmosphereCanvas ? new Atmosphere(atmosphereCanvas, document.body) : null;
const paradeCanvas = $('cast-parade');
const parade = paradeCanvas ? new CastParade(paradeCanvas, './img/loading_cast.png', paradeCanvas.closest('.account-stage') || paradeCanvas.parentElement) : null;

// ---------------------------------------------------------------- World Map Engine
const mapStage = $('map-stage');
let adminCtrl = null;

function setMood(nextMood) {
  currentMood = nextMood === 'day' || nextMood === 'blood' ? nextMood : 'night';
  document.documentElement.dataset.mood = currentMood;
  atmosphere?.setMood(currentMood === 'day' ? 'day' : 'night');
  mapEngine?.setMood(currentMood);

  const labelEl = $('mood-toggle-label');
  if (labelEl) {
    labelEl.textContent = currentMood === 'day'
      ? 'Morgengold'
      : currentMood === 'blood'
        ? 'Blutmond'
        : 'Nachtlichtung';
  }
  document.querySelectorAll('[data-map-mood]').forEach((btn) => {
    btn.classList.toggle('is-active', btn.dataset.mapMood === currentMood);
  });
}

function syncPinBannerUi() {
  if (!mapStage) return;
  const activeMode = mapStage.dataset.pinMode === 'active';
  const isPicking = mapEngine?.pinTool === 'pick';
  const banner = $('map-pick-banner');
  const pinBtn = $('map-pin-btn');
  const pinLabel = $('map-pin-label');
  if (banner) banner.hidden = !isPicking;
  if (pinBtn) pinBtn.classList.toggle('is-active', activeMode && !isPicking);
  if (pinLabel) pinLabel.textContent = activeMode && !isPicking ? 'Karte klicken…' : 'Marker';
}

function renderFeatureInspector(feat) {
  const drawer = $('map-inspector');
  if (!drawer) return;
  if (!feat) {
    drawer.hidden = true;
    return;
  }
  drawer.hidden = false;
  $('ins-cat').textContent = feat.category || 'Weltort';
  $('ins-title').textContent = feat.name || 'Unbekannter Ort';
  $('ins-sub').textContent = feat.sub || `${Math.round(feat.tile?.[0] ?? 550)} · ${Math.round(feat.tile?.[1] ?? 550)}`;

  const imgEl = $('ins-img');
  if (feat.image) {
    imgEl.src = feat.image;
    imgEl.alt = feat.name || '';
    imgEl.hidden = false;
  } else {
    imgEl.hidden = true;
  }

  $('ins-desc').textContent = feat.desc || '';

  const thoughtEl = $('ins-thought');
  if (feat.thought) {
    thoughtEl.textContent = `„${feat.thought}“`;
    thoughtEl.hidden = false;
  } else {
    thoughtEl.hidden = true;
  }

  const distList = $('ins-districts');
  distList.replaceChildren();
  if (Array.isArray(feat.districts) && feat.districts.length) {
    for (const d of feat.districts) {
      const li = el('li');
      const strong = el('strong', '', `${d.name}: `);
      li.append(strong, document.createTextNode(d.about || d.note || ''));
      distList.append(li);
    }
    distList.hidden = false;
  } else {
    distList.hidden = true;
  }

  const awakenBtn = $('ins-awaken-btn');
  const isWaystone = feat.kind === 'waystone';
  const alreadyAwake = isWaystone && mapEngine?.awakenedWaystones?.has(feat.id);
  awakenBtn.hidden = !isWaystone;
  if (isWaystone) {
    awakenBtn.disabled = !!alreadyAwake;
    awakenBtn.textContent = alreadyAwake ? 'Bereits erwacht' : 'Wächterin erwecken';
  }

  const delPinBtn = $('ins-delete-pin-btn');
  delPinBtn.hidden = !feat.isCustom;

  const adminPinBtn = $('ins-admin-pin-btn');
  adminPinBtn.hidden = String(profile?.role || '').toLowerCase() !== 'admin';
}

const mapEngine = mapStage
  ? new WorldMapEngine({
    stageEl: mapStage,
    glCanvas: $('map-gl'),
    overlayCanvas: $('map-overlay'),
    onHover(info) {
      if (!info) return;
      const biomeEl = $('map-biome-readout');
      const coordEl = $('map-coord-readout');
      const subEl = $('map-hover-name');
      if (biomeEl) biomeEl.textContent = info.biomeName || 'Die Lichtung';
      if (coordEl) coordEl.textContent = `${info.tile[0]} · ${info.tile[1]}`;
      if (subEl) {
        subEl.textContent = info.feature
          ? `${info.feature.category}: ${info.feature.name}`
          : info.land
            ? `${info.superName} · Ebene ${Math.round(info.level / 25)}`
            : 'Äußere Leere · Ziehen zum Erkunden';
      }
    },
    onSelect(feat) {
      renderFeatureInspector(feat);
    },
    onCamera({ scale, touring }) {
      const zoomEl = $('map-zoom-readout');
      if (zoomEl) zoomEl.textContent = `${Math.round(scale * 100)}%`;
      const tourBtn = $('map-tour-btn');
      const tourLbl = $('map-tour-label');
      if (tourBtn) tourBtn.classList.toggle('is-active', !!touring);
      if (tourLbl) tourLbl.textContent = touring ? 'Flug stoppen' : 'Sporen-Windflug';
    },
    onCustomPinsChange() {
      syncPinBannerUi();
    },
  })
  : null;

if (mapStage) {
  const pinObs = new MutationObserver(() => syncPinBannerUi());
  pinObs.observe(mapStage, { attributes: true, attributeFilter: ['data-pin-mode'] });
}

// Region quick-jumpers & feature jumpers
document.querySelectorAll('[data-super-jump]').forEach((btn) => {
  btn.addEventListener('click', () => {
    if (!mapEngine) return;
    const superId = Number(btn.dataset.superJump);
    document.querySelectorAll('[data-super-jump], [data-feat-jump]').forEach((b) => {
      b.classList.toggle('is-active', b === btn);
    });
    if (superId < 0) mapEngine.resetView();
    else mapEngine.setActiveSuper(superId);
  });
});

document.querySelectorAll('[data-feat-jump]').forEach((btn) => {
  btn.addEventListener('click', () => {
    if (!mapEngine) return;
    document.querySelectorAll('[data-super-jump], [data-feat-jump]').forEach((b) => {
      b.classList.toggle('is-active', b === btn);
    });
    mapEngine.selectFeatureById(btn.dataset.featJump);
  });
});

$('map-tour-btn')?.addEventListener('click', () => {
  if (!mapEngine) return;
  if (mapEngine.tour) mapEngine.stopTour();
  else {
    mapEngine.startWindTour();
    toast('Sporen-Windflug gestartet — folge der Kamera über Veldora.', 'good');
  }
});

$('map-fog-btn')?.addEventListener('click', () => {
  if (!mapEngine) return;
  const next = !mapEngine.fogMode;
  mapEngine.setFogMode(next);
  const btn = $('map-fog-btn');
  btn?.setAttribute('aria-pressed', String(next));
  btn?.classList.toggle('is-active', next);
  if (next) toast('Laternen-Nebel aktiv — bewege deinen Cursor als Lichtquelle.', 'good');
});

document.querySelectorAll('[data-map-mood]').forEach((btn) => {
  btn.addEventListener('click', () => setMood(btn.dataset.mapMood));
});

document.querySelectorAll('[data-map-layer]').forEach((chk) => {
  chk.addEventListener('change', () => {
    mapEngine?.setLayer(chk.dataset.mapLayer, chk.checked);
  });
});

$('map-zoom-in')?.addEventListener('click', () => {
  const c = $('map-overlay');
  if (mapEngine && c) mapEngine.zoomAt(1.35, c.clientWidth * 0.5, c.clientHeight * 0.5);
});
$('map-zoom-out')?.addEventListener('click', () => {
  const c = $('map-overlay');
  if (mapEngine && c) mapEngine.zoomAt(1 / 1.35, c.clientWidth * 0.5, c.clientHeight * 0.5);
});
$('map-reset-btn')?.addEventListener('click', () => {
  document.querySelectorAll('[data-super-jump]').forEach((b) => {
    b.classList.toggle('is-active', b.dataset.superJump === '-1');
  });
  document.querySelectorAll('[data-feat-jump]').forEach((b) => b.classList.remove('is-active'));
  mapEngine?.resetView();
});

$('map-pin-btn')?.addEventListener('click', () => {
  if (!mapEngine) return;
  const next = mapEngine.pinTool === 'waymark' ? '' : 'waymark';
  mapEngine.setPinTool(next);
  syncPinBannerUi();
  if (next) toast('Klicke auf einen Ort auf der Karte, um ein Wegzeichen zu setzen.');
});

$('map-pick-cancel')?.addEventListener('click', () => {
  mapEngine?.setPinTool('');
  syncPinBannerUi();
});

$('map-cloud-badge')?.addEventListener('click', () => {
  if (!mapEngine) return;
  mapEngine.selectFeatureById('start_home');
});

$('ins-close')?.addEventListener('click', () => {
  if (mapEngine) mapEngine.selectedFeature = null;
  renderFeatureInspector(null);
});

$('ins-awaken-btn')?.addEventListener('click', () => {
  const feat = mapEngine?.selectedFeature;
  if (!feat || feat.kind !== 'waystone') return;
  mapEngine.awakenWaystone(feat);
  renderFeatureInspector(feat);
  toast(`${feat.name} erwacht — Leylinien-Licht drängt den Nebel zurück.`, 'good');
});

$('ins-delete-pin-btn')?.addEventListener('click', () => {
  const feat = mapEngine?.selectedFeature;
  if (!feat?.isCustom) return;
  mapEngine.removeCustomPin(feat.id);
  toast('Wegzeichen entfernt.');
});

$('ins-share-btn')?.addEventListener('click', async () => {
  const feat = mapEngine?.selectedFeature;
  if (!feat?.tile) return;
  const x = Math.round(feat.tile[0]);
  const y = Math.round(feat.tile[1]);
  const z = Math.max(1.35, mapEngine.scale).toFixed(2);
  const url = `${location.origin}${location.pathname}#map=${x},${y},${z}`;
  try {
    await navigator.clipboard.writeText(url);
    toast(`Karten-Link (${x}, ${y}) kopiert.`, 'good');
  } catch {
    location.hash = `map=${x},${y},${z}`;
    toast(`Koordinaten #map=${x},${y},${z} in Adresszeile gesetzt.`);
  }
});

$('ins-admin-pin-btn')?.addEventListener('click', () => {
  const feat = mapEngine?.selectedFeature;
  if (!feat?.tile) return;
  navigate('admin');
  adminCtrl?.setActiveTab('site');
  const tEl = $('admin-pin-title');
  const nEl = $('admin-pin-note');
  const xEl = $('admin-pin-x');
  const yEl = $('admin-pin-y');
  if (tEl) tEl.value = feat.name || '';
  if (nEl) nEl.value = feat.sub || '';
  if (xEl) xEl.value = String(Math.round(feat.tile[0]));
  if (yEl) yEl.value = String(Math.round(feat.tile[1]));
  tEl?.focus();
});

// ---------------------------------------------------------------- Navigation & Motion State
function applyMotionState() {
  const paused = userPaused || reduceMql.matches;
  const mapActive = activePage === 'home';
  document.body.classList.toggle('is-paused', userPaused);

  atmosphere?.setReduced(reduceMql.matches);
  atmosphere?.setPaused(paused);
  parade?.setReduced(reduceMql.matches);
  parade?.setPaused(paused || activePage !== 'account');
  mapEngine?.setReducedMotion(reduceMql.matches);
  mapEngine?.setPaused(paused || !mapActive || document.hidden);

  if (!paused && !document.hidden) {
    atmosphere?.start();
    if (activePage === 'account') parade?.start();
    if (mapActive) mapEngine?.start();
  }

  const label = $('motion-toggle-btn');
  if (label) {
    label.textContent = userPaused ? 'Fortsetzen' : 'Pause';
  }
}

reduceMql.addEventListener('change', applyMotionState);
$('motion-toggle-btn')?.addEventListener('click', () => {
  userPaused = !userPaused;
  applyMotionState();
});

$('mood-toggle-btn')?.addEventListener('click', () => {
  const order = ['night', 'day', 'blood'];
  setMood(order[(order.indexOf(currentMood) + 1) % order.length]);
});

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) applyMotionState();
  else mapEngine?.setPaused(true);
});

const HASH_FOR_PAGE = {
  home: '#map',
  account: '#account',
  chronicle: '#chronicle',
  launcher: '#launcher',
  admin: '#admin',
};

function normalizePageName(raw) {
  const key = String(raw || '').toLowerCase();
  if (key === 'account' || key === 'login' || key === 'register' || key === 'redeem') return 'account';
  if (key === 'chronicle' || key === 'launcher' || key === 'admin') return key;
  return 'home';
}

function isAdminUser() {
  return Boolean(token && profile && String(profile.role || '').toLowerCase() === 'admin');
}

function syncAdminUiAccess() {
  const isAdmin = isAdminUser();
  const railAdmin = $('rail-admin-btn');
  if (railAdmin) {
    railAdmin.hidden = !isAdmin;
    railAdmin.dataset.adminUnlocked = isAdmin ? 'true' : 'false';
  }
  const hubAdminBtn = $('hub-admin-jump-btn');
  if (hubAdminBtn) hubAdminBtn.hidden = !isAdmin;
  const chipRole = $('chip-role-badge');
  if (chipRole) chipRole.hidden = !isAdmin;
  adminCtrl?.syncAccessState();
  if (!isAdmin && activePage === 'admin') {
    navigate('account');
  }
}

function navigate(targetPage, { updateHash = true } = {}) {
  let page = normalizePageName(targetPage);
  if (page === 'admin' && !isAdminUser()) {
    toast('Admin-Zentrale ist nur für angemeldete Administratoren sichtbar.', 'bad');
    page = 'account';
  }
  activePage = page;

  document.querySelectorAll('[data-page]').forEach((sec) => {
    const active = sec.dataset.page === page;
    sec.hidden = !active;
    sec.classList.toggle('is-active', active);
  });

  document.querySelectorAll('.rail-btn[data-nav]').forEach((btn) => {
    const active = btn.dataset.nav === page;
    if (active) btn.setAttribute('aria-current', 'page');
    else btn.removeAttribute('aria-current');
  });

  if (updateHash) {
    const desired = page === 'home' && location.hash.startsWith('#map=')
      ? location.hash
      : HASH_FOR_PAGE[page];
    if (location.hash !== desired) {
      history.replaceState(null, '', desired);
    }
  }

  if (page === 'home') {
    requestAnimationFrame(() => {
      mapEngine?.resize();
      applyMotionState();
    });
  } else {
    if (page !== 'home') window.scrollTo({ top: 0, behavior: 'instant' });
    applyMotionState();
  }

  if (page === 'admin') {
    adminCtrl?.refreshAll();
  } else {
    adminCtrl?.syncPolling();
  }
}

document.querySelectorAll('[data-nav], [data-go]').forEach((btn) => {
  btn.addEventListener('click', (e) => {
    if (btn.tagName === 'A') e.preventDefault();
    const target = btn.dataset.nav || btn.dataset.go;
    if (target) navigate(target);
  });
});

// ---------------------------------------------------------------- Website Public Banner & Config Sync
function applySiteConfig(cfg) {
  siteConfigCache = cfg || { banner_enabled: false, banner_text: '', banner_tone: 'teal', pins: [] };
  mapEngine?.setAdminPins(Array.isArray(siteConfigCache.pins) ? siteConfigCache.pins : []);

  const banner = $('site-broadcast');
  const txt = $('site-broadcast-text');
  if (!banner || !txt) return;
  let dismissed = '';
  try {
    dismissed = sessionStorage.getItem(BANNER_DISMISS_KEY) || '';
  } catch {
    // Ignore storage restriction
  }
  const msg = String(siteConfigCache.banner_text || '').trim();
  if (siteConfigCache.banner_enabled && msg && dismissed !== msg) {
    txt.textContent = msg;
    banner.dataset.tone = siteConfigCache.banner_tone || 'teal';
    banner.hidden = false;
  } else {
    banner.hidden = true;
  }
}

$('site-broadcast-close')?.addEventListener('click', () => {
  const banner = $('site-broadcast');
  const msg = $('site-broadcast-text')?.textContent.trim() || '';
  if (banner) banner.hidden = true;
  try {
    if (msg) sessionStorage.setItem(BANNER_DISMISS_KEY, msg);
  } catch {
    // Ignore
  }
});

// ---------------------------------------------------------------- Tabs (focusGroup + roving tabindex + beforematch)
function activateTab(tabs, tab) {
  for (const candidate of tabs) {
    const selected = candidate === tab;
    candidate.setAttribute('aria-selected', String(selected));
    candidate.toggleAttribute('focusgroupstart', selected);
    if (!('focusGroup' in HTMLElement.prototype)) {
      candidate.tabIndex = selected ? 0 : -1;
    }
    const panel = document.querySelector(`[role="tabpanel"][aria-labelledby="${candidate.id}"]`);
    if (panel) {
      if (selected) {
        panel.removeAttribute('hidden');
        panel.tabIndex = 0;
      } else {
        panel.setAttribute('hidden', 'until-found');
        panel.removeAttribute('tabindex');
      }
    }
  }
  try {
    tab.scrollIntoView({ block: 'nearest', inline: 'nearest', container: 'nearest' });
  } catch {
    tab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
}

document.querySelectorAll('.tablist').forEach((tablist) => {
  const tabs = [...tablist.querySelectorAll('[role="tab"]')];
  if (!tabs.length) return;

  if (!('focusGroup' in HTMLElement.prototype)) {
    const initial = tabs.find((t) => t.getAttribute('aria-selected') === 'true') || tabs[0];
    tabs.forEach((t) => { t.tabIndex = t === initial ? 0 : -1; });
    tablist.addEventListener('keydown', (e) => {
      const i = tabs.indexOf(document.activeElement);
      if (i < 0) return;
      let nextIdx = -1;
      if (e.key === 'ArrowRight') nextIdx = (i + 1) % tabs.length;
      else if (e.key === 'ArrowLeft') nextIdx = (i - 1 + tabs.length) % tabs.length;
      else if (e.key === 'Home') nextIdx = 0;
      else if (e.key === 'End') nextIdx = tabs.length - 1;
      if (nextIdx >= 0) {
        e.preventDefault();
        const target = tabs[nextIdx];
        target.focus();
        target.click();
      }
    });
  }

  tabs.forEach((tab) => tab.addEventListener('click', () => activateTab(tabs, tab)));

  tablist.parentElement?.addEventListener('beforematch', (e) => {
    const panel = e.target.closest?.('[role="tabpanel"]');
    if (!panel) return;
    const matchedTab = tabs.find((t) => t.id === panel.getAttribute('aria-labelledby'));
    if (matchedTab) activateTab(tabs, matchedTab);
  });
});

// ---------------------------------------------------------------- Validate Input After Interaction + Live ARIA Sync
const announcer = document.createElement('div');
announcer.setAttribute('aria-live', 'polite');
announcer.className = 'visually-hidden';
document.body.append(announcer);
let announceTimer = 0;
let announcedField = null;

function linkError(elNode, shown) {
  const errorId = elNode.dataset.error;
  if (!errorId) return;
  const ids = (elNode.getAttribute('aria-describedby') || '').split(/\s+/).filter((id) => id && id !== errorId);
  if (shown) ids.push(errorId);
  if (ids.length) elNode.setAttribute('aria-describedby', ids.join(' '));
  else elNode.removeAttribute('aria-describedby');
}

function announceError(elNode) {
  const errEl = $(elNode.dataset.error || '');
  if (!errEl) return;
  const label = elNode.labels?.[0] ? `${elNode.labels[0].textContent.trim()}: ` : '';
  clearTimeout(announceTimer);
  announcer.textContent = '';
  announcedField = elNode;
  announceTimer = setTimeout(() => {
    announcer.textContent = label + errEl.textContent.trim();
  }, 500);
}

const dirtyState = new WeakMap();
const flagged = new WeakSet();
const announced = new WeakSet();
const nativeUserInvalid = CSS.supports('selector(:user-invalid)');

function syncFieldAria(elNode, announce = false) {
  if (!elNode?.matches?.('input') || elNode.disabled) return;
  const state = dirtyState.get(elNode);
  const invalid = nativeUserInvalid
    ? elNode.matches(':user-invalid') || Boolean(state?.submitted && !elNode.validity.valid)
    : Boolean(state && (state.submitted || (state.hasBlurred && state.hasInteracted)) && !elNode.validity.valid);

  if (!nativeUserInvalid || state?.submitted) {
    elNode.classList.toggle('user-invalid-fallback', invalid);
    elNode.classList.toggle('user-valid-fallback', Boolean(state && !invalid && elNode.value));
  }
  if (elNode.validity.valid && state?.submitted) {
    state.submitted = false;
    elNode.classList.remove('user-invalid-fallback');
  }

  if (invalid) {
    if (announce && !announced.has(elNode)) {
      announceError(elNode);
      announced.add(elNode);
    }
    elNode.setAttribute('aria-invalid', 'true');
    linkError(elNode, true);
    flagged.add(elNode);
  } else if (flagged.has(elNode) || elNode.getAttribute('aria-invalid') !== 'true') {
    elNode.setAttribute('aria-invalid', 'false');
    linkError(elNode, false);
    flagged.delete(elNode);
    announced.delete(elNode);
    if (announcedField === elNode) {
      clearTimeout(announceTimer);
      announcer.textContent = '';
    }
  }
}

const authForm = $('auth-form');
authForm?.querySelectorAll('input').forEach((node) => node.setAttribute('aria-invalid', 'false'));

authForm?.addEventListener('blur', (e) => {
  const st = dirtyState.get(e.target) || { hasInteracted: false, hasBlurred: false };
  st.hasBlurred = true;
  dirtyState.set(e.target, st);
  syncFieldAria(e.target, true);
}, true);

authForm?.addEventListener('input', (e) => {
  const st = dirtyState.get(e.target) || { hasInteracted: false, hasBlurred: false };
  st.hasInteracted = true;
  dirtyState.set(e.target, st);
  if (e.target.hasAttribute('aria-invalid')) syncFieldAria(e.target, false);
});

authForm?.addEventListener('change', (e) => syncFieldAria(e.target, true), true);

authForm?.addEventListener('invalid', (e) => {
  dirtyState.set(e.target, { hasInteracted: true, hasBlurred: true });
  announced.add(e.target);
  syncFieldAria(e.target, false);
}, true);

authForm?.addEventListener('reset', () => {
  setTimeout(() => {
    authForm.querySelectorAll('input').forEach((node) => {
      dirtyState.delete(node);
      node.classList.remove('user-invalid-fallback', 'user-valid-fallback');
      syncFieldAria(node, false);
    });
    updateKeyRunes('');
  });
}, true);

// ---------------------------------------------------------------- Am Feuer Auth Ritual + Key Runes
function updateKeyRunes(rawKey) {
  const clean = normalizeLicenseKey(rawKey).replace(/[^A-Z0-9]/g, '');
  const slots = [...document.querySelectorAll('.rune-slot')];
  if (!slots.length) return;
  const body = clean.startsWith('SHADOW') ? clean.slice(6) : clean;
  const segments = [
    clean.slice(0, 1) || 'S',
    body.slice(0, 4) || '····',
    body.slice(4, 8) || '····',
    body.slice(8, 12) || '····',
  ];
  slots.forEach((slot, idx) => {
    const span = slot.querySelector('span');
    const txt = segments[idx] || '····';
    if (span) span.textContent = txt;
    const filled = idx === 0 ? clean.length >= 1 : (segments[idx] && !segments[idx].includes('·') && segments[idx].length >= 4);
    slot.classList.toggle('is-lit', !!filled);
  });
}

$('auth-key')?.addEventListener('input', () => {
  const input = $('auth-key');
  const pos = input.selectionStart;
  input.value = input.value.toUpperCase();
  if (typeof pos === 'number') input.setSelectionRange(pos, pos);
  if (input.required) {
    const stripped = normalizeLicenseKey(input.value).replace(/[^A-Z0-9]/g, '');
    input.setCustomValidity(stripped.length < 8 ? 'Bitte vollständigen Lizenzkey eingeben.' : '');
  } else {
    input.setCustomValidity('');
  }
  updateKeyRunes(input.value);
});

function hidePassword() {
  const pwd = $('auth-password');
  const btn = $('toggle-password-btn');
  if (!pwd || !btn) return;
  pwd.type = 'password';
  btn.textContent = 'Zeigen';
  btn.setAttribute('aria-label', 'Passwort anzeigen');
}

$('toggle-password-btn')?.addEventListener('click', () => {
  const pwd = $('auth-password');
  const btn = $('toggle-password-btn');
  if (!pwd || !btn) return;
  const showing = pwd.type === 'text';
  if (showing) {
    hidePassword();
  } else {
    pwd.type = 'text';
    btn.textContent = 'Verbergen';
    btn.setAttribute('aria-label', 'Passwort verbergen');
  }
});

function setFormStatus(message, isError = false) {
  const statusEl = $('auth-form-status');
  if (!statusEl) return;
  statusEl.textContent = message;
  statusEl.classList.toggle('is-error', isError);
}

function setAuthMode(next) {
  if (busy) return;
  authMode = next === 'signup' || next === 'redeem' ? next : 'login';
  const signup = authMode === 'signup';
  const needsKey = authMode !== 'login';

  const emblem = $('altar-emblem');
  if (emblem) emblem.dataset.ritual = authMode;

  const titleEl = $('auth-ritual-title');
  const subEl = $('auth-ritual-sub');
  if (titleEl) {
    titleEl.textContent = signup
      ? 'Konto registrieren'
      : authMode === 'redeem'
        ? 'Lizenzkey einlösen'
        : 'Mit Konto anmelden';
  }
  if (subEl) {
    subEl.textContent = signup
      ? 'Erstelle dein Shadowspore-Konto mit Beta-Key.'
      : authMode === 'redeem'
        ? 'Melde dich an, um einen weiteren Key auf dein Konto einzulösen.'
        : 'Melde dich mit deinem Shadowspore-Konto an.';
  }

  document.querySelectorAll('[data-auth-mode]').forEach((tab) => {
    const selected = tab.dataset.authMode === authMode;
    tab.setAttribute('aria-selected', String(selected));
    tab.toggleAttribute('focusgroupstart', selected);
    if (!('focusGroup' in HTMLElement.prototype)) tab.tabIndex = selected ? 0 : -1;
  });

  const userField = $('username-field');
  const userInput = $('auth-username');
  const keyField = $('key-field');
  const keyInput = $('auth-key');
  const pwdInput = $('auth-password');
  const submitLbl = $('auth-submit-label');

  if (userField && userInput) {
    userField.hidden = !signup;
    userInput.disabled = !signup;
    userInput.required = signup;
    syncFieldAria(userInput, false);
  }
  if (keyField && keyInput) {
    keyField.hidden = !needsKey;
    keyInput.disabled = !needsKey;
    keyInput.required = needsKey;
    if (!needsKey) keyInput.setCustomValidity('');
    syncFieldAria(keyInput, false);
  }
  if (pwdInput) pwdInput.autocomplete = signup ? 'new-password' : 'current-password';
  if (submitLbl) {
    submitLbl.textContent = signup
      ? 'Konto & Key aktivieren'
      : authMode === 'redeem'
        ? 'Anmelden & Key einlösen'
        : 'Jetzt anmelden';
  }
  setFormStatus('');
}

document.querySelectorAll('[data-auth-mode]').forEach((btn) => {
  btn.addEventListener('click', () => setAuthMode(btn.dataset.authMode));
});

function readStoredSession() {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (raw) {
      if (raw.startsWith('{')) {
        const parsed = JSON.parse(raw);
        return {
          token: String(parsed?.token || ''),
          refreshToken: String(parsed?.refreshToken || ''),
        };
      }
      return { token: String(raw), refreshToken: '' };
    }
    const legacy = sessionStorage.getItem(LEGACY_SESSION_KEY) || '';
    if (legacy) {
      return { token: legacy, refreshToken: '' };
    }
  } catch {
    // Storage access unavailable
  }
  return { token: '', refreshToken: '' };
}

function scheduleSessionRefresh(tok, rt) {
  clearTimeout(expiryTimer);
  if (!tok) return;
  const expMs = tokenExpiry(tok);
  const now = Date.now();
  if (rt) {
    const leadMs = Math.max(5_000, expMs - now - 300_000);
    expiryTimer = setTimeout(async () => {
      if (!refreshToken) {
        expireSession();
        return;
      }
      try {
        const next = await api.refreshSession(refreshToken);
        saveSession(next.token, next.refreshToken);
      } catch (err) {
        if (err?.status === 401 || err?.status === 403) {
          expireSession();
        } else {
          // Retry shortly on transient network blip rather than dropping the login.
          scheduleSessionRefresh(token, refreshToken);
        }
      }
    }, Math.min(leadMs, 2147483647));
  } else {
    expiryTimer = setTimeout(() => expireSession(), Math.max(0, Math.min(expMs - now, 2147483647)));
  }
}

function saveSession(value, nextRefresh = refreshToken) {
  token = value || '';
  refreshToken = value ? String(nextRefresh || '') : '';
  clearTimeout(expiryTimer);
  try {
    if (token) {
      localStorage.setItem(SESSION_KEY, JSON.stringify({ token, refreshToken }));
      sessionStorage.removeItem(LEGACY_SESSION_KEY);
    } else {
      localStorage.removeItem(SESSION_KEY);
      sessionStorage.removeItem(LEGACY_SESSION_KEY);
    }
  } catch {
    // Private browsing mode fallback
  }
  if (token) {
    scheduleSessionRefresh(token, refreshToken);
  }
}

function setBusy(value) {
  busy = value;
  const submit = $('auth-submit-btn');
  if (submit) submit.disabled = value;
  document.querySelectorAll('[data-auth-mode]').forEach((b) => { b.disabled = value; });
  authForm?.setAttribute('aria-busy', String(value));
}

const JOIN_MODE_META = {
  private: { label: 'Privat', hint: 'Nur du kannst deine Welt betreten.' },
  ask: { label: 'Auf Anfrage', hint: 'Freunde fragen an, du entscheidest im Spiel.' },
  open: { label: 'Offen', hint: 'Gefährten & Spieler mit Raumcode können direkt beitreten.' },
};

function renderCloudAndFriends(value, worldMeta, friendsList, worldErr, friendsErr) {
  const cloudBox = $('hub-cloud-box');
  const kpiCloud = $('hub-kpi-cloud');
  const kpiCloudSub = $('hub-kpi-cloud-sub');
  if (cloudBox) {
    if (worldErr) {
      cloudBox.textContent = 'Cloud-Stand konnte gerade nicht geladen werden.';
      if (kpiCloud) kpiCloud.textContent = 'Fehler';
      if (kpiCloudSub) kpiCloudSub.textContent = 'Abruf fehlgeschlagen';
    } else if (worldMeta && (worldMeta.exists || worldMeta.day || worldMeta.saved_at)) {
      const day = Number(worldMeta.day) || 1;
      const date = worldMeta.saved_at ? new Date(Number(worldMeta.saved_at) * 1000) : null;
      const when = date && !Number.isNaN(date.valueOf())
        ? date.toLocaleString('de-DE', { dateStyle: 'short', timeStyle: 'short' })
        : '';
      cloudBox.textContent = `Gespeicherte Welt · Spieltag ${day}${when ? ` (${when})` : ''}`;
      if (kpiCloud) kpiCloud.textContent = `Tag ${day}`;
      if (kpiCloudSub) kpiCloudSub.textContent = when ? `Gesichert ${when}` : 'Mit der Cloud synchronisiert';
      mapEngine?.setPlayerCloudInfo({ day });
    } else {
      cloudBox.textContent = 'Noch keine Welt in der Cloud gespeichert. Starte ein Spiel über den Launcher, um deinen Fortschritt automatisch zu sichern.';
      if (kpiCloud) kpiCloud.textContent = 'Leer';
      if (kpiCloudSub) kpiCloudSub.textContent = 'Noch kein Cloud-Save';
      mapEngine?.setPlayerCloudInfo({ day: null });
    }
  }

  const mapBadge = $('map-cloud-badge');
  const mapCloudText = $('map-cloud-text');
  if (mapBadge && mapCloudText) {
    mapBadge.hidden = !value;
    if (value) {
      mapCloudText.textContent = currentWorldMeta?.day ? `Dein Hof · Tag ${currentWorldMeta.day}` : 'Dein Hof';
    }
  }

  const items = Array.isArray(friendsList) ? friendsList : [];
  const accepted = items.filter((f) => Number(f.state ?? 0) === 0);
  const onlineCount = accepted.filter((f) => f.online).length;
  const pendingCount = items.length - accepted.length;
  if ($('hub-kpi-friends')) $('hub-kpi-friends').textContent = String(accepted.length);
  if ($('hub-kpi-friends-sub')) {
    $('hub-kpi-friends-sub').textContent = pendingCount
      ? `Online: ${onlineCount} · Offene Anfragen: ${pendingCount}`
      : `Online: ${onlineCount}`;
  }
  if ($('hub-friends-badge')) {
    $('hub-friends-badge').textContent = `${items.length} ${items.length === 1 ? 'Kontakt' : 'Kontakte'}`;
  }

  const friendsBox = $('hub-friends-list');
  if (!friendsBox) return;
  friendsBox.replaceChildren();

  if (friendsErr) {
    friendsBox.append(el('p', 'muted-copy', 'Freundesliste konnte gerade nicht geladen werden.'));
    return;
  }
  if (!items.length) {
    friendsBox.append(el('p', 'muted-copy', 'Noch ist es still am Feuer. Füge Gefährten oben über UID oder Spielername hinzu.'));
    return;
  }

  for (const friend of items) {
    const row = el('div', 'friend-row stair');
    const who = el('div', 'friend-who');
    const avaImg = el('img', 'friend-ava');
    avaImg.src = avatarSrc(friend.avatar_url);
    avaImg.width = 28;
    avaImg.height = 28;
    avaImg.alt = '';
    const dot = el('span', `status-dot${friend.online ? ' is-online' : ''}`);
    const nameTxt = friend.display_name || friend.username || 'Spieler';
    const statusTxt = friend.coop_active
      ? `In Koop-Welt${friend.coop_world_name ? `: ${friend.coop_world_name}` : ''}`
      : Number(friend.state) === 1
        ? 'Anfrage gesendet'
        : Number(friend.state) === 2
          ? 'Anfrage erhalten'
          : friend.online
            ? 'Online'
            : 'Offline';
    const metaWrap = el('div');
    metaWrap.append(el('strong', '', nameTxt));
    metaWrap.append(el('div', 'mono-sub', `@${friend.username || 'spieler'}${friend.uid ? ` · #${friend.uid}` : ''} · ${statusTxt}`));
    who.append(avaImg, dot, metaWrap);

    const acts = el('div', 'row-actions');
    if (Number(friend.state) === 2) {
      const acceptBtn = el('button', 'btn btn-teal btn-xs', 'Annehmen');
      acceptBtn.type = 'button';
      acceptBtn.addEventListener('click', async () => {
        try {
          await api.acceptFriend(token, friend.user_id);
          await loadPlayer(token, refreshToken);
          toast(`${nameTxt} als Gefährten angenommen.`, 'good');
        } catch (err) {
          toast(err.message, 'bad');
        }
      });
      acts.append(acceptBtn);
    }
    const rmBtn = el('button', 'btn btn-ghost btn-xs', Number(friend.state) === 1 ? 'Zurückziehen' : 'Entfernen');
    rmBtn.type = 'button';
    rmBtn.addEventListener('click', async () => {
      try {
        await api.removeFriend(token, friend.user_id);
        await loadPlayer(token, refreshToken);
        toast(`${nameTxt} aus der Gefährtenliste entfernt.`);
      } catch (err) {
        toast(err.message, 'bad');
      }
    });
    acts.append(rmBtn);
    row.append(who, acts);
    friendsBox.append(row);
  }
}

function formatLicenseExpiry(ts) {
  const expSec = Number(ts || 0);
  if (!expSec) return 'Unbegrenzt';
  const d = new Date(expSec * 1000);
  if (Number.isNaN(d.valueOf())) return 'Unbegrenzt';
  return `Bis ${d.toLocaleDateString('de-DE', { dateStyle: 'medium' })}`;
}

function renderSignedInState(value, worldMeta = null, friendsList = [], worldErr = false, friendsErr = false) {
  profile = value;
  currentWorldMeta = worldMeta;

  const isAdmin = String(value.role || '').toLowerCase() === 'admin';
  const ava = avatarSrc(value.avatar_url);

  // Header account chip & navigation rail
  const accountChip = $('account-chip');
  accountChip?.classList.remove('is-guest');
  accountChip?.setAttribute('aria-label', 'Konto verwalten');
  $('chip-name').textContent = value.display_name || value.username || 'Konto';
  $('chip-avatar-img').src = ava;
  $('chip-avatar-img').hidden = false;
  $('chip-avatar-icon').hidden = true;
  if ($('rail-account-label')) $('rail-account-label').textContent = 'Konto';
  if ($('rail-account-icon')) $('rail-account-icon').dataset.icon = '9';
  syncAdminUiAccess();
  if (mapEngine?.selectedFeature) renderFeatureInspector(mapEngine.selectedFeature);

  // Expand Account Dashboard across full width and hide the login altar
  $('hearth-shell')?.classList.add('is-signed-in');
  $('hearth-console')?.classList.add('is-signed-in');
  if ($('hearth-altar')) $('hearth-altar').hidden = true;
  $('auth-ritual-panel').hidden = true;
  $('account-hub-panel').hidden = false;

  $('hub-avatar-img').src = ava;
  $('hub-display-name').textContent = value.display_name || value.username || 'Wanderer';
  if ($('hub-username-handle')) {
    $('hub-username-handle').textContent = value.username ? `@${value.username}` : '';
  }

  const roleBadge = $('hub-role-badge');
  roleBadge.textContent = isAdmin ? 'Admin' : value.role || 'Spieler';
  roleBadge.className = `tag ${isAdmin ? 'tag-gold' : 'tag-teal'}`;

  const editionText = value.license_edition ? `${value.license_edition} Edition` : 'Standard';
  const expText = formatLicenseExpiry(value.license_expires_at);
  const licBadge = $('hub-license-badge');
  if (value.banned) {
    licBadge.textContent = `Gesperrt${value.ban_reason ? `: ${value.ban_reason}` : ''}`;
    licBadge.className = 'tag tag-danger';
  } else if (value.license_active) {
    licBadge.textContent = `${editionText} aktiv`;
    licBadge.className = 'tag tag-gold';
  } else {
    licBadge.textContent = value.license_error || 'Ohne Lizenzkey';
    licBadge.className = 'tag tag-warn';
  }

  if ($('hub-kpi-license')) {
    $('hub-kpi-license').textContent = value.banned ? 'Gesperrt' : value.license_active ? 'Aktiv' : 'Inaktiv';
  }
  if ($('hub-kpi-expiry')) {
    $('hub-kpi-expiry').textContent = value.license_active ? `${editionText} · ${expText}` : (value.license_error || 'Key benötigt');
  }
  if ($('hub-fact-username')) {
    $('hub-fact-username').textContent = value.username ? `@${value.username}` : '—';
  }
  if ($('hub-fact-edition')) {
    $('hub-fact-edition').textContent = `${editionText} · ${isAdmin ? 'Admin' : (value.role || 'Spieler')}`;
  }
  if ($('hub-fact-expiry')) {
    $('hub-fact-expiry').textContent = value.license_active ? expText : 'Nicht freigeschaltet';
  }

  $('hub-uid').textContent = value.uid || '—';
  const nameInput = $('hub-name-input');
  if (nameInput && !nameInput.matches(':focus')) {
    nameInput.value = value.display_name || value.username || '';
  }

  document.querySelectorAll('[data-pick-avatar]').forEach((btn) => {
    const id = value.avatar_url === 'ellie_leere' ? 'ellie_leere' : 'ellie_lichtung';
    btn.dataset.selected = String(btn.dataset.pickAvatar === id);
  });

  const jmRaw = String(value.world_join_mode ?? value.join_mode ?? 'ask').trim().toLowerCase();
  const jm = jmRaw === 'friends' ? 'ask' : (JOIN_MODE_META[jmRaw] ? jmRaw : 'ask');
  const jmInfo = JOIN_MODE_META[jm];
  document.querySelectorAll('[data-join-mode]').forEach((btn) => {
    btn.setAttribute('aria-pressed', String(btn.dataset.joinMode === jm));
  });
  if ($('hub-join-hint')) $('hub-join-hint').textContent = jmInfo.hint;
  if ($('hub-kpi-coop')) $('hub-kpi-coop').textContent = jmInfo.label;
  if ($('hub-kpi-coop-sub')) {
    const lobby = value.active_lobby;
    $('hub-kpi-coop-sub').textContent = lobby?.room_code
      ? `Aktiver Raum: ${lobby.room_code}`
      : 'Bereit für Koop über Launcher';
  }

  renderCloudAndFriends(value, worldMeta, friendsList, worldErr, friendsErr);
  adminCtrl?.syncAccessState();
  if (activePage === 'admin' && isAdmin) adminCtrl?.refreshAll();
}

function setHubStatus(message = '', isError = false) {
  const statusEl = $('hub-status');
  if (!statusEl) return;
  statusEl.textContent = message;
  statusEl.hidden = !message;
  statusEl.classList.toggle('is-error', isError);
}

function clearPlayer({ clearStorage = true } = {}) {
  profile = null;
  currentWorldMeta = null;
  epoch++;
  if (clearStorage) {
    saveSession('', '');
  } else {
    token = '';
    refreshToken = '';
    clearTimeout(expiryTimer);
  }

  const accountChip = $('account-chip');
  accountChip?.classList.add('is-guest');
  accountChip?.setAttribute('aria-label', 'Anmelden oder Konto öffnen');
  $('chip-name').textContent = 'Anmelden';
  $('chip-avatar-img').hidden = true;
  $('chip-avatar-icon').hidden = false;
  if ($('rail-account-label')) $('rail-account-label').textContent = 'Anmelden';
  if ($('rail-account-icon')) $('rail-account-icon').dataset.icon = '13';
  $('map-cloud-badge').hidden = true;

  setHubStatus('');
  syncAdminUiAccess();

  $('hearth-shell')?.classList.remove('is-signed-in');
  $('hearth-console')?.classList.remove('is-signed-in');
  if ($('hearth-altar')) $('hearth-altar').hidden = false;
  $('auth-ritual-panel').hidden = false;
  $('account-hub-panel').hidden = true;
  mapEngine?.setPlayerCloudInfo({ day: null });
  if (mapEngine?.selectedFeature) renderFeatureInspector(mapEngine.selectedFeature);
}

function expireSession() {
  clearPlayer({ clearStorage: true });
  setAuthMode('login');
  setFormStatus('Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.', true);
}

async function loadPlayer(currentToken, currentRefresh = refreshToken) {
  const requestEpoch = ++epoch;
  const value = await api.profile(currentToken);
  if (requestEpoch !== epoch) return;
  if (!value?.user_id) throw new Error('Dein Spielerprofil ist unvollständig.');

  saveSession(currentToken, currentRefresh);
  renderSignedInState(value, null, [], false, false);

  const [worldRes, friendsRes, siteRes] = await Promise.allSettled([
    api.worldSummary(currentToken, value.user_id),
    api.friends(currentToken),
    api.adminReadSiteConfig(currentToken, value.user_id),
  ]);
  if (requestEpoch !== epoch) return;

  if ([worldRes, friendsRes].some((r) => r.status === 'rejected' && r.reason?.status === 401)) {
    if (currentRefresh) {
      try {
        const refreshed = await api.refreshSession(currentRefresh);
        await loadPlayer(refreshed.token, refreshed.refreshToken);
        return;
      } catch {
        // Fall through to expire
      }
    }
    expireSession();
    return;
  }

  if (siteRes.status === 'fulfilled' && siteRes.value) {
    applySiteConfig(siteRes.value);
  }

  renderSignedInState(
    value,
    worldRes.status === 'fulfilled' ? worldRes.value : null,
    friendsRes.status === 'fulfilled' ? friendsRes.value : [],
    worldRes.status === 'rejected',
    friendsRes.status === 'rejected',
  );
}

authForm?.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (busy) return;

  const invalidControl = [...authForm.elements].find((node) => !node.disabled && node.willValidate && !node.validity.valid);
  if (invalidControl) {
    [...authForm.elements].forEach((node) => {
      if (!node.disabled && node.willValidate && !node.validity.valid) {
        dirtyState.set(node, { hasInteracted: true, hasBlurred: true, submitted: true });
        syncFieldAria(node, false);
      }
    });
    invalidControl.focus();
    return;
  }

  setBusy(true);
  setFormStatus('Verbindung wird hergestellt …');
  const submittedMode = authMode;
  let authenticated = false;

  try {
    const session = await api.authenticateSession({
      email: $('auth-email').value,
      password: $('auth-password').value,
      username: $('auth-username').value,
      licenseKey: $('auth-key').value,
      mode: authMode,
    });
    authenticated = true;
    $('auth-password').value = '';
    hidePassword();
    await loadPlayer(session.token, session.refreshToken);
    $('auth-key').value = '';
    updateKeyRunes('');
    toast('Erfolgreich angemeldet!', 'good');
  } catch (err) {
    const rawMsg = String(err?.message || '');
    let msg = rawMsg || 'Anmeldung fehlgeschlagen.';
    if (!authenticated) {
      if (/server key/i.test(rawMsg)) {
        msg = 'Verbindung abgelehnt: Client-Key stimmt nicht mit s.shadowspore.com überein.';
      } else if (err?.status === 401) {
        msg = 'E-Mail-Adresse oder Passwort stimmen nicht.';
      } else if (err?.status === 404) {
        msg = 'Kein Konto mit dieser E-Mail-Adresse gefunden.';
      }
    }
    setFormStatus(
      `${authenticated && submittedMode !== 'login' ? 'Kontoaktion erfolgreich, Profilabruf fehlgeschlagen. Bitte über „Anmelden“ erneut versuchen: ' : ''}${msg}`,
      true,
    );
  } finally {
    setBusy(false);
  }
});

// ---------------------------------------------------------------- Hub Actions
$('hub-copy-uid-btn')?.addEventListener('click', async () => {
  const uid = profile?.uid || '';
  if (!uid) return;
  try {
    await navigator.clipboard.writeText(uid);
    toast(`Spieler-ID ${uid} kopiert.`, 'good');
  } catch {
    toast('Kopieren fehlgeschlagen.', 'bad');
  }
});

$('hub-refresh-btn')?.addEventListener('click', async () => {
  if (!token) return;
  const btn = $('hub-refresh-btn');
  btn.disabled = true;
  try {
    await loadPlayer(token);
    toast('Kontostand aktualisiert.', 'good');
  } catch (err) {
    if (err?.status === 401) expireSession();
    else toast(err?.message || 'Aktualisierung fehlgeschlagen.', 'bad');
  } finally {
    btn.disabled = false;
  }
});

$('hub-logout-btn')?.addEventListener('click', async () => {
  const oldToken = token;
  clearPlayer();
  setAuthMode('login');
  authForm?.reset();
  hidePassword();
  setFormStatus('Du wurdest abgemeldet.');
  toast('Erfolgreich abgemeldet.');
  try {
    if (oldToken) await api.logout(oldToken);
  } catch {
    // Session cleared locally
  }
});

document.querySelectorAll('[data-pick-avatar]').forEach((btn) => {
  btn.addEventListener('click', async () => {
    if (!token) return;
    const avatarId = btn.dataset.pickAvatar;
    setHubStatus('Avatar wird gespeichert …');
    try {
      await api.updateAccount(token, { avatarUrl: avatarId });
      await loadPlayer(token, refreshToken);
      setHubStatus(`Avatar auf „${avatarId === 'ellie_leere' ? 'Leere' : 'Lichtung'}“ geändert.`);
      toast('Avatar gewechselt.', 'good');
    } catch (err) {
      setHubStatus(err.message || 'Avatar konnte nicht gespeichert werden.', true);
      toast(err.message, 'bad');
    }
  });
});

$('hub-name-form')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!token) return;
  const nameInput = $('hub-name-input');
  const name = nameInput?.value.trim() || '';
  if (name.length < 2) {
    setHubStatus('Bitte mindestens 2 Zeichen für den Anzeigenamen eingeben.', true);
    toast('Bitte mindestens 2 Zeichen eingeben.', 'bad');
    return;
  }
  const submitBtn = $('hub-name-form').querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;
  setHubStatus('Anzeigename wird gespeichert …');
  try {
    await api.updateAccount(token, { displayName: name });
    nameInput?.blur();
    await loadPlayer(token, refreshToken);
    setHubStatus(`Anzeigename auf „${name}“ gespeichert.`);
    toast('Anzeigename gespeichert.', 'good');
  } catch (err) {
    setHubStatus(err.message || 'Anzeigename konnte nicht gespeichert werden.', true);
    toast(err.message, 'bad');
  } finally {
    if (submitBtn) submitBtn.disabled = false;
  }
});

document.querySelectorAll('[data-join-mode]').forEach((btn) => {
  btn.addEventListener('click', async () => {
    if (!token) return;
    const jm = btn.dataset.joinMode;
    setHubStatus('Beitrittsmodus wird gespeichert …');
    try {
      await api.setJoinMode(token, jm);
      await loadPlayer(token, refreshToken);
      setHubStatus(`Koop-Weltzugang auf „${btn.textContent}“ gestellt.`);
      toast(`Beitrittsmodus auf „${btn.textContent}“ gestellt.`, 'good');
    } catch (err) {
      setHubStatus(err.message || 'Beitrittsmodus konnte nicht geändert werden.', true);
      toast(err.message, 'bad');
    }
  });
});

$('hub-wipe-btn')?.addEventListener('click', async () => {
  if (!token || !profile) return;
  const ok = await confirmAction({
    title: 'Cloud-Welt wirklich zurücksetzen?',
    body: 'Dein gespeicherter Cloud-Weltstand wird unwiderruflich geleert. Beim nächsten Spielstart beginnst du eine frische Lichtung.',
    okText: 'Unwiderruflich löschen',
  });
  if (!ok) return;
  try {
    await api.wipeCloudSave(token, profile.user_id);
    await loadPlayer(token, refreshToken);
    setHubStatus('Cloud-Weltstand zurückgesetzt.');
    toast('Cloud-Weltstand zurückgesetzt.', 'good');
  } catch (err) {
    setHubStatus(err.message || 'Cloud-Weltstand konnte nicht zurückgesetzt werden.', true);
    toast(err.message, 'bad');
  }
});

$('hub-redeem-form')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!token) return;
  const input = $('hub-redeem-input');
  const key = normalizeLicenseKey(input?.value || '');
  if (!key) return;
  try {
    await api.redeemKey(token, key);
    if (input) input.value = '';
    await loadPlayer(token, refreshToken);
    setHubStatus('Lizenzkey aktiviert.');
    toast('Lizenzkey eingelöst!', 'good');
  } catch (err) {
    setHubStatus(err.message || 'Lizenzkey konnte nicht eingelöst werden.', true);
    toast(err.message, 'bad');
  }
});

$('hub-friend-add-form')?.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!token) return;
  const q = $('hub-friend-uid')?.value.trim() || '';
  if (!q) return;
  try {
    const found = await api.findByUid(token, q);
    if (found?.found === false || !found?.user_id) {
      throw new Error(found?.error || 'Kein Spieler mit dieser UID oder diesem Namen gefunden.');
    }
    await api.addFriendByUid(token, found.uid || found.username || q);
    $('hub-friend-uid').value = '';
    await loadPlayer(token, refreshToken);
    setHubStatus(`Freundesanfrage an ${found.display_name || found.username} gesendet.`);
    toast(`Anfrage an ${found.display_name || found.username} gesendet.`, 'good');
  } catch (err) {
    setHubStatus(err.message || 'Freundesanfrage fehlgeschlagen.', true);
    toast(err.message, 'bad');
  }
});

$('hub-room-check-btn')?.addEventListener('click', async () => {
  if (!token) return;
  const code = $('hub-friend-uid')?.value.trim() || '';
  const box = $('hub-room-result');
  if (!code || !box) return;
  box.hidden = false;
  box.textContent = 'Prüfe Raumcode…';
  try {
    const res = await api.resolveRoomCode(token, code);
    const label = res.world_name || res.host_name || res.match_id || 'Aktive Welt';
    box.textContent = `Raum gefunden: ${label}${res.player_count != null ? ` (${res.player_count}/4 Spieler)` : ''}`;
  } catch (err) {
    box.textContent = err.message || 'Raumcode nicht gefunden.';
  }
});

// ---------------------------------------------------------------- Chronicle & Gallery & Launcher
function openShotLightbox(src, caption) {
  const dialog = $('gallery-dialog');
  const img = $('gallery-img');
  const cap = $('gallery-caption');
  if (!dialog || !img || !cap || !src) return;
  img.src = src;
  img.alt = caption || '';
  cap.textContent = caption || '';
  if (!dialog.open) dialog.showModal();
}

function selectChronicleVersion(index) {
  const v = chronicleVersions[index];
  if (!v) return;
  selectedVersionIdx = index;
  document.querySelectorAll('#chronicle-list .news-item').forEach((btn) => {
    btn.classList.toggle('is-active', Number(btn.dataset.versionIndex) === index);
  });
  const badge = $('news-badge');
  const dateEl = $('news-date');
  const titleEl = $('news-title');
  const bodyEl = $('news-body');
  if (badge) {
    badge.className = `tag ${index === 0 ? 'tag-new' : 'tag-gold'}`;
    badge.textContent = v.version;
  }
  if (dateEl) dateEl.textContent = v.date || '';
  if (titleEl) {
    const [, rest] = splitEmoji(v.title || v.version);
    titleEl.textContent = rest || v.title || v.version;
  }
  if (bodyEl) {
    bodyEl.innerHTML = renderMarkdown(v.body || '');
  }
}

function renderChronicleList(filter = '') {
  const list = $('chronicle-list');
  const countEl = $('chronicle-count');
  if (!list) return;
  const q = String(filter || '').trim().toLowerCase();
  list.replaceChildren();
  const visible = [];
  for (const v of chronicleVersions) {
    if (q && !`${v.version} ${v.title} ${v.body}`.toLowerCase().includes(q)) continue;
    visible.push(v);
  }
  if (countEl) {
    countEl.textContent = q
      ? `${visible.length} von ${chronicleVersions.length} Versionen`
      : `${chronicleVersions.length} veröffentlichte Versionen`;
  }
  if (!visible.length) {
    list.append(el('p', 'muted-copy', 'Keine passenden Versionseinträge gefunden.'));
    return;
  }
  for (const v of visible) {
    const btn = el('button', `news-item stair${v.index === selectedVersionIdx ? ' is-active' : ''}`);
    btn.type = 'button';
    btn.dataset.versionIndex = String(v.index);
    const top = el('div', 'news-item-top');
    top.append(el('span', `tag ${v.index === 0 ? 'tag-new' : 'tag-rework'}`, v.version));
    if (v.date) top.append(el('span', 'news-item-date', v.date));
    const [, headingText] = splitEmoji(v.title || '');
    const title = el('strong', '', headingText || v.title || v.version);
    btn.append(top, title);
    btn.addEventListener('click', () => selectChronicleVersion(v.index));
    list.append(btn);
  }
}

async function loadChronicle() {
  const titleEl = $('news-title');
  const bodyEl = $('news-body');
  try {
    const res = await fetch('./CHANGELOG.md', { cache: 'no-cache' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const md = await res.text();
    chronicleVersions = splitVersions(md);
    if (!chronicleVersions.length) throw new Error('Keine Versionen in CHANGELOG.md gefunden.');
    const latestVer = chronicleVersions[0].version;
    const brandVer = $('brand-version');
    if (brandVer) brandVer.textContent = latestVer;
    const launcherVer = $('launcher-dl-sub');
    if (launcherVer) launcherVer.textContent = `Windows 10 / 11 · x64 · ${latestVer}`;
    renderChronicleList($('chronicle-filter')?.value || '');
    selectChronicleVersion(0);
  } catch (err) {
    if (titleEl) titleEl.textContent = 'Chronik konnte nicht geladen werden';
    if (bodyEl) bodyEl.replaceChildren(el('p', 'muted-copy', err?.message || 'Netzwerkfehler beim Laden von CHANGELOG.md.'));
  }
}

$('chronicle-filter')?.addEventListener('input', (e) => {
  renderChronicleList(e.target.value);
});

$('news-body')?.addEventListener('click', (e) => {
  const shotBtn = e.target.closest?.('[data-shot]');
  if (shotBtn) {
    openShotLightbox(shotBtn.dataset.shot, shotBtn.dataset.caption);
  }
});

$('privacy-open-btn')?.addEventListener('click', () => {
  const dlg = $('privacy-dialog');
  if (dlg && !dlg.open) dlg.showModal();
});

$('copy-hash-btn')?.addEventListener('click', async () => {
  const hash = $('installer-sha256')?.textContent?.trim() || '';
  const stateNode = $('copy-hash-state');
  try {
    await navigator.clipboard.writeText(hash);
    if (stateNode) stateNode.textContent = 'SHA-256 Prüfsumme wurde in die Zwischenablage kopiert.';
    toast('SHA-256 Hash kopiert.', 'good');
  } catch {
    if (stateNode) stateNode.textContent = 'Kopieren nicht möglich — bitte Hash manuell markieren.';
  }
});

// ---------------------------------------------------------------- Admin Command Center
const adminRoot = $('admin-root');
adminCtrl = adminRoot
  ? new AdminController({
    rootEl: adminRoot,
    api,
    getToken: () => token,
    getProfile: () => profile,
    confirmAction,
    toast,
    onSiteConfigChange: (cfg) => applySiteConfig(cfg),
    onPickMapCoord(callback) {
      if (!mapEngine) return;
      navigate('home');
      mapEngine.setPinTool('pick', (coords) => {
        syncPinBannerUi();
        navigate('admin');
        callback(coords);
      });
      syncPinBannerUi();
      toast('Klicke einen Ort auf der Weltkarte, um die Koordinaten zu übernehmen.');
    },
  })
  : null;

// ---------------------------------------------------------------- Live Server Health & Boot Sequence
let healthInFlight = false;
let healthTimer = 0;

async function refreshServerStatus() {
  if (healthInFlight) return;
  const pill = $('server-status-pill');
  const lbl = $('server-status-label');
  if (!pill || !lbl) return;
  healthInFlight = true;
  try {
    const res = await api.probeServerHealth();
    pill.dataset.state = res.ok ? 'online' : 'offline';
    lbl.textContent = res.ok ? `Online · ${res.latencyMs} ms` : 'Server offline';
  } catch {
    pill.dataset.state = 'offline';
    lbl.textContent = 'Server offline';
  } finally {
    healthInFlight = false;
  }
}

function startHealthMonitor() {
  clearInterval(healthTimer);
  healthTimer = setInterval(() => {
    if (!document.hidden && navigator.onLine !== false) {
      refreshServerStatus();
    }
  }, 8000);
}

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) refreshServerStatus();
});
window.addEventListener('online', () => refreshServerStatus());
window.addEventListener('offline', () => {
  const pill = $('server-status-pill');
  const lbl = $('server-status-label');
  if (pill) pill.dataset.state = 'offline';
  if (lbl) lbl.textContent = 'Server offline';
});

async function restoreSession() {
  const stored = readStoredSession();
  let savedToken = stored.token;
  let savedRefresh = stored.refreshToken;
  if (!savedToken && !savedRefresh) return;

  setBusy(true);
  try {
    if (!savedToken || tokenExpiry(savedToken) <= Date.now() + 60_000) {
      if (!savedRefresh) {
        clearPlayer({ clearStorage: true });
        return;
      }
      const refreshed = await api.refreshSession(savedRefresh);
      savedToken = refreshed.token;
      savedRefresh = refreshed.refreshToken;
    }

    try {
      await loadPlayer(savedToken, savedRefresh);
    } catch (err) {
      if ((err?.status === 401 || err?.status === 403) && savedRefresh) {
        const refreshed = await api.refreshSession(savedRefresh);
        await loadPlayer(refreshed.token, refreshed.refreshToken);
      } else {
        throw err;
      }
    }
  } catch (err) {
    if (err?.status === 401 || err?.status === 403) {
      clearPlayer({ clearStorage: true });
      setFormStatus('Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.', true);
    } else {
      // Transient offline/5xx error: keep localStorage tokens intact instead of logging user out.
      token = savedToken;
      refreshToken = savedRefresh;
      toast('Sitzung konnte gerade nicht geprüft werden — Server nicht erreichbar.', 'bad');
    }
  } finally {
    setBusy(false);
  }
}

function handleHashRoute() {
  const h = location.hash || '';
  if (h.startsWith('#map=')) {
    navigate('home', { updateHash: false });
    const parts = h.slice(5).split(',').map(Number);
    if (parts.length >= 2 && Number.isFinite(parts[0]) && Number.isFinite(parts[1])) {
      const zoom = Number.isFinite(parts[2]) ? parts[2] : 1.5;
      mapEngine?.flyTo(parts[0], parts[1], zoom);
    }
    return;
  }
  if (h === '#register') {
    setAuthMode('signup');
    navigate('account', { updateHash: false });
  } else if (h === '#redeem') {
    setAuthMode('redeem');
    navigate('account', { updateHash: false });
  } else if (h === '#login' || h === '#account') {
    setAuthMode('login');
    navigate('account', { updateHash: false });
  } else if (h === '#chronicle') {
    navigate('chronicle', { updateHash: false });
  } else if (h === '#launcher') {
    navigate('launcher', { updateHash: false });
  } else if (h === '#admin') {
    navigate('admin', { updateHash: false });
  } else {
    navigate('home', { updateHash: false });
  }
}

clearPlayer({ clearStorage: false });
setAuthMode('login');
setMood('night');
applyMotionState();
refreshServerStatus();
startHealthMonitor();
loadChronicle();
await restoreSession();
handleHashRoute();
window.addEventListener('hashchange', handleHashRoute);
window.addEventListener('storage', (e) => {
  if (e.key !== SESSION_KEY) return;
  if (!e.newValue) {
    clearPlayer({ clearStorage: false });
  } else {
    restoreSession();
  }
});
