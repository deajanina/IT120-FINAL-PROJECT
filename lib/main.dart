import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/firestore_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

// ------------------------------------------------------
// APP ROOT
// ------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8D6E63); // brown-ish
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Raw Nuts Classification',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF9F4EF),
        fontFamily: 'Roboto',
      ),
      home: const OnboardingScreen(),
    );
  }
}

// ------------------------------------------------------
// SIMPLE MODEL FOR NUT INFORMATION
// ------------------------------------------------------
class NutInfo {
  final String label; // must match labels.txt text
  final String imagePath;
  final String shortDescription;

  const NutInfo({
    required this.label,
    required this.imagePath,
    required this.shortDescription,
  });
}

class PredictionLog {
  final String label;
  final double confidence;
  final DateTime time;
  final String? imagePath;

  bool verified;
  String? actualLabel;

  PredictionLog({
    required this.label,
    required this.confidence,
    required this.time,
    this.imagePath,
    this.verified = true,
    this.actualLabel,
  });
}

class AnalyticsService {

  static double verificationRate(List<PredictionLog> logs) {
    if (logs.isEmpty) return 0;
    final verified = logs.where((l) => l.verified).length;
    return verified / logs.length;
  }

  static double errorRate(List<PredictionLog> logs) {
    if (logs.isEmpty) return 0;
    final wrong = logs.where((l) => !l.verified).length;
    return wrong / logs.length;
  }

  static int totalDetections(List<PredictionLog> logs) => logs.length;

  static List<PredictionLog> wrongDetections(List<PredictionLog> logs) {
    return logs.where((l) => l.verified == false).toList();
  }

  static int todayDetections(List<PredictionLog> logs) {
    final now = DateTime.now();
    return logs.where((l) =>
    l.time.year == now.year &&
        l.time.month == now.month &&
        l.time.day == now.day
    ).length;
  }

  static double averageConfidence(List<PredictionLog> logs) {
    if (logs.isEmpty) return 0;
    final sum = logs.fold(0.0, (a, b) => a + b.confidence);
    return sum / logs.length;
  }

  static double accuracy(List<PredictionLog> logs) {
    if (logs.isEmpty) return 0;
    final correct = logs.where((l) => l.verified).length;
    return correct / logs.length;
  }

  static Map<String, int> perClassCount(List<PredictionLog> logs) {
    final Map<String, int> map = {};
    for (final l in logs) {
      map[l.label] = (map[l.label] ?? 0) + 1;
    }
    return map;
  }
}

Map<String, List<PredictionLog>> groupByMonth(List<PredictionLog> logs) {
  final Map<String, List<PredictionLog>> map = {};
  for (final l in logs) {
    final key = '${l.time.year}-${l.time.month}';
    map.putIfAbsent(key, () => []).add(l);
  }
  return map;
}

class AnalyticsColors {
  static const primary = Color(0xFF8D6E63); // brown
  static const secondary = Color(0xFF4E342E); // dark brown
  static const accent = Color(0xFFA1887F); // soft brown
  static const background = Color(0xFFF9F4EF);
}


class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = _predictionLogs;

    final total = AnalyticsService.totalDetections(logs);
    final totalAcc = AnalyticsService.accuracy(logs);
    final verifyRate = AnalyticsService.verificationRate(logs);
    final errorRate = AnalyticsService.errorRate(logs);
    final perClass = AnalyticsService.perClassCount(logs);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Overview')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// ================= KPI ROW =================
            Row(
              children: [
                _kpiCard('Total', total.toString()),
                _kpiCard(
                  'Total Accuracy',
                  '${(totalAcc * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
            Row(
              children: [
                _kpiCard(
                  'Verif. Rate',
                  '${(verifyRate * 100).toStringAsFixed(1)}%',
                ),
                _kpiCard(
                  'Error Rate',
                  '${(errorRate * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),

            const SizedBox(height: 28),

            const Divider(thickness: 1),
            const SizedBox(height: 32),
            const Text(
              'Wrong Detections (Error Analysis)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (AnalyticsService.wrongDetections(logs).isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No wrong detections recorded',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              WrongDetectionChart(
                logs: AnalyticsService.wrongDetections(logs),
              ),
            const SizedBox(height: 36),
            const Divider(thickness: 1),

            /// ================= CLASS BAR =================
            const SizedBox(height: 12),
            const Text(
              'Nut Classification Distribution',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            PerClassBarChart(data: perClass),

            const SizedBox(height: 36),
            const Divider(thickness: 1),
            const SizedBox(height: 16),

            ClassDataTable(data: perClass),

          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String title, String value) {
    return Expanded(
      child: SizedBox(
        height: 110,
        child: Card(
          margin: const EdgeInsets.all(6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13,),),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AnalyticsColors.primary,
                  ),
                ),

              ],
            ),
          ),
        ),
      )
    );
  }
}

