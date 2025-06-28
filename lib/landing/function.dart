import 'package:flutter/material.dart';
import 'package:water_drop_nav_bar/water_drop_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medisight/standards/login.dart';
import 'dart:convert';
import 'dart:io';
import '../services/ai_service.dart';
import 'package:alarm/alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Global navigator key for accessing context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Providers for state management
final selectedIndexProvider = StateProvider<int>((ref) => 0);
final medicineSearchQueryProvider = StateProvider<String>((ref) => '');
final medicineSearchResultsProvider = StateProvider<List<dynamic>>((ref) => []);
final isSearchingProvider = StateProvider<bool>((ref) => false);
final cameraControllerProvider = StateProvider<CameraController?>((ref) => null);
final availableCamerasProvider = FutureProvider<List<CameraDescription>>((ref) async {
  return await availableCameras();
});
final recognizedTextProvider = StateProvider<String?>((ref) => null);

final isProcessingImageProvider = StateProvider<bool>((ref) => false);
final aiAnalysisResultProvider = StateProvider<String?>((ref) => null);
final capturedImageProvider = StateProvider<File?>((ref) => null);
final userProvider = StateProvider<User?>((ref) => FirebaseAuth.instance.currentUser);
final medicationRemindersProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);

class Medisight extends ConsumerStatefulWidget {
  const Medisight({super.key});

  @override
  ConsumerState<Medisight> createState() => _MedisightState();
}

class _MedisightState extends ConsumerState<Medisight> {
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final TextRecognizer textRecognizer = TextRecognizer();

