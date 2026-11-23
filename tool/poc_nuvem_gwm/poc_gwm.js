#!/usr/bin/env node
// tool/poc_nuvem_gwm/poc_gwm.js — PoC descartável do EVAPP-9 (SincroVolt).
//
// O QUE FAZ: lê, SÓ LEITURA, os dados que a nuvem da GWM Brasil expõe para o
// carro do usuário (lista de veículos, último status e histórico de recargas),
// mede a latência carro→nuvem e escreve um relatório já mascarado (VIN e GPS)
// pronto para colar no Notion.
//
// O QUE NÃO FAZ: nenhum comando/escrita no carro. Os endpoints de comando
// (sendCmd, setChargingPlan) NÃO estão aqui, de propósito (card é "só leitura").
//
// Node.js puro, sem dependências (built-ins https/crypto/fs). É um PoC em tool/,
// não é código de produção nem do núcleo.
//
// Nada sensível mora neste arquivo: e-mail, senha, certificados e as constantes
// de assinatura ficam na PASTA LOCAL fora do repo. Ver README.md.
//
// Contrato da API (login, assinatura, endpoints) levantado como REFERÊNCIA do
// projeto público havaleiros/hassio-haval-h6-to-mqtt (sem copiar código).

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const https = require('https');
const crypto = require('crypto');
const readline = require('readline');

// --------------------------------------------------------------- endpoints/fatos
const EP = {
  login: 'https://br-h5-gateway.gwmcloud.com/app-api/api/v2.0',
  h5: 'https://br-h5-gateway.gwmcloud.com/app-api/api/v1.0',
  veiculo: 'https://br-app-gateway.gwmcloud.com/app-api/api/v1.0',
};

const APP_HEADERS = {
  rs: '2', terminal: 'GW_APP_GWM', brand: '6', language: 'pt_BR',
  systemtype: '2', regioncode: 'BR', country: 'BR', appid: '6',
  enterpriseid: 'CC01', channel: 'APP', cver: '1.4.2',
  'User-Agent': 'okhttp/4.9.3', accept: 'application/json',
};

// Dicionário mínimo de sinais (código → rótulo). Fatos públicos (nomes de sinais),
// usados como referência; o que não estiver aqui sai cru no relatório.
const SINAIS = {
  '2103010': { nome: 'Quilometragem total', unid: 'km' },
  '2013021': { nome: 'SoC da bateria de tração', unid: '%' },
  '2013005': { nome: 'SoC da bateria 12 V', unid: '%' },
  '2011501': { nome: 'Autonomia EV', unid: 'km' },
  '2011007': { nome: 'Autonomia combustão', unid: 'km' },
  '2017002': { nome: 'Nível de combustível', unid: 'L' },
  '2041142': { nome: 'Estado da carga', unid: '0=desconect. 1=carregando 3=concluído 5=aguardando' },
  '2013022': { nome: 'Tempo de carga', unid: 'min' },
  '2042071': { nome: 'Temperatura das baterias', unid: '' },
  '2101001': { nome: 'Pressão pneu diant. esq.', unid: 'kPa' },
  '2101002': { nome: 'Pressão pneu diant. dir.', unid: 'kPa' },
  '2101004': { nome: 'Pressão pneu tras. dir.', unid: 'kPa' },
  '2101003': { nome: 'Pressão pneu tras. esq.', unid: 'kPa' },
};

// Campos/códigos que são localização: nunca sair com valor (regra 3 do CLAUDE.md).
const GPS_RE = /lat|lon|lng|gps|coordinate|位置/i;

// --------------------------------------------------------------- utilidades
function morrer(msg) { console.error(`\n[ERRO] ${msg}`); process.exit(1); }

function mascararVin(v) {
  const s = String(v || '');
  if (s.length <= 3) return s;
  return s.slice(0, 3) + '*'.repeat(s.length - 3);
}

function pastaConfig() {
  return process.env.SINCROVOLT_GWM_DIR || path.join(os.homedir(), '.sincrovolt', 'gwm');
}

