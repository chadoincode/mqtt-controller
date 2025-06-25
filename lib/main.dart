import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IoT MQTT Controller',
      theme: ThemeData(
        primaryColor: Color(0xFF744D7E),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: MQTTController(),
    );
  }
}

class MQTTController extends StatefulWidget {
  @override
  _MQTTControllerState createState() => _MQTTControllerState();
}

class _MQTTControllerState extends State<MQTTController> {
  final client = MqttServerClient('broker.hivemq.com', 'flutter_client');
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool connected = false;
  bool ledStatus = false;
  double temperature = 0;
  double humidity = 0;
  Duration uptime = Duration.zero;

  @override
  void initState() {
    super.initState();
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = (topic) => print('Subscribed to $topic');
  }

  void onConnected() => setState(() => connected = true);
  void onDisconnected() => setState(() => connected = false);

  Future<void> connect() async {
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean();
    try {
      await client.connect();
      client.subscribe('sensor/dht', MqttQos.atLeastOnce);
      client.subscribe('led/status', MqttQos.atLeastOnce);
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final payload = (c[0].payload as MqttPublishMessage).payload.message;
        final message = String.fromCharCodes(payload);

        if (c[0].topic == 'sensor/dht') {
          final parts = message.split(',');
          setState(() {
            temperature = double.tryParse(parts[0]) ?? 0;
            humidity = double.tryParse(parts[1]) ?? 0;
          });
        } else if (c[0].topic == 'led/status') {
          setState(() => ledStatus = message == 'ON');
        }
      });
    } catch (e) {
      print('Connection failed: $e');
    }
  }

  void disconnect() {
    client.disconnect();
  }

  void toggleLed(bool value) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(value ? 'ON' : 'OFF');
    client.publishMessage('led/control', MqttQos.atLeastOnce, builder.payload!);
    setState(() => ledStatus = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('IoT MQTT Controller'),
        backgroundColor: Color(0xFF744D7E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: usernameController,
                    decoration: InputDecoration(labelText: 'Username'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: passwordController,
                    decoration: InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: connected ? null : connect,
                    child: Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF744D7E),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: connected ? disconnect : null,
                    child: Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text('Status: ${connected ? "Connected" : "Disconnected"}',
                style: TextStyle(
                    color: connected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold)),
            Divider(),
            ListTile(
              title: Text("Device Status"),
              subtitle: Text(connected ? 'ONLINE  •  Uptime: ${uptime.inMinutes}m ${uptime.inSeconds % 60}s' : 'OFFLINE'),
              leading: Icon(Icons.power_settings_new, color: connected ? Colors.green : Colors.grey),
            ),
            SwitchListTile(
              title: Text("Device Control"),
              subtitle: Text("LED: ${ledStatus ? 'ON' : 'OFF'}"),
              value: ledStatus,
              onChanged: connected ? toggleLed : null,
              activeColor: Color(0xFF744D7E),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.thermostat, color: Colors.red),
                title: Text("Sensor Data"),
                subtitle: Text("${temperature.toStringAsFixed(1)}°C Temperature  •  ${humidity.toStringAsFixed(1)}% Humidity"),
              ),
            )
          ],
        ),
      ),
    );
  }
}
