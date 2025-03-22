import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: "battery_service_channel",
      initialNotificationTitle: "Battery Monitor",
      initialNotificationContent: "Monitoring battery level...",
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onBackground,
    ),
  );

  try {
    await service.startService();
    print("Service started successfully");
  } catch (e) {
    print("Service start error: $e");
  }
}
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final battery = Battery();
  final database = FirebaseDatabase.instance.ref();
  final deviceInfo = DeviceInfoPlugin();

  // Qurilma identifikatorini olish
  String deviceId = "unknown_device";
  try {
    final androidInfo = await deviceInfo.androidInfo;
    deviceId = androidInfo.id ?? "unknown_device";
    print("Device ID: $deviceId");
  } catch (e) {
    print("Error getting device ID: $e");
  }

  // Foreground rejimi uchun bildirishnoma sozlamasi
  if (service is AndroidServiceInstance) {
    try {
      await service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: "Battery Monitor",
        content: "Monitoring battery level...",
      );
    } catch (e) {
      print("Foreground service error: $e");
    }
  }

  // Har 20 sekundda Firebase’ga ma’lumot yozish
  Timer.periodic(const Duration(seconds: 20), (timer) async {
    try {
      final batteryLevel = await battery.batteryLevel;
      final batteryState = await battery.batteryState;
      final isCharging = batteryState == BatteryState.charging;

      // Firebase’ga real vaqtda yozish
      await database.child('devices').child(deviceId).set({
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // UI uchun ma’lumot yuborish
      service.invoke("update", {
        "deviceId": deviceId,
        "batteryLevel": batteryLevel,
        "isCharging": isCharging,
      });
      print("Data sent to Firebase: $batteryLevel% (Charging: $isCharging)");
    } catch (e) {
      print("Error in timer: $e");
    }
  });

  // Xizmatni to‘xtatish
  service.on("stopService").listen((event) {
    service.stopSelf();
    print("Service stopped");
  });
}

@pragma('vm:entry-point')
bool onBackground(ServiceInstance service) {
  print("iOS background task running");
  return true;
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battery Level Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Battery _battery = Battery();
  int _batteryLevel = 0;
  String _statusMessage = "Checking...";
  final DatabaseReference _database = FirebaseDatabase.instance.ref("battery_level");

  // @override
  // void initState() {
  //   super.initState();
  //   _monitorBatteryLevel();
  //   _listenToDatabaseChanges();
  // }


  Future<void> _updateBatteryLevel() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      setState(() {
        _batteryLevel = batteryLevel;
      });
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      // Firebase-ga yozish
      await _database.set({
        "level": _batteryLevel,
        "deviceId": androidInfo.id,
        "deviceModel":androidInfo.model,
        "timestamp": DateTime.now().toIso8601String(),
      });

      setState(() {
        _statusMessage = "Battery level updated successfully!";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Error updating battery level: $e";
      });
    }
  }

  // 🔍 Firebase'ga yozilgan ma'lumotni doimiy kuzatish
  void _listenToDatabaseChanges() {
    _database.onValue.listen((DatabaseEvent event) {
      if (event.snapshot.value != null) {
        setState(() {
          _statusMessage = "Data successfully written: ${event.snapshot.value}";
        });
      } else {
        setState(() {
          _statusMessage = "No data in Firebase!";
        });
      }
    }, onError: (error) {
      setState(() {
        _statusMessage = "Error reading database: $error";
      });
    });
  }

  // 🔄 Zaryad holati o'zgarganda yangilash
  void _monitorBatteryLevel() {
    _battery.onBatteryStateChanged.listen((BatteryState state) {
      _updateBatteryLevel();
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Battery Level Monitor')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Battery Level: $_batteryLevel%', style: TextStyle(fontSize: 24)),
            Text('Device :  123', style: TextStyle(fontSize: 24)),
            SizedBox(height: 20),
            Text('Status: $_statusMessage', style: TextStyle(fontSize: 16, color: Colors.green)),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _updateBatteryLevel,
              child: Text("Update Battery Level"),
            ),
          ],
        ),
      ),
    );
  }
}
