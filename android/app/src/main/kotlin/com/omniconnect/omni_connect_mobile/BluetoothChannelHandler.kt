package com.omniconnect.omni_connect_mobile

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.WorkerThread
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

/** UUID for OmniConnect RFCOMM service. Must match both sides. */
private const val SERVICE_UUID_STRING = "fa87c0d0-afac-11de-8a39-0800200c9a66"
private const val SERVICE_NAME = "OmniConnect"

/**
 * Native Android RFCOMM Bluetooth transport for OmniConnect standalone peer-to-peer chat.
 *
 * Registered as a [FlutterPlugin] via [MainActivity.configureFlutterEngine]. Exposes a
 * MethodChannel (`omniconnect/bluetooth`) that Dart calls to probe availability, start the
 * RFCOMM server, connect to a peer, and send framed chat messages.
 *
 * All messages are ephemeral: kept in memory only by the Dart layer, never written to the DB.
 * Bluetooth is only advertised when the platform actually reports a working adapter.
 */
class BluetoothChannelHandler : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private val adapter = BluetoothAdapter.getDefaultAdapter()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var acceptThread: AcceptThread? = null
    private var connectThread: ConnectThread? = null
    private var connectedSocket: BluetoothSocket? = null
    private var readThread: ReadThread? = null

    /** Output stream for sending framed Bluetooth messages to the connected peer. */
    private var outputStream: OutputStream? = null
        private set

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "omniconnect/bluetooth")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isBluetoothAvailable())
            "startServer" -> result.success(startServer())
            "stopServer" -> { stop(); result.success(null) }
            "sendMessage" -> {
                val toPeerId = call.argument<String>("toPeerId") ?: ""
                val fromPeerId = call.argument<String>("fromPeerId") ?: "self"
                val fromPeerName = call.argument<String>("fromPeerName") ?: "Mobile"
                val content = call.argument<String>("content") ?: ""
                result.success(sendRaw(content, toPeerId, fromPeerId, fromPeerName))
            }
            "enable" -> result.success(ensureBluetoothEnabled())
            "disconnect" -> { disconnect(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun isBluetoothAvailable(): Boolean {
        return adapter != null
    }

    private fun ensureBluetoothEnabled(): Boolean {
        return if (adapter == null) false else {
            if (!adapter.isEnabled) adapter.enable()
            adapter.isEnabled
        }
    }

    private fun startServer(): Boolean {
        if (adapter == null) return false
        stop()

        acceptThread = AcceptThread()
        acceptThread!!.start()
        return true
    }

    private fun stop() {
        readThread?.let { it.interrupt(); readThread = null }
        connectThread?.let { it.interrupt(); connectThread = null }
        acceptThread?.let { it.interrupt(); acceptThread = null }
        connectedSocket?.let { try { it.close() } catch (_: IOException) {}; connectedSocket = null }
        outputStream = null
    }

    private fun disconnect() {
        stop()
    }

    /**
     * Sends a framed chat message over the connected socket.
     *
     * Frame layout (2-byte big-endian length prefix + UTF-8 JSON payload):
     *   [0..1]  PayloadLen  uint16
     *   [2..]   Payload     JSON UTF-8
     */
    private fun sendRaw(content: String, toPeerId: String, fromPeerId: String, fromPeerName: String): Boolean {
        val os = outputStream
        if (os == null) return false
        try {
            val now = java.time.Instant.now().toString()
            val json = """{"type":"chat","fromPeerId":"$fromPeerId","fromPeerName":"$fromPeerName","toPeerId":"$toPeerId","content":"$content","clientMessageId":"${UUID.randomUUID()}","sentAt":"$now"}"""
            val bytes = json.toByteArray(Charsets.UTF_8)
            val framed = ByteArray(2 + bytes.size)
            framed[0] = (bytes.size shr 8 and 0xFF).toInt().toByte()
            framed[1] = (bytes.size and 0xFF).toInt().toByte()
            System.arraycopy(bytes, 0, framed, 2, bytes.size)
            os.write(framed)
            os.flush()
            return true
        } catch (_: IOException) {
            disconnect()
            return false
        }
    }

    /** Called on the main thread once a peer connects. */
    private fun onConnected(socket: BluetoothSocket) {
        connectedSocket = socket
        try {
            outputStream = socket.outputStream
        } catch (e: IOException) {
            disconnect()
            return
        }
        readThread = ReadThread(socket)
        readThread!!.start()
        channel.invokeMethod("onConnected", null)
    }

    /** Connect thread: connect to a peer's RFCOMM server. */
    private inner class ConnectThread(
        private val device: BluetoothDevice
    ) : Thread("OmniConnect-BT-Connect") {
        private val socket: BluetoothSocket? by lazy {
            try {
                device.createRfcommSocketToServiceRecord(
                    UUID.fromString(SERVICE_UUID_STRING))
            } catch (e: Exception) {
                null
            }
        }

        override fun run() {
            adapter?.cancelDiscovery()
            val s = socket ?: return
            try {
                s.connect()
            } catch (e: IOException) {
                try { s.close() } catch (_: IOException) {}
                return
            }
            mainHandler.post { onConnected(s) }
        }

        fun cancel() {
            try { socket?.close() } catch (_: IOException) {}
        }
    }

    fun connectTo(deviceAddress: String): Boolean {
        if (adapter == null) return false
        val device = adapter.getRemoteDevice(deviceAddress)
        stop()
        connectThread = ConnectThread(device)
        connectThread!!.start()
        return true
    }

    /** Read thread: read framed messages from the connected peer. */
    @WorkerThread
    private inner class ReadThread(private val socket: BluetoothSocket) : Thread("OmniConnect-BT-Read") {
        private val inputStream: InputStream by lazy { socket.inputStream }

        override fun run() {
            while (!isInterrupted) {
                try {
                    // Read 2-byte length prefix.
                    val lenBytes = ByteArray(2)
                    var read = 0
                    while (read < 2) {
                        val r = inputStream.read(lenBytes, read, 2 - read)
                        if (r < 0) return // stream closed
                        read += r
                    }
                    val payloadLen = ((lenBytes[0].toInt() and 0xFF) shl 8) or (lenBytes[1].toInt() and 0xFF)
                    if (payloadLen <= 0 || payloadLen > 65535) continue

                    val payload = ByteArray(payloadLen)
                    read = 0
                    while (read < payloadLen) {
                        val r = inputStream.read(payload, read, payloadLen - read)
                        if (r < 0) return
                        read += r
                    }

                    val json = String(payload, Charsets.UTF_8)
                    mainHandler.post {
                        channel.invokeMethod("onMessageReceived", json)
                    }
                } catch (_: IOException) {
                    return
                }
            }
        }
    }

    // ── Accept thread: listen for incoming RFCOMM connections ──
    private inner class AcceptThread : Thread("OmniConnect-BT-Accept") {
        private val serverSocket: BluetoothServerSocket? by lazy {
            try {
                adapter.listenUsingRfcommWithServiceRecord(
                    SERVICE_NAME,
                    UUID.fromString(SERVICE_UUID_STRING))
            } catch (e: Exception) {
                null
            }
        }

        override fun run() {
            while (!isInterrupted) {
                val socket = try {
                    serverSocket?.accept()
                } catch (e: IOException) {
                    null
                }
                if (socket != null) {
                    val acceptedSocket = socket
                    mainHandler.post { onConnected(acceptedSocket) }
                    break // one connection at a time for simplicity
                }
            }
        }
    }
}
