// Administration workspace controller: Live worlds & Force Join, players/moderation,
// license keys, and build-gate / security event auditing. All RPCs are verified server-side.

export function createAdminController({
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
  refreshSocial,
  renderSession,
}) {
  const $ = (id) => document.getElementById(id);

  const adminState = {
    activeTab: "worlds",
    loadedTabs: new Set(),
    overview: null,
    worlds: [],
    accounts: [],
    keys: [],
    buildConfig: { enforce: false, hash_list: [] },
    localBuild: null,
    events: [],
    selectedUserId: "",
  };

  function isAdmin() {
    return Boolean(state.session && state.session.logged_in && roleKey(state.session.role) === "admin");
  }

  function pill(text, tone = "") {
    const el = document.createElement("span");
    el.className = "admin-pill" + (tone ? ` admin-pill-${tone}` : "");
    el.textContent = text;
    return el;
  }

  function makeBtn(label, className, handler) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = className;
    btn.textContent = label;
    btn.addEventListener("click", handler);
    return btn;
  }

  function td(label, ...children) {
    const cell = document.createElement("td");
    cell.dataset.label = label;
    cell.append(...children);
    return cell;
  }

  async function copyText(value, feedbackLabel) {
    if (!value) return;
    await navigator.clipboard?.writeText(value).catch(() => {});
    toast(feedbackLabel || `Kopiert: ${value}`);
  }

  // Native <dialog> confirmation helper obeying modern-web-guidance rules.
  const confirmDialog = $("admin-confirm-dialog");
  let pendingResolve = null;

  confirmDialog?.addEventListener("close", () => {
    const confirmed = confirmDialog.returnValue === "confirm";
    confirmDialog.returnValue = "";
    const done = pendingResolve;
    pendingResolve = null;
    if (done) done(confirmed);
  });

  function confirmAdminAction({ title, body, confirmLabel = "Bestätigen", danger = true }) {
    if (!confirmDialog || typeof confirmDialog.showModal !== "function") {
      return Promise.resolve(true);
    }
    $("admin-dialog-title").textContent = title;
    $("admin-dialog-body").textContent = body;
    const okBtn = $("admin-dialog-confirm");
    okBtn.textContent = confirmLabel;
    okBtn.className = `btn btn-sm ${danger ? "btn-danger" : "btn-gold"}`;
    confirmDialog.returnValue = "";
    return new Promise((resolve) => {
      pendingResolve = resolve;
      confirmDialog.showModal();
    });
  }

  // Subtabs: single horizontal row + keyboard ArrowLeft/ArrowRight/Home/End fallback
  const tabsList = document.querySelector(".admin-tabs");
  const tabButtons = tabsList ? [...tabsList.querySelectorAll('[role="tab"]')] : [];

  function activateTab(tabKey, { focusTab = false, refresh = true } = {}) {
    adminState.activeTab = tabKey;
    for (const btn of tabButtons) {
      const selected = btn.dataset.adminTab === tabKey;
      btn.setAttribute("aria-selected", String(selected));
      btn.tabIndex = selected ? 0 : -1;
      const panel = document.querySelector(`[role="tabpanel"][aria-labelledby="${btn.id}"]`);
      if (panel) panel.hidden = !selected;
      if (selected && focusTab) btn.focus();
    }
    if (refresh && isAdmin()) {
      loadTabData(tabKey).catch((err) => setStatus($("admin-global-status"), String(err), true));
    }
  }

  for (const btn of tabButtons) {
    btn.addEventListener("click", () => activateTab(btn.dataset.adminTab));
  }

  tabsList?.addEventListener("keydown", (e) => {
    const current = e.target.closest('[role="tab"]');
    if (!current || !tabButtons.length) return;
    const idx = tabButtons.indexOf(current);
    if (idx < 0) return;
    let next = -1;
    if (e.key === "ArrowRight") next = (idx + 1) % tabButtons.length;
    else if (e.key === "ArrowLeft") next = (idx - 1 + tabButtons.length) % tabButtons.length;
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = tabButtons.length - 1;
    if (next >= 0) {
      e.preventDefault();
      activateTab(tabButtons[next].dataset.adminTab, { focusTab: true });
    }
  });

  // ---------------------------------------------------------------- Overview & Force Join
  function renderOverview() {
    const o = adminState.overview;
    const worldsCount = o ? Number(o.active_worlds || 0) : adminState.worlds.length;
    $("stat-worlds").textContent = String(worldsCount);
    $("tab-worlds-count").textContent = String(worldsCount);
    $("admin-dot").hidden = !isAdmin() || worldsCount === 0;
    if (!o) return;
    $("stat-online").textContent = String(o.online_accounts || 0);
    $("stat-accounts").textContent = String(o.total_accounts || 0);
    $("stat-keys").textContent = String(o.unused_keys || 0);
    const buildNode = $("stat-build");
    buildNode.textContent = o.build_enforce ? `Streng (${o.build_hash_count || 0})` : "Offen";
    buildNode.classList.toggle("is-on", Boolean(o.build_enforce));
  }

  async function loadOverview() {
    adminState.overview = await invoke("admin_overview");
    renderOverview();
  }

  async function executeForceJoin({ query = "", matchId = "", roomCode = "", hostUserId = "" }) {
    if (!isAdmin()) return;
    const statusEl = $("admin-force-status");
    setStatus(statusEl, "Erteile Force-Join-Freigabe…");
    $("admin-force-submit").disabled = true;
    try {
      const res = await invoke("admin_force_join", {
        query: query || null,
        matchId: matchId || null,
        roomCode: roomCode || null,
        hostUserId: hostUserId || null,
      });
      await startGame("launch_join_match", {
        matchId: res.match_id,
        roomCode: res.room_code || null,
        worldName: res.world_name || null,
      });
      setStatus(statusEl, `Verbinde direkt mit „${res.world_name || "Welt"}“ (${res.host_name || res.host_uid || "Host"})…`);
      toast(`Force Join aktiv: ${res.world_name || res.room_code || res.match_id}`);
      $("admin-force-query").value = "";
    } catch (err) {
      setStatus(statusEl, String(err), true);
      toast(String(err), true);
    } finally {
      $("admin-force-submit").disabled = false;
    }
  }

  $("admin-quick-force-form")?.addEventListener("submit", (evt) => {
    evt.preventDefault();
    const query = $("admin-force-query").value.trim();
    if (!query) {
      setStatus($("admin-force-status"), "Bitte UID, Name, Raumcode oder Match-ID eingeben.", true);
      return;
    }
    executeForceJoin({ query });
  });

  // ---------------------------------------------------------------- Tab 1: Live Worlds
  function renderWorlds() {
    const filter = $("admin-worlds-filter").value.trim().toLowerCase();
    const modeFilter = $("admin-worlds-mode").value;
    const grid = $("admin-worlds-grid");
    const empty = $("admin-worlds-empty");
    const filtered = (adminState.worlds || []).filter((w) => {
      if (modeFilter !== "all" && normalizeJoinMode(w.join_mode) !== modeFilter) return false;
      if (!filter) return true;
      const hay = `${w.world_name} ${w.host_name} ${w.host_uid} ${w.room_code} ${w.match_id}`.toLowerCase();
      return hay.includes(filter);
    });

    grid.replaceChildren();
    empty.hidden = filtered.length > 0;

    for (const w of filtered) {
      const card = document.createElement("article");
      card.className = "admin-world-card stair";

      const head = document.createElement("div");
      head.className = "admin-world-head";

      const titleCol = document.createElement("div");
      titleCol.style.minWidth = "0";
      const h4 = document.createElement("h4");
      h4.className = "admin-world-title";
      h4.textContent = w.world_name || "KOOP-WELT";
      const hostMeta = document.createElement("div");
      hostMeta.className = "admin-world-host";
      hostMeta.textContent = `Host: ${w.host_name || "Spieler"}${w.host_uid ? ` · #${w.host_uid}` : ""}`;
      titleCol.append(h4, hostMeta);

      const badges = document.createElement("div");
      badges.className = "admin-world-badges";
      const mode = normalizeJoinMode(w.join_mode);
      const modeTone = mode === "private" ? "err" : mode === "open" ? "gold" : "ok";
      badges.append(pill(JOIN_LABEL[mode] || mode, modeTone));
      const full = Number(w.player_count || 1) >= Number(w.max_players || 4);
      badges.append(pill(`${w.player_count || 1} / ${w.max_players || 4}`, full ? "warn" : ""));
      if (w.room_code) {
        const codeBtn = makeBtn(w.room_code, "admin-code-chip", () =>
          copyText(w.room_code, `Raumcode ${w.room_code} kopiert.`),
        );
        codeBtn.title = "Raumcode kopieren";
        badges.append(codeBtn);
      }
      head.append(titleCol, badges);
      card.append(head);

      const peersBox = document.createElement("div");
      peersBox.className = "admin-peers-list";
      const peers = Array.isArray(w.peers) && w.peers.length ? w.peers : [];
      if (!peers.length) {
        const emptyPeer = document.createElement("div");
        emptyPeer.className = "admin-peer-row";
        emptyPeer.textContent = "Warte auf Host-Presence…";
        peersBox.append(emptyPeer);
      } else {
        for (const p of peers) {
          const row = document.createElement("div");
          row.className = "admin-peer-row";
          const name = document.createElement("span");
          name.className = "admin-peer-name";
          const isHost = p.user_id === w.host_user_id || Number(p.peer_id) === 1;
          name.textContent = `${p.display_name || p.username || "Spieler"}${p.uid ? ` (#${p.uid})` : ""}`;

          const right = document.createElement("div");
          right.className = "admin-cell-actions";
          if (isHost) {
            right.append(pill("Host", "gold"));
          } else {
            const pRole = roleKey(p.role);
            if (pRole !== "player") right.append(pill(ROLE_LABEL[pRole] || pRole, "ok"));
            right.append(
              makeBtn("Kick", "btn btn-danger btn-sm", async () => {
                const ok = await confirmAdminAction({
                  title: "Spieler aus Sitzung kicken?",
                  body: `${p.display_name || p.username} (#${p.uid || "?"}) wird sofort aus „${w.world_name}“ entfernt und für 60 Sekunden gesperrt.`,
                  confirmLabel: "Kicken",
                });
                if (!ok) return;
                await runAdminTask("Entferne Spieler…", async () => {
                  await invoke("admin_kick_match_peer", {
                    matchId: w.match_id,
                    targetUserId: p.user_id || p.uid,
                    cooldown: 60,
                  });
                  toast(`${p.display_name || p.username} gekickt.`);
                  await loadWorlds();
                });
              }),
            );
          }
          row.append(name, right);
          peersBox.append(row);
        }
      }
      card.append(peersBox);

      const actions = document.createElement("div");
      actions.className = "admin-world-actions";
      const isSelfHost = w.host_user_id && w.host_user_id === state.session?.user_id;
      const forceBtn = makeBtn(
        isSelfHost ? "Deine Welt" : "Force Join",
        "btn btn-gold btn-sm",
        () => executeForceJoin({ matchId: w.match_id, roomCode: w.room_code, hostUserId: w.host_user_id }),
      );
      if (isSelfHost) forceBtn.disabled = true;

      const copyMidBtn = makeBtn("Match-ID", "btn btn-ghost btn-sm", () =>
        copyText(w.match_id, "Match-ID kopiert."),
      );
      const closeBtn = makeBtn("Welt schließen", "btn btn-danger btn-sm", async () => {
        const ok = await confirmAdminAction({
          title: "Koop-Welt schließen?",
          body: `Alle verbundenen Spieler in „${w.world_name || w.room_code}“ (Host: ${w.host_name || w.host_uid}) werden sofort getrennt.`,
          confirmLabel: "Welt schließen",
        });
        if (!ok) return;
        await runAdminTask("Schließe Welt…", async () => {
          await invoke("admin_close_world", { matchId: w.match_id, hostUserId: w.host_user_id });
          toast("Welt geschlossen.");
          await Promise.all([loadWorlds(), loadOverview()]);
        });
      });
      actions.append(forceBtn, copyMidBtn, closeBtn);
      card.append(actions);
      grid.append(card);
    }
  }

  async function loadWorlds() {
    adminState.worlds = await invoke("admin_list_active_worlds");
    renderWorlds();
    renderOverview();
  }

  $("admin-worlds-filter")?.addEventListener("input", renderWorlds);
  $("admin-worlds-mode")?.addEventListener("change", renderWorlds);
  $("admin-worlds-reload-btn")?.addEventListener("click", () =>
    runAdminTask("Lade aktive Welten…", loadWorlds),
  );

  // ---------------------------------------------------------------- Tab 2: Players & Moderation
  function selectModerationAccount(acc) {
    adminState.selectedUserId = acc.user_id || "";
    $("admin-mod-target").value = acc.uid || acc.user_id || acc.username || "";
    $("admin-mod-role").value = roleKey(acc.role);
    renderAccounts();
  }

  function renderAccounts() {
    const tbody = $("admin-players-tbody");
    tbody.replaceChildren();
    const accounts = adminState.accounts || [];
    if (!accounts.length) {
      const tr = document.createElement("tr");
      const emptyCell = document.createElement("td");
      emptyCell.colSpan = 5;
      emptyCell.textContent = "Keine Konten für diesen Filter gefunden.";
      tr.append(emptyCell);
      tbody.append(tr);
      return;
    }

    for (const acc of accounts) {
      const tr = document.createElement("tr");
      if (acc.user_id === adminState.selectedUserId) tr.className = "is-selected";

      // Spieler column
      const playerMain = document.createElement("div");
      playerMain.className = "admin-cell-main";
      const strong = document.createElement("strong");
      strong.textContent = acc.display_name || acc.username || "Spieler";
      const sub = document.createElement("span");
      sub.className = "admin-cell-sub";
      sub.textContent = `@${acc.username || "?"} · #${acc.uid || "------"}${acc.email ? ` · ${acc.email}` : ""}`;
      playerMain.append(strong, sub);

      // Rolle column
      const role = roleKey(acc.role);
      const roleTone = role === "admin" ? "gold" : role === "moderator" || role === "tester" ? "ok" : "";

      // Status / Welt column
      const statusWrap = document.createElement("div");
      statusWrap.className = "admin-cell-actions";
      if (acc.banned) statusWrap.append(pill("Gesperrt", "err"));
      if (acc.coop_active) {
        statusWrap.append(
          pill(`Welt: ${acc.coop_world_name || "Koop"} (${acc.coop_players}/${acc.coop_max_players})`, "gold"),
        );
      } else if (acc.game_online) {
        statusWrap.append(pill("Im Spiel", "ok"));
      } else {
        statusWrap.append(pill("Offline"));
      }

      // Lizenz column
      const licEl = acc.license_active
        ? pill(`Aktiv (${(acc.license_edition || "std").toUpperCase()})`, "ok")
        : pill("Keine Lizenz", "err");

      // Actions column
      const actWrap = document.createElement("div");
      actWrap.className = "admin-cell-actions";
      actWrap.append(
        makeBtn("Auswählen", "btn btn-ghost btn-sm", () => selectModerationAccount(acc)),
      );
      if (acc.coop_active && acc.user_id !== state.session?.user_id) {
        actWrap.append(
          makeBtn("Force Join", "btn btn-gold btn-sm", () =>
            executeForceJoin({
              matchId: acc.coop_match_id,
              roomCode: acc.coop_room_code,
              hostUserId: acc.user_id,
            }),
          ),
        );
      }
      if (acc.user_id !== state.session?.user_id) {
        actWrap.append(
          makeBtn(acc.banned ? "Entbannen" : "Bannen", `btn btn-sm ${acc.banned ? "btn-ghost" : "btn-danger"}`, async () => {
            const targetBanned = !acc.banned;
            if (targetBanned) {
              const ok = await confirmAdminAction({
                title: `Konto „${acc.username || acc.uid}“ sperren?`,
                body: `Das Konto wird sofort abgemeldet, laufende Lobbys werden geschlossen und der Login gesperrt.`,
                confirmLabel: "Jetzt bannen",
              });
              if (!ok) return;
            }
            const reason = $("admin-mod-reason").value.trim();
            await runAdminTask(targetBanned ? "Sperre Konto…" : "Entsperre Konto…", async () => {
              await invoke("admin_set_ban", { target: acc.user_id, banned: targetBanned, reason });
              toast(targetBanned ? `${acc.username} gebannt.` : `${acc.username} entsperrt.`);
              await Promise.all([loadAccounts(), loadOverview()]);
            });
          }),
        );
      }

      tr.append(
        td("Spieler", playerMain),
        td("Rolle", pill(ROLE_LABEL[role] || role, roleTone)),
        td("Status / Welt", statusWrap),
        td("Lizenz", licEl),
        td("Aktionen", actWrap),
      );
      tbody.append(tr);
    }
  }

  async function loadAccounts() {
    adminState.accounts = await invoke("admin_list_accounts", {
      query: $("admin-players-query").value.trim() || null,
      role: $("admin-players-role-filter").value || "all",
      status: $("admin-players-status-filter").value || "all",
    });
    renderAccounts();
  }

  $("admin-players-search-form")?.addEventListener("submit", (evt) => {
    evt.preventDefault();
    runAdminTask("Suche Konten…", loadAccounts);
  });
  $("admin-players-role-filter")?.addEventListener("change", () =>
    runAdminTask("Filtere Konten…", loadAccounts),
  );
  $("admin-players-status-filter")?.addEventListener("change", () =>
    runAdminTask("Filtere Konten…", loadAccounts),
  );

  $("admin-mod-role-btn")?.addEventListener("click", async () => {
    const target = $("admin-mod-target").value.trim();
    const role = $("admin-mod-role").value;
    if (!target) return setStatus($("admin-global-status"), "Bitte Ziel-UID oder Namen angeben.", true);
    await runAdminTask("Aktualisiere Rolle…", async () => {
      state.session = await invoke("admin_set_role", { target, role });
      renderSession();
      toast(`Rolle von ${target} ist jetzt ${ROLE_LABEL[roleKey(role)]}.`);
      await Promise.all([loadAccounts(), refreshSocial()]);
    });
  });

  async function runStripMod(kind, flag) {
    const target = $("admin-mod-target").value.trim();
    const reason = $("admin-mod-reason").value.trim();
    if (!target) return setStatus($("admin-global-status"), "Bitte Ziel-UID, Name oder Key eingeben.", true);
    if (kind === "ban" && flag) {
      const ok = await confirmAdminAction({
        title: `„${target}“ permanent bannen?`,
        body: reason ? `Grund: ${reason}` : "Das Konto wird sofort vom Spiel und Launcher ausgeschlossen.",
        confirmLabel: "Bannen",
      });
      if (!ok) return;
    }
    if (kind === "license" && !flag) {
      const ok = await confirmAdminAction({
        title: `Lizenz für „${target}“ sperren?`,
        body: "Betroffene Konten verlieren sofort den Spielzugang.",
        confirmLabel: "Sperren",
      });
      if (!ok) return;
    }
    await runAdminTask("Führe Aktion aus…", async () => {
      if (kind === "ban") {
        await invoke("admin_set_ban", { target, banned: flag, reason });
        toast(flag ? `${target} gebannt.` : `${target} entsperrt.`);
      } else {
        await invoke("admin_set_license", { target, active: flag });
        toast(flag ? `Lizenz für ${target} aktiviert.` : `Lizenz für ${target} gesperrt.`);
      }
      await Promise.all([loadAccounts(), loadOverview()]);
    });
  }

  $("admin-mod-lic-on-btn")?.addEventListener("click", () => runStripMod("license", true));
  $("admin-mod-lic-off-btn")?.addEventListener("click", () => runStripMod("license", false));
  $("admin-mod-unban-btn")?.addEventListener("click", () => runStripMod("ban", false));
  $("admin-mod-ban-btn")?.addEventListener("click", () => runStripMod("ban", true));

  // ---------------------------------------------------------------- Tab 3: License Keys
  function renderKeys() {
    const tbody = $("admin-keys-tbody");
    tbody.replaceChildren();
    const keys = adminState.keys || [];
    if (!keys.length) {
      const tr = document.createElement("tr");
      const emptyCell = document.createElement("td");
      emptyCell.colSpan = 7;
      emptyCell.textContent = "Keine Lizenzkeys gefunden.";
      tr.append(emptyCell);
      tbody.append(tr);
      return;
    }

    for (const k of keys) {
      const tr = document.createElement("tr");
      const code = document.createElement("code");
      code.className = "admin-code-copy";
      code.textContent = k.key;
      code.title = "Klicken zum Kopieren";
      code.addEventListener("click", () => copyText(k.key, `Key kopiert: ${k.key}`));

      const stTone = k.status === "unused" ? "ok" : k.status === "claimed" ? "gold" : "err";
      const stLabel = k.status === "unused" ? "Unbenutzt" : k.status === "claimed" ? "Eingelöst" : "Widerrufen";

      const edRole = document.createElement("span");
      edRole.textContent = `${(k.edition || "standard").toUpperCase()} · ${ROLE_LABEL[roleKey(k.role_grant)] || k.role_grant}`;

      const noteEl = document.createElement("span");
      noteEl.textContent = k.note || "—";

      const claimer = document.createElement("span");
      claimer.textContent = k.claimed_by_uid
        ? `#${k.claimed_by_uid}${k.claimed_by_name ? ` (${k.claimed_by_name})` : ""}`
        : k.claimed_by || "—";

      const created = document.createElement("span");
      created.textContent = k.created_at ? formatUnix(k.created_at) : "—";

      const actWrap = document.createElement("div");
      actWrap.className = "admin-cell-actions";
      if (k.status !== "revoked") {
        actWrap.append(
          makeBtn("Widerrufen", "btn btn-danger btn-sm", async () => {
            const ok = await confirmAdminAction({
              title: "Lizenzkey widerrufen?",
              body: `Key ${k.key}${k.claimed_by_uid ? ` (bereits eingelöst von #${k.claimed_by_uid})` : ""} wird widerrufen.`,
              confirmLabel: "Widerrufen",
            });
            if (!ok) return;
            await runAdminTask("Widerrufe Key…", async () => {
              await invoke("admin_set_license", { target: k.key, active: false });
              toast(`Key ${k.key} widerrufen.`);
              await Promise.all([loadKeys(), loadOverview()]);
            });
          }),
        );
      } else {
        actWrap.append(pill("Widerrufen", "err"));
      }

      tr.append(
        td("Lizenzkey", code),
        td("Status", pill(stLabel, stTone)),
        td("Edition / Rolle", edRole),
        td("Notiz", noteEl),
        td("Eingelöst von", claimer),
        td("Erstellt", created),
        td("Aktion", actWrap),
      );
      tbody.append(tr);
    }
  }

  async function loadKeys() {
    adminState.keys = await invoke("admin_list_license_keys", {
      status: $("admin-keys-status-filter").value || "all",
      query: $("admin-keys-query").value.trim() || null,
    });
    renderKeys();
  }

  $("admin-keys-issue-form")?.addEventListener("submit", async (evt) => {
    evt.preventDefault();
    const count = Math.max(1, Math.min(50, Number($("admin-key-count").value || 1)));
    const edition = $("admin-key-edition").value;
    const roleGrant = $("admin-key-role").value;
    const expiresDays = Number($("admin-key-expiry").value || 0);
    const note = $("admin-key-note").value.trim();
    $("admin-key-issue-btn").disabled = true;
    await runAdminTask("Erzeuge Lizenzkeys…", async () => {
      const created = await invoke("admin_issue_license_key", {
        count,
        edition,
        roleGrant,
        note,
        expiresDays,
      });
      $("admin-key-note").value = "";
      if (created.length === 1 && created[0]?.key) {
        await copyText(created[0].key, `Key erzeugt & kopiert: ${created[0].key}`);
      } else {
        toast(`${created.length} Lizenzkeys erzeugt.`);
      }
      await Promise.all([loadKeys(), loadOverview()]);
    }).finally(() => {
      $("admin-key-issue-btn").disabled = false;
    });
  });

  $("admin-keys-status-filter")?.addEventListener("change", () =>
    runAdminTask("Lade Keys…", loadKeys),
  );
  $("admin-keys-query")?.addEventListener("input", () => {
    clearTimeout(keysQueryTimer);
    keysQueryTimer = setTimeout(() => loadKeys().catch(() => {}), 260);
  });
  let keysQueryTimer = 0;
  $("admin-keys-reload-btn")?.addEventListener("click", () =>
    runAdminTask("Lade Keys…", loadKeys),
  );

  // ---------------------------------------------------------------- Tab 4: Security & Builds
  function renderSecurityTab() {
    const cfg = adminState.buildConfig || { enforce: false, hash_list: [] };
    $("admin-build-enforce").checked = Boolean(cfg.enforce);
    $("admin-build-enforce-label").textContent = cfg.enforce ? "Aktiv (Strikt)" : "Offen (Dev erlaubt)";

    const lb = adminState.localBuild;
    if (!lb || !lb.found) {
      $("admin-local-build-summary").textContent = lb
        ? `Keine gebaute EXE gefunden (Version: ${lb.version || "dev"})`
        : "Prüfe…";
      $("admin-use-local-build-btn").disabled = true;
    } else {
      $("admin-local-build-summary").textContent =
        `v${lb.version || "?"} · ${lb.sha256.slice(0, 16)}… · ${lb.exe_path}`;
      $("admin-use-local-build-btn").disabled = false;
    }

    const bBody = $("admin-builds-tbody");
    bBody.replaceChildren();
    const hashes = cfg.hash_list || [];
    if (!hashes.length) {
      const tr = document.createElement("tr");
      const c = document.createElement("td");
      c.colSpan = 4;
      c.textContent = "Keine Build-Hashes registriert.";
      tr.append(c);
      bBody.append(tr);
    } else {
      for (const h of hashes) {
        const tr = document.createElement("tr");
        const code = document.createElement("code");
        code.className = "admin-code-copy";
        code.textContent = `${h.sha256.slice(0, 20)}…${h.sha256.slice(-8)}`;
        code.title = h.sha256;
        code.addEventListener("click", () => copyText(h.sha256, "SHA-256 kopiert."));

        const remBtn = makeBtn("Entfernen", "btn btn-danger btn-sm", async () => {
          const ok = await confirmAdminAction({
            title: "Build-Hash entfernen?",
            body: `Builds mit SHA-256 ${h.sha256.slice(0, 16)}… dürfen bei aktivem Build-Gate kein Launch-Ticket mehr erhalten.`,
            confirmLabel: "Entfernen",
          });
          if (!ok) return;
          await runAdminTask("Entferne Build-Hash…", async () => {
            adminState.buildConfig = await invoke("admin_register_build", { removeSha256: h.sha256 });
            renderSecurityTab();
            await loadOverview();
            toast("Build-Hash entfernt.");
          });
        });

        tr.append(
          td("SHA-256", code),
          td("Version", document.createTextNode(h.version || "—")),
          td("Hinzugefügt", document.createTextNode(h.added_at ? formatUnix(h.added_at) : "—")),
          td("Aktion", remBtn),
        );
        bBody.append(tr);
      }
    }

    const sevFilter = $("admin-events-severity").value;
    const eBody = $("admin-events-tbody");
    eBody.replaceChildren();
    const events = (adminState.events || []).filter(
      (ev) => sevFilter === "all" || (ev.severity || "info") === sevFilter,
    );
    if (!events.length) {
      const tr = document.createElement("tr");
      const c = document.createElement("td");
      c.colSpan = 5;
      c.textContent = "Keine Sicherheitsereignisse für diesen Filter.";
      tr.append(c);
      eBody.append(tr);
      return;
    }
    for (const ev of events) {
      const tr = document.createElement("tr");
      const sev = String(ev.severity || "info").toLowerCase();
      const sevTone = sev === "critical" ? "err" : sev === "warn" ? "warn" : "ok";
      const who = ev.uid || ev.username ? `${ev.username || ""}${ev.uid ? ` #${ev.uid}` : ""}` : ev.user_id || "System";
      tr.append(
        td("Zeit", document.createTextNode(ev.at ? formatUnix(ev.at) : "—")),
        td("Level", pill(sev.toUpperCase(), sevTone)),
        td("Ereignis", document.createTextNode(ev.kind || "UNKNOWN")),
        td("Spieler", document.createTextNode(who)),
        td("Detail", document.createTextNode(ev.detail || "—")),
      );
      eBody.append(tr);
    }
  }

  async function loadSecurityAndBuilds() {
    const [buildCfg, events, localBuild] = await Promise.all([
      invoke("admin_get_build_config"),
      invoke("admin_list_security_events"),
      invoke("inspect_local_build").catch(() => null),
    ]);
    adminState.buildConfig = buildCfg;
    adminState.events = events;
    adminState.localBuild = localBuild;
    renderSecurityTab();
  }

  $("admin-build-enforce")?.addEventListener("change", async () => {
    const enforce = $("admin-build-enforce").checked;
    await runAdminTask("Speichere Build-Gate…", async () => {
      adminState.buildConfig = await invoke("admin_register_build", { enforce });
      renderSecurityTab();
      await loadOverview();
      toast(enforce ? "Build-Signaturprüfung aktiviert." : "Build-Signaturprüfung deaktiviert.");
    });
  });

  $("admin-use-local-build-btn")?.addEventListener("click", async () => {
    const lb = adminState.localBuild;
    if (!lb || !lb.found || !lb.sha256) return;
    $("admin-build-sha").value = lb.sha256;
    $("admin-build-ver").value = lb.version || "";
    await runAdminTask("Registriere lokalen Build…", async () => {
      adminState.buildConfig = await invoke("admin_register_build", {
        exeSha256: lb.sha256,
        version: lb.version || "",
      });
      renderSecurityTab();
      await loadOverview();
      toast(`Lokaler Build ${lb.version || ""} registriert.`);
    });
  });

  $("admin-build-form")?.addEventListener("submit", async (evt) => {
    evt.preventDefault();
    const sha = $("admin-build-sha").value.trim();
    const ver = $("admin-build-ver").value.trim();
    if (!sha) return setStatus($("admin-global-status"), "Bitte gültigen 64-stelligen SHA-256 Hash eingeben.", true);
    await runAdminTask("Speichere Build-Hash…", async () => {
      adminState.buildConfig = await invoke("admin_register_build", {
        exeSha256: sha,
        version: ver,
      });
      $("admin-build-sha").value = "";
      renderSecurityTab();
      await loadOverview();
      toast("Build-Hash hinzugefügt.");
    });
  });

  $("admin-build-clear-btn")?.addEventListener("click", async () => {
    const ok = await confirmAdminAction({
      title: "Alle Build-Hashes löschen?",
      body: "Alle hinterlegten Shadowspore.exe SHA-256 Hashes werden entfernt.",
      confirmLabel: "Alle löschen",
    });
    if (!ok) return;
    await runAdminTask("Leere Build-Hashes…", async () => {
      adminState.buildConfig = await invoke("admin_register_build", { clear: true });
      renderSecurityTab();
      await loadOverview();
      toast("Alle Build-Hashes geleert.");
    });
  });

  $("admin-events-severity")?.addEventListener("change", renderSecurityTab);
  $("admin-events-reload-btn")?.addEventListener("click", () =>
    runAdminTask("Lade Protokoll…", loadSecurityAndBuilds),
  );

  // ---------------------------------------------------------------- Orchestration
  async function loadTabData(tabKey) {
    if (tabKey === "worlds") await loadWorlds();
    else if (tabKey === "players") await loadAccounts();
    else if (tabKey === "keys") await loadKeys();
    else if (tabKey === "security") await loadSecurityAndBuilds();
    adminState.loadedTabs.add(tabKey);
  }

  async function runAdminTask(statusText, fn) {
    const statusNode = $("admin-global-status");
    setStatus(statusNode, statusText);
    try {
      await fn();
      setStatus(statusNode, "");
    } catch (err) {
      setStatus(statusNode, String(err), true);
    }
  }

  async function refreshAll() {
    if (!isAdmin()) return;
    await runAdminTask("Synchronisiere Admin-Daten…", async () => {
      await Promise.all([loadOverview(), loadTabData(adminState.activeTab)]);
    });
  }

  function syncAccess() {
    const allowed = isAdmin();
    $("rail-admin-btn").hidden = !allowed;
    if (!allowed) {
      $("admin-dot").hidden = true;
      adminState.loadedTabs.clear();
    }
    return allowed;
  }

  $("admin-refresh-all-btn")?.addEventListener("click", refreshAll);

  // Live worlds auto-poll every 4s while the Admin Live-Worlds tab is active and visible.
  let pollInFlight = false;
  setInterval(async () => {
    const pageAdmin = $("page-admin");
    if (
      pollInFlight ||
      !isAdmin() ||
      !pageAdmin ||
      pageAdmin.hidden ||
      adminState.activeTab !== "worlds" ||
      document.visibilityState !== "visible" ||
      (confirmDialog && confirmDialog.open)
    ) {
      return;
    }
    pollInFlight = true;
    try {
      adminState.worlds = await invoke("admin_list_active_worlds");
      renderWorlds();
    } catch (_) {
      /* transient poll errors stay silent until manual refresh */
    } finally {
      pollInFlight = false;
    }
  }, 4000);

  return {
    isAdmin,
    syncAccess,
    refreshAll,
    onEnterPage: refreshAll,
  };
}
