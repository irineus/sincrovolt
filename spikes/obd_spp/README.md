# spike OBD (EVAPP-11) — descartável

App Android mínimo que fala com o ELM327 KONNWEI por **Bluetooth Clássico (SPP)**, para
provar que o SincroVolt consegue fazer sozinho o que o Car Scanner faz, e para descobrir
o endereço e os DIDs do BMS do Haval H6 GT. Código de aprendizado: não vai para `apps/`.

- `applicationId`: `com.sincrovolt.spike.obd` (nome na tela: **spike OBD**). Não colide com o
  `com.sincrovolt.app`.
- Flutter 3.50.1 (`.fvmrc`), Gradle 9.5.0 / AGP 9.3.3 / KGP 2.4.20, Material por
  `package:material_ui`. Sem dependência nova além das do app.
- SPP por canal de plataforma próprio em Kotlin (`MainActivity.kt`, UUID
  `00001101-0000-1000-8000-00805F9B34FB`, tenta RFCOMM seguro e depois inseguro), atrás
  da interface Dart `TransporteSpp`.

## Segurança: OBD só leitura

`lib/nucleo/comandos_permitidos.dart` é o **único caminho até o socket**: o transporte só
aceita um `Permitido`, e um `Permitido` só nasce na função `avaliar()`. O Kotlin tem uma
segunda trava, só de formato (`[0-9A-Z]{1,8}` + CR, ou o espaço que encerra o ATMA).

| Permitido | |
|---|---|
| AT de configuração | `ATZ` `ATE0` `ATL0` `ATS0` `ATH1` `ATSP0` `ATDP` `ATRV` `ATAT0-2` `ATSThh` |
| Cabeçalho e filtro | `ATSH7xx` `ATCRA7xx` (só 11 bits, faixa de diagnóstico 7xx) |
| Monitor | `ATMA`; encerramento = **um espaço sem CR** (um CR sozinho repetiria o último comando) |
| OBD/UDS | `01xx`, `09xx`, `22xxxx` (um PID/DID por pedido) |

Tudo o mais é recusado **antes de sair**, com o motivo na tela e no log: inclusive `04`,
`10`, `11`, `14`, `27`, `2E`, `2F`, `31`, `3B`, `3E`, `85`, comando vazio, CR, `;` e lixo.
Teste-portão: `test/comandos_permitidos_test.dart` (101 casos). Prova negativa feita na
sessão de 28/11/2026: com o modo 01 afrouxado para "qualquer hex", 40 casos reprovaram.

## Telas

| Aba | O que faz |
|---|---|
| **a. Conectar** | Pede `BLUETOOTH_CONNECT` e `BLUETOOTH_SCAN` (Android 12+), lista os aparelhos **já pareados** (nome, MAC, tipo clássico/LE/duplo) e conecta. Mostra há quanto tempo está conectado; aviso aos 25 min e alerta vermelho aos 30 min (tirar o adaptador: bateria 12 V). Tela fica ligada enquanto conectado. |
| **b. Sequência** | Um toque: `ATZ, ATE0, ATL0, ATH1, ATSP0, 0100, 0902, 01A6, 015B, 019A`, com tempo de cada pedido, resposta bruta e decodificada. VIN mascarado na tela (botão "Mostrar VIN" só para conferir). |
| **c. Console** | Campo livre + atalhos. Passa pela lista; recusa aparece em vermelho. `ATMA` liga o monitor (só escuta), que **para sozinho em 30 s** ou no botão. |
| **d. Taxa** | Escolha os pedidos (`015B`, `019A`, `01A6`, `010C`, `012F` ou `CAB:22DDDD`), a duração e a pausa; roda em rodízio e mostra amostras/s, intervalo médio, falhas, suspeitas e latência por sinal. O resumo vai para o log. |
| **e. Varredura** | Só modo 22. Cabeçalho (`7xx` ou faixa `7xx-7yy`) e DIDs (`XXXX` ou faixa, até 4096), pausa entre pedidos, filtro de resposta `cabeçalho + 8` (`ATCRA`). `7F 22 31` = DID inexistente, segue. **Para sozinha** em `7F 22 33`, `7F 22 7E` ou `7F 22 7F` com "PARE E PERGUNTE". `7F 22 11` pula o cabeçalho; N sem resposta seguidas = cabeçalho mudo, pula. |
| **f. Log** | Hora (ms) de cada pedido e resposta, latência, recusas e notas. **Copiar log** e **Compartilhar** entregam o texto com o VIN mascarado (3 primeiros caracteres), inclusive no hex da resposta bruta. |

Decodificação (Dart puro, `lib/nucleo/`): VIN multiquadro (ISO-TP, com ou sem
cabeçalho), `01A6` × 0,1 km, `015B` = A × 100/255 (e ÷ 0,95 para comparar com o painel),
`019A` tensão ÷ 64 V e corrente × 0,1 A com sinal (positiva = descarga), DIDs com
leituras candidatas (u8, u16, s16, ASCII). O filtro de plausibilidade **marca** (não
descarta) o absurdo: Bus current −1200 A, célula 7.462 mV, hodômetro que volta, SoC que
salta.

## Instalar no Galaxy

1. GitHub → Actions → **spike-apk** → último run verde → artifact **spike-obd-apk** (zip
   com `app-debug.apk`, retenção 14 dias).
2. No celular, abra o `app-debug.apk` e permita "instalar apps desconhecidos" para o app
   que abriu o arquivo.
3. Cada build do CI usa uma chave debug diferente: para atualizar, **desinstale o "spike
   OBD"** antes de instalar o novo.
4. Na primeira abertura: aba **a** → "Permissões e pareados" → **Permitir** em
   "Dispositivos próximos". O KONNWEI precisa estar pareado antes nas configurações de
   Bluetooth do Android.

## Rodar aqui

```
cd spikes/obd_spp
fvm flutter analyze --fatal-infos
fvm flutter test
fvm flutter build apk --debug
```
