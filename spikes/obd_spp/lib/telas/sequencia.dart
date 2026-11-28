// Tela (b): sequência básica de um toque.

import 'package:material_ui/material_ui.dart';

import '../app_estado.dart';
import '../elm/sessao_elm.dart';
import '../plataforma/transporte_spp.dart';
import 'comum.dart';

/// (comando, limite). O ATZ e o primeiro 0100 (busca de protocolo) demoram mais.
const List<(String, int)> sequenciaBasica = [
  ('ATZ', 10000),
  ('ATE0', 3000),
  ('ATL0', 3000),
  ('ATH1', 3000),
  ('ATSP0', 3000),
  ('0100', 15000),
  ('0902', 5000),
  ('01A6', 5000),
  ('015B', 5000),
  ('019A', 5000),
];

class TelaSequencia extends StatefulWidget {
  const TelaSequencia(this.estado, {super.key});
  final AppEstado estado;

  @override
  State<TelaSequencia> createState() => _TelaSequenciaState();
}

class _TelaSequenciaState extends State<TelaSequencia> {
  final _trocas = <Troca>[];
  DateTime? _inicio;
  Duration? _total;

  Future<void> _rodar() async {
    final e = widget.estado;
    e.definirOcupado(true);
    setState(() {
      _trocas.clear();
      _inicio = DateTime.now();
      _total = null;
    });
    for (final (cmd, ms) in sequenciaBasica) {
      final t = await e.sessao.enviar(cmd, limite: Duration(milliseconds: ms));
      if (!mounted) return;
      setState(() => _trocas.add(t));
    }
    setState(() => _total = DateTime.now().difference(_inicio!));
    e.definirOcupado(false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final pode = e.conexao == EstadoConexao.conectado && !e.ocupado && !e.sessao.monitorando;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(sequenciaBasica.map((x) => x.$1).join(', ')),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: pode ? _rodar : null, child: const Text('Rodar sequência')),
          const SizedBox(width: 12),
          if (_total != null) Text('total ${_total!.inMilliseconds} ms'),
          const Spacer(),
          TextButton(
            onPressed: e.alternarVin,
            child: Text(e.mostrarVin ? 'Esconder VIN' : 'Mostrar VIN'),
          ),
        ]),
        for (final t in _trocas) CartaoTroca(t, mostrarVin: e.mostrarVin),
      ],
    );
  }
}
