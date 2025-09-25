# flutter_contropad<br>

A new Flutter project.<br>

## Getting Started<br>

This project is a starting point for a Flutter application.<br>

A few resources to get you started if this is your first Flutter project:<br>

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)<br>
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)<br>

For help getting started with Flutter development, view the<br>
[online documentation](https://docs.flutter.dev/), which offers tutorials,<br>
samples, guidance on mobile development, and a full API reference.<br>

此版本已能完整發送ble<br>

請注意pubspec.yaml用了flutter_blue_plus、permission_handl、logging三個新增套件，請注意官網最新版本。<br>
...\android\app\src\main在這個資料夾裡的AndroidManifest.xml有設定與手機app使用權限相關的語法。<br>
------------------------------------------------------------------------------------------------------<br>
一、 應用程式與畫面結構 (App & Screen Structure)<br>
MaterialApp: 整個應用程式的根 Widget，設定了 App 的基本風格。<br>

Scaffold: 提供了標準的畫面佈局結構（例如背景色）。<br>

SafeArea: 一個包裝容器，確保其內容不會被手機的瀏海、圓角或系統操作區域遮擋。<br>

二、 佈局與定位 (Layout & Positioning)<br>
Stack: 堆疊佈局，讓多個 Widget 可以像疊圖層一樣互相覆蓋。在此用於將遊戲手把、Logo 和連線按鈕疊放在一起。<br>

Positioned: 只能在 Stack 中使用，用來精確地定位 Logo 和中間的連線按鈕區域。<br>

Row: 水平佈局，將其子元件（children）由左至右排列。用於排列方向鍵和動作按鈕。<br>

Column: 垂直佈局，將其子元件由上至下排列。用於堆疊方向鍵和中間的連線按鈕區塊。<br>

Center: 將其子元件（在此是 Logo 圖片）置於可用空間的正中央。<br>

Padding: 在其子元件周圍增加指定的空白間距。<br>

SizedBox: 一個具有特定尺寸的空白框，主要用於在元件之間創造固定的間距（例如圖示和文字之間）。<br>

Container: 一個多功能的容器，在此用於繪製方向鍵和動作按鈕的圓形背景、顏色和陰影。<br>

三、 互動元件 (Interactive Elements)<br>
ElevatedButton: 浮動按鈕，用於「藍牙連線」與「斷開連線」這個最主要的操作。<br>

IconButton: 圖示按鈕，用於方向鍵（Dpad）中的上下左右按鈕。<br>

InkWell: 為其子元件增加水波紋點擊效果，將動作按鈕（ActionButtons）中的 Container 變成了可以點擊的自訂按鈕。<br>

四、 視覺與顯示 (Visual & Display)<br>
Image (Image.asset): 用於顯示存放在 assets 資料夾中的 Logo 圖片。<br>

Text: 用於顯示所有文字，例如按鈕上的標籤和連線狀態訊息。<br>

Icon: 用於顯示方向鍵的箭頭圖示。<br>

CircularProgressIndicator: 圓形的進度指示器（轉圈圈的動畫），在藍牙連線過程中顯示，提示使用者程式正在忙碌。<br>