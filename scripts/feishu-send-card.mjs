#!/usr/bin/env node
/**
 * feishu-send-card.mjs — Send a Feishu interactive card via Feishu Open API.
 *
 * Usage:
 *   node feishu-send-card.mjs <target> <card-json-file-or-string>
 *
 * Examples:
 *   node feishu-send-card.mjs oc_064185c1b26c9f9c6a78f4a51dd04713 '{"schema":"2.0",...}'
 *   node feishu-send-card.mjs oc_064185c1b26c9f9c6a78f4a51dd04713 card.json
 *
 * Environment:
 *   OPENCLAW_CONFIG_PATH — Path to openclaw.json (default: ~/.openclaw/openclaw.json)
 *   FEISHU_APP_ID        — Override appId from config
 *   FEISHU_APP_SECRET    — Override appSecret from config
 */

import { readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

// ── Load openclaw config ──────────────────────────────────────────────────────
const configPath = process.env.OPENCLAW_CONFIG_PATH || join(homedir(), '.openclaw', 'openclaw.json');
let cfg;
try {
  cfg = JSON.parse(readFileSync(configPath, 'utf8'));
} catch (err) {
  console.error(`ERROR: Cannot read openclaw config at ${configPath}`);
  console.error(err.message);
  process.exit(1);
}

const feishuCfg = cfg.channels?.feishu;
if (!feishuCfg || !feishuCfg.enabled) {
  console.error('ERROR: Feishu channel not enabled in openclaw config');
  process.exit(1);
}

const appId = process.env.FEISHU_APP_ID || feishuCfg.appId;
const appSecret = process.env.FEISHU_APP_SECRET || feishuCfg.appSecret;
const domain = feishuCfg.domain || 'feishu';

if (!appId || !appSecret) {
  console.error('ERROR: Feishu appId and appSecret required in config or env');
  process.exit(1);
}

const apiBase = domain === 'lark' ? 'https://open.larksuite.com/open-apis' : 'https://open.feishu.cn/open-apis';

// ── Parse arguments ───────────────────────────────────────────────────────────
const [, , target, cardArg] = process.argv;
if (!target || !cardArg) {
  console.error('Usage: node feishu-send-card.mjs <target> <card-json-file-or-string>');
  process.exit(1);
}

let card;
try {
  card = JSON.parse(cardArg);
} catch {
  try {
    const cardJson = readFileSync(cardArg, 'utf8');
    card = JSON.parse(cardJson);
  } catch (err) {
    console.error(`ERROR: Cannot parse card JSON from argument or file: ${cardArg}`);
    console.error(err.message);
    process.exit(1);
  }
}

// ── Get tenant access token ───────────────────────────────────────────────────
async function getTenantAccessToken() {
  const response = await fetch(`${apiBase}/auth/v3/tenant_access_token/internal`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ app_id: appId, app_secret: appSecret }),
  });
  const data = await response.json();
  if (data.code !== 0 || !data.tenant_access_token) {
    throw new Error(`Get tenant_access_token failed: ${data.msg || JSON.stringify(data)}`);
  }
  return data.tenant_access_token;
}

// ── Send card ─────────────────────────────────────────────────────────────────
async function sendCard(token, receiveId, cardContent) {
  const response = await fetch(`${apiBase}/im/v1/messages?receive_id_type=open_id`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      receive_id: receiveId,
      msg_type: 'interactive',
      content: JSON.stringify(cardContent),
    }),
  });
  const data = await response.json();
  if (data.code !== 0) {
    throw new Error(`Send card failed: ${data.msg || JSON.stringify(data)}`);
  }
  return data.data;
}

// ── Main ──────────────────────────────────────────────────────────────────────
try {
  const token = await getTenantAccessToken();
  const result = await sendCard(token, target, card);
  console.log(`✅ Card sent successfully`);
  console.log(`Message ID: ${result.message_id || 'unknown'}`);
  console.log(`Chat ID: ${result.chat_id || target}`);
} catch (err) {
  console.error('ERROR: Failed to send card');
  console.error(err.message);
  process.exit(1);
}