function carregarConfig() {
  const dir = pastaConfig();
  const cfgPath = path.join(dir, 'config.json');
  if (!fs.existsSync(cfgPath)) {
    morrer(`não achei ${cfgPath}. Crie a pasta e os arquivos conforme o README.md.`);
  }
  let cfg;
  try { cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); }
  catch (e) { morrer(`config.json inválido: ${e.message}`); }
  for (const campo of ['email', 'signAppId', 'signHash']) {
    if (!cfg[campo]) morrer(`config.json sem o campo obrigatório "${campo}".`);
  }
  const certsDir = path.join(dir, 'certs');
  const lerCert = (nome) => {
    const p = path.join(certsDir, nome);
    if (!fs.existsSync(p)) morrer(`certificado ausente: ${p} (ver README.md).`);
    return fs.readFileSync(p, 'utf8');
  };
  cfg._dir = dir;
  cfg._cert = lerCert('gwm_general.cer');
  cfg._key = lerCert('gwm_general.key');
  cfg._root = lerCert('gwm_root.cer');
  cfg.countryCode = cfg.countryCode || '55';
  cfg.pollGapSeconds = Number(cfg.pollGapSeconds || 30);
  return cfg;
}

function deviceId(dir) {
  const p = path.join(dir, 'deviceid.txt');
  try {
    const v = fs.readFileSync(p, 'utf8').trim();
    if (/^[0-9a-f]{32}$/.test(v)) return v;
  } catch (_) { /* gera abaixo */ }
  const novo = crypto.randomBytes(16).toString('hex');
  try { fs.writeFileSync(p, novo); } catch (_) { /* segue sem persistir */ }
  return novo;
}

// Pergunta na linha de comando. Com oculto=true e um terminal de verdade (TTY),
// lê em raw mode sem ecoar a senha. O prompt é sempre escrito com um write
// direto ANTES de qualquer coisa, então ele sempre aparece. Sem TTY (entrada
// redirecionada), cai no readline normal — mostra o prompt e lê a linha.
function perguntar(texto, oculto = false) {
  const stdin = process.stdin;
  if (oculto && stdin.isTTY && typeof stdin.setRawMode === 'function') {
    return new Promise((resolve) => {
      process.stdout.write(texto);
      let buf = '';
      stdin.resume();
      stdin.setRawMode(true);
      const onData = (d) => {
        for (const ch of d.toString('utf8')) {
          if (ch === '\r' || ch === '\n') {
            stdin.setRawMode(false); stdin.pause(); stdin.removeListener('data', onData);
            process.stdout.write('\n'); resolve(buf.trim()); return;
          } else if (ch === '\u0003') { // Ctrl+C
            stdin.setRawMode(false); process.stdout.write('\n'); process.exit(1);
          } else if (ch === '\u007f' || ch === '\b') {
            buf = buf.slice(0, -1);
          } else if (ch >= ' ') {
            buf += ch;
          }
        }
      };
      stdin.on('data', onData);
    });
  }
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: stdin, output: process.stdout });
    rl.question(texto, (ans) => { rl.close(); resolve(ans.trim()); });
  });
}

// --------------------------------------------------------------- assinatura
// SHA-256 de encodeURIComponent(METHOD + path + auth + parâmetros + hash).
// Parâmetros: query (+ 'json'=corpo no POST), chaves ordenadas, espaços removidos.
function assinar(method, urlStr, corpo, cfg) {
  const u = new URL(urlStr);
  const m = new Map();
  for (const [k, v] of u.searchParams.entries()) m.set(k, v);
  if (method === 'POST' && corpo != null) m.set('json', corpo);
  const params = [...m.keys()].sort()
    .map((k) => `${k}=${String(m.get(k)).replace(/ /g, '')}`).join('');
  const nonce = crypto.randomBytes(8).toString('hex');
  const ts = String(Date.now());
  const auth = `gwm-auth-appkey:${cfg.signAppId}gwm-auth-nonce:${nonce}gwm-auth-timestamp:${ts}`;
  const raw = method + u.pathname + auth + params + cfg.signHash;
  const sign = crypto.createHash('sha256').update(encodeURIComponent(raw), 'utf8').digest('hex');
  return {
    'gwm-auth-appkey': cfg.signAppId,
    'gwm-auth-nonce': nonce,
    'gwm-auth-timestamp': ts,
    'gwm-auth-sign': sign,
  };
}

