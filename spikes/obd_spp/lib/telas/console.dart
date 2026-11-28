// Tela (c): console livre. Todo texto passa pela lista de comandos permitidos; o que
// estiver fora é recusado antes de sair, com o motivo em vermelho.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_estado.dart';
import '../elm/sessao_elm.dart';
import '../plataforma/transporte_spp.dart';
import 'comum.dart';

class TelaConsole extends StatefulWidget {
  const TelaConsole(this.estado, {super.key});
  final AppEstado estado;

  @override
  State<TelaConsole> createState() => _TelaConsoleState();
}

class _TelaConsoleState extends State<TelaConsole> {
  final _campo = TextEditingController();
  final _trocas = <Troca>[];
  final _monitor = <String>[];
  Timer? _limiteMonitor;
  static const _duracaoMonitor = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    widget.estado.sessao.aoLinhaMonitor = (l) {
      if (!mounted) return;
      setState(() {
        _monitor.add(l);
        if (_monitor.length > 300) _monitor.removeAt(0);
      });
    };
  }

  @override
  void dispose() {
    _limiteMonitor?.cancel();
    widget.estado.sessao.aoLinhaMonitor = null;
    _campo.dispose();
    super.dispose();
  }

  Future<void> _enviar(String texto) async {
    final s = widget.estado.sessao;
    final t = await s.enviar(texto);
    if (!mounted) return;
    setState(() => _trocas.insert(0, t));
    if (s.monitorando) {
      _monitor.clear();
      _limiteMonitor?.cancel();
      _limiteMonitor = Timer(_duracaoMonitor, _parar); // ATMA nunca fica ligado esquecido
    }
  }

  Future<void> _parar() async {
    _limiteMonitor?.cancel();
    final t = await widget.estado.sessao.pararMonitor();
    if (mounted) setState(() => _trocas.insert(0, t));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final conectado = e.conexao == EstadoConexao.conectado;
    final mon = e.sessao.monitorando;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Cabeçalho ativo: ${e.sessao.cabecalho}. Só passa o que está na lista '
            '(AT de configuração, 01xx, 09xx, 22xxxx).'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _campo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'ex.: ATRV, 0100, ATSH7E0, 22F190'),
              onSubmitted: conectado && !mon ? _enviar : null,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: conectado && !mon && !e.ocupado ? () => _enviar(_campo.text) : null,
          ),
        ]),
        Wrap(spacing: 6, children: [
          for (final c in const ['ATRV', 'ATDP', 'ATSH7DF', '0100', '0902', '01A6', '015B', '019A'])
            ActionChip(label: Text(c), onPressed: conectado && !mon && !e.ocupado ? () => _enviar(c) : null),
          ActionChip(
            label: const Text('ATMA (30 s)'),
            onPressed: conectado && !mon && !e.ocupado ? () => _enviar('ATMA') : null,
          ),
        ]),
        if (mon) ...[
          const Alerta('Monitor ATMA ligado (só escuta). Para sozinho em 30 s.', cor: Colors.indigo),
          FilledButton(onPressed: _parar, child: const Text('Parar monitor')),
          for (final l in _monitor.reversed.take(60)) Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
        const Divider(),
        for (final t in _trocas.take(50)) CartaoTroca(t, mostrarVin: e.mostrarVin),
      ],
    );
  }
}
