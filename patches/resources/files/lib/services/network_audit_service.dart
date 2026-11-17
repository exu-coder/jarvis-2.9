import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Active device discovered on the local Wi-Fi subnet.
class NetworkDevice {
  final String ip;
  final String mac;
  final String vendor;
  final String hostname;
  final List<int> openPorts;
  final bool isCameraStream;
  final bool isGateway;

  NetworkDevice({
    required this.ip,
    required this.mac,
    required this.vendor,
    required this.hostname,
    required this.openPorts,
    this.isCameraStream = false,
    this.isGateway = false,
  });
}

/// Structured network security posture audit.
///
/// Every field holds a value that was actually observed. Anything the sweep
/// could not measure stays `null` instead of being filled with a plausible
/// looking placeholder — the UI renders "n/a" for those.
class NetworkAuditReport {
  final String localIp;
  final String subnetPrefix;
  final int totalDevicesFound;
  final List<NetworkDevice> devices;

  /// 0–100, or `null` when the sweep found nothing to score.
  final int? securityScore;
  final List<String> vulnerabilities;

  /// Measured TCP round trip to the gateway in ms, or `null` when no gateway
  /// port answered. (ICMP needs raw sockets, which Android apps cannot open.)
  final int? pingLatencyMs;
  final DateTime auditedAt;

  const NetworkAuditReport({
    required this.localIp,
    required this.subnetPrefix,
    required this.totalDevicesFound,
    required this.devices,
    required this.securityScore,
    required this.vulnerabilities,
    required this.pingLatencyMs,
    required this.auditedAt,
  });
}

/// 🛡️ Stark Network Auditing & Wi-Fi Scanner Suite
///
/// Sweeps local Wi-Fi subnet, parses ARP cache for MACs, resolves hardware vendors,
/// probes for open ports (SSH, Telnet, RTSP Camera feeds), and compiles a cyber defense report.
class NetworkAuditService extends ChangeNotifier {
  NetworkAuditService._();
  static final NetworkAuditService instance = NetworkAuditService._();

  static const MethodChannel _channel = MethodChannel('com.jarvis.dev/accessibility');

  /// Native channel, exposed so tests can stub the ARP-table call.
  @visibleForTesting
  static MethodChannel get channel => _channel;

  bool _isAuditing = false;
  NetworkAuditReport? _lastReport;
  String? _lastError;
  bool _cancelled = false;

  bool get isAuditing => _isAuditing;
  NetworkAuditReport? get lastReport => _lastReport;

  /// Reason the most recent audit failed, or `null` when it succeeded.
  String? get lastError => _lastError;

  /// Abandons an in-flight sweep.
  ///
  /// Called when the audit dialog is closed so the 20-host port probe stops
  /// instead of finishing work nobody is waiting for.
  void cancelAudit() {
    _cancelled = true;
  }

  /// Scores 0–100 from the findings of a completed sweep.
  ///
  /// Returns `null` for an empty sweep: no discovered hosts means the scan
  /// could not see the network, which is not the same as a perfect score.
  @visibleForTesting
  static int? computeSecurityScore(List<NetworkDevice> devices) {
    if (devices.isEmpty) return null;
    var score = 100;
    for (final d in devices) {
      if (d.openPorts.contains(23)) score -= 20; // Telnet: plaintext admin
      if (d.openPorts.contains(21)) score -= 10; // FTP: plaintext transfer
      if (d.isCameraStream) score -= 15; // unauthenticated RTSP video
      if (d.openPorts.contains(22)) score -= 5; // SSH reachable from the LAN
    }
    return score.clamp(0, 100);
  }

