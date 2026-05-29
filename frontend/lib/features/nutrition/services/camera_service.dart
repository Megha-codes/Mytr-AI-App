import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';

class MealCameraService {
  final ImagePicker _picker = ImagePicker();

  // User taps camera button
  Future<File?> captureFromCamera() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85, // Compress before upload
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (photo == null) return null;
    return File(photo.path);
  }

  // User taps gallery button
  Future<File?> pickFromGallery() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (photo == null) return null;
    return File(photo.path);
  }

  // Convert to base64 for API upload
  Future<String> encodeToBase64(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return base64Encode(bytes);
  }
}
