import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:camera/camera.dart';

class OcrService {
  final textRecognizer = TextRecognizer();
  List<TextBlock> detectedBlocks = [];
  
  Future<String> processImage(XFile image) async {
    final inputImage = InputImage.fromFilePath(image.path);
    final recognizedText = await textRecognizer.processImage(inputImage);
    
    // Store detected blocks for UI highlighting
    detectedBlocks = recognizedText.blocks;
    
    return recognizedText.text;
  }
  
  List<TextBlock> getDetectedBlocks() {
    return detectedBlocks;
  }
  
  void dispose() {
    textRecognizer.close();
  }
}

// Provider for OCR service
final ocrServiceProvider = Provider<OcrService>((ref) => OcrService());

// Provider for available cameras
final availableCamerasProvider = FutureProvider<List<CameraDescription>>((ref) async {
  return await availableCameras();
});

// Provider for detected text blocks
final detectedTextBlocksProvider = StateProvider<List<TextBlock>>((ref) => []);

// Provider for selected text
final selectedTextProvider = StateProvider<String>((ref) => '');