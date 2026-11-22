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

## Como configurar e rodar

Veja o bloco **⚠️ Ação sua** na conversa da sessão (ou o resumo do card) para o passo a
passo com os caminhos exatos: criar a pasta, pôr os três certificados e o `config.json`,
e rodar `node tool/poc_nuvem_gwm/poc_gwm.js`. O arquivo `config.exemplo.json` ao lado
mostra os campos.
