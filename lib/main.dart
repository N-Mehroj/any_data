import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

Future<void> initializeApp(BuildContext context) async {
  try {
    await Firebase.initializeApp();
    print("Firebase initialized successfully in main");
  } catch (e) {
    print("Firebase initialization error in main: $e");
  }
  await _requestBackgroundPermission(context);
}

Future<void> _requestBackgroundPermission(BuildContext context) async {
  final bool permissionGranted = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Background Service Permission"),
      content: const Text(
          "This app needs to run in the background to monitor battery level even when closed. Allow it? For best results, disable battery optimization in Settings > Battery > Battery Optimization."),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("No"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("Yes"),
        ),
      ],
    ),
  ) ??
      false;

  if (permissionGranted) {
    await initializeService();
  } else {
    print("Background service permission denied by user");
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      autoStartOnBoot: true,
      isForegroundMode: false, // Bildirishnomasiz orqa fonda
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
  try {
    await Firebase.initializeApp();
    print("Firebase initialized successfully in background");
  } catch (e) {
    print("Firebase initialization error in background: $e");
    return;
  }

  final battery = Battery();
  final database = FirebaseDatabase.instance.ref('battery_level');
  final deviceInfo = DeviceInfoPlugin();

  String deviceId = "unknown_device";
  String deviceModel = "unknown_model";
  try {
    final androidInfo = await deviceInfo.androidInfo;
    deviceId = androidInfo.id ?? "unknown_device";
    deviceModel = androidInfo.model ?? "unknown_model";
    print("Device ID: $deviceId, Model: $deviceModel");
  } catch (e) {
    print("Error getting device info: $e");
  }

  Timer.periodic(const Duration(seconds: 20), (timer) async {
    try {
      final batteryLevel = await battery.batteryLevel;
      final batteryState = await battery.batteryState;
      final isCharging = batteryState == BatteryState.charging;

      await database.set({
        "level": batteryLevel,
        "deviceId": deviceId,
        "deviceModel": deviceModel,
        "isCharging": isCharging,
        "timestamp": DateTime.now().toIso8601String(),
      });

      service.invoke("update", {
        "batteryLevel": batteryLevel,
        "deviceId": deviceId,
        "deviceModel": deviceModel,
        "isCharging": isCharging,
      });
      print("Data sent to Firebase: $batteryLevel% (Charging: $isCharging)");
    } catch (e) {
      print("Error in timer: $e");
    }
  });

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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battery Level Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _batteryLevel = 0;
  String _statusMessage = "Checking...";
  String _deviceId = "Unknown";
  String _deviceModel = "Unknown";
  DatabaseReference? _database;
  bool _isDatabaseInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initializeApp(context);
      _initializeFirebaseAndDatabase().then((_) {
        if (_isDatabaseInitialized) {
          _listenToService();
          _listenToDatabaseChanges();
        }
      });
    });
  }

  Future<void> _initializeFirebaseAndDatabase() async {
    try {
      await Firebase.initializeApp();
      print("Firebase initialized successfully in UI");
      _database = FirebaseDatabase.instance.ref("battery_level");
      setState(() {
        _isDatabaseInitialized = true;
      });
      print("Database initialized successfully");
    } catch (e) {
      setState(() {
        _statusMessage = "Initialization error: $e";
      });
      print("Firebase/Database initialization error: $e");
    }
  }

  void _listenToService() {
    FlutterBackgroundService().on("update").listen((event) {
      setState(() {
        _batteryLevel = event?["batteryLevel"] ?? 0;
        _deviceId = event?["deviceId"] ?? "Unknown";
        _deviceModel = event?["deviceModel"] ?? "Unknown";
        _statusMessage = "Updated from background: $_batteryLevel%";
      });
    }, onError: (e) {
      setState(() {
        _statusMessage = "Service error: $e";
      });
      print("Service listener error: $e");
    });
  }

  void _listenToDatabaseChanges() {
    if (_database == null) return;
    _database!.onValue.listen((DatabaseEvent event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _batteryLevel = data['level'] as int? ?? 0;
          _deviceId = data['deviceId'] as String? ?? "Unknown";
          _deviceModel = data['deviceModel'] as String? ?? "Unknown";
          _statusMessage = "Data from Firebase: $_batteryLevel%";
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
      print("Database listener error: $error");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Battery Level Monitor')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Battery Level: $_batteryLevel%', style: const TextStyle(fontSize: 24)),
            Text('Device ID: $_deviceId', style: const TextStyle(fontSize: 18)),
            Text('Device Model: $_deviceModel', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Text('Status: $_statusMessage', style: const TextStyle(fontSize: 16, color: Colors.green)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                FlutterBackgroundService().invoke("stopService");
                setState(() {
                  _statusMessage = "Background service stopped";
                });
              },
              child: const Text("Stop Background Service"),
            ),
          ],
        ),
      ),
    );
  }
}