  /// Audits the local Wi-Fi network and active subnet.
  ///
  /// Returns `null` when the sweep could not run or could not resolve a local
  /// address; the reason is then available via [lastError]. Callers must
  /// surface that instead of inventing telemetry.
  Future<NetworkAuditReport?> auditNetwork({
    @visibleForTesting String? localIpOverride,
  }) async {
    _isAuditing = true;
    _cancelled = false;
    _lastError = null;
    notifyListeners();

    try {
      // 1. Get local device IP (real interface enumeration only).
      final localIp = localIpOverride ?? await _resolveLocalIp();
      if (localIp == null) {
        return _fail(
          'No local IPv4 address. Join a Wi-Fi network and retry the audit.',
        );
      }

      final subnetParts = localIp.split('.');
      if (subnetParts.length != 4) {
        return _fail('Unusable local address: $localIp');
      }
      final prefix = '${subnetParts[0]}.${subnetParts[1]}.${subnetParts[2]}';

      // 2. Fetch native ARP table from /proc/net/arp
      final arpList = await _fetchNativeArpTable();

      // 3. Probes candidates on subnet concurrently
      final discoveredDevices = <NetworkDevice>[];

      // Scan gateway + common IPs + ARP entries
      final ipsToScan = <String>{
        '$prefix.1', // Gateway
        localIp, // Self
      };
      for (final item in arpList) {
        if (item['ip'] != null) ipsToScan.add(item['ip']!);
      }
      // Add common LAN device hosts
      for (int i = 2; i <= 20; i++) {
        ipsToScan.add('$prefix.$i');
      }

      final scanFutures = ipsToScan.map((ip) async {
        if (_cancelled) return;
        final openPorts = await _scanPorts(ip);
        final isSelf = ip == localIp;
        final isGw = ip == '$prefix.1';

        if (openPorts.isNotEmpty || isSelf || isGw || arpList.any((a) => a['ip'] == ip)) {
          final arpMatch = arpList.firstWhere(
            (a) => a['ip'] == ip,
            orElse: () => {'mac': 'Unknown', 'device': 'wlan0'},
          );
          final mac = isSelf ? 'Local-Device' : (arpMatch['mac'] ?? 'Unknown');
          final vendor = _resolveVendor(mac, isSelf: isSelf, isGw: isGw);
          final hasCamera = openPorts.contains(554);

          discoveredDevices.add(
            NetworkDevice(
              ip: ip,
              mac: mac,
              vendor: vendor,
              hostname: isSelf ? 'J.A.R.V.I.S. Host Phone' : (isGw ? 'Wi-Fi Gateway Router' : 'LAN Client ($ip)'),
              openPorts: openPorts,
              isCameraStream: hasCamera,
              isGateway: isGw,
            ),
          );
        }
      });

      await Future.wait(scanFutures);
      if (_cancelled) return null;

      // 4. Vulnerability list + score, both derived from what was found.
      final vulnerabilities = <String>[];
      for (final d in discoveredDevices) {
        if (d.openPorts.contains(23)) {
          vulnerabilities.add('Unencrypted Telnet (port 23) active on ${d.ip}');
        }
        if (d.openPorts.contains(21)) {
          vulnerabilities.add('Plaintext FTP (port 21) active on ${d.ip}');
        }
        if (d.isCameraStream) {
          vulnerabilities.add('Unencrypted RTSP Video Surveillance feed on ${d.ip}:554');
        }
      }

      if (vulnerabilities.isEmpty) {
        vulnerabilities.add(
          discoveredDevices.isEmpty
              ? 'No hosts answered the sweep — nothing could be assessed.'
              : 'No critical unencrypted management ports exposed.',
        );
      }

      final report = NetworkAuditReport(
        localIp: localIp,
        subnetPrefix: '$prefix.0/24',
        totalDevicesFound: discoveredDevices.length,
        devices: List<NetworkDevice>.unmodifiable(discoveredDevices),
        securityScore: computeSecurityScore(discoveredDevices),
        vulnerabilities: vulnerabilities,
        pingLatencyMs: await _measureGatewayLatency(prefix),
        auditedAt: DateTime.now(),
      );

      _lastReport = report;
      return report;
    } catch (e, st) {
      // A failed audit stays a failure. Returning a hard-coded "report" here
      // used to present a fabricated LAN (192.168.x addresses, 14 ms latency)
      // as live telemetry.
      return _fail('Network audit failed: $e', st);
    } finally {
      _isAuditing = false;
      if (!_cancelled) notifyListeners();
    }
  }

  /// Records a failure, clears any stale report and returns `null`.
  NetworkAuditReport? _fail(String message, [StackTrace? st]) {
    debugPrint('[NetworkAuditService] $message');
    if (st != null) debugPrint('[NetworkAuditService] $st');
    _lastError = message;
    _lastReport = null;
    return null;
  }

