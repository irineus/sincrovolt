# CLAUDE.md — Contexto do projeto para o Claude Code

## O que é o SincroVolt
App mobile de **gestão de carros eletrificados** (BEV, PHEV e HEV) no Brasil. Promessa:
"Você dirige; o app anota, calcula e avisa". O app coleta dados do carro em camadas (API
conectada → OBD-II → redes de recarga → celular → NFC-e/OCR → Open Finance → bases
públicas), usa a melhor fonte disponível e calcula custo, consumo e saúde da bateria.

- Veículo de referência: **GWM Haval H6 GT (PHEV)**, adaptador **ELM327 KONNWEI** (Bluetooth
  Clássico) e **Galaxy S26 Ultra**. Lançamento **Android-primeiro**; iPhone não fala com
  ELM327 Bluetooth Clássico (iOS só depois, via BLE/Wi-Fi).
- O planejamento vive FORA deste repo, no Notion: board "App Carros Eletrificados — Board de
  Cards" e a página **Decisões vigentes**. Sessões do Claude Code são **execução no
  repositório**, um card por vez. Use a skill **`/proximo-card`** (`.claude/skills/proximo-card/`)
  para descobrir o próximo card, iniciar, concluir e atualizar o board. Ela exige o
  **conector do Notion habilitado** na sessão; sem ele, diga isso e pare.
- **Decisões vigentes vence** este arquivo em caso de conflito: leia-a (a skill faz isso)
  antes de opinar sobre stack, regra de negócio ou fonte de dados.

## Decisões travadas (não reabrir, não "melhorar")
| Decisão | Valor | Origem |
|---|---|---|
| Nome do produto | **SincroVolt** (supera "Rodovolt" e "Voltis"; renomeação no EVAPP-74) | EVAPP-20 |
| `applicationId` / bundle id | **`com.sincrovolt.app`** | EVAPP-20 |
| App mobile | **Flutter 3.50.1 (stable, Dart 3.14.0)**, pinado por **FVM** (`.fvmrc` na raiz); Material por `package:material_ui` | EVAPP-24, EVAPP-75 |
| Bluetooth Clássico (SPP) | canal de plataforma **próprio em Kotlin** atrás de interface Dart | EVAPP-24 |
| BLE | `universal_ble` (BSD-3) | EVAPP-24 |
| Núcleo | **Dart puro** (`packages/sincrovolt_core`): ELM327/PIDs, custos, regras | EVAPP-24 |
| Pacotes vetados por licença | `flutter_blue_plus` (comercial paga), `flutter_blue_classic` (GPL-3.0) | EVAPP-24 |
| Backend e hospedagem | **a decidir (EVAPP-25)** | — |
| Local-first × nuvem | **a decidir (EVAPP-26)** | — |
| `minSdk` | padrão do Flutter até card próprio decidir | — |
| Convenções de código | `docs/convencoes.md` (parte **a definir no EVAPP-22**) | — |
| Glossário | `docs/glossario.md` (parte **a definir no EVAPP-21**) | — |

## Mapa de pastas
```
.fvmrc                       # pin do Flutter — só ele é versionado; .fvm/ não
apps/sincrovolt_app/         # app Flutter: só orquestra e apresenta (EVAPP-36)
packages/sincrovolt_core/    # Dart puro: parser ELM327/PIDs, motor de custos, regras
tool/setup_env.sh            # bootstrap idempotente Linux (nuvem e CI), versões fixadas
tool/setup_nuvem.sh          # setup script do ambiente de nuvem (≤ 100 linhas; mesmas versões)
tool/verificar_ambiente.dart # verifica se o ambiente bate com o que o repo declara
tool/verificador/regras.dart # regras puras do verificador (versão do Flutter, sdks dos pubspec.lock)
tool/testar_verificador.dart # prova negativa das regras do verificador (roda no CI)
tool/varrer_segredos.sh      # varredura de segredos (CI e antes de todo PR)
dados/fixtures/              # logs reais anonimizados (sem GPS, VIN mascarado)
docs/                        # glossário, convenções, ambiente
.claude/skills/proximo-card/ # skill do board no Notion
```

