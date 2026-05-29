import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/food_models.dart';

/// Low-level service for calling the Gemini-powered image analysis endpoint.
/// Prefer [FoodImageProvider] for state-managed access.
class FoodRecognitionService {
  final Dio _dio;
  final String _basePath;

  FoodRecognitionService(this._dio, {String basePath = '/nutrition'})
      : _basePath = basePath;

  /// Encodes [imageFile] to base64 and calls POST /nutrition/analyze-image.
  /// Returns the list of food items identified by Gemini Vision.
  Future<List<FoodItem>> analyzeImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await _dio.post(
      '$_basePath/analyze-image',
      data: {'base64_image': base64Image},
      options: Options(
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final rawItems = data['food_items'] as List<dynamic>;
    return rawItems
        .map((e) => FoodItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Calls POST /nutrition/search for a given food name.
  /// Returns up to 10 USDA matches with nutrition per 100 g.
  Future<List<NutritionData>> searchFood(String foodName) async {
    final response = await _dio.post(
      '$_basePath/search',
      data: {'food_name': foodName},
      options: Options(receiveTimeout: const Duration(seconds: 20)),
    );

    final data = response.data as Map<String, dynamic>;
    final rawResults = data['results'] as List<dynamic>;
    return rawResults
        .map((e) => NutritionData.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
