import 'package:flutter/material.dart';
import '../../../../core/icons/lucide_icons.dart';
import 'dart:io';
import '../../../../core/app_colors.dart';
import '../widgets/meal_recognition_card.dart';
import '../../services/camera_service.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scanController;
  final MealCameraService _cameraService = MealCameraService();
  File? _capturedImage;
  bool _isScanning = false;
  
  // Simulated result from backend
  final MealRecognitionResult _demoResult = MealRecognitionResult(
    mealLogId: '1234',
    foodItems: [{'name': 'Avocado Toast & Eggs'}],
    totals: {
      'carbs_g': 32,
      'glycaemic_load': 14,
      'calories': 420,
      'protein_g': 18,
      'fat_g': 22,
    },
    recommendation: {'recommended_bolus': 4.2},
    recognitionConfidence: 0.95,
    requiresConfirmation: false,
  );

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _handleCapture(bool fromGallery) async {
    final file = fromGallery 
        ? await _cameraService.pickFromGallery()
        : await _cameraService.captureFromCamera();
        
    if (file != null) {
      setState(() {
        _capturedImage = file;
        _isScanning = true;
      });
      // Simulate network scan delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nutrition', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            labelColor: AppColors.nearBlack,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.limeAccent,
            tabs: [
              Tab(text: 'Scanner'),
              Tab(text: 'History'),
              Tab(text: 'Insights'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(), // Prevent accidental swipes while scanning
          children: [
            _buildScannerTab(),
            _buildHistoryTab(theme),
            _buildInsightsTab(theme),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: SCANNER
  // ==========================================
  Widget _buildScannerTab() {
    return Container(
      color: AppColors.cameraBackground,
      child: SafeArea(
        child: Stack(
          children: [
            // Mock Camera Preview Area
            Positioned.fill(
              child: Container(
                color: AppColors.nearBlack,
                child: _capturedImage != null
                    ? Image.file(_capturedImage!, fit: BoxFit.cover)
                    : const Center(
                        child: Icon(LucideIcons.image, color: Colors.white10, size: 100),
                      ),
              ),
            ),
            
            // Scanner Overlay
            if (_capturedImage == null || _isScanning)
              Positioned.fill(
                child: _buildScannerOverlay(),
              ),
            
            // Bottom Results & Shutter Row
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black, Colors.black87, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Detected Food Overlay (Only show if we captured something and aren't scanning)
                    if (_capturedImage != null && !_isScanning)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.darkSurface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _demoResult.foodItems[0]['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${_demoResult.totals["calories"]} kcal',
                                      style: const TextStyle(
                                        color: AppColors.vividOrange,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'GL ${_demoResult.totals["glycaemic_load"]}',
                                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _capturedImage = null; // reset
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.vividOrange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Log it'),
                            )
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 32),
                    
                    // Physical Shutter Button Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.image, color: Colors.white54, size: 28),
                          onPressed: () => _handleCapture(true),
                        ),
                        GestureDetector(
                          onTap: () => _handleCapture(false),
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
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.keyboard, color: Colors.white54, size: 28),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerOverlay() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Stack(
          children: [
            // Center Frame
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    // Corners
                    _buildCorner(Alignment.topLeft),
                    _buildCorner(Alignment.topRight),
                    _buildCorner(Alignment.bottomLeft),
                    _buildCorner(Alignment.bottomRight),
                    
                    // Scan Line
                    Positioned(
                      top: 250 * _scanController.value,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.limeAccent,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.limeAccent.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            top: (alignment == Alignment.topLeft || alignment == Alignment.topRight)
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
            bottom: (alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight)
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
            left: (alignment == Alignment.topLeft || alignment == Alignment.bottomLeft)
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
            right: (alignment == Alignment.topRight || alignment == Alignment.bottomRight)
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: HISTORY
  // ==========================================
  Widget _buildHistoryTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text('TODAY', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        _buildHistoryTile(theme, 'Breakfast', '08:12', '340 cal', '3.8u rec'),
        const Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Divider()),
        
        Text('YESTERDAY', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        _buildHistoryTile(theme, 'Dinner', '19:45', '620 cal', '5.1u rec'),
        const SizedBox(height: 8),
        _buildHistoryTile(theme, 'Lunch', '13:20', '480 cal', '4.2u rec'),
        const SizedBox(height: 8),
        _buildHistoryTile(theme, 'Breakfast', '08:05', '310 cal', '3.5u rec'),
      ],
    );
  }

  Widget _buildHistoryTile(ThemeData theme, String meal, String time, String calories, String bolus) {
    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(meal, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(time, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Text(calories, style: const TextStyle(color: Colors.grey)),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(bolus, style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text('Feature Vector Summary', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('• Sleep deficit detected (6.1h)\n• No recent activity\n• Glycaemic load: 24 (High)', style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: Colors.grey.shade700)),
                const SizedBox(height: 16),
                Text('Post-Meal Response', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.show_chart, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text('Peaked at 138 mg/dL (In range)', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.green)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: INSIGHTS
  // ==========================================
  Widget _buildInsightsTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('THIS WEEK', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  _buildContextRow(theme, 'Avg daily calories', '1,840'),
                  const Divider(),
                  _buildContextRow(theme, 'Avg carbs per meal', '54g'),
                  const Divider(),
                  _buildContextRow(theme, 'Highest GL meal', 'White rice dinner (GL 28)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          
          Card(
            color: Colors.indigo.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.lightbulb_outline, color: Colors.indigo),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Insight', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Your post-dinner glucose spikes are 40% lower on days you eat before 7:30 PM.', style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
