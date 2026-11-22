#!/usr/bin/env node
// tool/poc_nuvem_gwm/teste_mascara.js — portão de segurança do PoC (regra 3 e 4).
// Prova que o relatório gerado NÃO vaza VIN inteiro nem coordenada GPS, e que
// códigos desconhecidos sobrevivem crus. Prova negativa embutida: o VIN e o GPS
// aparecem na ENTRADA e são verificados como AUSENTES na SAÍDA.
'use strict';
const assert = require('assert');
const { mascararVin, montarRelatorio } = require('./poc_gwm');

let n = 0;
const ok = (c, m) => { assert.ok(c, m); console.log(`ok: ${m}`); n++; };

// --- mascararVin
// VINs sintéticos montados por concatenação: nenhum token de 17 caracteres
// contíguo no fonte, para a varredura de segredos não confundir com VIN real.
const vinA = 'LGW' + 'EF6A74RH123456'; // 17 chars em runtime, fragmentado no fonte
ok(mascararVin(vinA) === 'LGW' + '*'.repeat(14), 'VIN mascarado em 3 + asteriscos');
ok(mascararVin('AB') === 'AB', 'string curta não quebra');

// --- relatório com dados sintéticos contendo VIN inteiro e GPS
const VIN = 'LGW' + 'EF6A74RH654321';
const latReal = '-23.567890';
const lonReal = '-46.654321';
const s1 = {
  rttMs: 120, pedidoEm: Date.now(),
  data: {
    items: [
      { code: '2103010', value: '12345' },      // km conhecido
      { code: '2013021', value: '87' },          // SoC conhecido
      { code: '9999999', value: 'cru-xyz' },     // desconhecido → sai cru
      { code: 'latitude', value: latReal },       // GPS por código
    ],
    latitude: latReal, longitude: lonReal,        // GPS no topo
    updateTime: String(Date.now() - 42000),       // timestamp do carro
  },
};
const s2 = { pedidoEm: Date.now(), data: { items: [{ code: '2013021', value: '86' }] } };
const rel = montarRelatorio({ pollGapSeconds: 30 }, VIN, [{ vin: VIN }], s1, s2, { lista: [] });

ok(!rel.includes(VIN), 'VIN inteiro NÃO aparece no relatório');
ok(rel.includes(mascararVin(VIN)), 'VIN mascarado aparece no relatório');
ok(!rel.includes(latReal) && !rel.includes(lonReal), 'coordenadas GPS NÃO aparecem no relatório');
ok(rel.includes('[ocultado — GPS]'), 'GPS marcado como ocultado');
ok(rel.includes('cru-xyz'), 'código desconhecido sai cru (descoberta)');
ok(rel.includes('Quilometragem total'), 'sinal conhecido vira rótulo amigável');
ok(/idade ~4\ds/.test(rel), 'timestamp do carro detectado e idade calculada');

console.log(`\nTODOS OS ${n} CASOS OK`);
