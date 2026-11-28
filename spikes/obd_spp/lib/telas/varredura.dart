// Tela (e): varredura de DIDs, só modo 22. Cabeçalho (ou faixa) e faixa de DIDs
// informados por mim; pausa entre pedidos; PARA SOZINHA em 7F 22 33 / 7E / 7F
// ("pare e pergunte"). 7F 22 31 = DID inexistente, segue.

import 'package:material_ui/material_ui.dart';

import '../app_estado.dart';
import '../nucleo/decodificadores.dart';
import '../nucleo/registro.dart';
import '../nucleo/resposta_elm.dart';
import '../nucleo/varredura.dart';
import '../plataforma/transporte_spp.dart';
import 'comum.dart';

class TelaVarredura extends StatefulWidget {
  const TelaVarredura(this.estado, {super.key});
  final AppEstado estado;

  @override
  State<TelaVarredura> createState() => _TelaVarreduraState();
}

class _TelaVarreduraState extends State<TelaVarredura> {
  final _cabecalhos = TextEditingController(text: '7E0');
  final _dids = TextEditingController(text: 'F190');
  final _pausa = TextEditingController(text: '50');
  final _limiteMudo = TextEditingController(text: '8');
  bool _filtroResposta = true;
  bool _rodando = false;
  bool _parar = false;
  String _progresso = '';
  String? _pare;
  String? _erro;
  final _achados = <(String, ResultadoDid)>[];
  final _contagem = <Desfecho, int>{};

  Future<void> _rodar() async {
    final cabs = faixaDeCabecalhos(_cabecalhos.text);
    final dids = faixaDeDids(_dids.text);
    if (cabs == null || dids == null) {
      setState(() => _erro = 'Cabeçalho: 7xx ou 7xx-7yy. DIDs: XXXX ou XXXX-YYYY (até 4096).');
      return;
    }
    final pausa = Duration(milliseconds: int.tryParse(_pausa.text) ?? 50);
    final limiteMudo = int.tryParse(_limiteMudo.text) ?? 8;
    final e = widget.estado;
    final s = e.sessao;
    e.definirOcupado(true);
    setState(() {
      _erro = null;
      _pare = null;
      _rodando = true;
      _parar = false;
      _achados.clear();
      _contagem.clear();
    });
    final t0 = DateTime.now();
    var pedidos = 0;
    e.registro.adicionar(Entrada(t0, Sentido.nota,
        'VARREDURA cabeçalhos ${_cabecalhos.text} DIDs ${_dids.text} pausa ${pausa.inMilliseconds} ms'));

    fora:
    for (final cab in cabs) {
      final c = hex2(cab >> 8).substring(1) + hex2(cab & 0xFF);
      final ts = await s.enviar('ATSH$c', limite: const Duration(seconds: 2));
      if (ts.falha != null) {
        _erro = 'ATSH$c falhou: ${ts.falha}';
        break;
      }
      if (_filtroResposta) {
        final r = cab + 8;
        final rc = hex2(r >> 8).substring(1) + hex2(r & 0xFF);
        await s.enviar('ATCRA$rc', limite: const Duration(seconds: 2));
      }
      var mudos = 0;
      for (final did in dids) {
        if (_parar || e.conexao != EstadoConexao.conectado) break fora;
        final d = hex2(did >> 8) + hex2(did & 0xFF);
        if (mounted) setState(() => _progresso = 'cabeçalho $c · DID $d · $pedidos pedidos');
        final t = await s.enviar('22$d', limite: const Duration(seconds: 2));
        pedidos++;
        final res = t.resposta == null
            ? ResultadoDid(did, Desfecho.semResposta, '', t.falha ?? '')
            : classificarDid(did, t.resposta!);
        _contagem[res.desfecho] = (_contagem[res.desfecho] ?? 0) + 1;
        switch (res.desfecho) {
          case Desfecho.achado:
            _achados.add((c, res));
            e.registro.adicionar(Entrada(DateTime.now(), Sentido.nota,
                'ACHADO $c 22$d em ${res.ecu}: ${candidatasDid(res.dados)}'));
            mudos = 0;
          case Desfecho.pareEPergunte:
            _pare = 'PARE E PERGUNTE: $c 22$d respondeu ${res.detalhe} '
                '(${nomeNrc(res.detalhe.isEmpty ? null : int.tryParse(res.detalhe.split(' ').last, radix: 16))}). '
                'Este DID exige outra sessão ou acesso de segurança. Não continue sem falar com o Claude.';
            e.registro.adicionar(Entrada(DateTime.now(), Sentido.nota, _pare!));
            break fora;
          case Desfecho.moduloSemModo22:
            e.registro.adicionar(Entrada(DateTime.now(), Sentido.nota, '$c não aceita modo 22 (7F 22 11): próximo cabeçalho'));
            continue fora;
          case Desfecho.semResposta:
            mudos++;
            if (mudos >= limiteMudo) {
              e.registro.adicionar(Entrada(DateTime.now(), Sentido.nota, '$c mudo ($mudos sem resposta seguidas): próximo cabeçalho'));
              continue fora;
            }
          case Desfecho.inexistente || Desfecho.outraNegativa:
            mudos = 0;
        }
        if (pausa > Duration.zero) await Future<void>.delayed(pausa);
      }
    }
    // volta ao estado padrão do OBD
    await s.enviar('ATSH7DF', limite: const Duration(seconds: 2));
    final dur = DateTime.now().difference(t0);
    e.registro.adicionar(Entrada(DateTime.now(), Sentido.nota,
        'FIM DA VARREDURA: $pedidos pedidos em ${dur.inSeconds} s; ${_achados.length} achado(s); '
        '${_contagem.entries.map((x) => '${x.key.name} ${x.value}').join(', ')}'));
    e.definirOcupado(false);
    if (mounted) {
      setState(() {
        _rodando = false;
        _progresso = '$pedidos pedidos em ${dur.inSeconds} s';
      });
    }
  }

