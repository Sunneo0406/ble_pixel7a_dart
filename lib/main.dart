import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:logging/logging.dart' as logging;

final _logger = logging.Logger('GamepadScreen');

const String DEVICE_NAME = 'MyESP32';
const String SERVICE_UUID = '4faf59a6-976e-67a2-c044-869700000000';
const String CHARACTERISTIC_UUID = 'a0329f59-700a-ae2e-5a3d-030600000000';

class GamepadScreen extends StatefulWidget {
  const GamepadScreen({super.key});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;

  final Guid _serviceUuid = Guid(SERVICE_UUID);
  final Guid _characteristicUuid = Guid(CHARACTERISTIC_UUID);

  BluetoothCharacteristic? _writableCharacteristic;

  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (state != BluetoothAdapterState.on) {
        setState(() {
          _isConnected = false;
          _connectedDevice = null;
          _writableCharacteristic = null;
        });
        _logger.info('藍牙適配器狀態改變：$state');
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    setState(() {
      _isConnected = false;
    });

    _logger.info('偵錯開始：嘗試連線藍牙裝置...');

    final bluetoothStatus = await Permission.bluetooth.request();
    final bluetoothScanStatus = await Permission.bluetoothScan.request();
    final bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    if (bluetoothStatus.isGranted &&
        bluetoothScanStatus.isGranted &&
        bluetoothConnectStatus.isGranted &&
        locationStatus.isGranted) {
      _logger.info('偵錯：所有必要的藍牙權限都已授予。');
    } else {
      _logger.severe('偵錯：藍牙權限被拒絕。無法繼續。');
      return;
    }

    if (!await FlutterBluePlus.isSupported) {
      _logger.severe('偵錯：此裝置不支援藍牙。');
      return;
    }
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _logger.warning('偵錯：藍牙未開啟，正在請求開啟...');
      return;
    }

    try {
      _logger.info('偵錯：開始掃描裝置...');
      await FlutterBluePlus.startScan(
        withNames: [DEVICE_NAME], // 改為使用裝置名稱來掃描
        timeout: const Duration(seconds: 15),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (var result in results) {
          if (result.device.advName == DEVICE_NAME) {
            _logger.info('偵錯：找到目標裝置 - 名稱：${result.device.advName}, ID：${result.device.remoteId}');
            await FlutterBluePlus.stopScan();
            await _connectAndDiscover(result.device);
            return;
          }
        }
      });
    } catch (e) {
      _logger.severe('偵錯：連線過程中發生錯誤：$e');
    }
  }

  Future<void> _connectAndDiscover(BluetoothDevice device) async {
    try {
      _logger.info('偵錯：正在連線到裝置：${device.advName}...');
      await device.connect();
      _connectedDevice = device;

      _connectionSubscription = device.connectionState.listen((state) async {
        _logger.info('偵錯：連線狀態更新：$state');
        if (state == BluetoothConnectionState.connected) {
          setState(() => _isConnected = true);
          _logger.info('偵錯：連線成功！正在尋找服務...');
          await _discoverServices(device);
        } else if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _isConnected = false;
            _connectedDevice = null;
            _writableCharacteristic = null;
          });
          _logger.info('偵錯：裝置已斷線。');
          _connectionSubscription?.cancel();
        }
      });
    } catch (e) {
      _logger.severe('偵錯：連線發生錯誤：$e');
      setState(() => _isConnected = false);
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      _logger.info('偵錯：尋找服務中...');
      final services = await device.discoverServices();

      for (var service in services) {
        if (service.uuid == _serviceUuid) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == _characteristicUuid) {
              _logger.info('偵錯：找到目標特徵值！');
              _writableCharacteristic = characteristic;

              if (_writableCharacteristic!.properties.write) {
                _logger.info('偵錯：特徵值支援寫入。');
              } else {
                _logger.severe('偵錯：特徵值不支援寫入！');
                _disconnect();
                return;
              }
              return;
            }
          }
        }
      }
      _logger.warning('偵錯：未在裝置上找到指定的服務或特徵。');
      _disconnect();
    } catch (e) {
      _logger.severe('偵錯：尋找服務發生錯誤：$e');
      _disconnect();
    }
  }

  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        _logger.info('偵錯：已成功斷開連線。');
      } catch (e) {
        _logger.severe('偵錯：斷開連線失敗：$e');
      }
    }
    setState(() {
      _isConnected = false;
      _connectedDevice = null;
      _writableCharacteristic = null;
    });
    _connectionSubscription?.cancel();
  }

  Future<void> _sendData(String data) async {
    if (_writableCharacteristic != null) {
      try {
        await _writableCharacteristic!.write(data.codeUnits, withoutResponse: false);
        _logger.info('資料發送成功：$data');
      } on PlatformException catch (e) {
        _logger.severe('資料發送失敗 (PlatformException)：${e.code} - ${e.message}');
      } catch (e) {
        _logger.severe('資料發送失敗：$e');
      }
    } else {
      _logger.warning('偵錯：特徵值未就緒或未連線。');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            GamepadInterface(
              onDpadLeft: () => _sendData('1'),
              onDpadDown: () => _sendData('3'),
              onDpadRight: () => _sendData('2'),
              onButtonA: () => _sendData('4'),
              onButtonB: () => _sendData('5'),
            ),
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 301,
                  height: 158.4,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 80,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _isConnected ? _disconnect : _connectToDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.red : Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _isConnected ? '藍芽已連線' : '藍芽連線',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isConnected ? '藍芽已連線！' : '藍芽未連線',
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GamepadScreen(),
    );
  }
}