  /// First non-loopback IPv4 address, or `null` when the device has no LAN.
  Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // 10.0.2.x is the emulator's NAT link, never a real LAN.
          if (!addr.isLoopback && !addr.address.startsWith('10.0.2.')) {
            return addr.address;
          }
        }
      }
      debugPrint('[NetworkAuditService] No non-loopback IPv4 interface found.');
    } catch (e) {
      debugPrint('[NetworkAuditService] NetworkInterface.list failed: $e');
    }
    return null;
  }

  /// Times a TCP connect to the router's usual management ports.
  ///
  /// Returns `null` when no port answers, rather than a synthetic latency.
  Future<int?> _measureGatewayLatency(String prefix) async {
    final gateway = '$prefix.1';
    for (final port in const [443, 80, 22]) {
      Socket? socket;
      final stopwatch = Stopwatch()..start();
      try {
        socket = await Socket.connect(
          gateway,
          port,
          timeout: const Duration(milliseconds: 400),
        );
        stopwatch.stop();
        return stopwatch.elapsedMilliseconds;
      } catch (e) {
        debugPrint('[NetworkAuditService] Gateway probe $gateway:$port failed: $e');
      } finally {
        socket?.destroy();
      }
    }
    return null;
  }

  Future<List<Map<String, String>>> _fetchNativeArpTable() async {
    try {
      final res = await _channel.invokeListMethod<Map>('getNetworkArpTable');
      if (res != null) {
        return res.map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString()))).toList();
      }
    } catch (e) {
      // No ARP table (restricted ROM, or channel missing): the sweep still runs,
      // but the reason devices may look unnamed is worth one log line.
      debugPrint('[NetworkAuditService] ARP table unavailable: $e');
    }
    return [];
  }

  Future<List<int>> _scanPorts(String ip) async {
    const portsToProbe = [21, 22, 23, 80, 443, 554, 8080];
    final open = <int>[];

    final probes = portsToProbe.map((port) async {
      try {
        final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 250));
        socket.destroy();
        open.add(port);
      } catch (_) {
        // A13: intentionally silent. A closed port *is* the normal path for
        // this probe (6 of them throw per scan), so logging each one would bury
        // real errors. Kept as an empty catch by decision, not by oversight.
      }
    });

    await Future.wait(probes);
    return open;
  }

  String _resolveVendor(String mac, {bool isSelf = false, bool isGw = false}) {
    if (isSelf) return 'This Device';
    if (isGw) return 'Broadband Gateway / Router';

    final cleanMac = mac.toUpperCase().replaceAll(':', '').replaceAll('-', '');
    if (cleanMac.startsWith('001A2B') || cleanMac.startsWith('E4C722')) return 'Cisco Systems';
    if (cleanMac.startsWith('B827EB') || cleanMac.startsWith('DCA632')) return 'Raspberry Pi Foundation';
    if (cleanMac.startsWith('240AC4') || cleanMac.startsWith('30AEA4')) return 'Espressif Systems (IoT)';
    if (cleanMac.startsWith('F01898') || cleanMac.startsWith('ACDE48')) return 'Apple Inc.';
    if (cleanMac.startsWith('A47733') || cleanMac.startsWith('DCF505')) return 'Google LLC';
    if (cleanMac.startsWith('90324B') || cleanMac.startsWith('508569')) return 'Samsung Electronics';
    if (cleanMac.startsWith('50EC50') || cleanMac.startsWith('708BCD')) return 'TP-Link Technologies';

    return 'Network Node';
  }

  /// Spoken Stark telemetry report of the network audit.
  ///
  /// Returns an honest failure sentence when the sweep produced nothing —
  /// never a narration of invented data.
  Future<String> getSpokenAuditReport() async {
    final report = await auditNetwork();
    if (report == null) {
      return 'Network audit incomplete, sir. ${_lastError ?? 'The local subnet did not respond.'}';
    }

    final count = report.totalDevicesFound;
    final score = report.securityScore;
    final ping = report.pingLatencyMs;

    final cameras = report.devices.where((d) => d.isCameraStream).length;
    final cameraStr = cameras > 0 ? ' Discovered $cameras active IP camera streams.' : '';
    final pingStr = ping == null ? 'unavailable' : '$ping milliseconds';
    final scoreStr = score == null ? 'not scoreable' : '$score out of 100';

    return 'Network cyber audit complete, sir. $count connected devices detected on local subnet ${report.subnetPrefix}. Gateway round-trip is $pingStr. Overall security score is $scoreStr.$cameraStr';
  }
}

