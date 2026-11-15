/**
 * Complete Shadowspore Admin Command Center controller.
 * Connects to Nakama Admin RPCs + non-protected website_admin storage + World Map bridge.
 */

function el(tag, className = '', text = '') {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== '') node.textContent = text;
  return node;
}

function formatAge(sec) {
  const s = Math.max(0, Math.round(Number(sec || 0)));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

function formatTs(ts) {
  const n = Number(ts || 0);
  if (!n) return '—';
  const d = new Date(n > 1e12 ? n : n * 1000);
  return d.toLocaleString('de-DE', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function downloadText(filename, content) {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export class AdminController {
  constructor({
    rootEl,
    api,
    getToken,
    getProfile,
    confirmAction,
    toast,
    onSiteConfigChange,
    onPickMapCoord,
  }) {
    this.root = rootEl;
    this.api = api;
    this.getToken = getToken;
    this.getProfile = getProfile;
    this.confirm = confirmAction;
    this.toast = toast;
    this.onSiteConfigChange = onSiteConfigChange;
    this.onPickMapCoord = onPickMapCoord;

    this.activeTab = 'worlds';
    this.autoRefresh = true;
    this.pollTimer = 0;
    this.selectedAccount = null;
    this.issuedBatch = [];
    this.siteConfig = { banner_enabled: false, banner_text: '', banner_tone: 'teal', pins: [] };
    this.cached = {
      overview: null,
      worlds: [],
      accounts: [],
      keys: [],
      build: { enforce: false, hash_list: [] },
      events: [],
    };
    this.filters = {
      accQuery: '',
      accRole: '',
      accStatus: '',
      keyStatus: '',
      keyQuery: '',
      eventKind: '',
    };

    this.bindRootEvents();
  }

  isAdmin() {
    const p = this.getProfile();
    return Boolean(this.getToken() && p && String(p.role || '').toLowerCase() === 'admin');
  }

  setActiveTab(tab) {
    this.activeTab = tab;
    const tabs = [...this.root.querySelectorAll('[data-admin-tab]')];
    const panels = [...this.root.querySelectorAll('[data-admin-panel]')];
    tabs.forEach((b) => {
      const active = b.dataset.adminTab === tab;
      b.setAttribute('aria-selected', active ? 'true' : 'false');
      b.toggleAttribute('focusgroupstart', active);
    });
    panels.forEach((p) => {
      p.hidden = p.dataset.adminPanel !== tab;
    });
  }

  bindRootEvents() {
    const tabBtns = [...this.root.querySelectorAll('[data-admin-tab]')];
    tabBtns.forEach((btn) => {
      btn.addEventListener('click', () => {
        this.setActiveTab(btn.dataset.adminTab);
        this.refreshActiveTab();
      });
    });

    // Keyboard roving support even without native focusgroup
    const tablist = this.root.querySelector('[data-admin-tablist]');
    if (tablist) {
      tablist.addEventListener('keydown', (e) => {
        if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
        const idx = tabBtns.indexOf(document.activeElement);
        if (idx < 0) return;
        e.preventDefault();
        const next = tabBtns[(idx + (e.key === 'ArrowRight' ? 1 : -1) + tabBtns.length) % tabBtns.length];
        next.focus();
        this.setActiveTab(next.dataset.adminTab);
        this.refreshActiveTab();
      });
    }

    // Manual Refresh & Auto-Refresh
    this.root.querySelector('#admin-refresh-btn')?.addEventListener('click', () => this.refreshAll());
    const autoBtn = this.root.querySelector('#admin-auto-btn');
    autoBtn?.addEventListener('click', () => {
      this.autoRefresh = !this.autoRefresh;
      autoBtn.dataset.active = this.autoRefresh ? 'true' : 'false';
      autoBtn.textContent = this.autoRefresh ? 'Auto-Sync AN (4s)' : 'Auto-Sync AUS';
      this.syncPolling();
    });

    // Force-Join / Room Lookup Form
    this.root.querySelector('#admin-force-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const tok = this.getToken();
      if (!tok) return;
      const q = this.root.querySelector('#admin-force-query')?.value.trim() || '';
      const out = this.root.querySelector('#admin-force-result');
      if (!q) return;
      try {
        const res = await this.api.adminForceJoin(tok, { query: q, roomCode: q.includes('-') ? q : '' });
        this.renderForceResult(out, res);
        this.toast('Force-Join Ticket bereitgestellt.', 'good');
      } catch (err) {
        this.renderForceError(out, err.message);
      }
    });

    this.root.querySelector('#admin-code-probe-btn')?.addEventListener('click', async () => {
      const tok = this.getToken();
      const q = this.root.querySelector('#admin-force-query')?.value.trim() || '';
      const out = this.root.querySelector('#admin-force-result');
      if (!tok || !q) return;
      try {
        const res = await this.api.resolveRoomCode(tok, q);
        this.renderForceResult(out, res, true);
      } catch (err) {
        this.renderForceError(out, err.message);
      }
    });

    // Players Search & Filters
    const accSearchForm = this.root.querySelector('#admin-acc-search-form');
    accSearchForm?.addEventListener('submit', (e) => {
      e.preventDefault();
      this.filters.accQuery = this.root.querySelector('#admin-acc-query')?.value.trim() || '';
      this.filters.accRole = this.root.querySelector('#admin-acc-role')?.value || '';
      this.filters.accStatus = this.root.querySelector('#admin-acc-status')?.value || '';
      this.loadAccounts();
    });
    this.root.querySelector('#admin-uid-lookup-btn')?.addEventListener('click', async () => {
      const tok = this.getToken();
      const q = this.root.querySelector('#admin-acc-query')?.value.trim() || '';
      if (!tok || !q) return;
      try {
        const hit = await this.api.findByUid(tok, q);
        this.selectAccount(hit);
        this.toast(`Gefunden: ${hit.display_name || hit.username} (${hit.uid})`, 'good');
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });

    // Issue Keys Form
    this.root.querySelector('#admin-issue-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const tok = this.getToken();
      if (!tok) return;
      const count = Number(this.root.querySelector('#admin-key-count')?.value || 1);
      const edition = this.root.querySelector('#admin-key-edition')?.value || 'standard';
      const roleGrant = this.root.querySelector('#admin-key-role')?.value || 'player';
      const expiresDays = Number(this.root.querySelector('#admin-key-days')?.value || 0);
      const note = this.root.querySelector('#admin-key-note')?.value.trim() || '';
      try {
        const res = await this.api.adminIssueKeys(tok, { count, edition, roleGrant, note, expiresDays });
        this.issuedBatch = Array.isArray(res.keys) ? res.keys : [];
        this.renderIssuedBatch();
        this.toast(`${this.issuedBatch.length} Lizenzkey(s) erstellt.`, 'good');
        await Promise.all([this.loadKeys(), this.loadOverview()]);
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });

    this.root.querySelector('#admin-copy-batch-btn')?.addEventListener('click', async () => {
      if (!this.issuedBatch.length) return;
      await navigator.clipboard.writeText(this.issuedBatch.join('\n')).catch(() => {});
      this.toast('Key-Charge kopiert.', 'good');
    });

    this.root.querySelector('#admin-export-batch-btn')?.addEventListener('click', () => {
      if (!this.issuedBatch.length) return;
      downloadText(`shadowspore-keys-${new Date().toISOString().slice(0, 10)}.txt`, this.issuedBatch.join('\n'));
    });

    this.root.querySelector('#admin-key-filter-form')?.addEventListener('submit', (e) => {
      e.preventDefault();
      this.filters.keyStatus = this.root.querySelector('#admin-key-status-filter')?.value || '';
      this.filters.keyQuery = this.root.querySelector('#admin-key-query-filter')?.value.trim() || '';
      this.loadKeys();
    });

    // Build Gate Controls
    this.root.querySelector('#admin-build-enforce-btn')?.addEventListener('click', async () => {
      const tok = this.getToken();
      if (!tok) return;
      const next = !this.cached.build.enforce;
      try {
        this.cached.build = await this.api.adminRegisterBuild(tok, { enforce: next });
        this.renderBuild();
        await this.loadOverview();
        this.toast(`Build-Gate ${next ? 'aktiviert (strikt)' : 'deaktiviert'}.`, 'good');
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });

    this.root.querySelector('#admin-build-manifest-btn')?.addEventListener('click', async () => {
      try {
        const res = await fetch('./updates/manifest.json', { cache: 'no-store' });
        const mf = await res.json();
        const sha = mf.exe_sha256 || mf.sha256 || '';
        const ver = mf.version || '0.1.0';
        const shaInput = this.root.querySelector('#admin-build-sha');
        const verInput = this.root.querySelector('#admin-build-ver');
        if (shaInput) shaInput.value = sha;
        if (verInput) verInput.value = ver;
        this.toast(`Manifest ${ver} geladen.`, 'good');
      } catch {
        this.toast('updates/manifest.json konnte nicht gelesen werden.', 'bad');
      }
    });

    this.root.querySelector('#admin-build-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const tok = this.getToken();
      if (!tok) return;
      const exeSha256 = this.root.querySelector('#admin-build-sha')?.value.trim() || '';
      const version = this.root.querySelector('#admin-build-ver')?.value.trim() || '';
      if (!/^[a-fA-F0-9]{64}$/.test(exeSha256)) {
        this.toast('Bitte einen gültigen 64-Zeichen SHA-256 Hash eingeben.', 'bad');
        return;
      }
      try {
        this.cached.build = await this.api.adminRegisterBuild(tok, { exeSha256, version });
        this.renderBuild();
        await this.loadOverview();
        this.toast('Build-Hash freigegeben.', 'good');
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });

    this.root.querySelector('#admin-build-clear-btn')?.addEventListener('click', async () => {
      const ok = await this.confirm({
        title: 'Alle Build-Hashes leeren?',
        body: 'Danach ist kein Spiel-Build mehr auf der Allowlist hinterlegt.',
        confirmLabel: 'Allowlist leeren',
        danger: true,
      });
      if (!ok) return;
      try {
        this.cached.build = await this.api.adminRegisterBuild(this.getToken(), { clear: true });
        this.renderBuild();
        await this.loadOverview();
        this.toast('Allowlist geleert.', 'good');
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });

    this.root.querySelector('#admin-event-filter')?.addEventListener('change', (e) => {
      this.filters.eventKind = e.target.value;
      this.renderEvents();
    });

    // Website & Map CMS Tab
    this.root.querySelector('#admin-diag-run-btn')?.addEventListener('click', () => this.runDiagnostics());

    this.root.querySelector('#admin-site-banner-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      this.siteConfig.banner_enabled = !!this.root.querySelector('#admin-banner-enabled')?.checked;
      this.siteConfig.banner_text = this.root.querySelector('#admin-banner-text')?.value.trim() || '';
      this.siteConfig.banner_tone = this.root.querySelector('#admin-banner-tone')?.value || 'teal';
      await this.persistSiteConfig('Website-Banner gespeichert.');
    });

    this.root.querySelector('#admin-pin-pick-btn')?.addEventListener('click', () => {
      this.onPickMapCoord((coords) => {
        const xEl = this.root.querySelector('#admin-pin-x');
        const yEl = this.root.querySelector('#admin-pin-y');
        if (xEl) xEl.value = String(coords[0]);
        if (yEl) yEl.value = String(coords[1]);
        this.toast(`Karten-Kachel (${coords[0]}, ${coords[1]}) übernommen.`, 'good');
      });
    });

    this.root.querySelector('#admin-pin-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const title = this.root.querySelector('#admin-pin-title')?.value.trim() || '';
      const note = this.root.querySelector('#admin-pin-note')?.value.trim() || '';
      const x = Number(this.root.querySelector('#admin-pin-x')?.value || 550);
      const y = Number(this.root.querySelector('#admin-pin-y')?.value || 550);
      if (!title) return;
      this.siteConfig.pins = [
        { id: `evt_${Date.now()}`, title, note, tile: [x, y], kind: 'event' },
        ...(this.siteConfig.pins || []),
      ];
      e.target.reset();
      await this.persistSiteConfig('Server-Marker auf der Weltkarte veröffentlicht.');
    });

    this.root.querySelector('#admin-cms-export-btn')?.addEventListener('click', () => {
      downloadText('shadowspore-site-config.json', JSON.stringify(this.siteConfig, null, 2));
    });
  }

  syncPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = 0;
    }
    const pageVisible = !this.root.closest('[data-page]')?.hidden;
    if (this.autoRefresh && this.isAdmin() && pageVisible) {
      this.pollTimer = setInterval(() => {
        if (!document.hidden && this.activeTab === 'worlds') {
          this.loadWorlds();
          this.loadOverview();
        }
      }, 4000);
    }
  }

  async syncAccessState() {
    const gate = this.root.querySelector('#admin-gate');
    const desk = this.root.querySelector('#admin-desk');
    const gateMsg = this.root.querySelector('#admin-gate-msg');
    if (!this.getToken()) {
      if (gate) gate.hidden = false;
      if (desk) desk.hidden = true;
      if (gateMsg) gateMsg.textContent = 'Bitte melde dich mit einem Admin-Konto an, um Server, Spieler, Lizenzkeys und Weltkarten-Events live zu steuern.';
      this.syncPolling();
      return false;
    }
    if (!this.isAdmin()) {
      const role = this.getProfile()?.role || 'player';
      if (gate) gate.hidden = false;
      if (desk) desk.hidden = true;
      if (gateMsg) gateMsg.textContent = `Dein aktuelles Konto besitzt die Rolle „${role}“. Nur Konten mit der Server-Rolle „admin“ dürfen administrative RPCs ausführen.`;
      this.syncPolling();
      return false;
    }
    if (gate) gate.hidden = true;
    if (desk) desk.hidden = false;
    this.syncPolling();
    return true;
  }

  async refreshAll() {
    if (!(await this.syncAccessState())) return;
    await Promise.allSettled([
      this.loadOverview(),
      this.refreshActiveTab(),
      this.loadSiteConfig(),
    ]);
  }

  async refreshActiveTab() {
    if (!this.isAdmin()) return;
    if (this.activeTab === 'worlds') return this.loadWorlds();
    if (this.activeTab === 'players') return this.loadAccounts();
    if (this.activeTab === 'keys') return this.loadKeys();
    if (this.activeTab === 'build') return Promise.all([this.loadBuild(), this.loadEvents()]);
    if (this.activeTab === 'site') {
      await this.loadSiteConfig();
      return this.runDiagnostics();
    }
  }

  async loadOverview() {
    try {
      const ov = await this.api.adminOverview(this.getToken());
      this.cached.overview = ov;
      const set = (id, v) => {
        const n = this.root.querySelector(id);
        if (n) n.textContent = String(v);
      };
      set('#kpi-accounts', ov.total_accounts ?? 0);
      set('#kpi-online', ov.online_accounts ?? 0);
      set('#kpi-worlds', ov.active_worlds ?? 0);
      set('#kpi-keys-free', ov.unused_keys ?? 0);
      set('#kpi-keys-used', `${ov.claimed_keys ?? 0} aktiv · ${ov.revoked_keys ?? 0} widerrufen`);
      set('#kpi-build', ov.build_enforce ? `Strikt (${ov.build_hash_count ?? 0})` : `Offen (${ov.build_hash_count ?? 0})`);
      set('#kpi-events', ov.security_events ?? 0);
    } catch (err) {
      this.toast(err.message, 'bad');
    }
  }

  async loadWorlds() {
    const list = this.root.querySelector('#admin-worlds-list');
    if (!list) return;
    try {
      const res = await this.api.adminListWorlds(this.getToken());
      const worlds = Array.isArray(res.worlds) ? res.worlds : [];
      this.cached.worlds = worlds;
      list.replaceChildren();

      if (!worlds.length) {
        list.append(el('p', 'empty-note', 'Aktuell sind keine aktiven Mehrspieler-Welten auf s.shadowspore.com geöffnet.'));
        return;
      }

      for (const w of worlds) {
        const card = el('article', 'world-card stair');
        const head = el('div', 'world-card-head');
        const titleWrap = el('div');
        titleWrap.append(el('strong', '', `${w.host_name || 'Host'} (${w.host_uid || '—'})`));
        titleWrap.append(el('div', 'mono-sub', `Match: ${w.match_id || '—'} · Alter: ${formatAge(w.age_seconds)}`));
        const badges = el('div', 'row-badges');
        badges.append(el('span', 'tag tag-teal', `${w.player_count || 1}/${w.max_players || 4} Spieler`));
        const codeBtn = el('button', 'btn btn-ghost btn-xs', w.room_code || 'Kein Code');
        codeBtn.type = 'button';
        codeBtn.addEventListener('click', () => {
          navigator.clipboard?.writeText(w.room_code || w.match_id).catch(() => {});
          this.toast('Raumcode kopiert.', 'good');
        });
        badges.append(codeBtn);
        head.append(titleWrap, badges);
        card.append(head);

        // Peer list
        const peers = Array.isArray(w.peers) ? w.peers : [];
        if (peers.length) {
          const ul = el('ul', 'peer-list');
          for (const peer of peers) {
            const li = el('li', 'peer-row');
            const who = el('span', '', `${peer.display_name || peer.uid} · UID ${peer.uid || '—'}${peer.is_host ? ' (Host)' : ''}`);
            li.append(who);
            if (!peer.is_host) {
              const kickWrap = el('div', 'inline-controls');
              const cdSel = el('select', 'compact-select');
              cdSel.setAttribute('aria-label', 'Kick-Cooldown');
              for (const [sec, label] of [[60, '1 Min'], [300, '5 Min'], [1800, '30 Min'], [86400, '24 Std']]) {
                const opt = el('option', '', label);
                opt.value = String(sec);
                cdSel.append(opt);
              }
              const kickBtn = el('button', 'btn btn-danger btn-xs', 'Kick');
              kickBtn.type = 'button';
              kickBtn.addEventListener('click', async () => {
                await this.api.adminKickPeer(this.getToken(), {
                  matchId: w.match_id,
                  targetUserId: peer.user_id,
                  targetUid: peer.uid,
                  cooldown: Number(cdSel.value),
                });
                this.toast(`${peer.display_name || peer.uid} entfernt.`, 'good');
                this.loadWorlds();
              });
              kickWrap.append(cdSel, kickBtn);
              li.append(kickWrap);
            }
            ul.append(li);
          }
          card.append(ul);
        }

        const foot = el('div', 'world-card-foot');
        const joinBtn = el('button', 'btn btn-teal btn-xs', 'Force-Join Ticket');
        joinBtn.type = 'button';
        joinBtn.addEventListener('click', async () => {
          try {
            const res = await this.api.adminForceJoin(this.getToken(), { matchId: w.match_id, hostUserId: w.host_user_id });
            this.renderForceResult(this.root.querySelector('#admin-force-result'), res);
            this.toast('Force-Join Ticket erstellt.', 'good');
          } catch (err) {
            this.toast(err.message, 'bad');
          }
        });
        const closeBtn = el('button', 'btn btn-danger btn-xs', 'Welt schließen');
        closeBtn.type = 'button';
        closeBtn.addEventListener('click', async () => {
          const ok = await this.confirm({
            title: `Welt „${w.host_name || w.room_code}“ beenden?`,
            body: 'Alle verbundenen Spieler werden sofort getrennt und aus dem Match entfernt.',
            confirmLabel: 'Welt schließen',
            danger: true,
          });
          if (!ok) return;
          try {
            await this.api.adminCloseWorld(this.getToken(), { matchId: w.match_id, hostUserId: w.host_user_id });
            this.toast('Welt geschlossen.', 'good');
            this.loadWorlds();
            this.loadOverview();
          } catch (err) {
            this.toast(err.message, 'bad');
          }
        });
        foot.append(joinBtn, closeBtn);
        card.append(foot);
        list.append(card);
      }
    } catch (err) {
      list.replaceChildren(el('p', 'empty-note', err.message));
    }
  }

  renderForceResult(box, data, isRoomCheck = false) {
    if (!box) return;
    box.replaceChildren();
    const card = el('div', 'force-ticket stair');
    card.append(el('strong', '', isRoomCheck ? 'Aktiver Koop-Raum gefunden' : 'Admin Force-Join Ticket aktiv'));
    card.append(el('p', 'mono-sub', `Host: ${data.host_name || '—'} · Match: ${data.match_id || '—'} · Raum: ${data.room_code || '—'} (${data.player_count || '?'}/4)`));
    if (data.launch_token) {
      const cp = el('button', 'btn btn-ghost btn-xs', 'Ticket & Match-ID kopieren');
      cp.type = 'button';
      cp.addEventListener('click', () => {
        navigator.clipboard?.writeText(JSON.stringify({ match_id: data.match_id, room_code: data.room_code, launch_token: data.launch_token })).catch(() => {});
        this.toast('Ticket-Daten kopiert.', 'good');
      });
      card.append(cp);
    }
    box.append(card);
  }

  renderForceError(box, msg) {
    if (!box) return;
    box.replaceChildren(el('p', 'form-status is-error', msg));
  }

  async loadAccounts() {
    const tbody = this.root.querySelector('#admin-accounts-tbody');
    if (!tbody) return;
    try {
      const res = await this.api.adminListAccounts(this.getToken(), {
        query: this.filters.accQuery,
        role: this.filters.accRole,
        status: this.filters.accStatus,
        limit: 100,
      });
      const accounts = Array.isArray(res.accounts) ? res.accounts : [];
      this.cached.accounts = accounts;
      tbody.replaceChildren();

      if (!accounts.length) {
        const tr = el('tr');
        const td = el('td', '', 'Keine Konten für diesen Filter gefunden.');
        td.colSpan = 6;
        tr.append(td);
        tbody.append(tr);
        return;
      }

      for (const acc of accounts) {
        const tr = el('tr');
        if (this.selectedAccount?.user_id === acc.user_id) tr.classList.add('is-selected');
        const th = el('th', '', `${acc.display_name || acc.username} (#${acc.uid || '—'})`);
        th.scope = 'row';
        tr.append(th);
        tr.append(el('td', '', acc.username || '—'));
        tr.append(el('td', '', String(acc.role || 'player').toUpperCase()));
        tr.append(el('td', '', acc.license_active ? `Aktiv (${acc.license_edition || 'std'})` : 'Ohne Key'));
        tr.append(el('td', '', acc.banned ? 'GESPERRT' : (acc.online ? 'Online' : 'Offline')));

        const tdAct = el('td');
        const btn = el('button', 'btn btn-ghost btn-xs', 'Steuern');
        btn.type = 'button';
        btn.addEventListener('click', () => this.selectAccount(acc));
        tdAct.append(btn);
        tr.append(tdAct);
        tbody.append(tr);
      }
    } catch (err) {
      this.toast(err.message, 'bad');
    }
  }

  selectAccount(acc) {
    this.selectedAccount = acc;
    const panel = this.root.querySelector('#admin-acc-inspector');
    if (!panel || !acc) return;
    panel.replaceChildren();

    const header = el('div', 'inspector-head');
    header.append(el('h4', '', `${acc.display_name || acc.username} · UID ${acc.uid || '—'}`));
    header.append(el('span', 'mono-sub', acc.user_id || ''));
    panel.append(header);

    const grid = el('div', 'inspector-grid');

    // Role control
    const roleBox = el('div', 'inspector-group');
    roleBox.append(el('label', '', 'Rolle ändern'));
    const roleRow = el('div', 'inline-controls');
    const roleSel = el('select', 'compact-select');
    for (const r of ['player', 'tester', 'moderator', 'admin']) {
      const o = el('option', '', r);
      o.value = r;
      if (r === acc.role) o.selected = true;
      roleSel.append(o);
    }
    const roleBtn = el('button', 'btn btn-teal btn-xs', 'Rolle speichern');
    roleBtn.type = 'button';
    roleBtn.addEventListener('click', async () => {
      try {
        await this.api.adminSetRole(this.getToken(), { target: acc.uid || acc.user_id, role: roleSel.value });
        this.toast(`Rolle auf „${roleSel.value}“ gesetzt.`, 'good');
        await Promise.all([this.loadAccounts(), this.loadEvents()]);
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });
    roleRow.append(roleSel, roleBtn);
    roleBox.append(roleRow);
    grid.append(roleBox);

    // License control
    const licBox = el('div', 'inspector-group');
    licBox.append(el('label', '', 'Lizenz manuell setzen'));
    const licRow = el('div', 'inline-controls');
    const edSel = el('select', 'compact-select');
    for (const ed of ['standard', 'supporter', 'founder', 'beta']) {
      const o = el('option', '', ed);
      o.value = ed;
      if (ed === acc.license_edition) o.selected = true;
      edSel.append(o);
    }
    const toggleLicBtn = el('button', acc.license_active ? 'btn btn-ghost btn-xs' : 'btn btn-gold btn-xs', acc.license_active ? 'Entziehen' : 'Freischalten');
    toggleLicBtn.type = 'button';
    toggleLicBtn.addEventListener('click', async () => {
      try {
        await this.api.adminSetLicense(this.getToken(), {
          target: acc.uid || acc.user_id,
          active: !acc.license_active,
          edition: edSel.value,
        });
        this.toast(acc.license_active ? 'Lizenz entzogen.' : 'Lizenz freigeschaltet.', 'good');
        acc.license_active = !acc.license_active;
        this.selectAccount(acc);
        this.loadAccounts();
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });
    licRow.append(edSel, toggleLicBtn);
    licBox.append(licRow);
    grid.append(licBox);

    // Ban control
    const banBox = el('div', 'inspector-group');
    banBox.append(el('label', '', 'Kontosperre'));
    const banRow = el('div', 'inline-controls');
    const reasonIn = el('input', 'compact-input');
    reasonIn.type = 'text';
    reasonIn.placeholder = 'Grund für Sperre…';
    reasonIn.value = acc.ban_reason || '';
    const banBtn = el('button', acc.banned ? 'btn btn-teal btn-xs' : 'btn btn-danger btn-xs', acc.banned ? 'Entsperren' : 'Konto sperren');
    banBtn.type = 'button';
    banBtn.addEventListener('click', async () => {
      const nextBan = !acc.banned;
      if (nextBan) {
        const ok = await this.confirm({
          title: `Konto ${acc.username} (#${acc.uid}) sperren?`,
          body: `Der Spieler wird sofort getrennt und verliert jeden Zugang. Grund: ${reasonIn.value || 'Regelverstoß'}`,
          confirmLabel: 'Jetzt sperren',
          danger: true,
        });
        if (!ok) return;
      }
      try {
        await this.api.adminSetBan(this.getToken(), {
          target: acc.uid || acc.user_id,
          banned: nextBan,
          reason: reasonIn.value,
        });
        acc.banned = nextBan;
        acc.ban_reason = reasonIn.value;
        this.toast(nextBan ? 'Konto gesperrt.' : 'Sperre aufgehoben.', 'good');
        this.selectAccount(acc);
        await Promise.all([this.loadAccounts(), this.loadOverview(), this.loadEvents()]);
      } catch (err) {
        this.toast(err.message, 'bad');
      }
    });
    banRow.append(reasonIn, banBtn);
    banBox.append(banRow);
    grid.append(banBox);

    panel.append(grid);
  }

  renderIssuedBatch() {
    const wrap = this.root.querySelector('#admin-issued-wrap');
    const pre = this.root.querySelector('#admin-issued-list');
    if (!wrap || !pre) return;
    wrap.hidden = !this.issuedBatch.length;
    pre.textContent = this.issuedBatch.join('\n');
  }

  async loadKeys() {
    const tbody = this.root.querySelector('#admin-keys-tbody');
    if (!tbody) return;
    try {
      const res = await this.api.adminListKeys(this.getToken(), {
        status: this.filters.keyStatus,
        query: this.filters.keyQuery,
      });
      const keys = Array.isArray(res.keys) ? res.keys : [];
      this.cached.keys = keys;
      tbody.replaceChildren();

      if (!keys.length) {
        const tr = el('tr');
        const td = el('td', '', 'Keine Lizenzkeys gefunden.');
        td.colSpan = 6;
        tr.append(td);
        tbody.append(tr);
        return;
      }

      for (const k of keys) {
        const tr = el('tr');
        const th = el('th', 'mono-cell', k.key);
        th.scope = 'row';
        tr.append(th);
        tr.append(el('td', '', k.status || 'unused'));
        tr.append(el('td', '', `${k.edition || 'std'} · ${k.role_grant || 'player'}`));
        tr.append(el('td', '', k.claimed_uid || '—'));
        tr.append(el('td', '', k.note || '—'));

        const tdAct = el('td', 'inline-controls');
        const copyBtn = el('button', 'btn btn-ghost btn-xs', 'Kopieren');
        copyBtn.type = 'button';
        copyBtn.addEventListener('click', () => {
          navigator.clipboard?.writeText(k.key).catch(() => {});
          this.toast('Key kopiert.', 'good');
        });
        const nextStatus = k.status === 'revoked' ? 'unused' : 'revoked';
        const toggleBtn = el('button', k.status === 'revoked' ? 'btn btn-teal btn-xs' : 'btn btn-danger btn-xs', k.status === 'revoked' ? 'Reaktivieren' : 'Widerrufen');
        toggleBtn.type = 'button';
        toggleBtn.addEventListener('click', async () => {
          try {
            await this.api.adminSetLicense(this.getToken(), { licenseKey: k.key, keyStatus: nextStatus });
            this.toast(`Key-Status -> ${nextStatus}.`, 'good');
            await Promise.all([this.loadKeys(), this.loadOverview()]);
          } catch (err) {
            this.toast(err.message, 'bad');
          }
        });
        tdAct.append(copyBtn, toggleBtn);
        tr.append(tdAct);
        tbody.append(tr);
      }
    } catch (err) {
      this.toast(err.message, 'bad');
    }
  }

  async loadBuild() {
    try {
      this.cached.build = await this.api.adminGetBuildConfig(this.getToken());
      this.renderBuild();
    } catch (err) {
      this.toast(err.message, 'bad');
    }
  }

  renderBuild() {
    const enforceBtn = this.root.querySelector('#admin-build-enforce-btn');
    const enforceBadge = this.root.querySelector('#admin-build-enforce-badge');
    const list = this.root.querySelector('#admin-build-hashes');
    const enforce = !!this.cached.build?.enforce;
    if (enforceBtn) {
      enforceBtn.textContent = enforce ? 'Strict-Mode deaktivieren' : 'Strict-Mode aktivieren';
    }
    if (enforceBadge) {
      enforceBadge.textContent = enforce ? 'STRIKT AKTIV' : 'OFFEN (Jeder Build)';
      enforceBadge.className = enforce ? 'tag tag-new' : 'tag tag-warn';
    }
    if (!list) return;
    const hashes = Array.isArray(this.cached.build?.hash_list) ? this.cached.build.hash_list : [];
    list.replaceChildren();
    if (!hashes.length) {
      list.append(el('p', 'empty-note', 'Keine SHA-256 Builds eingetragen.'));
      return;
    }
    for (const item of hashes) {
      const row = el('div', 'hash-entry stair');
      const left = el('div');
      left.append(el('strong', '', item.version || 'Build'));
      left.append(el('div', 'mono-sub', item.sha256));
      const rmBtn = el('button', 'btn btn-danger btn-xs', 'Entfernen');
      rmBtn.type = 'button';
      rmBtn.addEventListener('click', async () => {
        try {
          this.cached.build = await this.api.adminRegisterBuild(this.getToken(), { removeSha256: item.sha256 });
          this.renderBuild();
          this.toast('Hash entfernt.', 'good');
        } catch (err) {
          this.toast(err.message, 'bad');
        }
      });
      row.append(left, rmBtn);
      list.append(row);
    }
  }

  async loadEvents() {
    try {
      const res = await this.api.adminListSecurityEvents(this.getToken());
      this.cached.events = Array.isArray(res.events) ? res.events : [];
      this.renderEvents();
    } catch (err) {
      this.toast(err.message, 'bad');
    }
  }

  renderEvents() {
    const tbody = this.root.querySelector('#admin-events-tbody');
    if (!tbody) return;
    const filter = this.filters.eventKind;
    const rows = (this.cached.events || []).filter((ev) => !filter || String(ev.kind || '').includes(filter));
    tbody.replaceChildren();
    if (!rows.length) {
      const tr = el('tr');
      const td = el('td', '', 'Keine Sicherheitsereignisse im gewählten Filter.');
      td.colSpan = 4;
      tr.append(td);
      tbody.append(tr);
      return;
    }
    for (const ev of rows) {
      const tr = el('tr');
      const th = el('th', '', formatTs(ev.ts));
      th.scope = 'row';
      tr.append(th);
      tr.append(el('td', '', ev.kind || 'EVENT'));
      tr.append(el('td', '', ev.uid || ev.user_id || '—'));
      tr.append(el('td', '', ev.details || '—'));
      tbody.append(tr);
    }
  }

  async loadSiteConfig() {
    const tok = this.getToken();
    const uid = this.getProfile()?.user_id;
    if (!tok || !uid) return;
    try {
      const saved = await this.api.adminReadSiteConfig(tok, uid);
      if (saved && typeof saved === 'object') {
        this.siteConfig = {
          banner_enabled: !!saved.banner_enabled,
          banner_text: saved.banner_text || '',
          banner_tone: saved.banner_tone || 'teal',
          pins: Array.isArray(saved.pins) ? saved.pins : [],
        };
      }
      this.renderSiteCms();
      this.onSiteConfigChange(this.siteConfig);
    } catch {
      this.renderSiteCms();
    }
  }

  async persistSiteConfig(msg) {
    try {
      await this.api.adminWriteSiteConfig(this.getToken(), this.siteConfig);
      this.renderSiteCms();
      this.onSiteConfigChange(this.siteConfig);
      this.toast(msg, 'good');
    } catch (err) {
      this.toast(err.message, 'bad');
    }
  }

  renderSiteCms() {
    const enEl = this.root.querySelector('#admin-banner-enabled');
    const txtEl = this.root.querySelector('#admin-banner-text');
    const toneEl = this.root.querySelector('#admin-banner-tone');
    if (enEl) enEl.checked = !!this.siteConfig.banner_enabled;
    if (txtEl) txtEl.value = this.siteConfig.banner_text || '';
    if (toneEl) toneEl.value = this.siteConfig.banner_tone || 'teal';

    const list = this.root.querySelector('#admin-cms-pins-list');
    if (!list) return;
    list.replaceChildren();
    const pins = this.siteConfig.pins || [];
    if (!pins.length) {
      list.append(el('p', 'empty-note', 'Keine offiziellen Server-Pins gesetzt.'));
      return;
    }
    for (const pin of pins) {
      const row = el('div', 'hash-entry stair');
      const left = el('div');
      left.append(el('strong', '', `${pin.title} · (${pin.tile?.[0] ?? 550}, ${pin.tile?.[1] ?? 550})`));
      left.append(el('div', 'mono-sub', pin.note || ''));
      const del = el('button', 'btn btn-danger btn-xs', 'Entfernen');
      del.type = 'button';
      del.addEventListener('click', () => {
        this.siteConfig.pins = this.siteConfig.pins.filter((p) => p.id !== pin.id);
        this.persistSiteConfig('Server-Marker entfernt.');
      });
      row.append(left, del);
      list.append(row);
    }
  }

  async runDiagnostics() {
    const box = this.root.querySelector('#admin-diag-box');
    if (!box) return;
    box.replaceChildren(el('p', 'mono-sub', 'Prüfe Endpunkte…'));

    const [health, manifestRes, installerRes] = await Promise.all([
      this.api.probeServerHealth(),
      fetch('./updates/manifest.json', { cache: 'no-store' }).then((r) => (r.ok ? r.json() : null)).catch(() => null),
      fetch('./downloads/Shadowspore-Launcher-Setup.exe', { method: 'HEAD', cache: 'no-store' }).then((r) => r.ok).catch(() => false),
    ]);

    const hashInDom = document.getElementById('installer-sha256')?.textContent.trim() || '';
    box.replaceChildren();

    const rows = [
      ['Nakama Server (s.shadowspore.com)', health.ok ? `ONLINE (${health.latencyMs} ms)` : 'NICHT ERREICHBAR', health.ok],
      ['Release-Manifest (updates/manifest.json)', manifestRes ? `V${manifestRes.version} · ${Math.round((manifestRes.size_bytes || 0) / 1048576)} MB` : 'FEHLT', !!manifestRes],
      ['Windows Setup EXE (Shadowspore-Launcher-Setup.exe)', installerRes ? `VERFÜGBAR · SHA ${hashInDom.slice(0, 14)}…` : 'NICHT GEFUNDEN', installerRes],
      ['Game Build-Gate Hash in Manifest', manifestRes?.exe_sha256 ? `${manifestRes.exe_sha256.slice(0, 18)}…` : 'KEINER', !!manifestRes?.exe_sha256],
    ];

    for (const [label, val, ok] of rows) {
      const row = el('div', 'diag-row stair');
      row.append(el('span', '', label));
      row.append(el('span', ok ? 'tag tag-new' : 'tag tag-danger', val));
      box.append(row);
    }
  }
}
