import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // 導入權限處理套件

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 將螢幕方向鎖定為橫向
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const MyApp());
  });
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

// 將 GamepadScreen 轉換為 StatefulWidget 以管理藍芽連線狀態
class GamepadScreen extends StatefulWidget {
  const GamepadScreen({Key? key}) : super(key: key);

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  // 藍芽相關變數
  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;

  // 定義藍芽服務和特徵 UUID
  final Guid _serviceUuid =
      Guid('4faf59a6-976e-67a2-c044-869700000000');
  final Guid _characteristicUuid =
      Guid('a0329f59-700a-ae2e-5a3d-030600000000');

  // 嘗試連接到藍芽裝置
  Future<void> _connectToDevice() async {
    setState(() {
      _isConnected = false;
    });

    print('====================================');
    print('偵錯開始: 嘗試連接藍牙裝置...');
    try {
      // 在開始掃描前，先請求所需的藍牙權限
      final status = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      if (status[Permission.bluetoothScan] != PermissionStatus.granted ||
          status[Permission.bluetoothConnect] != PermissionStatus.granted) {
        print('偵錯: 藍牙權限被拒絕。無法繼續。');
        return;
      }
      
      // 檢查藍牙狀態
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        print('偵錯: 藍牙配接器未開啟，目前狀態為：$adapterState');
        return;
      }
      
      // 掃描裝置
      print('偵錯: 開始掃描裝置...');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      print('偵錯: 掃描完成。');

      // 尋找目標裝置
      final scanResults = FlutterBluePlus.lastScanResults;
      print('偵錯: 掃描到 ${scanResults.length} 個裝置。');
      BluetoothDevice? targetDevice;
      for (var result in scanResults) {
        // 根據廣播的服務UUID來尋找目標裝置
        if (result.advertisementData.serviceUuids.contains(_serviceUuid)) {
          targetDevice = result.device;
          print('偵錯: 找到目標裝置 - 名稱: ${targetDevice.platformName}, ID: ${targetDevice.remoteId}');
          break;
        }
      }

      if (targetDevice != null) {
        // 連接到裝置
        print('偵錯: 正在連線到裝置 ID: ${targetDevice.remoteId}...');
        await targetDevice.connect();
        _connectedDevice = targetDevice;
        print('偵錯: 連線成功！');

        // 發現服務和特徵
        print('偵錯: 正在發現服務...');
        final services = await _connectedDevice!.discoverServices();
        print('偵錯: 發現了 ${services.length} 個服務。');
        for (var service in services) {
          print('偵錯: 檢查服務 UUID: ${service.uuid}');
          if (service.uuid == _serviceUuid) {
            print('偵錯: 找到目標服務 UUID: $_serviceUuid');
            for (var characteristic in service.characteristics) {
              print('偵錯: 檢查特徵 UUID: ${characteristic.uuid}');
              if (characteristic.uuid == _characteristicUuid) {
                _targetCharacteristic = characteristic;
                print('偵錯: 找到目標特徵 UUID: $_characteristicUuid');
                break;
              }
            }
          }
        }

        if (_targetCharacteristic != null) {
          setState(() {
            _isConnected = true;
          });
          print('偵錯: 藍牙連線已完全建立。');
        } else {
          print('偵錯: 找不到所需的特徵。可能是 UUID 不正確或權限問題。');
          _connectedDevice!.disconnect();
        }
      } else {
        print('偵錯: 掃描期間未找到目標裝置。請確認裝置已開啟並可被發現。');
      }
    } catch (e) {
      print('偵錯: 連線過程中發生錯誤: $e');
      if (_connectedDevice != null) {
        print('偵錯: 正在斷開已連線裝置的連線。');
        _connectedDevice!.disconnect();
      }
    } finally {
      print('偵錯: 停止掃描。');
      FlutterBluePlus.stopScan();
      print('偵錯結束: 完成連線嘗試。');
      print('====================================');
    }
  }

  // 發送字串資料到藍芽裝置
  Future<void> _sendData(String data) async {
    if (_isConnected && _targetCharacteristic != null) {
      try {
        await _targetCharacteristic!
            .write(data.codeUnits, withoutResponse: false);
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
            // 主要的遊戲手把介面
            GamepadInterface(
              onDpadLeft: () => _sendData('1'),
              onDpadDown: () => _sendData('3'),
              onDpadRight: () => _sendData('2'),
              onButtonA: () => _sendData('4'),
              onButtonB: () => _sendData('5'),
            ),

            // 位於上方的 Logo，並水平置中
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Image.asset(
                  'assets/images/logo.png', // 確保路徑和檔名正確
                  width: 301,
                  height: 158.4,
                ),
              ),
            ),

            // 位於畫面正中間的藍芽連線按鈕和文字標籤
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
          // 左側的十字方向鍵 (D-pad)
          Dpad(
            onDpadUp: () {}, // 這裡不需要傳送資料，所以保留空的
            onDpadLeft: onDpadLeft,
            onDpadDown: onDpadDown,
            onDpadRight: onDpadRight,
          ),
          // 右側的動作按鈕
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