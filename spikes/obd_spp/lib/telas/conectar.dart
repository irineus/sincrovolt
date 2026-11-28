// Tela (a): permissões, aparelhos pareados, conectar e o relógio dos 30 minutos.

import 'package:material_ui/material_ui.dart';

import '../app_estado.dart';
import '../plataforma/transporte_spp.dart';
import 'comum.dart';

class TelaConectar extends StatelessWidget {
  const TelaConectar(this.estado, {super.key});
  final AppEstado estado;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final minutos = e.tempoConectado.inMinutes;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (e.conexao == EstadoConexao.conectado && minutos >= 25)
          Alerta(minutos >= 30
              ? '30 min no carro: desconecte e TIRE o adaptador da tomada OBD (bateria 12 V).'
              : 'Faltam ${30 - minutos} min para o limite de 30 min no carro.',
              cor: minutos >= 30 ? Colors.red : Colors.orange),
        const Text('Carro PARADO. Não opere o celular dirigindo.',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Estado: ${switch (e.conexao) {
          EstadoConexao.conectado => 'conectado (${mmss(e.tempoConectado)})',
          EstadoConexao.conectando => 'conectando…',
          EstadoConexao.desconectado => 'desconectado',
        }}${e.motivoConexao.isEmpty ? '' : ' — ${e.motivoConexao}'}'),
        if (e.aparelho != null) Text('Aparelho: ${e.aparelho!.nome} (${e.aparelho!.endereco}, ${e.aparelho!.tipo})'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: e.conexao == EstadoConexao.conectando ? null : e.buscarPareados,
            child: const Text('Permissões e pareados'),
          ),
          if (e.conexao == EstadoConexao.conectado)
            OutlinedButton(onPressed: e.desconectar, child: const Text('Desconectar')),
        ]),
        if (e.erro != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(e.erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 8),
        for (final a in e.pareados)
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(a.nome),
            subtitle: Text('${a.endereco} · ${a.tipo}'),
            trailing: const Icon(Icons.link),
            onTap: e.conexao == EstadoConexao.desconectado ? () => e.conectar(a) : null,
          ),
      ],
    );
  }
}