class GamepadInterface extends StatelessWidget {
  final VoidCallback onDpadLeft;
  final VoidCallback onDpadDown;
  final VoidCallback onDpadRight;
  final VoidCallback onButtonA;
  final VoidCallback onButtonB;

  const GamepadInterface({
    super.key,
    required this.onDpadLeft,
    required this.onDpadDown,
    required this.onDpadRight,
    required this.onButtonA,
    required this.onButtonB,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Dpad(
            onDpadUp: () {},
            onDpadLeft: onDpadLeft,
            onDpadDown: onDpadDown,
            onDpadRight: onDpadRight,
          ),
          ActionButtons(
            onButtonA: onButtonA,
            onButtonB: onButtonB,
            onButtonX: () {},
            onButtonY: () {},
          ),
        ],
      ),
    );
  }
}

class Dpad extends StatelessWidget {
  final VoidCallback onDpadUp;
  final VoidCallback onDpadDown;
  final VoidCallback onDpadLeft;
  final VoidCallback onDpadRight;

  const Dpad({
    super.key,
    required this.onDpadUp,
    required this.onDpadDown,
    required this.onDpadLeft,
    required this.onDpadRight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _buildDpadButton(Icons.arrow_drop_up, onDpadUp),
        Row(
          children: <Widget>[
            _buildDpadButton(Icons.arrow_left, onDpadLeft),
            const SizedBox(width: 50),
            _buildDpadButton(Icons.arrow_right, onDpadRight),
          ],
        ),
        _buildDpadButton(Icons.arrow_drop_down, onDpadDown),
      ],
    );
  }

  Widget _buildDpadButton(IconData icon, VoidCallback onPressed) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[700],
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.3).round()),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 40),
        onPressed: onPressed,
      ),
    );
  }
}

class ActionButtons extends StatelessWidget {
  final VoidCallback onButtonA;
  final VoidCallback onButtonB;
  final VoidCallback onButtonX;
  final VoidCallback onButtonY;

  const ActionButtons({
    super.key,
    required this.onButtonA,
    required this.onButtonB,
    required this.onButtonX,
    required this.onButtonY,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            _buildActionButton('Y', Colors.green, onButtonY),
            _buildActionButton('X', Colors.blue, onButtonX),
          ],
        ),
        const SizedBox(height: 50),
        Row(
          children: <Widget>[
            _buildActionButton('B', Colors.red, onButtonB),
            _buildActionButton('A', Colors.yellow, onButtonA),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return Container(
      margin: const EdgeInsets.all(10.0),
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.3).round()),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  logging.Logger.root.level = logging.Level.ALL;
  logging.Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const MyApp());
  });
}
