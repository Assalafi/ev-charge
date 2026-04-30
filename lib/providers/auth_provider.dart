import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool _isLoading = true;
  Map<String, dynamic>? _user;
  String? _error;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  Map<String, dynamic>? get user => _user;
  String? get error => _error;
  String get userName => _user?['name'] ?? '';
  String get userEmail => _user?['email'] ?? '';
  String get userPhone => _user?['phone'] ?? '';
  String get userTagId => _user?['tagId'] ?? '';

  AuthProvider() {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      print('Auth check: token = $token'); // Debug log
      
      if (token != null) {
        final response = await ApiService.get('/auth/me');
        print('Auth check: /auth/me response = $response'); // Debug log
        
        if (response['success'] == true) {
          _user = response['user'] is Map<String, dynamic>
              ? response['user']
              : null;
          _isLoggedIn = _user != null;
          print('Auth check: _isLoggedIn = $_isLoggedIn, _user = $_user'); // Debug log
        }
      }
    } catch (e) {
      print('Auth check: error = $e'); // Debug log
      _isLoggedIn = false;
      _user = null;
    }

    _isLoading = false;
    print('Auth check: completed, _isLoggedIn = $_isLoggedIn'); // Debug log
    notifyListeners();
  }

  Future<bool> signup({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    _error = null;
    try {
      final response = await ApiService.post('/auth/signup', {
        'name': name,
        'phone': phone,
        'email': email,
        'password': password,
        'confirmPassword': confirmPassword,
      });

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', response['token']);
        _user = response['user'] is Map<String, dynamic>
            ? response['user']
            : null;
        _isLoggedIn = true;
        notifyListeners();
        return true;
      }
      _error = response['message'] ?? 'Signup failed';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Connection error. Please try again.';
    }
    notifyListeners();
    return false;
  }

  Future<bool> login({
    required String identifier,
    required String password,
    bool rememberMe = false,
  }) async {
    _error = null;
    try {
      final response = await ApiService.post('/auth/login', {
        'identifier': identifier,
        'password': password,
        'rememberMe': rememberMe,
      });

      if (response['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', response['token']);
        await prefs.setBool('rememberMe', rememberMe);
        _user = response['user'] is Map<String, dynamic>
            ? response['user']
            : null;
        _isLoggedIn = true;
        notifyListeners();
        return true;
      }
      _error = response['message'] ?? 'Login failed';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Connection error. Please try again.';
    }
    notifyListeners();
    return false;
  }

  Future<String?> verifyIdentity({
    required String phone,
    required String email,
  }) async {
    _error = null;
    try {
      final response = await ApiService.post('/auth/verify-identity', {
        'phone': phone,
        'email': email,
      });
      if (response['success'] == true) {
        return response['resetToken'] as String?;
      }
      _error = response['message'] ?? 'Verification failed';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Connection error. Please try again.';
    }
    notifyListeners();
    return null;
  }

  Future<bool> resetPassword({
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _error = null;
    try {
      final response = await ApiService.post('/auth/reset-password', {
        'resetToken': resetToken,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      });
      if (response['success'] == true) return true;
      _error = response['message'] ?? 'Reset failed';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Connection error. Please try again.';
    }
    notifyListeners();
    return false;
  }

  Future<void> updateUserData({
    required String name,
    required String email,
    required String phone,
  }) async {
    if (_user != null) {
      _user!['name'] = name;
      _user!['email'] = email;
      _user!['phone'] = phone;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('rememberMe');
    _isLoggedIn = false;
    _user = null;
    notifyListeners();
  }
}
