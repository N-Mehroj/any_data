import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:battery_plus/battery_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
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

  @override
  void initState() {
    super.initState();
    _monitorBatteryLevel();
    _listenToDatabaseChanges();
  }


  Future<void> _updateBatteryLevel() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      setState(() {
        _batteryLevel = batteryLevel;
      });

      // Firebase-ga yozish
      await _database.set({
        "level": _batteryLevel,
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
