import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IoT MQTT Controller',
      theme: ThemeData(
        primarySwatch: MaterialColor(0xFF8B6099, {
          50: Color(0xFFF3F0F5),
          100: Color(0xFFE2D9E7),
          200: Color(0xFFCFC0D7),
          300: Color(0xFFBBA6C7),
          400: Color(0xFFAC93BB),
          500: Color(0xFF8B6099),
          600: Color(0xFF7D5691),
          700: Color(0xFF6C4A87),
          800: Color(0xFF5C3E7D),
          900: Color(0xFF432B6B),
        }),
        scaffoldBackgroundColor: Color(0xFFF8F9FA),
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          headlineMedium: TextStyle(color: Color(0xFF2C3E50), fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: Color(0xFF34495E)),
          bodyMedium: TextStyle(color: Color(0xFF7F8C8D)),
        ),
      ),
      home: MQTTController(),
    );
  }
}

class MQTTController extends StatefulWidget {
  @override
  _MQTTControllerState createState() => _MQTTControllerState();
}

class _MQTTControllerState extends State<MQTTController> with TickerProviderStateMixin {
  final client = MqttServerClient('broker.hivemq.com', 'flutter_client');
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  
  bool connected = false;
  bool ledStatus = false;
  bool isConnecting = false;
  double temperature = 0;
  double humidity = 0;
  double lumen = 0;
  Duration uptime = Duration.zero;
  Timer? _uptimeTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupMQTT();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _setupMQTT() {
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = (topic) => print('Subscribed to $topic');
  }

  void onConnected() {
    setState(() {
      connected = true;
      isConnecting = false;
    });
    _startUptimeTimer();
  }

  void onDisconnected() {
    setState(() {
      connected = false;
      isConnecting = false;
    });
    _stopUptimeTimer();
  }

