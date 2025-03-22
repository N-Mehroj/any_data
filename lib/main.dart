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
  try {
    await Firebase.initializeApp();
    print("Firebase initialized successfully");
  } catch (e) {
    print("Firebase initialization error: $e");
    return; // Firebase ishlamasa, ilova to‘xtaydi
  }
  await initializeService();
  runApp(const MyApp());
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String deviceId = "Unknown";
  int batteryLevel = 0;
  bool isCharging = false;
  final database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _listenToFirebase(); // Firebase’dan real vaqtda o‘qish
  }

  void _listenToFirebase() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      final androidInfo = await deviceInfo.androidInfo;
      final deviceId = androidInfo.id ?? "unknown_device";
      database.child('devices').child(deviceId).onValue.listen((event) {
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            this.deviceId = deviceId;
            batteryLevel = data['batteryLevel'] as int? ?? 0;
            isCharging = data['isCharging'] as bool? ?? false;
          });
          print("Data received from Firebase: $batteryLevel%");
        } else {
          print("No data in Firebase for device: $deviceId");
        }
      }, onError: (error) {
        print("Firebase read error: $error");
      });
    } catch (e) {
      print("Error getting device info for Firebase: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Battery Status"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Device ID: $deviceId", style: const TextStyle(fontSize: 18)),
              Text("Battery Level: $batteryLevel%", style: const TextStyle(fontSize: 24)),
              Text("Charging: ${isCharging ? 'Yes' : 'No'}", style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  FlutterBackgroundService().invoke("stopService");
                },
                child: const Text("Stop Service"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
