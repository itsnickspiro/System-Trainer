#!/usr/bin/env node
//
// tools/appstoreconnect.js
//
// Minimal zero-dep App Store Connect API helper for the RPT iOS app.
// Uses only Node.js stdlib (crypto, https) — no npm install required.
//
// Generates an ES256 JWT from the .p8 key at
// ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 and calls the
// App Store Connect API for build management.
//
// Usage:
//   node tools/appstoreconnect.js list
//       List all TestFlight builds for com.SpiroTechnologies.RPT,
//       newest first.
//
//   node tools/appstoreconnect.js list --all
//       Also include already-expired builds in the output.
//
//   node tools/appstoreconnect.js expire <buildId> [<buildId> ...]
//       Mark one or more builds as expired (hidden from testers).
//       Expiration is irreversible on the Apple side.
//
//   node tools/appstoreconnect.js expire-cleanup
//       DRY RUN: propose a cleanup plan. Keeps the newest build of
//       each marketing version, lists all the older intermediate
//       builds of the same version as candidates to expire, and
//       prints the exact command you'd run to actually expire them.
//       Never expires anything without an explicit follow-up.
//
// Config via environment variables (with sensible defaults):
//   APP_STORE_CONNECT_KEY_ID    default: 2Y773SS5ZG
//   APP_STORE_CONNECT_ISSUER_ID default: afd36895-c825-4ae2-b576-0c259f6b49ca
//   APP_STORE_CONNECT_KEY_PATH  default: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
//   APP_BUNDLE_ID               default: SpiroTechnologies.RPT

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const https = require('https');

const KEY_ID = process.env.APP_STORE_CONNECT_KEY_ID || '2Y773SS5ZG';
const ISSUER_ID = process.env.APP_STORE_CONNECT_ISSUER_ID || 'afd36895-c825-4ae2-b576-0c259f6b49ca';
const KEY_PATH = process.env.APP_STORE_CONNECT_KEY_PATH
  || path.join(os.homedir(), '.appstoreconnect', 'private_keys', `AuthKey_${KEY_ID}.p8`);
const BUNDLE_ID = process.env.APP_BUNDLE_ID || 'SpiroTechnologies.RPT';

// ── JWT (ES256) ──────────────────────────────────────────────────────────────
//
// App Store Connect expects an ES256 JWT with:
//   header: { alg: "ES256", kid: <KEY_ID>, typ: "JWT" }
//   payload: { iss: <ISSUER_ID>, exp: <now + 20min>, aud: "appstoreconnect-v1" }
//
// Node 15+ supports dsaEncoding: 'ieee-p1363' which returns the raw r||s
// 64-byte concatenation JWT needs (instead of DER-encoded ECDSA).

function base64url(buf) {
  return Buffer.from(buf).toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function makeJWT() {
  if (!fs.existsSync(KEY_PATH)) {
    console.error(`ERROR: private key not found at ${KEY_PATH}`);
    console.error('Make sure AuthKey_<KEY_ID>.p8 is in ~/.appstoreconnect/private_keys/');
    process.exit(1);
  }
  const privateKey = fs.readFileSync(KEY_PATH, 'utf8');

  const header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: ISSUER_ID,
    iat: now,
    exp: now + 20 * 60, // 20 minutes, App Store Connect's max
    aud: 'appstoreconnect-v1',
  };

  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const signature = crypto.sign('sha256', Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });
  const sigB64 = base64url(signature);

  return `${signingInput}.${sigB64}`;
}

// ── HTTPS helper ─────────────────────────────────────────────────────────────