// --------------------------------------------------------------- HTTP
function req(method, urlStr, { corpo, extraHeaders = {}, agent } = {}, cfg) {
  const bodyStr = corpo != null ? JSON.stringify(corpo) : undefined;
  const headers = { ...APP_HEADERS, ...extraHeaders, ...assinar(method, urlStr, bodyStr ?? null, cfg) };
  if (bodyStr !== undefined) headers['content-type'] = 'application/json';
  const u = new URL(urlStr);
  const opts = { method, hostname: u.hostname, path: u.pathname + u.search, headers, agent, timeout: 20000 };
  return new Promise((resolve, reject) => {
    const r = https.request(opts, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(data); } catch (_) { /* deixa cru */ }
        resolve({ status: res.statusCode, json, raw: data });
      });
    });
    r.on('error', reject);
    r.on('timeout', () => { r.destroy(new Error('timeout de 20s')); });
    if (bodyStr !== undefined) r.write(bodyStr);
    r.end();
  });
}

function agenteVeiculo(cfg) {
  return new https.Agent({
    cert: `${cfg._cert.trim()}\n${cfg._root.trim()}\n`,
    key: cfg._key,
    minVersion: 'TLSv1.2',
    ciphers: 'DEFAULT:@SECLEVEL=0',
    rejectUnauthorized: false, // PoC: só leitura; evita tropeço de cadeia de CA
  });
}

// --------------------------------------------------------------- login
async function login(cfg, dev) {
  const account = String(cfg.email).trim();
  const accountType = account.includes('@') ? '2' : '1';
  const extra = { deviceId: dev, iccid: dev };
  const agent = new https.Agent();
  const senha = process.env.GWM_SENHA || await perguntar('Senha do My GWM (não aparece): ', true);
  if (!senha) morrer('senha vazia.');

  const payload = {
    account, accountType, countryCode: cfg.countryCode, agreement: [1, 2],
    password: senha, deviceId: dev, appType: '0', pushToken: null, country: 'BR',
  };

  let r = await req('POST', `${EP.login}/userAuth/loginWithPassword`, { corpo: payload, extraHeaders: extra, agent }, cfg);
  let d = r.json;

  if (d && d.code === '308103') {
    console.log('\n[info] A GWM exige verificação deste dispositivo (código 308103).');
    await req('POST', `${EP.login}/userAuth/getVerifyCode`, {
      corpo: { type: '17', account, accountType, countryCode: cfg.countryCode, validCodeMode: 1, operateCode: '', captchaType: '', captchaId: '', token: '' },
      extraHeaders: extra, agent,
    }, cfg);
    console.log('[info] Pedi o código por e-mail. Veja a caixa de entrada da conta GWM.');
    const code = process.env.GWM_VERIFY_CODE || await perguntar('Código recebido por e-mail: ');
    if (!code) morrer('código de verificação vazio.');
    const chk = await req('POST', `${EP.login}/userAuth/checkVerifyCode`, {
      corpo: { type: '17', account, accountType, countryCode: cfg.countryCode, validCodeMode: 1, verifyCode: code },
      extraHeaders: extra, agent,
    }, cfg);
    if (!chk.json || chk.json.code !== '000000') {
      morrer(`código rejeitado: ${chk.json ? chk.json.code + ' ' + chk.json.description : 'resposta inválida'}`);
    }
    r = await req('POST', `${EP.login}/userAuth/loginWithPassword`, {
      corpo: { ...payload, verifyCode: code, validCodeMode: '1' }, extraHeaders: extra, agent,
    }, cfg);
    d = r.json;
  }

  if (d && d.code === '000000' && d.data && d.data.accessToken) {
    return { accessToken: d.data.accessToken, refreshToken: d.data.refreshToken || '', gwId: d.data.gwId != null ? String(d.data.gwId) : '' };
  }
  morrer(`login falhou: ${d ? 'code=' + d.code + ' ' + d.description : 'HTTP ' + r.status}`);
}

function headersVeiculo(sess, dev) {
  const h = { accessToken: sess.accessToken, refreshToken: sess.refreshToken || '', deviceId: dev, iccid: dev };
  if (sess.gwId) h.gwId = sess.gwId;
  return h;
}

// --------------------------------------------------------------- leitura
async function acquireVehicles(cfg, sess, dev, agent) {
  const r = await req('GET', `${EP.veiculo}/globalapp/vehicle/acquireVehicles`, { extraHeaders: headersVeiculo(sess, dev), agent }, cfg);
  if (!r.json || r.json.code !== '000000') morrer(`acquireVehicles: ${r.json ? r.json.code + ' ' + r.json.description : 'HTTP ' + r.status}`);
  return r.json.data;
}

