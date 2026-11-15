/**
 * Nakama REST client for Shadowspore accounts, social, cloud state, and Admin Panel.
 * Talks to https://s.shadowspore.com using the public client key (no admin secrets).
 */

const BASE = 'https://s.shadowspore.com';
const CLIENT_KEY = 'shadowspore_live_client_v1';
const STORAGE_COLLECTION_ADMIN = 'website_admin';

export class ApiError extends Error {
  constructor(message, status = 0) {
    super(message);
    this.status = status;
  }
}

function basicAuthHeader() {
  return `Basic ${btoa(`${CLIENT_KEY}:`)}`;
}

export function tokenExpiry(token) {
  try {
    const seg = String(token || '').split('.')[1];
    if (!seg) return 0;
    const pad = seg.replace(/-/g, '+').replace(/_/g, '/');
    const json = atob(pad + '='.repeat((4 - (pad.length % 4)) % 4));
    const payload = JSON.parse(json);
    return Number(payload.exp || 0) * 1000;
  } catch {
    return 0;
  }
}

export function normalizeLicenseKey(raw) {
  const clean = String(raw || '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
  if (!clean) return '';
  if (clean.startsWith('SHADOW') && clean.length > 6) {
    const rest = clean.slice(6);
    const groups = rest.match(/.{1,4}/g) || [];
    return `SHADOW-${groups.join('-')}`;
  }
  const groups = clean.match(/.{1,4}/g) || [];
  return groups.join('-');
}

function isUuid(s) {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(
    String(s || '').trim()
  );
}

function targetPayload(target) {
  const clean = String(target || '').trim();
  if (!clean) return {};
  if (isUuid(clean)) {
    return { target_user_id: clean, query: clean };
  }
  return { target_uid: clean, query: clean };
}

export function createAccountApi(fetcher = globalThis.fetch) {
  async function request(path, { method = 'GET', auth = 'none', token = '', body } = {}) {
    const headers = {};
    if (auth === 'basic') headers.Authorization = basicAuthHeader();
    else if (auth === 'bearer' && token) headers.Authorization = `Bearer ${token}`;

    const init = {
      method,
      headers,
      credentials: 'omit',
      redirect: 'error',
    };
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      init.body = typeof body === 'string' ? body : JSON.stringify(body);
    }

    let res;
    try {
      res = await fetcher(`${BASE}${path}`, init);
    } catch {
      throw new ApiError('Server s.shadowspore.com ist derzeit nicht erreichbar.', 0);
    }

    const text = await res.text();
    let data = {};
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        throw new ApiError('Antwort des Servers konnte nicht gelesen werden.', res.status || 0);
      }
    }

    if (!res.ok) {
      if (res.status === 429) {
        throw new ApiError('Zu viele Anfragen — bitte kurz warten.', 429);
      }
      const msg =
        (data && (data.message || data.error)) ||
        `Anfrage fehlgeschlagen (HTTP ${res.status})`;
      throw new ApiError(msg, res.status);
    }
    return data;
  }

  async function rpc(id, token, payload = {}) {
    const res = await request(`/v2/rpc/${encodeURIComponent(id)}`, {
      method: 'POST',
      auth: 'bearer',
      token,
      // Nakama REST expects the JSON payload serialized as a JSON string literal.
      body: JSON.stringify(JSON.stringify(payload || {})),
    });

    let inner;
    if (typeof res.payload === 'string') {
      try {
        inner = JSON.parse(res.payload || '{}');
      } catch {
        throw new ApiError('Antwort des Servers war unvollständig.', 502);
      }
    } else if (res.payload && typeof res.payload === 'object') {
      inner = res.payload;
    } else if (res && typeof res === 'object') {
      inner = res;
    } else {
      throw new ApiError('Antwort des Servers war unvollständig.', 502);
    }

    if (inner && inner.ok === false) {
      throw new ApiError(inner.error || 'Aktion abgelehnt.', 400);
    }
    return inner;
  }

  async function storageRead(token, objectIds) {
    const res = await request('/v2/storage', {
      method: 'POST',
      auth: 'bearer',
      token,
      body: { object_ids: objectIds },
    });
    const obj = (res.objects || [])[0];
    if (!obj || obj.value === undefined || obj.value === null) return null;
    return typeof obj.value === 'string' ? JSON.parse(obj.value) : obj.value;
  }

  async function storageWrite(token, objects) {
    await request('/v2/storage', {
      method: 'PUT',
      auth: 'bearer',
      token,
      body: { objects },
    });
    return true;
  }

  return {
    async authenticateSession({ email, password, username = '', licenseKey = '', mode = 'login' }) {
      const cleanEmail = String(email || '').trim().toLowerCase();
      const cleanUser = String(username || '').trim();
      const cleanKey = normalizeLicenseKey(licenseKey);
      const isSignup = mode === 'signup';

      const params = new URLSearchParams();
      params.set('create', isSignup ? 'true' : 'false');
      if (isSignup && cleanUser) params.set('username', cleanUser);

      const body = { email: cleanEmail, password: String(password ?? '') };
      if (isSignup && cleanKey) {
        body.vars = { license_key: cleanKey };
      }

      const session = await request(`/v2/account/authenticate/email?${params.toString()}`, {
        method: 'POST',
        auth: 'basic',
        body,
      });

      const tok = String(session.token || '');
      const refreshToken = String(session.refresh_token || '');
      if (!tok || tokenExpiry(tok) <= Date.now()) {
        throw new ApiError('Keine gültige Sitzung erhalten.', 401);
      }

      if (mode === 'redeem') {
        await rpc('redeem_license_key', tok, { license_key: cleanKey });
      }
      return { token: tok, refreshToken };
    },

    async authenticate(opts) {
      const { token: tok } = await this.authenticateSession(opts);
      return tok;
    },

    async refreshSession(refreshToken) {
      const rt = String(refreshToken || '').trim();
      if (!rt) {
        throw new ApiError('Kein Refresh-Token vorhanden.', 401);
      }
      const session = await request('/v2/account/session/refresh', {
        method: 'POST',
        auth: 'basic',
        body: { token: rt },
      });
      const tok = String(session.token || '');
      const nextRefresh = String(session.refresh_token || rt);
      if (!tok || tokenExpiry(tok) <= Date.now()) {
        throw new ApiError('Sitzung konnte nicht erneuert werden.', 401);
      }
      return { token: tok, refreshToken: nextRefresh };
    },

    async redeemKey(token, licenseKey) {
      return rpc('redeem_license_key', token, {
        license_key: normalizeLicenseKey(licenseKey),
      });
    },

    async profile(token) {
      return rpc('get_my_profile', token, {});
    },

    async updateAccount(token, opts = {}) {
      const displayName = opts.displayName !== undefined ? opts.displayName : opts.display_name;
      const avatarUrl = opts.avatarUrl !== undefined ? opts.avatarUrl : opts.avatar_url;
      const body = {};
      if (displayName !== undefined) body.display_name = String(displayName).trim();
      if (avatarUrl !== undefined) body.avatar_url = String(avatarUrl).trim();
      if (!Object.keys(body).length) {
        throw new ApiError('Keine Profiländerungen angegeben.', 400);
      }
      await request('/v2/account', {
        method: 'PUT',
        auth: 'bearer',
        token,
        body,
      });
      return true;
    },

    async setJoinMode(token, joinMode) {
      const raw = String(joinMode || 'ask').trim().toLowerCase();
      const normalized = raw === 'friends' ? 'ask' : raw;
      return rpc('set_world_join_mode', token, {
        join_mode: normalized,
      });
    },

    async friends(token) {
      const inner = await rpc('list_friends', token, {});
      return Array.isArray(inner.friends) ? inner.friends : [];
    },

    async findByUid(token, query) {
      return rpc('find_by_uid', token, { uid: String(query || '').trim() });
    },

    async addFriendByUid(token, query) {
      return rpc('add_friend_by_uid', token, { uid: String(query || '').trim() });
    },

    async acceptFriend(token, userId) {
      return rpc('accept_friend', token, { user_id: String(userId || '').trim() });
    },

    async removeFriend(token, userId) {
      return rpc('remove_friend', token, { user_id: String(userId || '').trim() });
    },

    async resolveRoomCode(token, roomCode) {
      return rpc('coop_resolve_code', token, {
        room_code: String(roomCode || '').trim().toUpperCase(),
      });
    },

    async world(token, userId) {
      return storageRead(token, [
        { collection: 'saves', key: 'world_meta', user_id: String(userId || '') },
      ]);
    },

    async worldSummary(token, userId) {
      const state = await storageRead(token, [
        { collection: 'saves', key: 'world_state', user_id: String(userId || '') },
      ]).catch(() => null);
      if (state && !state.empty) return state;
      const meta = await this.world(token, userId).catch(() => null);
      if (meta && !meta.empty) return meta;
      return null;
    },

    async wipeCloudSave(token) {
      return rpc('wipe_cloud_save', token, {});
    },

    async logout(token) {
      if (!token) return;
      try {
        await request('/v2/session/logout', {
          method: 'POST',
          auth: 'bearer',
          token,
          body: { token },
        });
      } catch {
        // Ignore remote session revocation timeout on client sign-out.
      }
    },

    // ================================================================ ADMIN RPCs
    async adminOverview(token) {
      return rpc('admin_overview', token, {});
    },

    async adminListWorlds(token) {
      return rpc('admin_list_active_worlds', token, {});
    },

    async adminForceJoin(token, { query = '', matchId = '', roomCode = '', hostUserId = '' } = {}) {
      return rpc('admin_force_join', token, {
        query: String(query || '').trim(),
        match_id: String(matchId || '').trim(),
        room_code: String(roomCode || '').trim().toUpperCase(),
        host_user_id: String(hostUserId || '').trim(),
      });
    },

    async adminKickPeer(token, { matchId, targetUserId = '', targetUid = '', cooldown = 300 } = {}) {
      return rpc('admin_kick_match_peer', token, {
        match_id: String(matchId || '').trim(),
        target_user_id: String(targetUserId || '').trim(),
        target_uid: String(targetUid || '').trim(),
        cooldown: Number(cooldown || 0),
      });
    },

    async adminCloseWorld(token, { matchId = '', hostUserId = '' } = {}) {
      return rpc('admin_close_world', token, {
        match_id: String(matchId || '').trim(),
        host_user_id: String(hostUserId || '').trim(),
      });
    },

    async adminListAccounts(token, { query = '', role = '', status = '', limit = 100 } = {}) {
      return rpc('admin_list_accounts', token, {
        query: String(query || '').trim(),
        role: String(role || '').trim().toLowerCase(),
        status: String(status || '').trim().toLowerCase(),
        limit: Number(limit || 100),
      });
    },

    async adminSetRole(token, { target, role }) {
      return rpc('admin_set_role', token, {
        uid: String(target || '').trim(),
        query: String(target || '').trim(),
        role: String(role || 'player').trim().toLowerCase(),
      });
    },

    async adminSetLicense(token, { target = '', licenseKey = '', keyStatus = '', active, edition = 'standard' } = {}) {
      const payload = { ...targetPayload(target) };
      if (licenseKey) payload.license_key = normalizeLicenseKey(licenseKey);
      if (keyStatus) payload.key_status = String(keyStatus).trim().toLowerCase();
      if (typeof active === 'boolean') payload.active = active;
      if (edition) payload.edition = String(edition).trim().toLowerCase();
      return rpc('admin_set_license', token, payload);
    },

    async adminSetBan(token, { target, banned, reason = '' }) {
      return rpc('admin_set_ban', token, {
        ...targetPayload(target),
        banned: !!banned,
        reason: String(reason || '').trim().slice(0, 200),
      });
    },

    async adminIssueKeys(token, { count = 1, edition = 'standard', roleGrant = 'player', note = '', expiresDays = 0 } = {}) {
      return rpc('admin_issue_license_key', token, {
        count: Math.max(1, Math.min(50, Number(count || 1))),
        edition: String(edition || 'standard').trim().toLowerCase(),
        role_grant: String(roleGrant || 'player').trim().toLowerCase(),
        note: String(note || '').trim().slice(0, 120),
        expires_days: Math.max(0, Number(expiresDays || 0)),
      });
    },

    async adminListKeys(token, { status = '', query = '' } = {}) {
      return rpc('admin_list_license_keys', token, {
        status: String(status || '').trim().toLowerCase(),
        query: String(query || '').trim(),
      });
    },

    async adminGetBuildConfig(token) {
      return rpc('admin_get_build_config', token, {});
    },

    async adminRegisterBuild(token, { exeSha256 = '', version = '', enforce, removeSha256 = '', clear = false } = {}) {
      const payload = {};
      if (exeSha256) payload.exe_sha256 = String(exeSha256).trim().toLowerCase();
      if (version) payload.version = String(version).trim();
      if (typeof enforce === 'boolean') payload.enforce = enforce;
      if (removeSha256) payload.remove_sha256 = String(removeSha256).trim().toLowerCase();
      if (clear) payload.clear = true;
      return rpc('admin_register_build', token, payload);
    },

    async adminListSecurityEvents(token) {
      return rpc('admin_list_security_events', token, {});
    },

    async adminReadSiteConfig(token, userId) {
      return storageRead(token, [
        { collection: STORAGE_COLLECTION_ADMIN, key: 'site_config', user_id: String(userId || '') },
      ]);
    },

    async adminWriteSiteConfig(token, value) {
      return storageWrite(token, [
        {
          collection: STORAGE_COLLECTION_ADMIN,
          key: 'site_config',
          value: JSON.stringify(value ?? {}),
          permission_read: 2,
          permission_write: 1,
        },
      ]);
    },

    async probeServerHealth() {
      const started = performance.now();
      try {
        const res = await fetcher(`${BASE}/healthcheck?_=${Date.now()}`, {
          method: 'GET',
          credentials: 'omit',
        });
        const ms = Math.max(1, Math.round(performance.now() - started));
        return { ok: res.ok, status: res.status, latencyMs: ms };
      } catch {
        return { ok: false, status: 0, latencyMs: 0 };
      }
    },
  };
}
