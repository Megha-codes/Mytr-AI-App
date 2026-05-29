import 'package:flutter_dotenv/flutter_dotenv.dart';

class Environment {
  static String get fileName => '.env';
  
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000/api/v1';
  static String get wsBaseUrl => dotenv.env['WS_BASE_URL'] ?? 'ws://localhost:8000/ws';
  
  static Future<void> init() async {
    await dotenv.load(fileName: 'assets/$fileName');
  }
}
