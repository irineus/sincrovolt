package com.sincrovolt.spike.obd

// Canal de plataforma próprio para Bluetooth Clássico (SPP) — decisão EVAPP-24.
// O Dart decide O QUE pode ser enviado (lib/nucleo/comandos_permitidos.dart); aqui há
// só uma segunda trava, grosseira, de formato: [0-9A-Z]{1,8} + CR, ou o espaço que
// encerra o ATMA. Qualquer outra coisa é recusada sem tocar no socket.

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val PEDIDO_PERMISSAO = 4711
        private val FORMATO_PERMITIDO = Regex("^([0-9A-Z]{1,8}\r| )$")
    }

    private val principal = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var socket: BluetoothSocket? = null
    private var leitor: Thread? = null
    private var eventos: EventChannel.EventSink? = null
    private var permissaoPendente: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mensageiro = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(mensageiro, "sincrovolt.spike/spp/eventos").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventos = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventos = null
                }
            },
        )

        MethodChannel(mensageiro, "sincrovolt.spike/spp").setMethodCallHandler { call, result ->
            when (call.method) {
                "pedirPermissoes" -> pedirPermissoes(result)
                "listarPareados" -> listarPareados(result)
                "conectar" -> conectar(call.argument<String>("endereco") ?: "", result)
                "desconectar" -> {
                    fecharSocket("desconectado pelo app")
                    result.success(null)
                }
                "escrever" -> escrever(call.argument<String>("texto") ?: "", result)
                "compartilhar" -> {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, "log spike OBD (EVAPP-11)")
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("texto") ?: "")
                    }
                    startActivity(Intent.createChooser(intent, "Salvar/compartilhar log"))
                    result.success(null)
                }
                "manterTelaLigada" -> {
                    if (call.argument<Boolean>("ligar") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------------ permissões

    private fun permissoesNecessarias(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        } else {
            emptyArray() // até o Android 11, BLUETOOTH/BLUETOOTH_ADMIN são concedidas na instalação
        }

    private fun faltando(): List<String> =
        permissoesNecessarias().filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }

    private fun pedirPermissoes(result: MethodChannel.Result) {
        val falta = faltando()
        if (falta.isEmpty()) {
            result.success(null)
            return
        }
        permissaoPendente?.success("pedido anterior substituído")
        permissaoPendente = result
        requestPermissions(falta.toTypedArray(), PEDIDO_PERMISSAO)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PEDIDO_PERMISSAO) return
        val negadas = permissions.filterIndexed { i, _ -> grantResults.getOrNull(i) != PackageManager.PERMISSION_GRANTED }
        permissaoPendente?.success(
            if (negadas.isEmpty()) null else "negada(s): ${negadas.joinToString { it.substringAfterLast('.') }}",
        )
        permissaoPendente = null
    }

    // ------------------------------------------------------------------ aparelhos

    private fun adaptador() = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter

    @SuppressLint("MissingPermission") // conferido em faltando()
    private fun listarPareados(result: MethodChannel.Result) {
        if (faltando().isNotEmpty()) {
            result.error("permissao", "permissão de Bluetooth não concedida: ${faltando().joinToString()}", null)
            return
        }
        val a = adaptador()
        if (a == null) {
            result.error("sem_bluetooth", "este aparelho não tem Bluetooth", null)
            return
        }
        if (!a.isEnabled) {
            result.error("desligado", "o Bluetooth está desligado", null)
            return
        }
        val lista = a.bondedDevices.map { d ->
            mapOf(
                "nome" to (d.name ?: "(sem nome)"),
                "endereco" to d.address,
                "tipo" to when (d.type) {
                    BluetoothDevice.DEVICE_TYPE_CLASSIC -> "clássico"
                    BluetoothDevice.DEVICE_TYPE_LE -> "le"
                    BluetoothDevice.DEVICE_TYPE_DUAL -> "duplo (clássico + LE)"
                    else -> "desconhecido"
                },
            )
        }
        result.success(lista)
    }

    // ------------------------------------------------------------------ conexão

    private fun estado(estado: String, motivo: String = "") {
        principal.post { eventos?.success(mapOf("tipo" to "estado", "estado" to estado, "motivo" to motivo)) }
    }

    @SuppressLint("MissingPermission")
    private fun conectar(endereco: String, result: MethodChannel.Result) {
        if (faltando().isNotEmpty()) {
            result.error("permissao", "permissão de Bluetooth não concedida", null)
            return
        }
        val a = adaptador()
        if (a == null || !a.isEnabled) {
            result.error("desligado", "o Bluetooth está desligado", null)
            return
        }
        fecharSocket("nova conexão")
        estado("conectando")
        executor.execute {
            val aparelho = a.getRemoteDevice(endereco)
            try {
                a.cancelDiscovery()
            } catch (_: SecurityException) {
            }
            var modo = "seguro"
            var s: BluetoothSocket? = null
            var erro: Exception? = null
            for (tentativa in listOf("seguro", "inseguro")) {
                try {
                    val candidato = if (tentativa == "seguro") {
                        aparelho.createRfcommSocketToServiceRecord(SPP_UUID)
                    } else {
                        aparelho.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                    }
                    candidato.connect()
                    s = candidato
                    modo = tentativa
                    break
                } catch (e: IOException) {
                    erro = e
                }
            }
            if (s == null) {
                estado("desconectado", "falha ao conectar: ${erro?.message}")
                principal.post { result.error("conexao", "falha ao conectar (seguro e inseguro): ${erro?.message}", null) }
                return@execute
            }
            socket = s
            iniciarLeitor(s)
            estado("conectado", "RFCOMM $modo")
            principal.post { result.success("RFCOMM $modo") }
        }
    }

    private fun iniciarLeitor(s: BluetoothSocket) {
        leitor = Thread {
            val buffer = ByteArray(1024)
            try {
                val entrada = s.inputStream
                while (!Thread.currentThread().isInterrupted) {
                    val n = entrada.read(buffer)
                    if (n < 0) break
                    val texto = String(buffer, 0, n, Charsets.ISO_8859_1)
                    principal.post { eventos?.success(mapOf("tipo" to "dados", "texto" to texto)) }
                }
            } catch (e: IOException) {
                if (socket === s) estado("desconectado", "conexão caiu: ${e.message}")
            }
            if (socket === s) {
                socket = null
                estado("desconectado", "fim do fluxo")
            }
        }.apply {
            name = "spp-leitor"
            isDaemon = true
            start()
        }
    }

    private fun escrever(texto: String, result: MethodChannel.Result) {
        if (!FORMATO_PERMITIDO.matches(texto)) {
            result.error("recusado", "formato fora do permitido (trava do Kotlin)", null)
            return
        }
        val s = socket
        if (s == null) {
            result.error("desconectado", "sem conexão com o adaptador", null)
            return
        }
        executor.execute {
            try {
                s.outputStream.write(texto.toByteArray(Charsets.US_ASCII))
                s.outputStream.flush()
                principal.post { result.success(null) }
            } catch (e: IOException) {
                principal.post { result.error("escrita", "falha ao escrever: ${e.message}", null) }
            }
        }
    }

    private fun fecharSocket(motivo: String) {
        val s = socket ?: return
        socket = null
        leitor?.interrupt()
        try {
            s.close()
        } catch (_: IOException) {
        }
        estado("desconectado", motivo)
    }

    override fun onDestroy() {
        fecharSocket("app fechado")
        executor.shutdown()
        super.onDestroy()
    }
}