  @override
  void initState() {
    super.initState();
    // Remove automatic camera initialization
    // _initializeCamera();

    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      ref.read(userProvider.notifier).state = user;
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    textRecognizer.close();
    final cameraController = ref.read(cameraControllerProvider);
    if (cameraController != null) {
      cameraController.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await cameraController.initialize();
      if (mounted) {
        ref.read(cameraControllerProvider.notifier).state = cameraController;
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> searchMedicine(String query) async {
    if (query.isEmpty) return;

    ref.read(isSearchingProvider.notifier).state = true;
    ref.read(medicineSearchQueryProvider.notifier).state = query;

    try {
      final response = await http.get(
        Uri.parse('https://api.fda.gov/drug/label.json?search=openfda.brand_name:"$query"&limit=5'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        ref.read(medicineSearchResultsProvider.notifier).state = data['results'] ?? [];
      } else {
        // Show error in snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.black,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              content: const Text(
                'Error searching for medicine',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Show error in snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: const Text(
              'Error searching for medicine',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      ref.read(isSearchingProvider.notifier).state = false;
    }
  }

  Future<void> processImage(CameraController controller) async {
    if (ref.read(isProcessingImageProvider)) return;

    ref.read(isProcessingImageProvider.notifier).state = true;
    ref.read(recognizedTextProvider.notifier).state = null;
    
    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text(
                  "Scanning the Medicine",
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          );
        },
      );
    }

    try {
      final image = await controller.takePicture();
      final file = File(image.path);
      ref.read(capturedImageProvider.notifier).state = file;

      final inputImage = InputImage.fromFile(file);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      if (recognizedText.text.isNotEmpty) {
        ref.read(recognizedTextProvider.notifier).state = recognizedText.text;
        // Instead of searching FDA, analyze with OpenRouter AI
        analyzeWithAI(recognizedText.text.split('\n').first);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.black,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              content: const Text(
                'No text recognized',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      print('Error processing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: const Text(
              'Error processing image',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      ref.read(isProcessingImageProvider.notifier).state = false;
    }
  }

  Future<void> analyzeWithAI(String medicineName) async {
    try {
      // Use the OpenRouter AI service from aiServiceProvider
      final aiService = ref.read(aiServiceProvider);
      final analysisResult = await aiService.getMedicineInfo(medicineName);
      
      // Update the analysis result provider
      ref.read(aiAnalysisResultProvider.notifier).state = analysisResult;
      
      // Get current user from userProvider
      final user = ref.read(userProvider);
      
      // Save scan result to Firestore if user is logged in
      if (user != null) {
        await FirebaseFirestore.instance.collection('scanHistories').add({
          'userId': user.uid,
          'medicineName': medicineName,
          'analysisResult': analysisResult,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      
      // Show the analysis result in a modal dialog
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.9,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder: (_, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Medicine Analysis: $medicineName',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: _buildFormattedAnalysisResult(analysisResult),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: const Text(
              'AI Analysis Error',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  // Helper method to format the analysis result
  Widget _buildFormattedAnalysisResult(String analysisResult) {
    // Split the result into sections based on common patterns
    final sections = analysisResult.split(RegExp(r'\n\s*\n|\n(?=[A-Z][\w\s]+:)'));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        // Clean up the section text
        final cleanSection = section
            .replaceAll(RegExp(r'[#\-~*]+\s*'), '')
            .trim();
            
        if (cleanSection.isEmpty) return const SizedBox.shrink();
        
        // Check if this section has a title
        final hasTitle = RegExp(r'^[A-Z][\w\s]+:').hasMatch(cleanSection);
        
        if (hasTitle) {
          final parts = cleanSection.split(':');
          final title = parts[0].trim();
          final content = parts.sublist(1).join(':').trim();
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              cleanSection,
              style: const TextStyle(fontSize: 16),
            ),
          );
        }
      }).toList(),
    );
  }

  void _openCameraScreen() async {
    // Initialize camera on demand
    await _initializeCamera();
    
    final cameraController = ref.read(cameraControllerProvider);
    if (cameraController == null || !cameraController.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: const Text(
            'Camera not initialized',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }
    
    // Show camera preview in a modal bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            Expanded(
              child: CameraPreview(cameraController),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                  FloatingActionButton(
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.camera_alt, color: Colors.black),
                    onPressed: () {
                      Navigator.pop(context);
                      processImage(cameraController);
                    },
                  ),
                  const SizedBox(width: 56), // For balance
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMedicineDetails(Map<String, dynamic> result) {
    final brandName = result['openfda']?['brand_name']?[0] ?? 'Unknown Brand';
    final genericName = result['openfda']?['generic_name']?[0] ?? 'Unknown Generic Name';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Medicine Analysis',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brandName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        genericName,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (result['indications_and_usage'] != null) ...[  
                        const Text(
                          'Indications and Usage',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(result['indications_and_usage'][0]),
                        const SizedBox(height: 20),
                      ],
                      if (result['warnings'] != null) ...[  
                        const Text(
                          'Warnings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(result['warnings'][0]),
                        const SizedBox(height: 20),
                      ],
                      if (result['adverse_reactions'] != null) ...[  
                        const Text(
                          'Adverse Reactions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(result['adverse_reactions'][0]),
                        const SizedBox(height: 20),
                      ],
                      if (result['dosage_and_administration'] != null) ...[  
                        const Text(
                          'Dosage and Administration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(result['dosage_and_administration'][0]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedIndexProvider);
    final searchResults = ref.watch(medicineSearchResultsProvider);
    final isSearching = ref.watch(isSearchingProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showMedicationReminderDialog(context),
          backgroundColor: Colors.blue,
          child: const Icon(Icons.alarm_add, color: Colors.white),
        ),
        resizeToAvoidBottomInset: false, 
        backgroundColor: Colors.white,
        body: IndexedStack(
          index: selectedIndex,
          children: [
            // Home Page
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MediSight',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Search Bar
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          )
                        ],
                      ),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: "Search Medicine",
                          border: InputBorder.none,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => searchMedicine(searchController.text),
                          ),
                        ),
                        onSubmitted: (value) => searchMedicine(value),
                      ),
                    ),
                    
                    // Search Results with Back Button and White Background
                    if (searchResults.isNotEmpty) ...[  
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () {
                              // Clear search results and return to home
                              ref.read(medicineSearchResultsProvider.notifier).state = [];
                              searchController.clear();
                            },
                          ),
                          const Text(
                            'Search Results',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: isSearching
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final result = searchResults[index];
                                  final brandName = result['openfda']?['brand_name']?[0] ?? 'Unknown';
                                  final genericName = result['openfda']?['generic_name']?[0] ?? 'Unknown';
                                  
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    color: Colors.white,  // Ensure white background
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(10),
                                      title: Text(
                                        brandName,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(genericName),
                                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                      onTap: () => _showMedicineDetails(result),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ] else if (isSearching) ...[  
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ] else ...[  
                      const SizedBox(height: 40),
                      Center(
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _openCameraScreen,
                              child: Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(2, 2),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 50,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Scan Medicine',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Take a photo of your medicine to get information',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Frequently Asked Questions',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildFaqItem(
                      'What is Medisight?',
                      'Medisight is an innovative mobile application designed to help users identify medications and access important information about them. Using advanced camera technology and AI analysis, Medisight allows you to scan medicine packaging or pills to get detailed information about usage, side effects, and precautions.'
                    ),
                    _buildFaqItem(
                      'How does Medisight work?',
                      'Medisight uses your device\'s camera to capture images of medication packaging or pills. Our advanced text recognition technology extracts the medicine name, which is then analyzed by our AI system to provide you with comprehensive information about the medication, including usage instructions, side effects, and precautions.'
                    ),
                    _buildFaqItem(
                      'Is my data secure with Medisight?',
                      'Yes, we take data security very seriously. All personal information is encrypted and stored securely. We do not share your medical information with third parties without your explicit consent. You can review our privacy policy for more details on how we handle your data.'
                    ),
                    _buildFaqItem(
                      'How accurate is Medisight\'s medicine identification?',
                      'Medisight uses advanced text recognition and AI technology to provide accurate information. However, the accuracy depends on factors like image quality, lighting conditions, and text clarity. Always consult with a healthcare professional before making decisions based on the app\'s information.'
                    ),
                    _buildFaqItem(
                      'Can I use Medisight without an internet connection?',
                      'Medisight requires an internet connection to analyze medications and provide information. This ensures you receive the most up-to-date and accurate information about your medications.'
                    ),
                    _buildFaqItem(
                      'Is Medisight a substitute for professional medical advice?',
                      'No, Medisight is designed to be an informational tool only. It should not replace professional medical advice, diagnosis, or treatment. Always consult with a qualified healthcare provider regarding any medical conditions or medications.'
                    ),
                    _buildFaqItem(
                      'How do I search for a medication?',
                      'You can search for medications in two ways: 1) Use the search bar on the home screen to type in the name of the medication, or 2) Tap the camera icon to scan the medication packaging or pill directly.'
                    ),
                    _buildFaqItem(
                      'What should I do if Medisight cannot identify my medication?',
                      'If Medisight cannot identify your medication, try improving the lighting conditions, ensuring the text is clearly visible, or using the manual search function instead. If issues persist, you can contact our support team for assistance.'
                    ),
                    _buildFaqItem(
                      'How do I update my account information?',
                      'You can update your account information by navigating to the Account tab, then selecting "Edit Profile". From there, you can modify your name, email, and other account details.'
                    ),
                    _buildFaqItem(
                      'Is Medisight available in multiple languages?',
                      'Currently, Medisight is available in English only. We are working on adding support for additional languages in future updates.'
                    ),
                  ],
                ),
              ),
            ),
            // Settings Page
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildSettingsSection(
                      'Notifications',
                      [
                        _buildSettingsToggle('Medication History', true),
                        _buildSettingsToggle('App Updates', false),
                        _buildSettingsToggle('Health Tips', true),
                      ],
                    ),
                    _buildSettingsSection(
                      'Appearance',
                      [
                        _buildSettingsOption('Text Size', 'Medium'),
                        _buildSettingsOption('Theme', 'Light'),
                      ],
                    ),
                    _buildSettingsSection(
                      'Privacy',
                      [
                        _buildSettingsToggle('Save Search History', true),
                        _buildSettingsToggle('Analytics', false),
                      ],
                    ),
                    _buildSettingsSection(
                      'Camera',
                      [
                        _buildSettingsOption('Default Resolution', 'High'),
                        _buildSettingsToggle('Auto Flash', false),
                      ],
                    ),
                    _buildSettingsSection(
                      'Medication',
                      [
                        _buildSettingsButton('Medication Reminders', onTap: () => _showMedicationReminderDialog(context)),
                      ],
                    ),
                    _buildSettingsSection(
                      'About',
                      [
                        _buildSettingsInfo('Version', '1.0.0'),
                        _buildSettingsInfo('Build', 'Rolddevs 28.06.2025'),
                        _buildSettingsButton('Terms of Service'),
                        _buildSettingsButton('Privacy Policy'),
                        _buildSettingsButton('Licenses'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
                        SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(userProvider);
                    final displayName = user?.displayName?.split(' ').first ?? 'User';
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        Center(
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.blue,
                                child: Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Hello, $displayName',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                user?.email ?? '',
                                style: const TextStyle(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildAccountSection(
                          'Account Settings',
                          [
                            _buildAccountOption(
                              'Edit Profile',
                              Icons.person_outline,
                              () => _showEditProfileDialog(context),
                            ),
                            _buildAccountOption(
                              'Change Password',
                              Icons.lock_outline,
                              () => _showChangePasswordDialog(context),
                            ),
                            _buildAccountOption(
                              'Email Preferences',
                              Icons.email_outlined,
                              () => _showEmailPreferencesDialog(context),
                            ),
                             _buildAccountOption(
                              'History',
                              Icons.history_outlined,
                              () => _showScanHistoryDialog(context),
                            ),
                          ],
                        ),
                        // _buildAccountSection(
                        //   'App Settings',
                        //   [
                        //     _buildAccountOption(
                        //       'Notification Settings',
                        //       Icons.notifications_none,
                        //       () {},
                        //     ),
                        //     _buildAccountOption(
                        //       'Privacy Settings',
                        //       Icons.privacy_tip_outlined,
                        //       () {},
                        //     ),
                        //   ],
                        // ),
                        // _buildAccountSection(
                        //   'Support',
                        //   [
                        //     _buildAccountOption(
                        //       'Help Center',
                        //       Icons.help_outline,
                        //       () {},
                        //     ),
                        //     _buildAccountOption(
                        //       'Contact Us',
                        //       Icons.mail_outline,
                        //       () {},
                        //     ),
                        //   ],
                        // ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                              if (mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (context) => const Login()),
                                  (route) => false,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Sign Out'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        // Bottom Navigation Bar
        bottomNavigationBar: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  offset: const Offset(0, -2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: WaterDropNavBar(
              backgroundColor: Colors.white,
              waterDropColor: Colors.black,
              onItemSelected: (index) {
                ref.read(selectedIndexProvider.notifier).state = index;
              },
              selectedIndex: selectedIndex,
              barItems: [
                BarItem(
                  filledIcon: Icons.home_rounded,
                  outlinedIcon: Icons.home_outlined,
                ),
                BarItem(
                  filledIcon: Icons.help_rounded,
                  outlinedIcon: Icons.help_outline_rounded,
                ),
                BarItem(
                  filledIcon: Icons.settings_rounded,
                  outlinedIcon: Icons.settings_outlined,
                ),
                BarItem(
                  filledIcon: Icons.person_rounded,
                  outlinedIcon: Icons.person_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Add this helper method for FAQ items
Widget _buildFaqItem(String question, String answer) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: ExpansionTile(
      title: Text(
        question,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            answer,
            style: const TextStyle(color: Colors.black),
          ),
        ),
      ],
    ),
  );
}

// Add these helper methods for Settings
Widget _buildSettingsSection(String title, List<Widget> children) {
  return Container(
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

Widget _buildSettingsToggle(String title, bool initialValue) {
  return Consumer(builder: (context, ref, _) {
    // Create a provider for each toggle if you want to persist state
    final toggleStateProvider = StateProvider.family<bool, String>((ref, id) => initialValue);
    final isEnabled = ref.watch(toggleStateProvider(title));
    
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.black)),
      trailing: Switch(
        value: isEnabled,
        onChanged: (newValue) {
          // Update the state using the provider
          ref.read(toggleStateProvider(title).notifier).state = newValue;
          // Here you would typically save this preference
          // For example: SharedPreferences.getInstance().then((prefs) => prefs.setBool(title, newValue));
        },
        activeColor: Colors.blue,
      ),
    );
  });
}

Widget _buildSettingsOption(String title, String value) {
  return Consumer(builder: (context, ref, _) {
    // Create a provider for each option if you want to persist state
    final optionStateProvider = StateProvider.family<String, String>((ref, id) => value);
    final currentValue = ref.watch(optionStateProvider(title));
    
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.black)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(currentValue, style: TextStyle(color: Colors.grey[600])),
          const Icon(Icons.arrow_forward_ios, size: 16),
        ],
      ),
      onTap: () {
        // Show options dialog
        showDialog(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text(title, style: const TextStyle(color: Colors.black)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title == 'Text Size') ...[  
                    _buildOptionItem(dialogContext, ref, title, 'Small', optionStateProvider),
                    _buildOptionItem(dialogContext, ref, title, 'Medium', optionStateProvider),
                    _buildOptionItem(dialogContext, ref, title, 'Large', optionStateProvider),
                  ] else if (title == 'Theme') ...[  
                    _buildOptionItem(dialogContext, ref, title, 'Light', optionStateProvider),
                    _buildOptionItem(dialogContext, ref, title, 'Dark', optionStateProvider),
                    _buildOptionItem(dialogContext, ref, title, 'System', optionStateProvider),
                  ] else if (title == 'Default Resolution') ...[  
                    _buildOptionItem(dialogContext, ref, title, 'Low', optionStateProvider),
                    _buildOptionItem(dialogContext, ref, title, 'Medium', optionStateProvider),
                    _buildOptionItem(dialogContext, ref, title, 'High', optionStateProvider),
                  ]
                ],
              ),
            );
          },
        );
      },
    );
  });
}

Widget _buildOptionItem(BuildContext context, WidgetRef ref, String title, String option, 
    StateProvider<String> Function(String) optionStateProvider) {
  final currentValue = ref.watch(optionStateProvider(title));
  final isSelected = currentValue == option;
  
  return ListTile(
    title: Text(option, style: const TextStyle(color: Colors.black)),
    trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
    onTap: () {
      // Update the state using the provider
      ref.read(optionStateProvider(title).notifier).state = option;
      // Here you would save the selected option
      // For example: SharedPreferences.getInstance().then((prefs) => prefs.setString(title, option));
      Navigator.of(context).pop();
    },
  );
}

Widget _buildSettingsInfo(String title, String value) {
  return ListTile(
    title: Text(title, style: const TextStyle(color: Colors.black)),
    trailing: Text(value, style: TextStyle(color: Colors.grey[600])),
  );
}

Widget _buildSettingsButton(String title, {VoidCallback? onTap}) {
  return ListTile(
    title: Text(title, style: const TextStyle(color: Colors.black)),
    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
    onTap: onTap ?? () {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(title, style: const TextStyle(color: Colors.black)),
            content: SingleChildScrollView(
              child: Text(
                'This is the $title content. In a real app, this would contain the actual $title information.',
                style: const TextStyle(color: Colors.black),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}

// Add these helper methods for Account page
Widget _buildAccountSection(String title, List<Widget> children) {
  return Container(
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    ),
  );
}

Widget _buildAccountOption(String title, IconData icon, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Colors.blue),
    title: Text(title, style: const TextStyle(color: Colors.black)),
    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
    onTap: onTap,
  );
}

void _showEditProfileDialog(BuildContext context) {
  final nameController = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Edit Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(
          labelText: 'Name',
          labelStyle: TextStyle(color: Colors.black),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue),
          ),
        ),
        style: const TextStyle(color: Colors.black),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () async {
            try {
              await FirebaseAuth.instance.currentUser?.updateDisplayName(nameController.text);
              
              // Update Firestore document
              final userId = FirebaseAuth.instance.currentUser?.uid;
              if (userId != null) {
                await FirebaseFirestore.instance.collection('users').doc(userId).update({
                  'name': nameController.text,
                });
              }
              
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated successfully')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating profile: $e')),
                );
              }
            }
          },
          child: const Text('Save', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

void _showChangePasswordDialog(BuildContext context) {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Change Password', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: currentPasswordController,
            decoration: const InputDecoration(
              labelText: 'Current Password',
              labelStyle: TextStyle(color: Colors.black),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            obscureText: true,
            style: const TextStyle(color: Colors.black),
          ),
          TextField(
            controller: newPasswordController,
            decoration: const InputDecoration(
              labelText: 'New Password',
              labelStyle: TextStyle(color: Colors.black),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            obscureText: true,
            style: const TextStyle(color: Colors.black),
          ),
          TextField(
            controller: confirmPasswordController,
            decoration: const InputDecoration(
              labelText: 'Confirm New Password',
              labelStyle: TextStyle(color: Colors.black),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            obscureText: true,
            style: const TextStyle(color: Colors.black),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () async {
            if (newPasswordController.text != confirmPasswordController.text) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Passwords do not match')),
              );
              return;
            }
            
            try {
              // Re-authenticate user
              final user = FirebaseAuth.instance.currentUser;
              final credential = EmailAuthProvider.credential(
                email: user?.email ?? '',
                password: currentPasswordController.text,
              );
              
              await user?.reauthenticateWithCredential(credential);
              await user?.updatePassword(newPasswordController.text);
              
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated successfully')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating password: $e')),
                );
              }
            }
          },
          child: const Text('Update', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

void _showEmailPreferencesDialog(BuildContext context) {
  final emailController = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.email ?? '',
  );
  bool receiveUpdates = true;
  
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Email Preferences', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: TextStyle(color: Colors.black),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.black),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Receive Updates', style: TextStyle(color: Colors.black)),
                value: receiveUpdates,
                onChanged: (value) {
                  setState(() => receiveUpdates = value ?? false);
                },
                activeColor: Colors.blue,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.currentUser?.updateEmail(emailController.text);
                  
                  // Update Firestore document
                  final userId = FirebaseAuth.instance.currentUser?.uid;
                  if (userId != null) {
                    await FirebaseFirestore.instance.collection('users').doc(userId).update({
                      'email': emailController.text,
                      'receiveUpdates': receiveUpdates,
                    });
                  }
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Email preferences updated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating email: $e')),
                    );
                  }
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    ),
  );
}

