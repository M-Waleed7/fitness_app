import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:light/light.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting

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
    'Sitting': 1200, // for example, 20 minutes
  };

  // Date filtering related variables
  DateTime _selectedDate = DateTime.now();
  DateTime _filterStartDate = DateTime.now();
  DateTime _filterEndDate = DateTime.now();
  String _filterType = 'Today'; // 'Today', 'Date Range', 'All Time'

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
  double _userWeight = 70.0; // Default weight in kg

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

  double _calculateCaloriesBurnt(String activity, int durationInSeconds) {
    double metValue;

    switch (activity) {
      case 'Running':
        metValue = 9.8; // Moderate running
        break;
      case 'Walking':
        metValue = 3.8; // Brisk walking
        break;
      case 'Jumping':
        metValue = 10.0; // Vigorous jump rope
        break;
      case 'Sitting':
        metValue = 1.0; // Resting MET
        break;
      case 'Sleeping':
        metValue = 0.9;
        break;
      default:
        metValue = 1.0;
    }
    // Convert duration to hours
    double durationInHours = durationInSeconds / 3600.0;

    // Calories burned formula: Calories = MET * weight (kg) * duration (hr)
    return metValue * _userWeight * durationInHours;
  }

  // Calculate total calories burned across all activities
  double _calculateTotalCaloriesBurnt() {
    double totalCalories = 0.0;

    _activityDurations.forEach((activity, duration) {
      totalCalories += _calculateCaloriesBurnt(activity, duration);
    });

    return totalCalories;
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
        activity = 'Sitting';
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
        activity = 'Sitting';
      }
    }

    if (activity != _lastActivity) {
      _currentActivityStartTime = DateTime.now();
      _currentActivityDuration = 0;
    }

    // Debug: Check if sitting activity is detected
    print("Detected activity: $activity");

    // When activity changes or continues, save it with the current date
    // This is where you'd save the activity data with timestamp to your database
    if (activity == _lastActivity) {
      _activityDurations[activity] = (_activityDurations[activity] ?? 0) + 2;

      // TODO: When implementing database, save this activity increment with the current date
      // Example: saveActivityUpdate(activity, 2, DateTime.now());
    } else {
      _lastActivity = activity;
    }

    setState(() {
      _predictedActivity = activity;
    });
  }

  // New function to filter activity data by date
  Map<String, int> _getFilteredActivityData() {
    // TODO: When implementing database, replace this with actual queries
    // based on the selected filter type and dates

    switch (_filterType) {
      case 'Today':
        // Return only today's activities
        // Example query: getActivitiesByDate(_selectedDate);
        return _activityDurations; // Currently returns all data as placeholder

      case 'Date Range':
        // Return activities within date range
        // Example query: getActivitiesByDateRange(_filterStartDate, _filterEndDate);
        return _activityDurations; // Currently returns all data as placeholder

      case 'All Time':
      default:
        // Return all stored activities
        // Example query: getAllActivities();
        return _activityDurations;
    }
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  backgroundColor: _surfaceColor,
                  title: Text(
                    'Filter Activities',
                    style: TextStyle(color: _primaryTextColor),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filter type selection
                        Text(
                          'Filter by:',
                          style: TextStyle(color: _secondaryTextColor),
                        ),
                        SizedBox(height: 8),
                        DropdownButton<String>(
                          dropdownColor: _cardBackground,
                          value: _filterType,
                          isExpanded: true,
                          style: TextStyle(color: _primaryTextColor),
                          underline: Container(
                            height: 1,
                            color: Colors.blueAccent,
                          ),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setDialogState(() {
                                _filterType = newValue;
                              });
                            }
                          },
                          items:
                              <String>[
                                'Today',
                                'Date Range',
                                'All Time',
                              ].map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                        ),

                        SizedBox(height: 16),

                        // Show date pickers based on filter type
                        if (_filterType == 'Today')
                          ListTile(
                            title: Text(
                              'Select Date',
                              style: TextStyle(color: _primaryTextColor),
                            ),
                            subtitle: Text(
                              DateFormat('MMM dd, yyyy').format(_selectedDate),
                              style: TextStyle(color: Colors.blueAccent),
                            ),
                            trailing: Icon(
                              Icons.calendar_today,
                              color: Colors.blueAccent,
                            ),
                            onTap: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: ColorScheme.dark(
                                        primary: Colors.blueAccent,
                                        onPrimary: Colors.white,
                                        surface: _cardBackground,
                                        onSurface: _primaryTextColor,
                                      ),
                                      dialogBackgroundColor: _surfaceColor,
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  _selectedDate = picked;
                                });
                              }
                            },
                          ),

                        if (_filterType == 'Date Range')
                          Column(
                            children: [
                              ListTile(
                                title: Text(
                                  'Start Date',
                                  style: TextStyle(color: _primaryTextColor),
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(_filterStartDate),
                                  style: TextStyle(color: Colors.blueAccent),
                                ),
                                trailing: Icon(
                                  Icons.calendar_today,
                                  color: Colors.blueAccent,
                                ),
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: _filterStartDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    builder: (context, child) {
                                      return Theme(
                                        data: ThemeData.dark().copyWith(
                                          colorScheme: ColorScheme.dark(
                                            primary: Colors.blueAccent,
                                            onPrimary: Colors.white,
                                            surface: _cardBackground,
                                            onSurface: _primaryTextColor,
                                          ),
                                          dialogBackgroundColor: _surfaceColor,
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      _filterStartDate = picked;
                                    });
                                  }
                                },
                              ),
                              ListTile(
                                title: Text(
                                  'End Date',
                                  style: TextStyle(color: _primaryTextColor),
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(_filterEndDate),
                                  style: TextStyle(color: Colors.blueAccent),
                                ),
                                trailing: Icon(
                                  Icons.calendar_today,
                                  color: Colors.blueAccent,
                                ),
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: _filterEndDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    builder: (context, child) {
                                      return Theme(
                                        data: ThemeData.dark().copyWith(
                                          colorScheme: ColorScheme.dark(
                                            primary: Colors.blueAccent,
                                            onPrimary: Colors.white,
                                            surface: _cardBackground,
                                            onSurface: _primaryTextColor,
                                          ),
                                          dialogBackgroundColor: _surfaceColor,
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      _filterEndDate = picked;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                      ],
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
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        // Apply the filter
                        setState(() {
                          // This is where you would update the filtered data in a real app
                          // Example: _filteredActivities = _getFilteredActivityData();
                        });
                        Navigator.pop(context);
                      },
                      child: Text('Apply Filter'),
                    ),
                  ],
                ),
          ),
    );
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

  void _setUserWeightDialog() {
    final controller = TextEditingController(text: _userWeight.toString());
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: _surfaceColor,
            title: Text(
              'Set Your Weight',
              style: TextStyle(color: _primaryTextColor),
            ),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: TextStyle(color: _primaryTextColor),
              decoration: InputDecoration(
                hintText: 'Enter weight in kg',
                hintStyle: TextStyle(color: _secondaryTextColor),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.blueAccent.withOpacity(0.5),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blueAccent),
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
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final input = double.tryParse(controller.text);
                  if (input != null && input > 0) {
                    setState(() {
                      _userWeight = input;
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
      case 'Sitting':
        return Color.fromARGB(255, 214, 211, 211); // Medium grey
      case 'Sleeping':
        return Color.fromARGB(255, 44, 205, 103); // Rich purple
      default:
        return Color(0xFF78909C); // Blue grey
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total calories
    final totalCalories = _calculateTotalCaloriesBurnt();

    // Get filtered activity data
    final filteredActivities = _getFilteredActivityData();

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
        actions: [
          IconButton(
            icon: Icon(Icons.person_outline),
            onPressed: _setUserWeightDialog,
            tooltip: 'Set Weight',
          ),
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: _showDateFilterDialog,
            tooltip: 'Filter Data',
          ),
        ],
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
                // Date Card
                Card(
                  elevation: 8,
                  color: _cardBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.teal.withOpacity(0.6),
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: Colors.teal,
                              size: 28,
                            ),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "TODAY",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _secondaryTextColor,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  DateFormat(
                                    'EEE, MMM d, yyyy',
                                  ).format(DateTime.now()),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: _primaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _filterType,
                            style: TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Current Activity Card
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
                        SizedBox(height: 16),
                        // Current activity calories burnt display
                        Text(
                          "Current Calories: ${_calculateCaloriesBurnt(_predictedActivity, _currentActivityDuration).toStringAsFixed(2)} kcal",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Total Calories Card
                SizedBox(height: 24),
                Card(
                  elevation: 8,
                  color: _cardBackground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.amber.withOpacity(0.6),
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          "TOTAL CALORIES BURNED",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _secondaryTextColor,
                            letterSpacing: 2.0,
                          ),
                        ),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              color: Colors.amber,
                              size: 40,
                            ),
                            SizedBox(width: 10),
                            Text(
                              "${totalCalories.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              "kcal",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: _primaryTextColor,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Weight: $_userWeight kg",
                          style: TextStyle(
                            fontSize: 16,
                            color: _secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Activity Detail Cards
                SizedBox(height: 30),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
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
                      GestureDetector(
                        onTap: _showDateFilterDialog,
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_list,
                              color: Colors.blueAccent,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Filter",
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                // List of activity cards with progress
                ..._activityGoals.entries.map((entry) {
                  final activity = entry.key;
                  final goal = entry.value;
                  final done = filteredActivities[activity] ?? 0;
                  final progress = (done / goal).clamp(0.0, 1.0);
                  final caloriesBurned = _calculateCaloriesBurnt(
                    activity,
                    done,
                  );

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
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${(progress * 100).toInt()}% Complete',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _getActivityColor(activity),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.local_fire_department,
                                          size: 16,
                                          color: Colors.amber,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          '${caloriesBurned.toStringAsFixed(2)} kcal',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),

                // No activities message when filtered data is empty
                if (filteredActivities.isEmpty)
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.fitness_center_outlined,
                            color: _secondaryTextColor.withOpacity(0.5),
                            size: 70,
                          ),
                          SizedBox(height: 16),
                          Text(
                            "No activities found for this period",
                            style: TextStyle(
                              fontSize: 16,
                              color: _secondaryTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Try adjusting your filter or get moving!",
                            style: TextStyle(
                              fontSize: 14,
                              color: _secondaryTextColor.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