class ClassDataTable extends StatelessWidget {
  final Map<String, int> data;

  const ClassDataTable({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(
        AnalyticsColors.primary.withValues(alpha: 0.1),
      ),
      columns: const [
        DataColumn(
          label: Center(child: Text('Nut Type')),
        ),
        DataColumn(
          label: Center(child: Text('Detections')),
          numeric: true,
        ),
      ],
      rows: data.entries.map((e) {
        return DataRow(
          cells: [
            DataCell(
              Center(child: Text(e.key)),
            ),
            DataCell(
              Center(child: Text(e.value.toString())),
            ),
          ],
        );
      }).toList(),
    );

  }
}


const List<NutInfo> kNutInfos = [
  NutInfo(
    label: 'Almond',
    imagePath: 'assets/nuts/almond.jpg',
    shortDescription:
    'A crunchy tree nut with mild flavor, often eaten raw or roasted.',
  ),
  NutInfo(
    label: 'Cashew',
    imagePath: 'assets/nuts/cashew.jpg',
    shortDescription:
    'Soft and buttery, commonly used in snacks, desserts, and sauces.',
  ),
  NutInfo(
    label: 'Peanut',
    imagePath: 'assets/nuts/peanut.jpg',
    shortDescription:
    'A groundnut rich in protein, popular in peanut butter and snacks.',
  ),
  NutInfo(
    label: 'Walnut',
    imagePath: 'assets/nuts/walnut.jpg',
    shortDescription:
    'Brain-shaped nut with a slightly bitter taste, great for baking.',
  ),
  NutInfo(
    label: 'Pistachio',
    imagePath: 'assets/nuts/pistachio.jpg',
    shortDescription:
    'Small green nut in a half-open shell, enjoyed as a salty snack.',
  ),
  NutInfo(
    label: 'Hazelnut',
    imagePath: 'assets/nuts/hazelnut.jpg',
    shortDescription:
    'Round nut with sweet taste, famous in chocolate spreads and pralines.',
  ),
  NutInfo(
    label: 'Macadamia',
    imagePath: 'assets/nuts/macadamia.jpg',
    shortDescription:
    'Rich and creamy nut, often used in cookies and premium snacks.',
  ),
  NutInfo(
    label: 'Pecan',
    imagePath: 'assets/nuts/pecan.jpg',
    shortDescription:
    'Sweet, buttery nut commonly used in pies and roasted mixes.',
  ),
  NutInfo(
    label: 'Pili',
    imagePath: 'assets/nuts/pili.jpg',
    shortDescription:
    'Native to the Philippines, soft and oily with a rich, buttery taste.',
  ),
  NutInfo(
    label: 'Pine',
    imagePath: 'assets/nuts/pine.jpg',
    shortDescription:
    'Tiny seeds from pine cones, often used in pesto and salads.',
  ),
];

NutInfo? nutInfoForLabel(String label) {
  for (final n in kNutInfos) {
    if (n.label.toLowerCase().trim() == label.toLowerCase().trim()) {
      return n;
    }
  }
  return null;
}

// ------------------------------------------------------
// ONBOARDING SCREEN
// ------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _slide =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(_fade);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const MainNavigationPage(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF4E342E),
              Color(0xFF8D6E63),
              Color(0xFFF3E5AB),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Raw Nuts\nClassification',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Capture raw nut samples and instantly know which nut class they belong to.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Center(
                  child: Hero(
                    tag: 'hero-nuts-main',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/nuts/mixed.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                SlideTransition(
                  position: _slide,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.eco_rounded,
                                color: color.secondaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              'Supports 10 nut varieties',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.camera_alt_rounded,
                                color: color.secondaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              'Use camera or gallery images',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _goToHome,
                            style: ElevatedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF4E342E),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 6,
                            ),
                            child: const Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------
// MAIN CLASSIFIER SCREEN (HOME)
// ------------------------------------------------------
class ClassifierScreen extends StatefulWidget {
  const ClassifierScreen({super.key});

  @override
  State<ClassifierScreen> createState() => _ClassifierScreenState(

  );
}