void _showScanHistoryDialog(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Scan History', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: user != null
          ? StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                .collection('scanHistories')
                .where('userId', isEqualTo: user.uid)
                .orderBy('timestamp', descending: true)
                .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                
                final docs = snapshot.data?.docs ?? [];
                
                if (docs.isEmpty) {
                  return const Center(child: Text('No scan history found'));
                }
                
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final medicineName = data['medicineName'] as String? ?? 'Unknown';
                    final timestamp = data['timestamp'] as Timestamp?;
                    final date = timestamp != null
                      ? DateTime.fromMillisecondsSinceEpoch(timestamp.millisecondsSinceEpoch)
                      : DateTime.now();
                    final formattedDate = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
                    
                    return ListTile(
                      title: Text(medicineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Scanned on $formattedDate'),
                      onTap: () => _showHistoryDetails(context, data),
                    );
                  },
                );
              },
            )
          : const Center(child: Text('Please log in to view scan history')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Colors.blue)),
        ),
      ],
    ),
  );
}

void _showHistoryDetails(BuildContext context, Map<String, dynamic> data) {
  final medicineName = data['medicineName'] as String? ?? 'Unknown';
  final analysisResult = data['analysisResult'] as String? ?? 'No analysis available';
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Details: $medicineName', 
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Analysis Result:', 
              style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(analysisResult),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: Colors.blue)),
        ),
      ],
    ),
  );
}

