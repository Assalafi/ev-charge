import 'dart:convert';
import 'package:http/http.dart' as http;

class Ad {
  final int id;
  final String title;
  final String body;
  final String? photo;
  final int order;

  Ad({
    required this.id,
    required this.title,
    required this.body,
    this.photo,
    required this.order,
  });

  factory Ad.fromJson(Map<String, dynamic> json) {
    return Ad(
      id: json['id'],
      title: json['title'],
      body: json['body'],
      photo: json['photo'],
      order: json['order'],
    );
  }
}

class AdsService {
  static const String baseUrl = 'https://evcharging.eride.ng/api';
  
  static Future<List<Ad>> getActiveAds() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/ads-board'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> adsJson = data['data'];
          return adsJson.map((json) => Ad.fromJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching ads: $e');
      return [];
    }
  }
}
