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
 * Frame format (OM Bluetooth Frame - matches Desktop Shared Models & Flutter bluetooth_frame.dart):
 *   [0..1]   Magic        0x4F 0x4D ("OM")
 *   [2]      Version      1
 *   [3]      FrameType    0x01=ChatMessage, 0x02=Discovery, 0x03=Ack
 *   [4..5]   PayloadLen   uint16 (big-endian)
 *   [6..6+n] Payload      JSON UTF-8
 *   [6+n..]  Checksum     uint16 (sum of bytes [0..6+n))
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

    companion object {
        const val MAGIC1 = 0x4F.toByte() // 'O'
        const val MAGIC2 = 0x4D.toByte() // 'M'
        const val VERSION = 1.toByte()
        const val FRAME_TYPE_CHAT = 0x01.toByte()
        const val FRAME_TYPE_DISCOVERY = 0x02.toByte()
        const val FRAME_TYPE_ACK = 0x03.toByte()
    }

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
                val frameBytes = call.argument<ByteArray>("frameBytes")
                if (frameBytes != null) {
                    result.success(sendRawFrame(frameBytes))
                } else {
                    // Fallback for older callers
                    val toPeerId = call.argument<String>("toPeerId") ?: ""
                    val fromPeerId = call.argument<String>("fromPeerId") ?: "self"
                    val fromPeerName = call.argument<String>("fromPeerName") ?: "Mobile"
                    val content = call.argument<String>("content") ?: ""
                    result.success(sendChatMessage(content, toPeerId, fromPeerId, fromPeerName))
                }
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
     * Sends a framed chat message using the OM Bluetooth Frame format.
     * Frame layout (all big-endian):
     *   [0..1]   Magic        0x4F 0x4D ("OM")
     *   [2]      Version      1
     *   [3]      FrameType    0x01=ChatMessage
     *   [4..5]   PayloadLen   uint16
     *   [6..6+n] Payload      JSON UTF-8
     *   [6+n..]  Checksum     uint16 (sum of bytes [0..6+n))
     */
    private fun sendChatMessage(content: String, toPeerId: String, fromPeerId: String, fromPeerName: String): Boolean {
        val os = outputStream
        if (os == null) return false
        try {
            val now = java.time.Instant.now().toString()
            val json = """{"type":"chat","fromPeerId":"$fromPeerId","fromPeerName":"$fromPeerName","toPeerId":"$toPeerId","content":"$content","clientMessageId":"${UUID.randomUUID()}","sentAt":"$now"}"""
            val payloadBytes = json.toByteArray(Charsets.UTF_8)
            
            // Build OM frame: Magic(2) + Version(1) + FrameType(1) + PayloadLen(2) + Payload + Checksum(2)
            val frameLength = 6 + payloadBytes.size + 2
            val frame = ByteArray(frameLength)
            frame[0] = MAGIC1
            frame[1] = MAGIC2
            frame[2] = VERSION
            frame[3] = FRAME_TYPE_CHAT
            frame[4] = (payloadBytes.size shr 8 and 0xFF).toByte()
            frame[5] = (payloadBytes.size and 0xFF).toByte()
            System.arraycopy(payloadBytes, 0, frame, 6, payloadBytes.size)
            
            // Checksum (sum of bytes [0..6+payloadLength))
            var checksum = 0
            for (i in 0 until 6 + payloadBytes.size) {
                checksum += frame[i].toInt() and 0xFF
            }
            frame[6 + payloadBytes.size] = (checksum shr 8 and 0xFF).toByte()
            frame[7 + payloadBytes.size] = (checksum and 0xFF).toByte()
            
            os.write(frame)
            os.flush()
            return true
        } catch (_: IOException) {
            disconnect()
            return false
        }
    }

    /**
     * Send a pre-built OM Bluetooth frame directly.
     */
    private fun sendRawFrame(frameBytes: ByteArray): Boolean {
        val os = outputStream
        if (os == null) return false
        try {
            os.write(frameBytes)
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

    /**
     * Read thread: read OM-framed messages from the connected peer.
     * Frame format: Magic(2) + Version(1) + FrameType(1) + PayloadLen(2) + Payload + Checksum(2)
     */
    @WorkerThread
    private inner class ReadThread(private val socket: BluetoothSocket) : Thread("OmniConnect-BT-Read") {
        private val inputStream: InputStream by lazy { socket.inputStream }
        private val buffer = ByteArray(4096) // reusable buffer

        override fun run() {
            while (!isInterrupted) {
                try {
                    // Need at least 8 bytes for minimal frame (header + empty payload + checksum)
                    val header = ByteArray(6)
                    var read = 0
                    while (read < 6) {
                        val r = inputStream.read(header, read, 6 - read)
                        if (r < 0) return // stream closed
                        read += r
                    }

                    // Validate magic
                    if (header[0] != MAGIC1 || header[1] != MAGIC2 || header[2] != VERSION) {
                        continue
                    }

                    val frameType = header[3]
                    val payloadLength = ((header[4].toInt() and 0xFF) shl 8) or (header[5].toInt() and 0xFF)
                    
                    if (payloadLength < 0 || payloadLength > 65535) continue

                    // Read payload + checksum (2 bytes)
                    val remaining = payloadLength + 2
                    val rest = ByteArray(remaining)
                    read = 0
                    while (read < remaining) {
                        val r = inputStream.read(rest, read, remaining - read)
                        if (r < 0) return
                        read += r
                    }

                    // Verify checksum
                    var expectedChecksum = 0
                    for (i in 0 until 6 + payloadLength) {
                        expectedChecksum += if (i < 6) header[i].toInt() and 0xFF else rest[i - 6].toInt() and 0xFF
                    }
                    val actualChecksum = ((rest[payloadLength].toInt() and 0xFF) shl 8) or (rest[payloadLength + 1].toInt() and 0xFF)
                    if (expectedChecksum != actualChecksum) {
                        continue // corrupted frame
                    }

                    // Extract payload
                    val payload = ByteArray(payloadLength)
                    System.arraycopy(rest, 0, payload, 0, payloadLength)

                    // Only handle chat frames
                    if (frameType == FRAME_TYPE_CHAT) {
                        val json = String(payload, Charsets.UTF_8)
                        mainHandler.post {
                            channel.invokeMethod("onMessageReceived", json)
                        }
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
