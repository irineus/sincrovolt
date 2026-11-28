// Tela (d): laço de taxa por sinal. Escolho os pedidos e a duração; o laço roda em
// rodízio o mais rápido que o adaptador responder (ou com a pausa escolhida) e mostra
// amostras/s por sinal. Pedido de modo 22 entra como "CAB:22DDDD" (ex.: 7E4:22F190):
// o laço manda o ATSH quando o cabeçalho muda e volta ao 7DF para o OBD padrão.

import 'package:material_ui/material_ui.dart';

import '../app_estado.dart';
import '../nucleo/comandos_permitidos.dart';
import '../nucleo/registro.dart';
import '../nucleo/taxa.dart';
import '../plataforma/transporte_spp.dart';

const List<String> presets = ['015B', '019A', '01A6', '010C', '012F'];
const List<int> duracoesS = [30, 60, 120, 300];

/// (cabeçalho, comando) de uma entrada da lista; `null` = inválida.
(String, String)? entradaDoLaco(String texto) {
  final t = normalizar(texto);
  final partes = t.split(':');
  final (cab, cmd) = partes.length == 2 ? (partes[0], partes[1]) : ('7DF', t);
  if (!RegExp(r'^7[0-9A-F]{2}$').hasMatch(cab)) return null;
  if (avaliar(cmd) is! Permitido || cmd.startsWith('AT')) return null;
  return (cab, cmd);
}

class TelaTaxa extends StatefulWidget {
  const TelaTaxa(this.estado, {super.key});
  final AppEstado estado;

  @override
  State<TelaTaxa> createState() => _TelaTaxaState();
}

class _TelaTaxaState extends State<TelaTaxa> {
  final _escolhidos = <String>{'015B', '019A'};
  final _extras = TextEditingController();
  final _pausa = TextEditingController(text: '0');
  int _duracao = 120;
  bool _rodando = false;
  bool _parar = false;
  DateTime? _inicio;
  Duration _decorrido = Duration.zero;
  Map<String, EstatisticaSinal> _stats = {};
  String? _erro;

  Future<void> _rodar() async {
    final entradas = <(String, String)>[];
    for (final p in _escolhidos) {
      entradas.add(entradaDoLaco(p)!);
    }
    for (final x in _extras.text.split(RegExp(r'[,\s]+')).where((x) => x.isNotEmpty)) {
      final en = entradaDoLaco(x);
      if (en == null) {
        setState(() => _erro = '"$x" não é um pedido válido da lista (use 01xx, 09xx ou CAB:22DDDD)');
        return;
      }
      entradas.add(en);
    }
    if (entradas.isEmpty) return;
    final pausa = Duration(milliseconds: int.tryParse(_pausa.text) ?? 0);
    final e = widget.estado;
    final s = e.sessao;
    e.definirOcupado(true);
    setState(() {
      _erro = null;
      _rodando = true;
      _parar = false;
      _inicio = DateTime.now();
      _stats = {for (final (c, cmd) in entradas) '$c:$cmd': EstatisticaSinal(c == '7DF' ? cmd : '$c:$cmd')};
    });
    final fim = _inicio!.add(Duration(seconds: _duracao));
    while (!_parar && DateTime.now().isBefore(fim) && e.conexao == EstadoConexao.conectado) {
      for (final (cab, cmd) in entradas) {
        if (_parar) break;
        if (s.cabecalho != cab) {
          final t = await s.enviar('ATSH$cab', limite: const Duration(seconds: 2));
          if (t.falha != null) {
            _parar = true;
            _erro = 'ATSH$cab falhou: ${t.falha}';
            break;
          }
        }
        final t = await s.enviar(cmd, limite: const Duration(seconds: 3));
        _stats['$cab:$cmd']!.registrar(sucesso: t.sucesso, latenciaMs: t.latenciaMs, suspeita: t.suspeita);
        if (pausa > Duration.zero) await Future<void>.delayed(pausa);
        if (!mounted) return;
        setState(() => _decorrido = DateTime.now().difference(_inicio!));
      }
    }
    if (s.cabecalho != '7DF') await s.enviar('ATSH7DF');
    final resumo = _stats.values.map((x) => x.resumo(_decorrido)).join('\n');
    e.registro.adicionar(Entrada(DateTime.now(), Sentido.nota,
        'TAXA (${_decorrido.inSeconds} s, pausa ${pausa.inMilliseconds} ms):\n$resumo'));
    e.definirOcupado(false);
    if (mounted) setState(() => _rodando = false);
  }

  @override
  void dispose() {
    _parar = true;
    _extras.dispose();
    _pausa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final pode = e.conexao == EstadoConexao.conectado && !e.ocupado && !e.sessao.monitorando;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(spacing: 6, children: [
          for (final p in presets)
            FilterChip(
              label: Text(p),
              selected: _escolhidos.contains(p),
              onSelected: _rodando ? null : (v) => setState(() => v ? _escolhidos.add(p) : _escolhidos.remove(p)),
            ),
        ]),
        TextField(
          controller: _extras,
          enabled: !_rodando,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Outros (vírgula): ex. 7E4:22F190'),
        ),
        Row(children: [
          const Text('Duração: '),
          DropdownButton<int>(
            value: _duracao,
            items: [for (final d in duracoesS) DropdownMenuItem(value: d, child: Text('$d s'))],
            onChanged: _rodando ? null : (v) => setState(() => _duracao = v!),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _pausa,
              enabled: !_rodando,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pausa (ms)'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: pode && !_rodando ? _rodar : null, child: const Text('Iniciar')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _rodando ? () => setState(() => _parar = true) : null, child: const Text('Parar')),
          const SizedBox(width: 12),
          if (_inicio != null) Text('${_decorrido.inSeconds} / $_duracao s'),
        ]),
        if (_erro != null) Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        for (final st in _stats.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(st.resumo(_decorrido)),
            ),
          ),
      ],
    );
  }
}
