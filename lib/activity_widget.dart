import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorActivityDetector extends StatefulWidget {
  const SensorActivityDetector({Key? key}) : super(key: key);

  @override
  State<SensorActivityDetector> createState() => _SensorActivityDetectorState();
}

class _SensorActivityDetectorState extends State<SensorActivityDetector> {
  List<double> _accMagnitudes = [];
  List<double> _gyroValues = [];
  String _predictedActivity = 'Detecting...';
  late Timer _processingTimer;

  @override
  void initState() {
    super.initState();
    _startSensorListeners();
    _processingTimer = Timer.periodic(
      Duration(seconds: 2),
      (_) => _classifyActivity(),
    );
  }

  void _startSensorListeners() {
    accelerometerEvents.listen((event) {
      double mag = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _accMagnitudes.add(mag);
      if (_accMagnitudes.length > 100) _accMagnitudes.removeAt(0);
    });

    gyroscopeEvents.listen((event) {
      double motion = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _gyroValues.add(motion);
      if (_gyroValues.length > 100) _gyroValues.removeAt(0);
    });
  }

  void _classifyActivity() {
    double avgAcc =
        _accMagnitudes.fold(0.0, (a, b) => a + b) /
        max(_accMagnitudes.length, 1);
    double varAcc =
        _accMagnitudes
            .map((e) => pow(e - avgAcc, 2).toDouble())
            .fold(0.0, (a, b) => a + b) /
        max(_accMagnitudes.length, 1);
    double avgGyro =
        _gyroValues.fold(0.0, (a, b) => a + b) / max(_gyroValues.length, 1);

    // Debugging: check actual values
    print("avgAcc: $avgAcc, varAcc: $varAcc, avgGyro: $avgGyro");

    String activity;

    if (avgAcc < 5.0 && avgGyro < 0.2) {
      activity = 'Still';
    } else if (avgAcc > 16 && varAcc > 6.0) {
      activity = 'Jumping';
    } else if (avgAcc > 12 && avgGyro > 1.0 && varAcc <= 6.0) {
      activity = 'Running';
    } else if (avgAcc > 9.5 && varAcc > 0.8) {
      activity = 'Walking';
    } else if (avgAcc < 9.8 && avgGyro < 0.5) {
      activity = 'Sitting';
    } else {
      activity = 'Sleeping';
    }

    setState(() {
      _predictedActivity = activity;
    });
  }

  @override
  void dispose() {
    _processingTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "Detected Activity: $_predictedActivity",
        style: TextStyle(fontSize: 24),
      ),
    );
  }
}
