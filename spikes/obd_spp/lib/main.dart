// Spike EVAPP-11: ler OBD-II por Bluetooth Clássico (SPP) num app Android próprio.
// Descartável: fica em spikes/, fora de apps/. Ver README.md.

import 'package:material_ui/material_ui.dart';

import 'app_estado.dart';
import 'plataforma/transporte_spp.dart';
import 'telas/comum.dart';
import 'telas/conectar.dart';
import 'telas/console.dart';
import 'telas/log.dart';
import 'telas/sequencia.dart';
import 'telas/taxa.dart';
import 'telas/varredura.dart';

void main() {
  runApp(SpikeApp(AppEstado(TransporteKotlin())));
}

class SpikeApp extends StatelessWidget {
  const SpikeApp(this.estado, {super.key});
  final AppEstado estado;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'spike OBD',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: ListenableBuilder(
        listenable: estado,
        builder: (context, _) => DefaultTabController(
          length: 6,
          child: Scaffold(
            appBar: AppBar(
              title: Text(switch (estado.conexao) {
                EstadoConexao.conectado => 'spike OBD · conectado ${mmss(estado.tempoConectado)}',
                EstadoConexao.conectando => 'spike OBD · conectando…',
                EstadoConexao.desconectado => 'spike OBD · desconectado',
              }),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'a. Conectar'),
                  Tab(text: 'b. Sequência'),
                  Tab(text: 'c. Console'),
                  Tab(text: 'd. Taxa'),
                  Tab(text: 'e. Varredura'),
                  Tab(text: 'f. Log'),
                ],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(), // gesto lateral não troca de aba sem querer
              children: [
                TelaConectar(estado),
                TelaSequencia(estado),
                TelaConsole(estado),
                TelaTaxa(estado),
                TelaVarredura(estado),
                TelaLog(estado),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