void _showMedicationReminderDialog(BuildContext context) {
  final TextEditingController medicationNameController = TextEditingController();
  final TextEditingController dosageController = TextEditingController();
  
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();
  bool repeat = false;
  List<bool> weekdays = List.generate(7, (_) => false); // [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
  
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              'Set Medication Reminder',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: medicationNameController,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Medication Name',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dosageController,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Dosage',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Date: ', style: TextStyle(color: Colors.black)),
                      TextButton(
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        child: Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Time: ', style: TextStyle(color: Colors.black)),
                      TextButton(
                        onPressed: () async {
                          final TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (picked != null) {
                            setState(() {
                              selectedTime = picked;
                            });
                          }
                        },
                        child: Text(
                          '${selectedTime.hour}:${selectedTime.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Repeat: ', style: TextStyle(color: Colors.black)),
                      Switch(
                        value: repeat,
                        onChanged: (value) {
                          setState(() {
                            repeat = value;
                          });
                        },
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                  if (repeat) ...[  
                    const SizedBox(height: 8),
                    const Text('Select days:', style: TextStyle(color: Colors.black)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildDayChip('Mon', weekdays[0], (val) => setState(() => weekdays[0] = val)),
                        _buildDayChip('Tue', weekdays[1], (val) => setState(() => weekdays[1] = val)),
                        _buildDayChip('Wed', weekdays[2], (val) => setState(() => weekdays[2] = val)),
                        _buildDayChip('Thu', weekdays[3], (val) => setState(() => weekdays[3] = val)),
                        _buildDayChip('Fri', weekdays[4], (val) => setState(() => weekdays[4] = val)),
                        _buildDayChip('Sat', weekdays[5], (val) => setState(() => weekdays[5] = val)),
                        _buildDayChip('Sun', weekdays[6], (val) => setState(() => weekdays[6] = val)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () {
                  _setMedicationReminder(
                    context,
                    medicationNameController.text,
                    dosageController.text,
                    selectedDate,
                    selectedTime,
                    repeat,
                    weekdays,
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save', style: TextStyle(color: Colors.blue)),
              ),
            ],
          );
        },
      );
    },
  );
}

// Helper method to build day selection chips
Widget _buildDayChip(String label, bool selected, Function(bool) onSelected) {
  return FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: onSelected,
    backgroundColor: Colors.grey[200],
    selectedColor: Colors.blue[100],
    checkmarkColor: Colors.blue,
    labelStyle: TextStyle(color: selected ? Colors.blue[800] : Colors.black),
  );
}

