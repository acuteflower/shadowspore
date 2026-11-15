import test from 'node:test';
import assert from 'node:assert/strict';
import { createAccountApi, tokenExpiry } from '../public/account.mjs';

const token = `header.${Buffer.from(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.signature`;
const response = (data, status = 200) => new Response(JSON.stringify(data), { status });
function transport(replies) {
  const requests = [];
  const api = createAccountApi(async (url, options) => {
    requests.push({ url, ...options, parsed: options.body ? JSON.parse(options.body) : undefined });
    assert.ok(replies.length, 'unexpected request');
    return replies.shift();
  });
  return { api, requests };
}

test('launcher login never creates a second account; password preserved verbatim', async () => {
  const { api, requests } = transport([response({ token })]);
  assert.equal(await api.authenticate({ email: ' Player@Example.com ', password: ' spaced password ' }), token);
  assert.equal(requests[0].url, 'https://s.shadowspore.com/v2/account/authenticate/email?create=false');
  assert.deepEqual(requests[0].parsed, { email: 'player@example.com', password: ' spaced password ' });
  assert.equal(requests[0].credentials, 'omit');
  assert.equal(requests[0].redirect, 'error');
  assert.equal(atob(requests[0].headers.Authorization.slice(6)), 'shadowspore_live_client_v1:');
});
test('signup supplies the license to the existing authentication hook', async () => {
  const { api, requests } = transport([response({ token })]);
  await api.authenticate({ email: 'p@example.com', password: 'password', username: 'Ellie.1', licenseKey: ' shadow-abcd-efgh-1234 ', mode: 'signup' });
  assert.ok(requests[0].url.endsWith('?create=true&username=Ellie.1'));
  assert.deepEqual(requests[0].parsed.vars, { license_key: 'SHADOW-ABCD-EFGH-1234' });
});
test('redemption authenticates existing account then uses double-encoded Nakama RPC payload', async () => {
  const { api, requests } = transport([response({ token }), response({ payload: '{"ok":true}' })]);
  await api.authenticate({ email: 'p@example.com', password: 'password', licenseKey: 'shadow-abcd-efgh-1234', mode: 'redeem' });
  assert.ok(requests[0].url.endsWith('create=false'));
  assert.ok(requests[1].url.endsWith('/v2/rpc/redeem_license_key'));
  assert.equal(requests[1].headers.Authorization, `Bearer ${token}`);
  assert.deepEqual(JSON.parse(requests[1].parsed), { license_key: 'SHADOW-ABCD-EFGH-1234' });
});
test('failed license redemption is not reported as success', async () => {
  const { api } = transport([response({ token }), response({ payload: '{"ok":false,"error":"Key already used"}' })]);
  await assert.rejects(api.authenticate({ email: 'p@example.com', password: 'password', mode: 'redeem' }), /Key already used/);
});
test('expired and malformed session tokens are rejected', async () => {
  assert.equal(tokenExpiry('bad'), 0);
  const expired = `header.${Buffer.from('{"exp":1}').toString('base64url')}.signature`;
  const { api } = transport([response({ token: expired })]);
  await assert.rejects(api.authenticate({ email: 'p@example.com', password: 'password' }), /gültige Sitzung/);
});
test('authentication and rate-limit errors preserve status for session handling', async () => {
  const { api } = transport([response({ message: 'Unauthenticated' }, 401), response({}, 429)]);
  await assert.rejects(api.profile(token), error => error.status === 401);
  await assert.rejects(api.profile(token), error => error.status === 429 && /Zu viele/.test(error.message));
});
test('invalid JSON and RPC envelopes produce useful errors', async () => {
  const { api } = transport([new Response('<html>Gateway</html>'), response({ payload: 'bad' })]);
  await assert.rejects(api.profile(token), /nicht gelesen/);
  await assert.rejects(api.profile(token), /unvollständig/);
});
test('network failure is distinct from an empty friend list', async () => {
  const api = createAccountApi(async () => { throw new TypeError('offline'); });
  await assert.rejects(api.friends(token), /nicht erreichbar/);
  const fixture = transport([response({ payload: '{"ok":true,"friends":{}}' })]);
  assert.deepEqual(await fixture.api.friends(token), []);
});
test('world overview reads only own metadata, never downloads or mutates game saves', async () => {
  const { api, requests } = transport([response({ objects: [{ value: '{"day":9,"saved_at":1700000000}' }] }), response({ objects: [] })]);
  assert.deepEqual(await api.world(token, 'own-user-id'), { day: 9, saved_at: 1700000000 });
  assert.deepEqual(requests[0].parsed, { object_ids: [{ collection: 'saves', key: 'world_meta', user_id: 'own-user-id' }] });
  assert.equal(await api.world(token, 'own-user-id'), null);
});
test('logout revokes only this website session token', async () => {
  const { api, requests } = transport([response({})]);
  await api.logout(token);
  assert.ok(requests[0].url.endsWith('/v2/session/logout'));
  assert.deepEqual(requests[0].parsed, { token });
});

