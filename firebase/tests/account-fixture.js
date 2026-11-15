// Only served by preview.py --account-fixture, outside Firebase's public root.
const realFetch = window.fetch.bind(window);
const params = new URLSearchParams(location.search);
const scenario = params.get('scenario') || '';
const roleParam = params.get('role') || '';
const fixtureToken = `fixture.${btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600 }))}.fixture`;
const fixtureRefreshToken = `refresh.${btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 86400 }))}.fixture`;

let currentRole = roleParam === 'admin' || scenario === 'admin' ? 'admin' : 'player';
let mockProfile = {
  user_id: 'fixture-user',
  username: currentRole === 'admin' ? 'levin_admin' : 'ellie_test',
  display_name: currentRole === 'admin' ? 'Levin · Weltenbauer' : 'Vorschau · Ellie',
  uid: currentRole === 'admin' ? '100001' : '100123',
  avatar_url: currentRole === 'admin' ? 'ellie_lichtung' : 'ellie_leere',
  world_join_mode: 'ask',
  role: currentRole,
  license_active: true,
  license_edition: currentRole === 'admin' ? 'founder' : 'standard',
  license_expires_at: 0,
  banned: false,
  ban_reason: '',
};

let mockSiteConfig = {
  banner_enabled: false,
  banner_text: '',
  banner_tone: 'teal',
  pins: [
    { id: 'evt-1', title: 'Kristallschauer am Glockenteich', note: 'Bis Sonntag erhöhte Sternensplitter-Dichte im Osten.', tile: [801, 525], kind: 'event' },
  ],
};

let mockAccounts = [
  { user_id: 'fixture-user', uid: '100001', username: 'levin_admin', display_name: 'Levin · Weltenbauer', role: 'admin', online: true, license_active: true, license_edition: 'founder', banned: false, created_at: 1794000000 },
  { user_id: 'u-maren', uid: '100124', username: 'maren_lichtung', display_name: 'Maren', role: 'moderator', online: true, license_active: true, license_edition: 'supporter', banned: false, created_at: 1794100000 },
  { user_id: 'u-gustav', uid: '100125', username: 'gustav_holz', display_name: 'Gustav', role: 'tester', online: false, license_active: true, license_edition: 'standard', banned: false, created_at: 1794200000 },
  { user_id: 'u-shadow', uid: '100126', username: 'leere_wanderer', display_name: 'Nachtwandler', role: 'player', online: false, license_active: false, license_edition: 'standard', banned: true, ban_reason: 'Test-Sperre (Spore-Duplizierung)', created_at: 1794300000 },
];

let mockKeys = [
  { key: 'SHADOW-L9A2-K8M4-Q1Z7', status: 'unused', edition: 'founder', role_grant: 'tester', note: 'Creator-Welle', expires_days: 0, claimed_uid: '' },
  { key: 'SHADOW-P4X7-R2D9-W8N3', status: 'claimed', edition: 'standard', role_grant: 'player', note: 'Beta Invite #14', expires_days: 0, claimed_uid: '100124' },
  { key: 'SHADOW-V1C8-M5J2-T6H9', status: 'revoked', edition: 'standard', role_grant: 'player', note: 'Storniert', expires_days: 30, claimed_uid: '' },
];

let mockWorlds = [
  {
    match_id: 'world-match-01.nakama',
    room_code: 'SPORE-4821',
    host_user_id: 'u-maren',
    host_uid: '100124',
    host_name: 'Maren',
    join_mode: 'friends',
    player_count: 2,
    max_players: 4,
    age_seconds: 1840,
    peers: [
      { user_id: 'u-maren', uid: '100124', display_name: 'Maren', is_host: true },
      { user_id: 'u-gustav', uid: '100125', display_name: 'Gustav', is_host: false },
    ],
  },
];

let mockBuildConfig = {
  enforce: true,
  hashes: {
    '8a73e041c3113c83afca54dcb767f5b2dcc4e251f2a77d996377bdff0b343fc5': { version: '0.1.0-win64', registered_at: 1794700000 },
  },
  hash_list: [
    { sha256: '8a73e041c3113c83afca54dcb767f5b2dcc4e251f2a77d996377bdff0b343fc5', version: '0.1.0-win64', registered_at: 1794700000 },
  ],
};

