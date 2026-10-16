import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothPermissionRequest extends StatefulWidget {
  const BluetoothPermissionRequest({super.key});

  @override
  State<BluetoothPermissionRequest> createState() => _BluetoothPermissionRequestState();
}

class _BluetoothPermissionRequestState extends State<BluetoothPermissionRequest> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    setState(() => _requested = true);
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
