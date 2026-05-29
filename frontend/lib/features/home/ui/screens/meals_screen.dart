import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/stat_widgets.dart';
import '../../../profile/providers/user_profile_provider.dart';
import '../../providers/providers.dart';
import '../widgets/meals_widgets.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import 'dart:io';

class MealsScreen extends ConsumerStatefulWidget {
  const MealsScreen({super.key});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  String _entryMode = 'PHOTO'; // PHOTO, SEARCH, MANUAL

  // Manual entry controllers
  final _nameCtrl     = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _carbsCtrl    = TextEditingController();
  final _proteinCtrl  = TextEditingController();
  final _fatCtrl      = TextEditingController();
  bool _manualLoading = false; // toggled via setState during submit

  // Search
  final _searchCtrl = TextEditingController();

  // Gallery picker
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _nameCtrl.dispose();
    _caloriesCtrl.dispose();
    _carbsCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recognitionAsync = ref.watch(mealRecognitionProvider);
    final userAsync = ref.watch(userProfileProvider);
    final inference = ref.watch(inferenceProvider);
    final nutritionAsync = ref.watch(nutritionProvider);

    return userAsync.when(
      data: (user) => Scaffold(
        backgroundColor: recognitionAsync.value == null ? AppTheme.backgroundDark : AppTheme.backgroundCream,
        body: Column(
          children: [
            _buildTopZone(recognitionAsync, inference),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.screenPadding),
                child: recognitionAsync.value == null
                    ? _buildModeA(user.userType)
                    : _buildModeB(recognitionAsync.value!, user, inference, nutritionAsync),
              ),
            ),
          ],
        ),
      ),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildTopZone(AsyncValue<RecognitionResult?> recognition, InferenceState inference) {
    final result = recognition.value;
    if (result != null) {
      return DetectionBanner(
        meal: result.meal,
        confidence: result.confidence.toStringAsFixed(1),
      );
    }

    return Container(
      height: 450,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          if (_isCameraReady && _entryMode == 'PHOTO') CameraPreview(_controller!),
          if (_entryMode == 'PHOTO') const CameraOverlay(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Meal Scanner', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      if (recognition.isLoading || inference.isLoading) 
                         const Text('AI is processing...', style: TextStyle(color: AppTheme.accentCyan, fontSize: 12))
                      else
                         const TagPill(label: 'AI ACTIVE', backgroundColor: AppTheme.accentCyan, textColor: Colors.white),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, color: Colors.white)),
                ],
              ),
            ),
          ),

          if (_entryMode == 'PHOTO' && !recognition.isLoading)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CircleIconBtn(icon: LucideIcons.image, onPressed: _handleGalleryPick),
                  GestureDetector(
                    onTap: _handleCapture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      child: Center(child: Container(width: 56, height: 56, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
                    ),
                  ),
                  _CircleIconBtn(icon: LucideIcons.search, onPressed: () => setState(() => _entryMode = 'SEARCH')),
                ],
              ),
            ),
          
          if (recognition.isLoading)
            const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan)),
        ],
      ),
    );
  }

  Widget _buildModeA(UserType userType) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _ModeBtn(label: '📷 Photo', isActive: _entryMode == 'PHOTO', userType: userType, onTap: () => setState(() => _entryMode = 'PHOTO'))),
            const SizedBox(width: 12),
            Expanded(child: _ModeBtn(label: '🔍 Search', isActive: _entryMode == 'SEARCH', userType: userType, onTap: () => setState(() => _entryMode = 'SEARCH'))),
            const SizedBox(width: 12),
            Expanded(child: _ModeBtn(label: '✏️ Manual', isActive: _entryMode == 'MANUAL', userType: userType, onTap: () => setState(() => _entryMode = 'MANUAL'))),
          ],
        ),
        const SizedBox(height: 24),
        if (_entryMode == 'SEARCH') _buildSearchSection(),
        if (_entryMode == 'MANUAL') _buildManualSection(),
      ],
    );
  }

  Widget _buildModeB(RecognitionResult result, UserProfile user, InferenceState inference, AsyncValue<NutritionState> nutritionAsync) {
    final isDiabetic = user.userType != UserType.fitness;
    
    return Column(
      children: [
        if (isDiabetic) 
          BolusRecommendationCard(
            dose: inference.recommendedDose,
            adjustment: inference.lifestyleAdjustmentPercent,
            drivers: inference.drivers,
            confidence: inference.confidence,
            showDoctorFlag: inference.showDoctorFlag,
            onConfirm: () async {
               await ref.read(mealRecognitionProvider.notifier).confirmAndLog();
               if (mounted) Navigator.pop(context);
            },
          )
        else
          NutritionSummaryCard(
            meal: result.meal,
            onLog: () async {
               await ref.read(mealRecognitionProvider.notifier).confirmAndLog();
               if (mounted) Navigator.pop(context);
            },
          ),
        
        const SizedBox(height: 32),
        nutritionAsync.when(
          data: (nutrition) => MealHistoryList(meals: nutrition.todaysMeals),
          loading: () => const ListShimmer(count: 2),
          error: (e, s) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSearchSection() {
    return AppCard(
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search for a food item...',
          prefixIcon: const Icon(LucideIcons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSubmitted: (val) {
          final trimmed = val.trim();
          if (trimmed.isEmpty) return;
          // Pre-fill manual entry with the searched name and switch to MANUAL
          _nameCtrl.text = trimmed;
          setState(() => _entryMode = 'MANUAL');
        },
      ),
    );
  }

  Widget _buildManualSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Food Name'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _caloriesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Calories'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _carbsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Carbs (g)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _proteinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Protein (g)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _fatCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Fat (g)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _manualLoading ? null : _handleManualSubmit,
            child: _manualLoading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Log Meal'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleManualSubmit() async {
    final name     = _nameCtrl.text.trim();
    final calories = int.tryParse(_caloriesCtrl.text.trim()) ?? 0;
    final carbs    = double.tryParse(_carbsCtrl.text.trim()) ?? 0;
    final protein  = double.tryParse(_proteinCtrl.text.trim()) ?? 0;
    final fat      = double.tryParse(_fatCtrl.text.trim()) ?? 0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a food name')),
      );
      return;
    }

    setState(() => _manualLoading = true);
    try {
      final meal = LoggedMeal(
        id: '',
        name: name,
        timestamp: DateTime.now(),
        calories: calories,
        carbsG: carbs.toInt(),
        proteinG: protein.toInt(),
        fatG: fat.toInt(),
      );
      await ref.read(nutritionProvider.notifier).logMeal(meal);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log meal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _manualLoading = false);
    }
  }

  Future<void> _handleGalleryPick() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await ref.read(mealRecognitionProvider.notifier).recognizeMeal(File(picked.path));
  }

  void _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final image = await _controller!.takePicture();
      await ref.read(mealRecognitionProvider.notifier).recognizeMeal(File(image.path));
    } catch (e) {
      debugPrint('Capture error: $e');
    }
  }
}

class _ModeBtn extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final UserType userType;
  const _ModeBtn({required this.label, required this.isActive, required this.onTap, required this.userType});

  @override
  Widget build(BuildContext context) {
    final activeColor = userType == UserType.fitness ? AppTheme.accentOrange : AppTheme.accentCyan;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? activeColor : AppTheme.borderLight),
        ),
        child: Center(child: Text(label, style: AppTheme.labelSmall.copyWith(color: isActive ? Colors.white : AppTheme.textPrimary))),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _CircleIconBtn({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 24),
      style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2), padding: const EdgeInsets.all(12)),
    );
  }
}