// Method to set the medication reminder
Future<void> _setMedicationReminder(
  BuildContext context,
  String medicationName,
  String dosage,
  DateTime date,
  TimeOfDay time,
  bool repeat,
  List<bool> weekdays,
) async {
  if (medicationName.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please enter medication name')),
    );
    return;
  }

  // Create a DateTime object for the alarm
  final now = DateTime.now();
  DateTime alarmDateTime = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  
  // If the selected time is in the past, set it for tomorrow
  if (alarmDateTime.isBefore(now) && !repeat) {
    alarmDateTime = alarmDateTime.add(const Duration(days: 1));
  }

  // Generate a unique ID for this alarm
  final int alarmId = DateTime.now().millisecondsSinceEpoch % 100000;

  // Create alarm settings
  final alarmSettings = AlarmSettings(
    id: alarmId,
    dateTime: alarmDateTime,
    assetAudioPath: 'assets/audio/alarm.mp3',
    loopAudio: true,
    vibrate: true,
    warningNotificationOnKill: Platform.isIOS,
    androidFullScreenIntent: true,
    volumeSettings: VolumeSettings.fade(
      volume: 0.8,
      fadeDuration: const Duration(seconds: 5),
      volumeEnforced: true,
    ),
    notificationSettings: NotificationSettings(
      title: 'Medication Reminder',
      body: 'Time to take $medicationName ($dosage)',
      stopButton: 'Stop',
      icon: 'notification_icon',
      iconColor: const Color(0xff000000),
    ),
  );

  try {
    // Set the alarm
    await Alarm.set(alarmSettings: alarmSettings);
    
    // Save the reminder details to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final reminders = prefs.getStringList('medication_reminders') ?? [];
    
    final reminderData = {
      'id': alarmId,
      'name': medicationName,
      'dosage': dosage,
      'time': '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
      'repeat': repeat,
      'weekdays': weekdays,
    };
    
    reminders.add(jsonEncode(reminderData));
    await prefs.setStringList('medication_reminders', reminders);
    
    // Show success message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminder set for $medicationName'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set reminder: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
