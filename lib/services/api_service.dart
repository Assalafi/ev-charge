import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final headers = await _headers();
    final response = await http
        .get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: headers)
        .timeout(ApiConfig.timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    final headers = await _headers();
    final response = await http
        .post(Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: headers, body: jsonEncode(body))
        .timeout(ApiConfig.timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> put(
      String path, Map<String, dynamic> body) async {
    final headers = await _headers();
    final response = await http
        .put(Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: headers, body: jsonEncode(body))
        .timeout(ApiConfig.timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> delete(
      String path, {Map<String, dynamic>? body}) async {
    final headers = await _headers();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(ApiConfig.timeout);
    return _handleResponse(response);
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['message'] ?? 'Something went wrong',
    );
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => message;
}
