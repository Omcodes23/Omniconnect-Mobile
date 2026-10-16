import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user.dart';

class ApiService {
  late String baseUrl;
  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _token;

  String? get token => _token;

  ApiService({String? baseUrl}) {
    // Fallback chain keeps the app working on any network without editing code:
    // an explicitly configured URL, then --dart-define, then the loopback address.
    const override = String.fromEnvironment('API_BASE_URL');
    this.baseUrl =
        baseUrl ?? (override.isNotEmpty ? override : 'http://192.168.29.27:5000');
  }

  /// The port the OmniConnect backend listens on.
  static const int _backendPort = 5000;

  /// Finds a reachable backend on the local network
  ///
  /// A phone has no stable address across Wi-Fi networks, so rather than hard
  /// coding an IP we ask the OS which interface is currently primary and build
  /// the LAN address from it. A saved URL always wins over discovery.
  Future<String?> _discoverBackendUrl() async {
    final candidates = <String>{};

    // --dart-define override always wins, e.g.
    // flutter run --dart-define=API_BASE_URL=http://192.168.1.5:5000
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) candidates.add(override);

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // Prefer the first non-virtual IPv4 address; virtual adapters (VPN,
      // Hyper-V, Docker) usually sort first but rarely host the backend.
      final addresses = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          addresses.add(addr.address);
        }
      }

      // Every interface is a candidate — on a phone there is usually only one.
      for (final address in addresses) {
        candidates.add('http://$address:$_backendPort');
      }

      // Race them: first one that answers /health wins.
      for (final candidate in candidates) {
        if (await _isBackendAlive(candidate)) return candidate;
      }
    } on SocketException {
      // No network enumeration available (some emulators/sandboxes).
    }

    return null;
  }

  Future<bool> _isBackendAlive(String url) async {
    try {
      final response = await _client
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(milliseconds: 800));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    // Request Bluetooth permission on first app open
    try {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.location.request();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      baseUrl = savedUrl;
    } else {
      // Nothing saved yet — try to find the backend on the current network.
      final discovered = await _discoverBackendUrl();
      if (discovered != null) {
        baseUrl = discovered;
        await prefs.setString('server_url', discovered);
      }
    }
    _token = await _storage.read(key: 'auth_token');
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    baseUrl = url;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<AuthResponse> login(String email, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode != 200) {
      throw HttpException('Login failed: ${response.body}');
    }
    final auth = AuthResponse.fromJson(jsonDecode(response.body));
    _token = auth.token;
    await _storage.write(key: 'auth_token', value: auth.token);
    return auth;
  }

  Future<AuthResponse> register(
      String username, String email, String password, String displayName) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
        'displayName': displayName,
      }),
    );
    if (response.statusCode != 200) {
      throw HttpException('Registration failed: ${response.body}');
    }
    final auth = AuthResponse.fromJson(jsonDecode(response.body));
    _token = auth.token;
    await _storage.write(key: 'auth_token', value: auth.token);
    return auth;
  }

  Future<List<dynamic>> get(String path) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw HttpException('GET $path failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw HttpException('GET $path failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic>? body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw HttpException('POST $path failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body);
  }

  // ── Devices ──────────────────────────────────────────────────────
  /// Fetches the device list plus the backend node's own device id.
  ///
  /// The endpoint returns `{devices: [...], selfDeviceId: "..."}` so clients
  /// can hide the machine they are signed in on. Older servers returned a bare
  /// array, so both shapes are accepted.
  Future<({List<dynamic> devices, String selfDeviceId})> getDevices() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/devices'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw HttpException('GET /api/devices failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      final processed = <dynamic>[];
      for (final d in decoded) {
        if (d is Map) {
          final id = d['deviceId']?.toString() ?? '';
          if (id.startsWith('device-OMEGA')) continue;
          final transports = List<String>.from(d['availableTransports'] ?? <String>[]);
          if (!transports.contains('LAN')) transports.add('LAN');
          if (!transports.contains('Internet')) transports.add('Internet');
          final map = Map<String, dynamic>.from(d);
          map['availableTransports'] = transports;
          processed.add(map);
        }
      }
      return (devices: processed, selfDeviceId: '');
    }
    if (decoded is Map<String, dynamic>) {
      var rawDevices = (decoded['devices'] as List?) ?? const [];
      var processed = <dynamic>[];
      for (final d in rawDevices) {
        if (d is Map) {
          final id = d['deviceId']?.toString() ?? '';
          if (id.startsWith('device-OMEGA')) continue; // hide self
          final transports = List<String>.from(d['availableTransports'] ?? <String>[]);
          if (!transports.contains('LAN')) transports.add('LAN');
          if (!transports.contains('Internet')) transports.add('Internet');
          final map = Map<String, dynamic>.from(d);
          map['availableTransports'] = transports;
          processed.add(map);
        }
      }
      return (
        devices: processed,
        selfDeviceId: decoded['selfDeviceId']?.toString() ?? '',
      );
    }
    return (devices: const [], selfDeviceId: '');
  }

  // ── Friends ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> ensureFriend(String userId) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/friends/ensure/$userId'),
        headers: _headers,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Calls ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> initiateCall(String calleeId, String type) async {
    return await post('/api/calls/initiate', {
      'calleeId': calleeId,
      'type': type,
    });
  }

  Future<void> answerCall(String callId) async {
    await post('/api/calls/$callId/accept', null);
  }

  Future<void> rejectCall(String callId) async {
    await post('/api/calls/$callId/reject', null);
  }

  Future<void> endCall(String callId) async {
    await post('/api/calls/$callId/end', null);
  }

  Future<List<dynamic>> getCallHistory() async {
    return await get('/api/calls/history');
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: 'auth_token');
  }

  bool get isAuthenticated => _token != null;

  // ── Direct (offline LAN) peer-to-peer messages ──────────────────────
  /// Send a direct message to a peer's listener over LAN (no backend, no DB).
  Future<bool> sendDirectMessage({
    required String peerIp,
    required int peerPort,
    required String fromPeerId,
    required String fromPeerName,
    required String toPeerId,
    required String content,
    String type = 'Text',
  }) async {
    try {
      final body = {
        'fromPeerId': fromPeerId,
        'fromPeerName': fromPeerName,
        'toPeerId': toPeerId,
        'content': content,
        'type': type,
        'clientMessageId': DateTime.now().millisecondsSinceEpoch.toString(),
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      };
      final response = await _client.post(
        Uri.parse('http://$peerIp:$peerPort/api/direct/message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Drain ephemeral direct messages from a peer's listener (no backend, no DB).
  Future<List<Map<String, dynamic>>> fetchDirectMessages({
    required String peerIp,
    required int peerPort,
    required String peerId,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('http://$peerIp:$peerPort/api/direct/messages/${Uri.encodeComponent(peerId)}'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Quickly check whether a peer's direct listener is reachable.
  Future<bool> isDirectPeerReachable({
    required String peerIp,
    required int peerPort,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('http://$peerIp:$peerPort/api/direct/health'),
      ).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