let mockEvents = [
  { ts: 1794774000, kind: 'BUILD_REGISTERED', uid: '100001', details: '0.1.0-win64 eingetragen (enforce=true)' },
  { ts: 1794769000, kind: 'ACCOUNT_BANNED', uid: '100126', details: 'Test-Sperre (Spore-Duplizierung)' },
  { ts: 1794750000, kind: 'ROLE_UPDATED', uid: '100124', details: 'Rolle -> moderator' },
];

window.fetch = async (url, options = {}) => {
  if (!String(url).startsWith('https://s.shadowspore.com/')) return realFetch(url, options);
  const path = new URL(url).pathname;
  const method = (options.method || 'GET').toUpperCase();
  const rawBody = options.body ? JSON.parse(options.body) : {};
  const rpcPayload = typeof rawBody === 'string' ? JSON.parse(rawBody || '{}') : rawBody;
  const json = (data, status = 200) => Promise.resolve(new Response(JSON.stringify(data), { status }));
  const rpcOk = (obj) => json({ payload: JSON.stringify({ ok: true, ...obj }) });

  if (path.endsWith('/healthcheck')) return json({ ok: true });
  if (path.includes('/authenticate/')) {
    if (String(rawBody.email || '').includes('admin')) {
      currentRole = 'admin';
      mockProfile = { ...mockProfile, role: 'admin', username: 'levin_admin', display_name: 'Levin · Weltenbauer', uid: '100001', license_edition: 'founder' };
    }
    return json({ token: fixtureToken, refresh_token: fixtureRefreshToken });
  }
  if (path.endsWith('/v2/account/session/refresh')) {
    if (!rawBody.token) return json({ message: 'Invalid refresh token' }, 401);
    return json({ token: fixtureToken, refresh_token: fixtureRefreshToken });
  }
  if (path.endsWith('/v2/account') && method === 'PUT') {
    if (rawBody.display_name) mockProfile.display_name = rawBody.display_name;
    if (rawBody.avatar_url) mockProfile.avatar_url = rawBody.avatar_url;
    return json({});
  }
  if (path.endsWith('/get_my_profile')) return rpcOk(mockProfile);
  if (path.endsWith('/set_world_join_mode')) {
    const jm = String(rpcPayload.join_mode || '');
    if (!['private', 'ask', 'open'].includes(jm)) {
      return json({ payload: JSON.stringify({ ok: false, error: 'Ungueltiger Modus (erlaubt: private, ask, open).' }) });
    }
    mockProfile.world_join_mode = jm;
    return rpcOk({ world_join_mode: mockProfile.world_join_mode });
  }
  if (path.endsWith('/redeem_license_key')) {
    mockProfile.license_active = true;
    return rpcOk({ licensed: true, edition: 'founder' });
  }
  if (path.endsWith('/list_friends')) {
    if (scenario === 'partial') return json({ message: 'Unavailable' }, 503);
    return rpcOk({
      friends: scenario === 'empty' ? [] : [
        { user_id: 'u-maren', username: 'Maren', uid: '100124', state: 0, online: true, coop_active: true, coop_world_name: 'Glimmrast-Tal', avatar_url: 'ellie_lichtung' },
        { user_id: 'u-gustav', username: 'Gustav', uid: '100125', state: 2, online: false, avatar_url: 'ellie_leere' },
      ],
    });
  }
  if (path.endsWith('/find_by_uid')) {
    const q = String(rpcPayload.uid || '').toLowerCase();
    const hit = mockAccounts.find((a) => a.uid === q || a.username.toLowerCase().includes(q));
    if (!hit) return rpcOk({ ok: false, error: 'Spieler nicht gefunden.' });
    return rpcOk(hit);
  }
  if (path.endsWith('/add_friend_by_uid') || path.endsWith('/accept_friend') || path.endsWith('/remove_friend')) return rpcOk({});
  if (path.endsWith('/coop_resolve_code')) {
    const w = mockWorlds.find((x) => x.room_code === rpcPayload.room_code);
    if (!w) return json({ payload: JSON.stringify({ ok: false, error: 'Raumcode nicht aktiv.' }) });
    return rpcOk({ match_id: w.match_id, host_name: w.host_name, player_count: w.player_count, room_code: w.room_code });
  }
  if (path.endsWith('/wipe_cloud_save')) return rpcOk({});
  if (path.endsWith('/storage')) {
    if (method === 'PUT') {
      const first = (rawBody.objects || [])[0];
      if (first && first.collection === 'website_admin') {
        mockSiteConfig = JSON.parse(first.value || '{}');
      }
      return json({});
    }
    const oid = (rawBody.object_ids || [])[0] || {};
    if (oid.collection === 'website_admin') {
      return json({ objects: [{ value: JSON.stringify(mockSiteConfig) }] });
    }
    return json({ objects: scenario === 'empty' ? [] : [{ value: JSON.stringify({ day: 12, time: 0.72, saved_at: 1794740400 }) }] });
  }
  if (path.endsWith('/session/logout')) return json({});

  // Admin RPCs
  if (path.endsWith('/admin_overview')) {
    return rpcOk({
      total_accounts: mockAccounts.length,
      banned_accounts: mockAccounts.filter((a) => a.banned).length,
      online_accounts: mockAccounts.filter((a) => a.online).length,
      active_worlds: mockWorlds.length,
      unused_keys: mockKeys.filter((k) => k.status === 'unused').length,
      claimed_keys: mockKeys.filter((k) => k.status === 'claimed').length,
      revoked_keys: mockKeys.filter((k) => k.status === 'revoked').length,
      security_events: mockEvents.length,
      build_enforce: mockBuildConfig.enforce,
      build_hash_count: mockBuildConfig.hash_list.length,
    });
  }
  if (path.endsWith('/admin_list_active_worlds')) return rpcOk({ worlds: mockWorlds });
  if (path.endsWith('/admin_force_join')) {
    return rpcOk({ match_id: 'world-match-01.nakama', room_code: 'SPORE-4821', host_name: 'Maren', launch_token: 'adm-ticket-998' });
  }
  if (path.endsWith('/admin_kick_match_peer')) {
    mockWorlds = mockWorlds.map((w) => w.match_id === rpcPayload.match_id ? { ...w, peers: w.peers.filter((p) => p.user_id !== rpcPayload.target_user_id), player_count: Math.max(1, w.player_count - 1) } : w);
    mockEvents.unshift({ ts: Math.floor(Date.now() / 1000), kind: 'PEER_KICKED', uid: rpcPayload.target_uid || '?', details: `Cooldown ${rpcPayload.cooldown}s` });
    return rpcOk({});
  }
  if (path.endsWith('/admin_close_world')) {
    mockWorlds = mockWorlds.filter((w) => w.match_id !== rpcPayload.match_id);
    mockEvents.unshift({ ts: Math.floor(Date.now() / 1000), kind: 'WORLD_CLOSED', uid: mockProfile.uid, details: rpcPayload.match_id });
    return rpcOk({});
  }
  if (path.endsWith('/admin_list_accounts')) {
    let list = [...mockAccounts];
    const q = String(rpcPayload.query || '').toLowerCase();
    if (q) list = list.filter((a) => a.uid.includes(q) || a.username.toLowerCase().includes(q) || a.display_name.toLowerCase().includes(q));
    if (rpcPayload.role) list = list.filter((a) => a.role === rpcPayload.role);
    if (rpcPayload.status === 'banned') list = list.filter((a) => a.banned);
    if (rpcPayload.status === 'online') list = list.filter((a) => a.online);
    if (rpcPayload.status === 'licensed') list = list.filter((a) => a.license_active);
    return rpcOk({ accounts: list });
  }
  if (path.endsWith('/admin_set_role')) {
    mockAccounts = mockAccounts.map((a) => (a.uid === rpcPayload.uid || a.user_id === rpcPayload.uid) ? { ...a, role: rpcPayload.role } : a);
    mockEvents.unshift({ ts: Math.floor(Date.now() / 1000), kind: 'ROLE_UPDATED', uid: rpcPayload.uid, details: `-> ${rpcPayload.role}` });
    return rpcOk({ user_id: 'u-target', uid: rpcPayload.uid, role: rpcPayload.role });
  }
  if (path.endsWith('/admin_set_license')) {
    if (rpcPayload.license_key) {
      mockKeys = mockKeys.map((k) => k.key === rpcPayload.license_key ? { ...k, status: rpcPayload.key_status || 'revoked' } : k);
    } else {
      mockAccounts = mockAccounts.map((a) => (a.uid === rpcPayload.target_uid || a.user_id === rpcPayload.target_user_id) ? { ...a, license_active: !!rpcPayload.active, license_edition: rpcPayload.edition || a.license_edition } : a);
    }
    return rpcOk({});
  }
  if (path.endsWith('/admin_set_ban')) {
    mockAccounts = mockAccounts.map((a) => (a.uid === rpcPayload.target_uid || a.user_id === rpcPayload.target_user_id) ? { ...a, banned: !!rpcPayload.banned, ban_reason: rpcPayload.reason || '' } : a);
    mockEvents.unshift({ ts: Math.floor(Date.now() / 1000), kind: rpcPayload.banned ? 'ACCOUNT_BANNED' : 'ACCOUNT_UNBANNED', uid: rpcPayload.target_uid || rpcPayload.target_user_id, details: rpcPayload.reason || '' });
    return rpcOk({});
  }
  if (path.endsWith('/admin_issue_license_key')) {
    const n = Math.max(1, Math.min(50, Number(rpcPayload.count || 1)));
    const created = [];
    for (let i = 0; i < n; i++) {
      const k = `SHADOW-${Math.random().toString(36).slice(2, 6).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
      created.push(k);
      mockKeys.unshift({ key: k, status: 'unused', edition: rpcPayload.edition || 'standard', role_grant: rpcPayload.role_grant || 'player', note: rpcPayload.note || '', expires_days: rpcPayload.expires_days || 0, claimed_uid: '' });
    }
    return rpcOk({ keys: created });
  }
  if (path.endsWith('/admin_list_license_keys')) {
    let list = [...mockKeys];
    if (rpcPayload.status) list = list.filter((k) => k.status === rpcPayload.status);
    const q = String(rpcPayload.query || '').toLowerCase();
    if (q) list = list.filter((k) => k.key.toLowerCase().includes(q) || (k.note || '').toLowerCase().includes(q));
    return rpcOk({ keys: list });
  }
  if (path.endsWith('/admin_get_build_config')) return rpcOk(mockBuildConfig);
  if (path.endsWith('/admin_register_build')) {
    if (typeof rpcPayload.enforce === 'boolean') mockBuildConfig.enforce = rpcPayload.enforce;
    if (rpcPayload.clear) {
      mockBuildConfig.hashes = {};
      mockBuildConfig.hash_list = [];
    }
    if (rpcPayload.remove_sha256) {
      delete mockBuildConfig.hashes[rpcPayload.remove_sha256];
      mockBuildConfig.hash_list = mockBuildConfig.hash_list.filter((h) => h.sha256 !== rpcPayload.remove_sha256);
    }
    if (rpcPayload.exe_sha256) {
      const entry = { sha256: rpcPayload.exe_sha256, version: rpcPayload.version || '0.1.0', registered_at: Math.floor(Date.now() / 1000) };
      mockBuildConfig.hashes[rpcPayload.exe_sha256] = entry;
      mockBuildConfig.hash_list = [entry, ...mockBuildConfig.hash_list.filter((h) => h.sha256 !== rpcPayload.exe_sha256)];
    }
    return rpcOk(mockBuildConfig);
  }
  if (path.endsWith('/admin_list_security_events')) return rpcOk({ events: mockEvents });

  throw new Error(`Unconfigured fixture request: ${path}`);
};
document.addEventListener('DOMContentLoaded', () => { document.title = 'LOKALE TESTDATEN · ' + document.title; });
