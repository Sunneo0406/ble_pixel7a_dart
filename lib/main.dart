import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:logging/logging.dart' as logging;

final _logger = logging.Logger('GamepadScreen');

// 新增常數，與 bletestok_main.dart 保持一致
const String DEVICE_NAME = 'MyESP32';
const String SERVICE_UUID = '4faf59a6-976e-67a2-c044-869700000000';
const String CHARACTERISTIC_UUID = 'a0329f59-700a-ae2e-5a3d-030600000000';

class GamepadScreen extends StatefulWidget {
  const GamepadScreen({super.key});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  // 狀態變數
  String _statusMessage = '點擊按鈕開始藍牙連線';
  bool _isConnecting = false;
  BluetoothCharacteristic? _writableCharacteristic;
  bool _isConnected = false;

  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    // 監聽藍牙適配器狀態
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (state != BluetoothAdapterState.on) {
        // 藍牙關閉時，更新連線狀態
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _connectedDevice = null;
          _writableCharacteristic = null;
          _statusMessage = '藍牙已關閉，連線已斷開';
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  // 輔助函式：顯示 Snackbar
  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _connectToDevice() async {
    if (_isConnecting) return;

    setState(() {
      _statusMessage = '掃描中...';
      _isConnecting = true;
      _isConnected = false;
    });

    try {
      // 請求藍牙權限
      if (await Permission.bluetoothScan.request().isDenied ||
          await Permission.bluetoothConnect.request().isDenied) {
        _showSnackbar('藍牙權限被拒絕，無法繼續。');
        setState(() => _statusMessage = '連線失敗：缺少權限');
        return;
      }

      // 檢查藍牙是否開啟
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _showSnackbar('藍牙未開啟，請手動開啟。');
        setState(() => _statusMessage = '連線失敗：藍牙未開啟');
        return;
      }

      // 開始掃描裝置
      _logger.info('偵錯：開始掃描裝置...');
      await FlutterBluePlus.startScan(
        withNames: [DEVICE_NAME],
        timeout: const Duration(seconds: 10),
      );

      // 等待掃描結果並找到第一個符合的裝置
      BluetoothDevice? targetDevice;
      var subscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == DEVICE_NAME) {
            targetDevice = r.device;
            _logger.info('偵錯：找到目標裝置：${targetDevice!.platformName}');
            FlutterBluePlus.stopScan(); // 找到裝置後立即停止掃描
            break;
          }
        }
      });

      // 等待掃描結束
      await FlutterBluePlus.isScanning.where((isScanning) => !isScanning).first;
      subscription.cancel();

      if (targetDevice == null) {
        _showSnackbar('找不到裝置名稱為 "$DEVICE_NAME" 的裝置');
        setState(() => _statusMessage = '連線失敗：找不到裝置');
        return;
      }

      // 連線到裝置
      setState(() {
        _statusMessage = '找到裝置：${targetDevice!.platformName}，正在連線...';
      });
      await targetDevice!.connect();

      // 監聽連線狀態
      _connectionSubscription = targetDevice!.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.connected) {
          setState(() {
            _statusMessage = '已連線到裝置：${targetDevice!.platformName}';
            _isConnected = true;
          });
          _logger.info('偵錯：連線成功！正在尋找服務...');
          await _discoverServices(targetDevice!);
        } else if (state == BluetoothConnectionState.disconnected) {
          _disconnect(); // 呼叫斷線函式來更新狀態
        }
      });
    } catch (e) {
      _showSnackbar('連線過程中發生錯誤：$e');
      setState(() => _statusMessage = '連線失敗');
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      BluetoothService? targetService;

      for (var service in services) {
        if (service.uuid == Guid(SERVICE_UUID)) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        _showSnackbar('找不到指定的服務 UUID');
        _disconnect();
        return;
      }

      BluetoothCharacteristic? targetChar;
      for (var characteristic in targetService.characteristics) {
        if (characteristic.uuid == Guid(CHARACTERISTIC_UUID)) {
          targetChar = characteristic;
          break;
        }
      }

      if (targetChar == null) {
        _showSnackbar('找不到指定的特徵 UUID');
        _disconnect();
        return;
      }

      _writableCharacteristic = targetChar;
      setState(() {
        _statusMessage = '已找到服務和特徵，可以發送資料';
      });
    } catch (e) {
      _showSnackbar('尋找服務發生錯誤：$e');
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
      _isConnecting = false;
      _connectedDevice = null;
      _writableCharacteristic = null;
      _statusMessage = '已斷開連線';
    });
    _connectionSubscription?.cancel();
  }

  Future<void> _sendData(String data) async {
    if (_writableCharacteristic == null) {
      _showSnackbar('尚未連線到裝置');
      return;
    }
    try {
      await _writableCharacteristic!.write(data.codeUnits, withoutResponse: false);
      _showSnackbar('成功發送資料：$data');
      setState(() {
        _statusMessage = '已發送資料: $data';
      });
    } on PlatformException catch (e) {
      _showSnackbar('資料發送失敗 (PlatformException)：${e.code} - ${e.message}');
    } catch (e) {
      _showSnackbar('資料發送失敗：$e');
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
                    onPressed: _isConnecting
                        ? null // 連線中禁用按鈕
                        : (_isConnected ? _disconnect : _connectToDevice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.red : Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isConnecting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _isConnected ? '斷開藍牙連線' : '藍牙連線',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
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

// 以下類別保持不變
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