async function getLastStatus(cfg, sess, dev, agent, vin) {
  const t0 = Date.now();
  const r = await req('GET', `${EP.veiculo}/vehicle/getLastStatus?vin=${encodeURIComponent(vin.toUpperCase())}&flag=true`, { extraHeaders: headersVeiculo(sess, dev), agent }, cfg);
  const t1 = Date.now();
  if (!r.json || r.json.code !== '000000') morrer(`getLastStatus: ${r.json ? r.json.code + ' ' + r.json.description : 'HTTP ' + r.status}`);
  return { data: r.json.data, rttMs: t1 - t0, pedidoEm: t0 };
}

async function getChargeLogs(cfg, sess, dev, agent, vin) {
  const r = await req('POST', `${EP.veiculo}/vehicleCharge/getChargeLogs`, {
    corpo: { vin: vin.toUpperCase(), pageNum: '1', pageSize: '100', continuation: '0' },
    extraHeaders: headersVeiculo(sess, dev), agent,
  }, cfg);
  if (!r.json || r.json.code !== '000000') return { erro: r.json ? r.json.code + ' ' + r.json.description : 'HTTP ' + r.status };
  return { lista: (r.json.data && r.json.data.list) || [] };
}

// --------------------------------------------------------------- relatório
function ehEpoch(v) { return typeof v === 'string' && /^\d{13}$/.test(v) || (typeof v === 'number' && v > 1e12); }

function linhasStatus(data) {
  const linhas = [];
  const itens = (data && data.items) || [];
  for (const it of itens) {
    const def = SINAIS[String(it.code)];
    const nome = def ? def.nome : `(código ${it.code})`;
    const unid = def ? def.unid : '';
    let valor = GPS_RE.test(nome) ? '[ocultado — GPS]' : it.value;
    linhas.push({ code: it.code, nome, valor, unid });
  }
  return linhas;
}

function topoNaoItens(data) {
  const extras = [];
  for (const [k, v] of Object.entries(data || {})) {
    if (k === 'items') continue;
    if (GPS_RE.test(k)) { extras.push([k, '[ocultado — GPS]']); continue; }
    extras.push([k, typeof v === 'object' ? JSON.stringify(v) : String(v)]);
  }
  return extras;
}

function fmtData(ms) {
  try { return new Date(ms).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }); }
  catch (_) { return String(ms); }
}

function montarRelatorio(cfg, vin, veics, s1, s2, charge) {
  const L = [];
  L.push(`# PoC nuvem GWM (EVAPP-9) — ${fmtData(Date.now())}`);
  L.push('');
  L.push('> Gerado por tool/poc_nuvem_gwm/poc_gwm.js. VIN mascarado, GPS ocultado. Só leitura.');
  L.push('');
  L.push(`- Veículos na conta: **${veics.length}**`);
  for (const v of veics) {
    const vv = v.vin || v.VIN || v.vehicleVin || '';
    L.push(`  - ${mascararVin(vv)}${v.vehicleName ? ' — ' + v.vehicleName : ''}`);
  }
  L.push(`- VIN analisado: **${mascararVin(vin)}**`);
  L.push('');

  // latência
  L.push('## Latência carro→nuvem');
  L.push(`- RTT da requisição (1ª leitura): **${s1.rttMs} ms**`);
  L.push(`- 1ª leitura pedida em: ${fmtData(s1.pedidoEm)}`);
  L.push(`- 2ª leitura pedida em: ${fmtData(s2.pedidoEm)} (intervalo ~${cfg.pollGapSeconds}s)`);
  // tenta achar timestamp do carro no topo
  const tsCampos1 = topoNaoItens(s1.data).filter(([, v]) => ehEpoch(v));
  if (tsCampos1.length) {
    L.push('- Campos com cara de timestamp no retorno (epoch ms):');
    for (const [k, v] of tsCampos1) L.push(`  - \`${k}\` = ${v} → ${fmtData(Number(v))} (idade ~${Math.round((s1.pedidoEm - Number(v)) / 1000)}s)`);
  } else {
    L.push('- Não identifiquei automaticamente um timestamp do carro no retorno (ver campos de topo abaixo).');
  }
  L.push('');

  // mudanças entre as duas leituras
  const map1 = new Map(linhasStatus(s1.data).map((l) => [String(l.code), l.valor]));
  const map2 = new Map(linhasStatus(s2.data).map((l) => [String(l.code), l.valor]));
  const mudou = [];
  for (const [code, v2] of map2) if (map1.get(code) !== v2) mudou.push(code);
  L.push(`- Sinais que mudaram entre as duas leituras: **${mudou.length}**${mudou.length ? ' (' + mudou.join(', ') + ')' : ''}`);
  L.push('');

  // status
  L.push('## Último status (getLastStatus)');
  L.push('| Código | Sinal | Valor | Unidade |');
  L.push('|---|---|---|---|');
  for (const l of linhasStatus(s1.data)) L.push(`| ${l.code} | ${l.nome} | ${l.valor} | ${l.unid} |`);
  L.push('');
  const extras = topoNaoItens(s1.data);
  if (extras.length) {
    L.push('### Campos de topo (fora de items)');
    L.push('| Campo | Valor |');
    L.push('|---|---|');
    for (const [k, v] of extras) L.push(`| ${k} | ${v} |`);
    L.push('');
  }

  // recargas
  L.push('## Histórico de recargas (getChargeLogs)');
  if (charge.erro) {
    L.push(`- Erro: ${charge.erro}`);
  } else {
    L.push(`- Registros retornados: **${charge.lista.length}**`);
    for (const c of charge.lista.slice(0, 5)) {
      const ini = c.startTime ? fmtData(Number(c.startTime)) : '?';
      const fim = c.endTime ? fmtData(Number(c.endTime)) : '?';
      L.push(`  - ${ini} → ${fim}`);
    }
    if (charge.lista.length > 5) L.push(`  - … (+${charge.lista.length - 5})`);
  }
  L.push('');
  L.push('## Riscos (lembrete)');
  L.push('- Caminho não oficial: certificado de cliente da GWM; pode violar termos de uso e quebrar sem aviso.');
  L.push('- É o último estado que o carro enviou à nuvem, não tempo real.');
  L.push('- Não há SoH, nem tensão/corrente da bateria de tração, nem kWh recarregado (esses só pelo OBD/BMS — EVAPP-7/8).');
  return L.join('\n');
}