  void _startUptimeTimer() {
    _uptimeTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        uptime = Duration(seconds: uptime.inSeconds + 1);
      });
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    setState(() {
      uptime = Duration.zero;
    });
  }

  Future<void> connect() async {
    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      _showSnackBar('Please enter username and password', Colors.red);
      return;
    }

    setState(() => isConnecting = true);
    
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs(usernameController.text, passwordController.text)
        .startClean();
    
    try {
      await client.connect();
      // Subscribe to sensor topics
      client.subscribe('sensor/dht', MqttQos.atLeastOnce);
      client.subscribe('sensor/lumen', MqttQos.atLeastOnce);
      client.subscribe('led/status', MqttQos.atLeastOnce);
      
      // Subscribe to UAS25-IOT topics
      client.subscribe('UAS25-IOT/33423304/SUHU', MqttQos.atLeastOnce);
      client.subscribe('UAS25-IOT/33423304/KELEMBAPAN', MqttQos.atLeastOnce);
      
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final payload = (c[0].payload as MqttPublishMessage).payload.message;
        final message = String.fromCharCodes(payload);

        // Handle DHT sensor data (combined temperature and humidity)
        if (c[0].topic == 'sensor/dht') {
          final parts = message.split(',');
          setState(() {
            temperature = double.tryParse(parts[0]) ?? 0;
            humidity = double.tryParse(parts[1]) ?? 0;
          });
        } 
        // Handle individual UAS25-IOT temperature data
        else if (c[0].topic == 'UAS25-IOT/33423304/SUHU') {
          setState(() {
            temperature = double.tryParse(message) ?? 0;
          });
        }
        // Handle individual UAS25-IOT humidity data
        else if (c[0].topic == 'UAS25-IOT/33423304/KELEMBAPAN') {
          setState(() {
            humidity = double.tryParse(message) ?? 0;
          });
        }
        // Handle lumen sensor data
        else if (c[0].topic == 'sensor/lumen') {
          setState(() {
            lumen = double.tryParse(message) ?? 0;
          });
        } 
        // Handle LED status
        else if (c[0].topic == 'led/status') {
          setState(() => ledStatus = message == 'ON');
        }
      });
      
      _showSnackBar('Connected successfully!', Colors.green);
    } catch (e) {
      setState(() => isConnecting = false);
      _showSnackBar('Connection failed: ${e.toString()}', Colors.red);
    }
  }

  void disconnect() {
    client.disconnect();
    _showSnackBar('Disconnected', Colors.orange);
  }

  // LED control function removed - now only displaying status

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _uptimeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F9FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              SizedBox(height: 30),
              _buildLoginSection(),
              SizedBox(height: 25),
              _buildConnectionButtons(),
              SizedBox(height: 30),
              _buildStatusCard(),
              SizedBox(height: 20),
              _buildControlSection(),
              SizedBox(height: 20),
              _buildSensorData(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Color(0xFF8B6099),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.developer_board, color: Colors.white, size: 28),
          ),
          SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IoT Controller',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              Text(
                'MQTT Device Manager',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF7F8C8D),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MQTT Credentials',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          SizedBox(height: 15),
          TextField(
            controller: usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline, color: Color(0xFF8B6099)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFFE0E6ED)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFF8B6099), width: 2),
              ),
              filled: true,
              fillColor: Color(0xFFF8F9FA),
            ),
          ),
          SizedBox(height: 15),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline, color: Color(0xFF8B6099)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFFE0E6ED)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Color(0xFF8B6099), width: 2),
              ),
              filled: true,
              fillColor: Color(0xFFF8F9FA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            child: ElevatedButton(
              onPressed: (connected || isConnecting) ? null : connect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF8B6099),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: isConnecting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Connecting...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow, size: 20),
                        SizedBox(width: 5),
                        Text('Start', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ),
        SizedBox(width: 15),
        Expanded(
          child: Container(
            height: 50,
            child: ElevatedButton(
              onPressed: connected ? disconnect : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFE74C3C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop, size: 20),
                  SizedBox(width: 5),
                  Text('Stop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: connected ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: connected ? Color(0xFF2ECC71) : Color(0xFF95A5A6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    connected ? Icons.wifi : Icons.wifi_off,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              );
            },
          ),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: connected ? Color(0xFF2ECC71) : Color(0xFF95A5A6),
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  connected 
                      ? 'Uptime: ${uptime.inHours}h ${uptime.inMinutes % 60}m ${uptime.inSeconds % 60}s'
                      : 'Device offline',
                  style: TextStyle(
                    color: Color(0xFF7F8C8D),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          SizedBox(height: 15),
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: ledStatus ? Color(0xFFFFC107) : Color(0xFFE0E6ED),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lightbulb,
                  color: ledStatus ? Colors.white : Color(0xFF95A5A6),
                  size: 25,
                ),
              ),
              SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LED Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    Text(
                      'Status: ${ledStatus ? 'ON' : 'OFF'}',
                      style: TextStyle(
                        color: ledStatus ? Color(0xFF2ECC71) : Color(0xFF95A5A6),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ledStatus ? Color(0xFF2ECC71).withOpacity(0.1) : Color(0xFF95A5A6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ledStatus ? 'ACTIVE' : 'INACTIVE',
                  style: TextStyle(
                    color: ledStatus ? Color(0xFF2ECC71) : Color(0xFF95A5A6),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorData() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sensor Data',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _buildSensorCard('Temperature', '${temperature.toStringAsFixed(1)}°C', Icons.thermostat, Color(0xFFE74C3C))),
            SizedBox(width: 15),
            Expanded(child: _buildSensorCard('Humidity', '${humidity.toStringAsFixed(1)}%', Icons.water_drop, Color(0xFF3498DB))),
          ],
        ),
        SizedBox(height: 15),
        _buildSensorCard('Light Level', '${lumen.toStringAsFixed(0)} lux', Icons.wb_sunny, Color(0xFFFFC107)),
      ],
    );
  }

  Widget _buildSensorCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF7F8C8D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 15),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
        ],
      ),
    );
  }
}