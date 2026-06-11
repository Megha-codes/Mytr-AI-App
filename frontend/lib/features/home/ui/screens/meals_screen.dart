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

  final _nameCtrl     = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _carbsCtrl    = TextEditingController();
  final _proteinCtrl  = TextEditingController();
  final _fatCtrl      = TextEditingController();
  bool _manualLoading = false;

  final _searchCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
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
    final userAsync        = ref.watch(userProfileProvider);
    final inference        = ref.watch(inferenceProvider);
    final nutritionAsync   = ref.watch(nutritionProvider);

    return userAsync.when(
      data: (user) => _buildMain(user, recognitionAsync, inference, nutritionAsync),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildMain(
    UserProfile user,
    AsyncValue<RecognitionResult?> recognitionAsync,
    InferenceState inference,
    AsyncValue<NutritionState> nutritionAsync,
  ) {
    if (recognitionAsync.isLoading) return _buildProcessingScreen();
    if (recognitionAsync.hasError)  return _buildErrorScreen(recognitionAsync.error!);
    if (recognitionAsync.value != null) {
      return _buildResultScreen(recognitionAsync.value!, user, inference, nutritionAsync);
    }
    if (_entryMode == 'PHOTO') return _buildCameraScreen(user);
    return _buildFormScreen(user);
  }

  // ── Fullscreen camera ──────────────────────────────────────────────────────

  Widget _buildCameraScreen(UserProfile user) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraReady)
            CameraPreview(_controller!)
          else
            const ColoredBox(color: Colors.black),

          const CameraOverlay(),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Meal Scanner',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      TagPill(label: 'AI ACTIVE', backgroundColor: AppTheme.accentCyan, textColor: Colors.white),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 44),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: _ModeBtn(label: '📷 Photo', isActive: true, userType: user.userType, onTap: () {})),
                      const SizedBox(width: 12),
                      Expanded(child: _ModeBtn(label: '🔍 Search', isActive: false, userType: user.userType, onTap: () => setState(() => _entryMode = 'SEARCH'))),
                      const SizedBox(width: 12),
                      Expanded(child: _ModeBtn(label: '✏️ Manual', isActive: false, userType: user.userType, onTap: () => setState(() => _entryMode = 'MANUAL'))),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CircleIconBtn(icon: LucideIcons.image, onPressed: _handleGalleryPick),
                      GestureDetector(
                        onTap: _handleCapture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Center(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      _CircleIconBtn(
                        icon: LucideIcons.flashlight,
                        onPressed: _toggleFlash,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Processing (loading) screen ────────────────────────────────────────────

  Widget _buildProcessingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Meal Scanner',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'AI is processing...',
                        style: AppTheme.labelSmall.copyWith(color: AppTheme.accentCyan),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.accentCyan, strokeWidth: 3),
                  const SizedBox(height: 24),
                  Text(
                    'Identifying your meal...',
                    style: AppTheme.bodyMedium.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error screen ───────────────────────────────────────────────────────────

  Widget _buildErrorScreen(Object error) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.alertCircle, color: Colors.redAccent, size: 52),
                      const SizedBox(height: 20),
                      Text(
                        _friendlyError(error),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => ref.read(mealRecognitionProvider.notifier).reset(),
                        icon: const Icon(LucideIcons.refreshCcw, size: 18),
                        label: const Text('Try again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentCyan,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results screen ─────────────────────────────────────────────────────────

  Widget _buildResultScreen(
    RecognitionResult result,
    UserProfile user,
    InferenceState inference,
    AsyncValue<NutritionState> nutritionAsync,
  ) {
    final isDiabetic = user.userType != UserType.fitness;
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: Column(
        children: [
          DetectionBanner(
            meal: result.meal,
            confidence: result.confidence.toStringAsFixed(1),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.screenPadding),
              child: Column(
                children: [
                  if (result.requiresConfirmation && result.confirmationMessage != null) ...[
                    _WarningBanner(message: result.confirmationMessage!),
                    const SizedBox(height: 16),
                  ],
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
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search / Manual form screen ────────────────────────────────────────────

  Widget _buildFormScreen(UserProfile user) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: Column(
        children: [
          Container(
            color: AppTheme.backgroundDark,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Meal Scanner',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.screenPadding),
              child: _buildModeA(user.userType),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode A: photo/search/manual tab switcher ───────────────────────────────

  Widget _buildModeA(UserType userType) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _ModeBtn(label: '📷 Photo',  isActive: _entryMode == 'PHOTO',  userType: userType, onTap: () => setState(() => _entryMode = 'PHOTO'))),
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
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Food Name')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _caloriesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Calories'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _carbsCtrl,    keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carbs (g)'))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _proteinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Protein (g)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _fatCtrl,     keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fat (g)'))),
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

  // ── Capture handlers ───────────────────────────────────────────────────────

  Future<void> _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final image = await _controller!.takePicture();
      await ref.read(mealRecognitionProvider.notifier).recognizeMeal(File(image.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $e')),
        );
      }
    }
  }

  Future<void> _handleGalleryPick() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await ref.read(mealRecognitionProvider.notifier).recognizeMeal(File(picked.path));
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isCameraReady) return;
    final current = _controller!.value.flashMode;
    await _controller!.setFlashMode(
      current == FlashMode.off ? FlashMode.torch : FlashMode.off,
    );
    setState(() {});
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _friendlyError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('401') || msg.contains('unauthorized') || msg.contains('not authenticated')) {
      return 'Your session has expired.\nPlease log in again.';
    }
    if (msg.contains('503') || msg.contains('502') || msg.contains('google_api_key') || msg.contains('service unavailable')) {
      return 'Food recognition is temporarily unavailable.\nPlease try again shortly.';
    }
    if (msg.contains('timeout') || msg.contains('connection') || msg.contains('network') || msg.contains('socket')) {
      return 'Network error.\nCheck your connection and try again.';
    }
    if (msg.contains('10 mb') || msg.contains('image exceeds')) {
      return 'Photo is too large.\nTry a lower-quality image.';
    }
    return 'Something went wrong.\nPlease try again.';
  }
}

// ── Warning banner (shown when no USDA data found) ────────────────────────────

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: Colors.amber.shade900, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Shared button widgets ──────────────────────────────────────────────────────

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
        child: Center(
          child: Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: isActive ? Colors.white : AppTheme.textPrimary),
          ),
        ),
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
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}