// --------------------------------------------------------------- main
async function main() {
  const cfg = carregarConfig();
  const dev = deviceId(cfg._dir);
  console.log(`[info] pasta de configuração: ${cfg._dir}`);
  console.log('[info] fazendo login...');
  const sess = await login(cfg, dev);
  console.log('[ok] autenticado.');

  const agent = agenteVeiculo(cfg);
  console.log('[info] listando veículos...');
  const veicsRaw = await acquireVehicles(cfg, sess, dev, agent);
  const veics = Array.isArray(veicsRaw) ? veicsRaw : (veicsRaw && veicsRaw.list) || [];
  if (!veics.length) morrer('nenhum veículo na conta.');
  const vin = cfg.vin || veics[0].vin || veics[0].VIN || veics[0].vehicleVin;
  if (!vin) morrer('não achei o VIN; preencha "vin" no config.json.');
  console.log(`[ok] ${veics.length} veículo(s). Analisando ${mascararVin(vin)}.`);

  console.log('[info] 1ª leitura de status...');
  const s1 = await getLastStatus(cfg, sess, dev, agent, vin);
  console.log(`[ok] status 1 (${s1.rttMs} ms). Aguardando ${cfg.pollGapSeconds}s para a 2ª...`);
  await new Promise((r) => setTimeout(r, cfg.pollGapSeconds * 1000));
  const s2 = await getLastStatus(cfg, sess, dev, agent, vin);
  console.log('[ok] status 2.');

  console.log('[info] histórico de recargas...');
  const charge = await getChargeLogs(cfg, sess, dev, agent, vin);
  console.log(`[ok] recargas: ${charge.erro ? 'erro ' + charge.erro : charge.lista.length + ' registro(s)'}.`);

  const rel = montarRelatorio(cfg, vin, veics, s1, s2, charge);
  const saidaDir = path.join(cfg._dir, 'saida');
  fs.mkdirSync(saidaDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const saidaPath = path.join(saidaDir, `relatorio-${ts}.md`);
  fs.writeFileSync(saidaPath, rel, 'utf8');

  console.log('\n' + '='.repeat(60));
  console.log(rel);
  console.log('='.repeat(60));
  console.log(`\n[ok] relatório salvo (já mascarado) em:\n  ${saidaPath}`);
}

if (require.main === module) {
  main().catch((e) => morrer(e && e.stack ? e.stack : String(e)));
}

// Exporta as funções puras para teste offline (sem rede).
module.exports = { mascararVin, assinar, montarRelatorio, linhasStatus, GPS_RE, perguntar };
