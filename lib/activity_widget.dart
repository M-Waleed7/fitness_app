import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:light/light.dart';

class SensorActivityDetector extends StatefulWidget {
  const SensorActivityDetector({Key? key}) : super(key: key);

  @override
  State<SensorActivityDetector> createState() => _SensorActivityDetectorState();
}

class _SensorActivityDetectorState extends State<SensorActivityDetector> {
  List<double> _accMagnitudes = [];
  List<double> _gyroValues = [];
  double _lightLevel = 0.0;
  String _predictedActivity = 'Detecting...';
  String _lastActivity = '';
  Map<String, int> _activityDurations = {};
  Map<String, int> _activityGoals = {
    'Running': 300,
    'Walking': 600,
    'Jumping': 180,
    'Sleeping': 28800,
  };

  late Timer _processingTimer;
  late Timer _durationTimer;
  int _currentActivityDuration = 0;
  DateTime? _currentActivityStartTime;
  DateTime? _stillStartTime;

  Light? _light;
  StreamSubscription? _lightSubscription;

  @override
  void initState() {
    super.initState();
    _startSensorListeners();
    _processingTimer = Timer.periodic(
      Duration(seconds: 2),
      (_) => _classifyActivity(),
    );
    _durationTimer = Timer.periodic(
      Duration(seconds: 1),
      (_) => _updateCurrentActivityDuration(),
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

    _initializeLightSensor();
  }

  void _initializeLightSensor() {
    try {
      _light = Light();
      _lightSubscription = _light?.lightSensorStream.listen((int luxValue) {
        setState(() {
          _lightLevel = luxValue.toDouble();
        });
      });
    } catch (e) {
      print('Error initializing light sensor: $e');
      setState(() {
        _lightLevel = -1.0;
      });
    }
  }

  void _updateCurrentActivityDuration() {
    if (_currentActivityStartTime != null) {
      setState(() {
        _currentActivityDuration =
            DateTime.now().difference(_currentActivityStartTime!).inSeconds;
      });
    }
  }

  void _classifyActivity() {
    if (_accMagnitudes.length < 10 || _gyroValues.length < 10) return;

    double avgAcc =
        _accMagnitudes.reduce((a, b) => a + b) / _accMagnitudes.length;
    double varAcc =
        _accMagnitudes
            .map((e) => pow(e - avgAcc, 2).toDouble())
            .reduce((a, b) => a + b) /
        _accMagnitudes.length;
    double avgGyro = _gyroValues.reduce((a, b) => a + b) / _gyroValues.length;

    String activity;
    bool isStill = varAcc < 0.01 && avgGyro < 0.3;

    if (isStill) {
      _stillStartTime ??= DateTime.now();
      int stillDuration = DateTime.now().difference(_stillStartTime!).inSeconds;

      if (_lightLevel < 10 && stillDuration > 60) {
        activity = 'Sleeping';
      } else {
        activity = 'Still';
      }
    } else {
      _stillStartTime = null;

      if (avgAcc > 18 && varAcc > 8.0 && avgGyro > 0.5) {
        activity = 'Jumping';
      } else if (avgAcc > 13 && avgGyro > 1.5 && varAcc > 3.0 && varAcc < 8.0) {
        activity = 'Running';
      } else if (avgAcc > 9.5 && varAcc > 1.0 && avgAcc < 13) {
        activity = 'Walking';
      } else {
        activity = 'Still';
      }
    }

    if (activity != _lastActivity) {
      _currentActivityStartTime = DateTime.now();
      _currentActivityDuration = 0;
    }

    if (activity == _lastActivity) {
      _activityDurations[activity] = (_activityDurations[activity] ?? 0) + 2;
    } else {
      _lastActivity = activity;
    }

    setState(() {
      _predictedActivity = activity;
    });
  }

  void _setGoalDialog(String activity) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Set Goal for $activity'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: 'Enter goal in seconds'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final input = int.tryParse(controller.text);
                  if (input != null && input > 0) {
                    setState(() {
                      _activityGoals[activity] = input;
                    });
                  }
                  Navigator.pop(context);
                },
                child: Text('Save'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _processingTimer.cancel();
    _durationTimer.cancel();
    _lightSubscription?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Color _getActivityColor(String activity) {
    switch (activity) {
      case 'Running':
        return Colors.redAccent;
      case 'Walking':
        return Colors.blueAccent;
      case 'Jumping':
        return Colors.greenAccent;
      case 'Still':
        return Colors.grey;
      case 'Sleeping':
        return Colors.purpleAccent;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Activity Tracker'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _getActivityColor(_predictedActivity),
      ),
      body: Container(
        color: Colors.black,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        "CURRENT ACTIVITY",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _predictedActivity,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: _getActivityColor(_predictedActivity),
                        ),
                      ),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer, color: Colors.grey),
                          SizedBox(width: 8),
                          Text(
                            _formatDuration(_currentActivityDuration),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),
              Text(
                "Activity Summary",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              ..._activityGoals.entries.map((entry) {
                final activity = entry.key;
                final goal = entry.value;
                final done = _activityDurations[activity] ?? 0;
                final progress = (done / goal).clamp(0.0, 1.0);

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _getActivityColor(activity),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  activity,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit, size: 20),
                                onPressed: () => _setGoalDialog(activity),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.grey[300],
                            color: _getActivityColor(activity),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${_formatDuration(done)} / ${_formatDuration(goal)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}