## Ambiente e comandos
Os três ambientes (nuvem, Windows com o Galaxy S26, CI) estão em `docs/ambiente.md`.
```
bash tool/setup_env.sh && source tool/env      # Linux: nuvem e CI
fvm dart run tool/verificar_ambiente.dart       # confere o ambiente (todos)
bash tool/varrer_segredos.sh                    # antes de todo commit/PR
cd packages/sincrovolt_core && fvm dart test
cd apps/sincrovolt_app && fvm flutter analyze && fvm flutter test
```
Se um download essencial falhar na nuvem, **pare e diga exatamente qual domínio foi
bloqueado**. Não contorne com mirror não oficial.

## Regras permanentes
1. **OBD é só leitura.** Nunca enviar modo `04` (apagar códigos de falha), comandos de
   escrita, codificação, adaptação ou reset de módulo — nem em teste, nem em simulador que
   depois rode no carro. Comando novo para o adaptador precisa estar numa lista
   explícita de comandos permitidos, com teste que reprova o que não estiver nela.
2. **O repositório é público** (decisão do usuário, para o CI não consumir minutos pagos).
   Tudo o que for commitado é visível para qualquer pessoa: escreva pensando nisso.
   **Segredos nunca entram no repositório nem em sessão de nuvem**: keystore, senhas,
   tokens (nuvem GWM, Open Finance), chaves de API, certificados. Rode
   `tool/varrer_segredos.sh` antes de todo PR. Credencial que o usuário precisa configurar
   vira bloco "Ação sua" com o nome do campo e de onde o valor sai, nunca o valor.
3. **Dados reais do carro**: fixture só entra **sem coordenadas GPS e com o VIN mascarado**
   (provisório até o EVAPP-22: só os 3 primeiros caracteres visíveis, o resto `*`). Logs brutos ficam fora do repo (`dados/brutos/` está no
   `.gitignore`).
4. **Prova negativa em todo teste-portão.** Teste, script ou verificação que decide se algo
   passa precisa ser visto **falhando** uma vez com a entrada errada antes de ser aceito.
   Mostre a falha na sessão.
5. **Dinheiro em centavos inteiros (`int`), nunca `double`/float**, em lugar nenhum: custo
   de recarga, combustível, manutenção, tarifa. Unidades de energia e distância: a definir
   no EVAPP-22 (até lá, pergunte antes de escolher).
6. **Todo card fecha oferecendo PR e merge.** Nenhum card termina em branch órfã: ao fechar,
   abra (ou ofereça abrir) o PR e ofereça o merge explicitamente. Código fora do `main` não
   conta como concluído. Branch: `evapp-<n>-<slug>`; commits em Conventional Commits com
   `EVAPP-<n>` no rodapé.
7. **Dúvida de regra = perguntar com opções fechadas.** Regra de negócio, de segurança
   veicular, fiscal ou jurídica ambígua: apresente opções fechadas (a/b) com um exemplo
   concreto que separe as leituras. Enquanto não fecha, o comportamento seguro é falhar
   visível.
8. **Toda dependência nova passa por checagem de licença** (MIT, BSD, Apache-2.0 ok;
   GPL/AGPL/licença comercial = perguntar antes). Código de projetos da comunidade
   (HavalShisuku, hassio-haval-h6-to-mqtt) é só referência de nomes de sinais: não copiar.
9. **Versão do Flutter e de toolchain só muda por card**, nunca de carona num setup.
10. **Um card por sessão.** Trabalho novo descoberto no caminho vira "candidato a card" no
    resumo final, não execução. Ao fim da sessão, bloco de resumo: feito, pendente,
    candidatos a card e o PR para merge.
