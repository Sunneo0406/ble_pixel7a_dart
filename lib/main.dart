import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

// 將 GamepadScreen 轉換為 StatefulWidget 以管理藍芽連線狀態
class GamepadScreen extends StatefulWidget {
  const GamepadScreen({Key? key}) : super(key: key);

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  // flutter_reactive_ble 實例
  final _ble = FlutterReactiveBle();
  // 連線狀態變數
  bool _isConnected = false;
  // 連線裝置 ID
  String? _connectedDeviceId;

  // 定義藍牙服務和特徵 UUID
  final Uuid _serviceUuid = Uuid.parse('4faf59a6-976e-67a2-c044-869700000000');
  final Uuid _characteristicUuid = Uuid.parse('a0329f59-700a-ae2e-5a3d-030600000000');

  // 掃描和連線的訂閱變數
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    setState(() {
      _isConnected = false;
    });

    print('====================================');
    print('偵錯開始: 嘗試連接藍牙裝置...');
    
    // 檢查並請求所有必要的藍牙權限
    final bluetoothScanStatus = await Permission.bluetoothScan.request();
    final bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    final locationStatus = await Permission.locationWhenInUse.request(); // Android 13 仍可能需要
    
    print('偵錯: 藍牙掃描權限狀態: $bluetoothScanStatus');
    print('偵錯: 藍牙連線權限狀態: $bluetoothConnectStatus');
    print('偵錯: 位置權限狀態: $locationStatus');

    if (bluetoothScanStatus.isGranted && bluetoothConnectStatus.isGranted) {
      print('偵錯: 所有必要的藍牙權限都已授予。');
    } else {
      print('偵錯: 藍牙權限被拒絕。無法繼續。');
      return;
    }

    try {
      _scanSubscription = _ble.scanForDevices(
        withServices: [_serviceUuid],
        scanMode: ScanMode.lowLatency,
      ).listen((device) async {
        if (device.serviceUuids.contains(_serviceUuid)) {
          print('偵錯: 找到目標裝置 - 名稱: ${device.name}, ID: ${device.id}');
          
          _scanSubscription?.cancel();
          await _connectAndDiscover(device.id);
        }
      }, onError: (Object error) {
        print('偵錯: 藍牙掃描發生錯誤: $error');
      });

      print('偵錯: 開始持續掃描...');
    } catch (e) {
      print('偵錯: 連線過程中發生錯誤: $e');
    }
  }

  Future<void> _connectAndDiscover(String deviceId) async {
    _connectionSubscription = _ble.connectToDevice(
      id: deviceId,
    ).listen((update) async {
      print('偵錯: 連線狀態更新: ${update.connectionState}');
      if (update.connectionState == DeviceConnectionState.connected) {
        _connectedDeviceId = deviceId;
        setState(() {
          _isConnected = true;
        });
        print('偵錯: 連線成功！正在尋找服務...');
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        setState(() {
          _isConnected = false;
        });
        _connectedDeviceId = null;
        print('偵錯: 裝置已斷線。');
      }

      if (update.connectionState == DeviceConnectionState.connected) {
        try {
          final services = await _ble.discoverAllServices(update.deviceId);
          for (var service in services) {
            if (service.serviceId == _serviceUuid) {
              for (var characteristic in service.characteristicIds) {
                if (characteristic.characteristicId == _characteristicUuid) {
                  print('偵錯: 找到目標服務和特徵。');
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('偵錯: 尋找服務發生錯誤: $e');
        }
      }
    }, onError: (Object error) {
      print('偵錯: 連線發生錯誤: $error');
      setState(() {
        _isConnected = false;
      });
    });
  }

  Future<void> _sendData(String data) async {
    if (_isConnected && _connectedDeviceId != null) {
      try {
        final characteristic = QualifiedCharacteristic(
          serviceId: _serviceUuid,
          characteristicId: _characteristicUuid,
          deviceId: _connectedDeviceId!,
        );
        await _ble.writeCharacteristicWithResponse(characteristic, value: data.codeUnits);
        print('資料發送成功: $data');
      } catch (e) {
        print('資料發送失敗: $e');
      }
    } else {
      print('未連線到藍芽裝置。');
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
                    onPressed: _connectToDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.green : Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      _isConnected ? '已連線' : '藍芽連線',
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
  const MyApp({Key? key}) : super(key: key);

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
    Key? key,
    required this.onDpadLeft,
    required this.onDpadDown,
    required this.onDpadRight,
    required this.onButtonA,
    required this.onButtonB,
  }) : super(key: key);

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
    Key? key,
    required this.onDpadUp,
    required this.onDpadDown,
    required this.onDpadLeft,
    required this.onDpadRight,
  }) : super(key: key);

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
            color: Colors.black.withOpacity(0.3),
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
    Key? key,
    required this.onButtonA,
    required this.onButtonB,
    required this.onButtonX,
    required this.onButtonY,
  }) : super(key: key);

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
            color: Colors.black.withOpacity(0.3),
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
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const MyApp());
  });
}