// NOTE: Using a shared in-memory list for simplicity.
// In production, this would be handled via Provider / Riverpod / BLoC.
final List<PredictionLog> _predictionLogs = [];
List<double> _lastOutputScores = [];

const double CONFIDENCE_THRESHOLD = 0.95;

class ConfidenceBarGraph extends StatelessWidget {
  final List<String> labels;
  final List<double> scores;

  const ConfidenceBarGraph({
    super.key,
    required this.labels,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) return const SizedBox();

    final maxScore = scores.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Confidence Graph',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...List.generate(scores.length, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    labels[i],
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: maxScore == 0 ? 0 : scores[i] / maxScore,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.brown.shade400,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(scores[i] * 100).toStringAsFixed(1)}%'),
              ],
            ),
          );
        }),
      ],
    );
  }
}



class _ClassifierScreenState extends State<ClassifierScreen> {
  File? _imageFile;

  Interpreter? _interpreter;
  List<String> _labels = [];

  late CameraController _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isCameraReady = false;
  bool _isLoading = false;
  bool _showConfidenceGraph = false;

  String _resultLabel = '';
  double _resultConfidence = 0.0;
  NutInfo? _predictedNut;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initTFLiteModel().then((_) {
      // You can print info here if you want
      _printModelInfo();
    });
  }

  @override
  void dispose() {
    if (_isCameraReady) {
      _cameraController.dispose();
    }
    _interpreter?.close();
    super.dispose();
  }


  // ------------------- MODEL LOADING -------------------
  Future<void> _initTFLiteModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model_unquant.tflite');
      debugPrint('MODEL LOADED SUCCESSFULLY!');
    } catch (e) {
      debugPrint('MODEL LOADING FAILED: $e');
    }

    try {
      final rawLabels = await rootBundle.loadString('assets/labels.txt');
      _labels =
          rawLabels.split('\n').where((e) => e.trim().isNotEmpty).toList();
      debugPrint('LABELS LOADED: ${_labels.length}');
    } catch (e) {
      debugPrint('LABELS FAILED TO LOAD: $e');
    }
  }

  void _printModelInfo() {
    if (_interpreter == null) {
      debugPrint('Interpreter is NULL, cannot print model info.');
      return;
    }
    final input = _interpreter!.getInputTensors();
    final output = _interpreter!.getOutputTensors();

    debugPrint('==== MODEL INFO ====');
    for (final t in input) {
      debugPrint('INPUT: name=${t.name}, shape=${t.shape}, type=${t.type}');
    }
    for (final t in output) {
      debugPrint('OUTPUT: name=${t.name}, shape=${t.shape}, type=${t.type}');
    }
  }

  // ------------------- CAMERA -------------------
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _cameraController = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController.initialize();
      if (!mounted) return;

      setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    _selectedCameraIndex = _selectedCameraIndex == 0 ? 1 : 0;
    setState(() => _isCameraReady = false);

    await _cameraController.dispose();
    await _initCamera();
  }

  Future<void> _takePhoto() async {
    if (!_cameraController.value.isInitialized) return;

    try {
      final XFile file = await _cameraController.takePicture();
      final imgFile = File(file.path);

      setState(() {
        _imageFile = imgFile;
      });
      setState(() {
        _showConfidenceGraph = false;
      });


      await _classifyImage(imgFile);

      await _cameraController.resumePreview();

    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }

  // ------------------- GALLERY PICK -------------------
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    // Just pause preview, do not dispose
    if (_cameraController.value.isInitialized) {
      await _cameraController.pausePreview();
    }

    final imgFile = File(image.path);
    setState(() {
      _isCameraReady = false;
      _imageFile = imgFile;
    });
    setState(() {
      _showConfidenceGraph = false;
    });


    await _classifyImage(imgFile);
  }

  // ------------------- CLASSIFICATION -------------------
  Future<void> _classifyImage(File imageFile) async {
    if (_interpreter == null) {
      debugPrint('ERROR: Interpreter not loaded.');
      return;
    }

    setState(() {
      _isLoading = true;
      _resultLabel = '';
      _resultConfidence = 0.0;
      _predictedNut = null;
    });

    final bytes = await imageFile.readAsBytes();
    final oriImage = img.decodeImage(bytes);

    if (oriImage == null) {
      debugPrint('Could not decode image.');
      setState(() => _isLoading = false);
      return;
    }

    final resized = img.copyResize(
      oriImage,
      width: 224,
      height: 224,
    );

    // shape: [1, 224, 224, 3]
    final input = List.generate(
      1,
          (_) =>
          List.generate(
            224,
                (_) =>
                List.generate(
                  224,
                      (_) => List.filled(3, 0.0),
                ),
          ),
    );

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        input[0][y][x][0] = pixel.r / 255.0;
        input[0][y][x][1] = pixel.g / 255.0;
        input[0][y][x][2] = pixel.b / 255.0;
      }
    }

    // 10 output classes
    final output = List.filled(10, 0.0).reshape([1, 10]);

    _interpreter!.run(input, output);

    double maxProb = -1;
    int maxIndex = -1;
    for (int i = 0; i < output[0].length; i++) {
      if (output[0][i] > maxProb) {
        maxProb = output[0][i];
        maxIndex = i;
      }
    }

    final label =
    (maxIndex >= 0 && maxIndex < _labels.length)
        ? _labels[maxIndex]
        : '';

    final bool isVerified = maxProb >= CONFIDENCE_THRESHOLD;

    final log = PredictionLog(
      label: label,
      confidence: maxProb,
      time: DateTime.now(),
      imagePath: imageFile.path,
      verified: isVerified,
      actualLabel: isVerified ? label : null,
    );


    setState(() {
      _isLoading = false;
      _resultLabel = label;
      _resultConfidence = maxProb;
      _predictedNut = nutInfoForLabel(label);
      _lastOutputScores = List<double>.from(output[0]);
      _predictionLogs.insert(0, log);
      _showConfidenceGraph = true;
    });

    await FirestoreService.savePrediction(log);
  }

  void _openNutClasses() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NutClassesPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => const OnboardingScreen(),
              ),
                  (route) => false,
            );
          },
        ),
        title: const Text('Raw Nuts Classification'),
        centerTitle: true,
        elevation: 2,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              // BIG CARD
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFF5E6D3),
                      Color(0xFFE6D1B3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.brown,
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        height: 280,
                        width: double.infinity,
                        color: Colors.black,
                        child: (!_isCameraReady && _imageFile != null)
                            ? Image.file(_imageFile!, fit: BoxFit.cover)
                            : _isCameraReady
                            ? Stack(
                          children: [
                            Positioned.fill(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _cameraController
                                      .value.previewSize!.height,
                                  height: _cameraController
                                      .value.previewSize!.width,
                                  child:
                                  CameraPreview(_cameraController),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.cameraswitch),
                                  onPressed: _switchCamera,
                                ),
                              ),
                            ),
                          ],
                        )
                            : const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _isLoading
                          ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                          : Column(
                        key: ValueKey(_resultLabel + _resultConfidence.toString()),
                        children: [
                          Text(
                            _resultLabel.isEmpty
                                ? 'No Prediction Yet'
                                : 'Prediction: $_resultLabel',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_resultConfidence > 0)
                            Text(
                              'Confidence: ${(_resultConfidence * 100).toStringAsFixed(2)}%',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (_predictedNut != null)
                            Column(
                              children: [
                                Hero(
                                  tag:
                                  'nut-${_predictedNut!.label}-hero-prediction',
                                  child: ClipRRect(
                                    borderRadius:
                                    BorderRadius.circular(16),
                                    child: Image.asset(
                                      _predictedNut!.imagePath,
                                      height: 130,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _predictedNut!.shortDescription,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),

                          if (_showConfidenceGraph && _lastOutputScores.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: ConfidenceBarGraph(
                                labels: _labels,
                                scores: _lastOutputScores,
                              ),
                            ),

                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Take Photo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      backgroundColor: const Color(0xFF4E7D3A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 4,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _openNutClasses,
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('View All Nut Classes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------
// NUT CLASSES PAGE (LIST)
// ------------------------------------------------------
class NutClassesPage extends StatelessWidget {
  const NutClassesPage({super.key});

  void _openDetail(BuildContext context, NutInfo nut) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NutDetailPage(nut: nut)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nut Classes'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: kNutInfos.length,
        itemBuilder: (context, index) {
          final nut = kNutInfos[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InkWell(
              onTap: () => _openDetail(context, nut),
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.brown,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Hero(
                      tag: 'nut-${nut.label}-hero',
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                        ),
                        child: Image.asset(
                          nut.imagePath,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nut.label,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              nut.shortDescription,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.chevron_right,
                                    size: 18, color: color.primary),
                                Text(
                                  'See more',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: color.primary,
                                  ),
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
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------
// NUT DETAIL PAGE
// ------------------------------------------------------
class NutDetailPage extends StatelessWidget {
  final NutInfo nut;

  const NutDetailPage({super.key, required this.nut});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(nut.label),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'nut-${nut.label}-hero',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  nut.imagePath,
                  width: double.infinity,
                  height: 260,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              nut.label,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              nut.shortDescription,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: color.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Image shown is a sample reference for this nut class. '
                          'Captured predictions may look slightly different depending on lighting and angle.',
                      style: TextStyle(
                        fontSize: 14,
                        color: color.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to classes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------
// PREDICTION LOGS PAGE
// ------------------------------------------------------
class PredictionLogsPage extends StatelessWidget {
  final List<PredictionLog> logs;

  const PredictionLogsPage({
    super.key,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prediction Logs'),
        centerTitle: true,
      ),
      body: logs.isEmpty
          ? const Center(child: Text('No predictions yet'))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: log.imagePath != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(log.imagePath!),
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              )
                  : const Icon(Icons.eco),

              title: Text(log.label),
              subtitle: Text(
                'Confidence: ${(log.confidence * 100).toStringAsFixed(2)}%',
              ),
              trailing: Text(
                '${log.time.hour}:${log.time.minute.toString().padLeft(2, '0')}',
              ),
            ),
          );
        },
      ),
    );
  }
}

class ConfidenceGraphPage extends StatelessWidget {
  final List<String> labels;
  final List<double> scores;

  const ConfidenceGraphPage({
    super.key,
    required this.labels,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confidence Graph'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: scores.isEmpty
            ? const Center(child: Text('No prediction data yet'))
            : SingleChildScrollView(
          child: ConfidenceBarGraph(
            labels: labels,
            scores: scores,
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _clearCloudData(BuildContext context) async {
    await FirestoreService.clearAllPredictions();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cloud prediction history cleared'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            // 🔹 LOCAL CLEAR
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear Local History'),
              subtitle: const Text('Removes predictions from this device only'),
              onTap: () {
                _predictionLogs.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Local data cleared')),
                );
              },
            ),

            const Divider(),

            // 🔹 CLOUD CLEAR
            ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text('Clear Cloud History'),
              subtitle: const Text('Deletes predictions from Firebase'),
              onTap: () => _clearCloudData(context),
            ),

            const Divider(),

            // 🔹 FIREBASE STATUS
            const ListTile(
              leading: Icon(Icons.cloud_done, color: Colors.green),
              title: Text('Firebase Status'),
              subtitle: Text('Connected to Firestore'),
            ),

            const Divider(),

            // 🔹 APP INFO
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('App Information'),
              subtitle: Text(
                'Raw Nuts Classification\n'
                    'Model: TFLite CNN\n'
                    'Input: 224×224 Image\n'
                    'Classes: 10 nut varieties',
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _index = 0;

  late final List<Widget> pages = [
    const ClassifierScreen(),
    const AnalyticsPage(),
    PredictionLogsPage(logs: _predictionLogs),
    const SettingsPage(),
  ];

        @override
        void initState() {
        super.initState();
        _loadHistory();
        }

        Future<void> _loadHistory() async {
        final data = await FirestoreService.loadPredictions();
        setState(() {
        _predictionLogs
        ..clear()
        ..addAll(data);
        });
        }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class PerClassBarChart extends StatelessWidget {
  final Map<String, int> data;

  const PerClassBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No data yet'));
    }

    final labels = data.keys.toList();

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),

          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),

            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
              ),
            ),

            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox();

                  return Transform.rotate(
                    angle: -0.6, // slant left
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        labels[i],
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  );
                },

              ),
            ),
          ),

          barGroups: List.generate(labels.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[labels[i]]!.toDouble(),
                  width: 18,
                  color: AnalyticsColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class WrongDetectionChart extends StatelessWidget {
  final List<PredictionLog> logs;

  const WrongDetectionChart({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Text('No wrong detections 🎉');
    }

    final Map<String, int> errors = {};

    for (final l in logs) {
      final key = '${l.label}';
      errors[key] = (errors[key] ?? 0) + 1;
    }

    final keys = errors.keys.toList();

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= keys.length) return const SizedBox();

                  return Transform.rotate(
                    angle: -0.6, // ~ -35 degrees
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        keys[i],
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  );
                },


              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, interval: 1),
            ),
          ),
          barGroups: List.generate(keys.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: errors[keys[i]]!.toDouble(),
                  color: Colors.redAccent,
                  width: 18,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}