  @override
  void dispose() {
    _parar = true;
    for (final c in [_cabecalhos, _dids, _pausa, _limiteMudo]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _campo(TextEditingController c, String rotulo, {bool numero = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: c,
            enabled: !_rodando,
            keyboardType: numero ? TextInputType.number : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: rotulo),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final pode = e.conexao == EstadoConexao.conectado && !e.ocupado && !e.sessao.monitorando;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_pare != null) Alerta(_pare!),
        const Text('Só modo 22 (leitura). Para sozinha em 7F 22 33/7E/7F.'),
        Row(children: [
          _campo(_cabecalhos, 'Cabeçalho (7xx ou 7xx-7yy)'),
          _campo(_dids, 'DIDs (XXXX ou XXXX-YYYY)'),
        ]),
        Row(children: [
          _campo(_pausa, 'Pausa (ms)', numero: true),
          _campo(_limiteMudo, 'Mudo após N sem resposta', numero: true),
        ]),
        CheckboxListTile(
          value: _filtroResposta,
          onChanged: _rodando ? null : (v) => setState(() => _filtroResposta = v ?? true),
          title: const Text('Filtrar resposta em cabeçalho + 8 (ATCRA)'),
          dense: true,
        ),
        Row(children: [
          FilledButton(onPressed: pode && !_rodando ? _rodar : null, child: const Text('Iniciar')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _rodando ? () => setState(() => _parar = true) : null, child: const Text('Parar')),
        ]),
        if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Text(_progresso),
        Text(_contagem.entries.map((x) => '${x.key.name}: ${x.value}').join(' · ')),
        const Divider(),
        for (final (c, r) in _achados)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('$c → ${r.ecu} · DID ${hex2(r.did >> 8)}${hex2(r.did & 0xFF)}\n${candidatasDid(r.dados)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
      ],
    );
  }
}