test('admin RPC helpers serialize expected double-encoded payloads', async () => {
  const { api, requests } = transport([
    response({ payload: '{"ok":true,"total_accounts":42,"active_worlds":3}' }),
    response({ payload: '{"ok":true,"role":"moderator"}' }),
    response({ payload: '{"ok":true,"banned":true}' }),
    response({ payload: '{"ok":true,"enforce":true,"hash_list":[]}' }),
    response({ payload: '{"ok":true,"keys":["SHADOW-AAAA-BBBB-CCCC"]}' }),
  ]);

  const ov = await api.adminOverview(token);
  assert.equal(ov.total_accounts, 42);
  assert.ok(requests[0].url.endsWith('/v2/rpc/admin_overview'));

  await api.adminSetRole(token, { target: '100124', role: 'moderator' });
  assert.deepEqual(JSON.parse(requests[1].parsed), { uid: '100124', query: '100124', role: 'moderator' });

  await api.adminSetBan(token, { target: '100124', banned: true, reason: 'Griefing' });
  assert.deepEqual(JSON.parse(requests[2].parsed), {
    target_uid: '100124',
    query: '100124',
    banned: true,
    reason: 'Griefing',
  });

  await api.adminRegisterBuild(token, {
    exeSha256: 'ABCD1234',
    version: '0.1.0',
    enforce: true,
  });
  assert.deepEqual(JSON.parse(requests[3].parsed), {
    exe_sha256: 'abcd1234',
    version: '0.1.0',
    enforce: true,
  });

  const issued = await api.adminIssueKeys(token, { count: 1, edition: 'founder', roleGrant: 'tester' });
  assert.deepEqual(issued.keys, ['SHADOW-AAAA-BBBB-CCCC']);
  assert.deepEqual(JSON.parse(requests[4].parsed), {
    count: 1,
    edition: 'founder',
    role_grant: 'tester',
    note: '',
    expires_days: 0,
  });
});

test('social and site storage helpers send exact Nakama envelopes', async () => {
  const { api, requests } = transport([
    response({ payload: '{"ok":true,"world_join_mode":"open"}' }),
    response({ payload: '{"ok":true,"uid":"100124"}' }),
    response({}),
  ]);
  await api.setJoinMode(token, 'open');
  assert.deepEqual(JSON.parse(requests[0].parsed), { join_mode: 'open' });

  await api.findByUid(token, '100124');
  assert.deepEqual(JSON.parse(requests[1].parsed), { uid: '100124' });

  await api.adminWriteSiteConfig(token, { banner: 'Beta', pins: [] });
  assert.equal(requests[2].method, 'PUT');
  assert.equal(requests[2].parsed.objects[0].collection, 'website_admin');
  assert.equal(requests[2].parsed.objects[0].key, 'site_config');
});

test('updateAccount, join mode mapping, and session refresh match Nakama schema', async () => {
  const { api, requests } = transport([
    response({ token, refresh_token: 'ref-1' }),
    response({ token, refresh_token: 'ref-2' }),
    response({}),
    response({}),
    response({ payload: '{"ok":true,"world_join_mode":"ask"}' }),
  ]);

  const session = await api.authenticateSession({ email: 'nxye@example.com', password: 'password123' });
  assert.deepEqual(session, { token, refreshToken: 'ref-1' });

  const refreshed = await api.refreshSession('ref-1');
  assert.deepEqual(refreshed, { token, refreshToken: 'ref-2' });
  assert.equal(requests[1].url, 'https://s.shadowspore.com/v2/account/session/refresh');
  assert.deepEqual(requests[1].parsed, { token: 'ref-1' });

  await api.updateAccount(token, { displayName: 'Levin' });
  assert.equal(requests[2].method, 'PUT');
  assert.deepEqual(requests[2].parsed, { display_name: 'Levin' });

  await api.updateAccount(token, { avatar_url: 'ellie_leere' });
  assert.deepEqual(requests[3].parsed, { avatar_url: 'ellie_leere' });

  await api.setJoinMode(token, 'friends');
  assert.deepEqual(JSON.parse(requests[4].parsed), { join_mode: 'ask' });
});