function apiRequest(method, pathname, jwtToken, body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.appstoreconnect.apple.com',
      path: pathname,
      method,
      headers: {
        'Authorization': `Bearer ${jwtToken}`,
        'Content-Type': 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(data ? JSON.parse(data) : {});
          } catch (e) {
            resolve(data);
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ── Commands ─────────────────────────────────────────────────────────────────

async function resolveAppId(jwtToken) {
  // Find the app's numeric App Store ID from its bundle ID.
  const res = await apiRequest(
    'GET',
    `/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}`,
    jwtToken
  );
  if (!res.data || res.data.length === 0) {
    throw new Error(`No app found for bundle ID ${BUNDLE_ID}`);
  }
  return res.data[0].id;
}

async function cmdList(args) {
  const includeExpired = args.includes('--all');
  const jwtToken = makeJWT();
  const appId = await resolveAppId(jwtToken);

  // Fetch builds sorted newest-first. Page size 200 is the max.
  let filter = `filter[app]=${appId}`;
  if (!includeExpired) filter += '&filter[expired]=false';
  const res = await apiRequest(
    'GET',
    `/v1/builds?${filter}&sort=-uploadedDate&limit=200`,
    jwtToken
  );

  const builds = res.data || [];
  console.log(`Found ${builds.length} build(s) for ${BUNDLE_ID}:`);
  console.log('');
  console.log('ID                                     | Version    | Build | Expired | Processed | Uploaded');
  console.log('-'.repeat(110));
  for (const b of builds) {
    const a = b.attributes;
    const uploaded = a.uploadedDate ? a.uploadedDate.slice(0, 16).replace('T', ' ') : '?';
    const row = [
      b.id.padEnd(38),
      (a.version || '?').padEnd(10),
      (a.buildAudienceType || '').padEnd(0),
      (a.processingState || '?').padEnd(9),
    ];
    console.log(
      `${b.id.padEnd(38)} | ${(a.version || '?').padEnd(10)} | ${(a.expirationDate ? 'exp ' + a.expirationDate.slice(0, 10) : 'live').padEnd(5)} | ${String(a.expired).padEnd(7)} | ${(a.processingState || '?').padEnd(9)} | ${uploaded}`
    );
  }
}

async function cmdExpire(buildIds) {
  if (buildIds.length === 0) {
    console.error('Usage: expire <buildId> [<buildId> ...]');
    process.exit(1);
  }
  const jwtToken = makeJWT();
  for (const id of buildIds) {
    try {
      await apiRequest('PATCH', `/v1/builds/${id}`, jwtToken, {
        data: {
          type: 'builds',
          id,
          attributes: { expired: true },
        },
      });
      console.log(`✓ Expired ${id}`);
    } catch (e) {
      console.error(`✗ Failed to expire ${id}: ${e.message}`);
    }
  }
}

async function cmdExpireCleanup() {
  // Propose which builds to expire: keep the newest LIVE build of each
  // marketing version, flag all older LIVE builds of the same marketing
  // version as candidates. Never expires anything — just prints the plan.
  const jwtToken = makeJWT();
  const appId = await resolveAppId(jwtToken);
  const res = await apiRequest(
    'GET',
    `/v1/builds?filter[app]=${appId}&filter[expired]=false&sort=-uploadedDate&limit=200`,
    jwtToken
  );
  const builds = (res.data || []).map((b) => ({
    id: b.id,
    version: b.attributes.version,
    marketingVersion: b.attributes.version, // build number
    uploadedDate: b.attributes.uploadedDate,
    processingState: b.attributes.processingState,
  }));

  // We need the preReleaseVersion (the 2.8.x) too, which is a relationship.
  // Fetch it in a second pass.
  const fullBuilds = [];
  for (const b of builds) {
    const full = await apiRequest(
      'GET',
      `/v1/builds/${b.id}?include=preReleaseVersion`,
      jwtToken
    );
    const preReleaseVersionId = full.data.relationships.preReleaseVersion.data.id;
    const included = (full.included || []).find((i) => i.id === preReleaseVersionId);
    b.marketingVersion = included ? included.attributes.version : '?';
    fullBuilds.push(b);
  }

  // Group by marketingVersion, keep newest, flag rest.
  const byVersion = {};
  for (const b of fullBuilds) {
    (byVersion[b.marketingVersion] = byVersion[b.marketingVersion] || []).push(b);
  }

  console.log('Cleanup plan (DRY RUN — nothing expired):');
  console.log('');
  const toExpire = [];
  for (const [version, list] of Object.entries(byVersion)) {
    list.sort((a, b) => (b.uploadedDate || '').localeCompare(a.uploadedDate || ''));
    const keep = list[0];
    const rest = list.slice(1);
    console.log(`── ${version} (${list.length} live build${list.length > 1 ? 's' : ''}) ──`);
    console.log(`   KEEP     ${keep.id}  build ${keep.version}  ${keep.uploadedDate}`);
    for (const r of rest) {
      console.log(`   EXPIRE   ${r.id}  build ${r.version}  ${r.uploadedDate}`);
      toExpire.push(r.id);
    }
    console.log('');
  }

  if (toExpire.length === 0) {
    console.log('Nothing to expire — every marketing version has just one live build.');
    return;
  }

  console.log(`Total candidates to expire: ${toExpire.length}`);
  console.log('');
  console.log('To actually expire them, run:');
  console.log(`   node tools/appstoreconnect.js expire ${toExpire.join(' ')}`);
}

// ── Dispatch ─────────────────────────────────────────────────────────────────

async function main() {
  const [cmd, ...args] = process.argv.slice(2);
  switch (cmd) {
    case 'list':
      await cmdList(args);
      break;
    case 'expire':
      await cmdExpire(args);
      break;
    case 'expire-cleanup':
      await cmdExpireCleanup();
      break;
    default:
      console.log('Usage: node tools/appstoreconnect.js <command>');
      console.log('Commands:');
      console.log('  list [--all]           List current TestFlight builds');
      console.log('  expire-cleanup         Propose a cleanup plan (dry run)');
      console.log('  expire <id> [<id>...]  Expire specific build IDs');
      process.exit(1);
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
