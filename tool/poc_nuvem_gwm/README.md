# PoC — leitura da nuvem GWM (EVAPP-9)

Prova de conceito **descartável** e **só leitura** que descobre quais dados a nuvem da
GWM Brasil (My GWM) expõe para o Haval H6 GT, e com que latência. Não é código de
produção nem do núcleo — é um script em `tool/` para fechar o EVAPP-9.

- **Faz:** lista os veículos da conta, lê o último status (SoC, autonomias, hodômetro,
  combustível, pneus, estado de recarga…) duas vezes para medir latência, e lê o
  histórico de recargas. Escreve um relatório em Markdown **já com o VIN mascarado e o
  GPS ocultado**, pronto para colar no Notion.
- **Não faz:** nenhum comando/escrita no carro. Os endpoints de comando (`sendCmd`,
  `setChargingPlan`) foram deixados de fora de propósito — o card é só leitura.
- **Não tem na nuvem:** SoH, tensão/corrente da bateria de tração, kWh recarregado.
  Esses só saem pelo OBD/BMS (EVAPP-7/8).

O contrato da API (login, assinatura das requisições, endpoints) foi levantado como
**referência** do projeto público `havaleiros/hassio-haval-h6-to-mqtt` — sem copiar
código (CLAUDE.md, regra 8). Caminho não oficial: usa certificado de cliente da GWM e
pode violar os termos de uso (Decisões vigentes, seção 5).

## Por que Node, e não Dart

O gateway `br-app-gateway.gwmcloud.com` exige TLS com cifras antigas (`@SECLEVEL=0`),
que o `HttpClient` do Dart (BoringSSL) recusa e o Node negocia. Como é um PoC
descartável, roda em **Node.js puro, sem dependências** (só `https`/`crypto`). Requer
Node 18+ (testado no 24).

## Nada sensível no repo

E-mail, senha, certificados e as constantes de assinatura **moram fora do repo**, em:

```
%USERPROFILE%\.sincrovolt\gwm\
├─ config.json          (email, signAppId, signHash, vin opcional)
├─ certs\
│  ├─ gwm_general.cer   (certificado de cliente)
│  ├─ gwm_general.key   (chave privada)
│  └─ gwm_root.cer      (cadeia/raiz)
├─ deviceid.txt         (gerado na 1ª execução)
└─ saida\               (relatórios gerados)
```

A senha nunca vai para arquivo nem para o repo: o script pergunta na hora (ou lê da
variável de ambiente `GWM_SENHA`, se você preferir).

## Certificado e assinatura

O gateway de leitura exige um certificado de cliente (mTLS), e toda requisição leva uma
assinatura SHA-256 feita com duas constantes do app My GWM. As duas coisas estão no
repositório de referência `havaleiros/hassio-haval-h6-to-mqtt`:

| O quê | Onde no repo de referência | Para onde vai |
|---|---|---|
| `gwm_general.cer`, `gwm_general.key`, `gwm_root.cer` | `haval-h6-mqtt/certs/` | `%USERPROFILE%\.sincrovolt\gwm\certs\` |
| `appKey` | `haval-h6-mqtt/signing.js` | campo `signAppId` do `config.json` |
| `appSecret` | `haval-h6-mqtt/signing.js` | campo `signHash` do `config.json` |

Nenhum desses valores entra neste repo.

## Como configurar e rodar (Windows, PowerShell)

1. Crie a pasta e baixe os três certificados:

   ```powershell
   $dir = "$env:USERPROFILE\.sincrovolt\gwm"
   New-Item -ItemType Directory -Force "$dir\certs" | Out-Null
   $base = "https://raw.githubusercontent.com/havaleiros/hassio-haval-h6-to-mqtt/main/haval-h6-mqtt/certs"
   foreach ($f in "gwm_general.cer", "gwm_general.key", "gwm_root.cer") { Invoke-WebRequest "$base/$f" -OutFile "$dir\certs\$f" }
   ```

2. Copie `config.exemplo.json` para `%USERPROFILE%\.sincrovolt\gwm\config.json` e preencha:
   `email` (login do My GWM), `signAppId` e `signHash` (tabela acima). `vin` é opcional —
   vazio usa o primeiro carro da conta.

3. Rode a partir da raiz do repo:

   ```powershell
   node tool/poc_nuvem_gwm/poc_gwm.js
   ```

   O script pede a senha do My GWM (não aparece na tela; ou defina `$env:GWM_SENHA` antes).
   No primeiro acesso de um dispositivo novo, a GWM manda um **código por e-mail** e o
   script pede esse código.

4. O relatório sai na tela e em `%USERPROFILE%\.sincrovolt\gwm\saida\relatorio-*.md`, com o
   VIN mascarado (inclusive dentro de `deviceId`/`id`) e o GPS ocultado.

Rode de preferência logo depois de usar o carro: a nuvem guarda o último estado que o carro
enviou, não o estado em tempo real.

## Teste

`node tool/poc_nuvem_gwm/teste_mascara.js` prova, sem rede, que o relatório não vaza VIN
nem coordenada GPS.
