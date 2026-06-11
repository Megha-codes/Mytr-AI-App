import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/api/api_client.dart';
import '../models/food_models.dart';

class FoodRecognitionService {
  final ApiClient _client;
  final String _basePath;

  FoodRecognitionService(this._client, {String basePath = '/nutrition'})
      : _basePath = basePath;

  Future<List<FoodItem>> analyzeImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await _client.post(
      '$_basePath/analyze-image',
      data: {'base64_image': base64Image},
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final rawItems = data['food_items'] as List<dynamic>;
    return rawItems
        .map((e) => FoodItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NutritionData>> searchFood(String foodName) async {
    final response = await _client.post(
      '$_basePath/search',
      data: {'food_name': foodName},
      options: Options(receiveTimeout: const Duration(seconds: 30)),
    );

    final data = response.data as Map<String, dynamic>;
    final rawResults = data['results'] as List<dynamic>;
    return rawResults
        .map((e) => NutritionData.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
