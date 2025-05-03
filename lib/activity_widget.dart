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

  // Dark theme colors
  final _darkBackground = Color(0xFF121212);
  final _cardBackground = Color(0xFF1E1E1E);
  final _surfaceColor = Color(0xFF2C2C2C);
  final _primaryTextColor = Colors.white;
  final _secondaryTextColor = Colors.white70;

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
            backgroundColor: _surfaceColor,
            title: Text(
              'Set Goal for $activity',
              style: TextStyle(color: _primaryTextColor),
            ),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(color: _primaryTextColor),
              decoration: InputDecoration(
                hintText: 'Enter goal in seconds',
                hintStyle: TextStyle(color: _secondaryTextColor),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: _getActivityColor(activity).withOpacity(0.5),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _getActivityColor(activity)),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getActivityColor(activity),
                  foregroundColor: Colors.black,
                ),
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
        return Color(0xFFFF5252); // Vibrant red
      case 'Walking':
        return Color(0xFF448AFF); // Bright blue
      case 'Jumping':
        return Color.fromARGB(255, 178, 217, 71); // Bright green
      case 'Still':
        return Color.fromARGB(255, 214, 211, 211); // Medium grey
      case 'Sleeping':
        return Color.fromARGB(255, 44, 205, 103); // Rich purple
      default:
        return Color(0xFF78909C); // Blue grey
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBackground,
      appBar: AppBar(
        title: Text(
          'Activity Tracker',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _getActivityColor(_predictedActivity).withOpacity(0.8),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: _darkBackground,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _getActivityColor(_predictedActivity).withOpacity(0.15),
              _darkBackground,
            ],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 8,
                  color: _cardBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: _getActivityColor(
                        _predictedActivity,
                      ).withOpacity(0.6),
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          "CURRENT ACTIVITY",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _secondaryTextColor,
                            letterSpacing: 2.0,
                          ),
                        ),
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _getActivityColor(
                              _predictedActivity,
                            ).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _predictedActivity,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: _getActivityColor(_predictedActivity),
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.timer,
                              color: _secondaryTextColor,
                              size: 28,
                            ),
                            SizedBox(width: 10),
                            Text(
                              _formatDuration(_currentActivityDuration),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w500,
                                color: _primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 30),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _primaryTextColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        "ACTIVITY SUMMARY",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _primaryTextColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                ..._activityGoals.entries.map((entry) {
                  final activity = entry.key;
                  final goal = entry.value;
                  final done = _activityDurations[activity] ?? 0;
                  final progress = (done / goal).clamp(0.0, 1.0);

                  return Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Card(
                      elevation: 4,
                      color: _cardBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                                      color: _primaryTextColor,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                    color: _getActivityColor(activity),
                                  ),
                                  onPressed: () => _setGoalDialog(activity),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            Stack(
                              children: [
                                Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _surfaceColor,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: progress,
                                  child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _getActivityColor(activity),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_formatDuration(done)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _secondaryTextColor,
                                  ),
                                ),
                                Text(
                                  '${_formatDuration(goal)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                            if (done > 0)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  '${(progress * 100).toInt()}% Complete',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: _getActivityColor(activity),
                                  ),
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
      ),
    );
  }
}
