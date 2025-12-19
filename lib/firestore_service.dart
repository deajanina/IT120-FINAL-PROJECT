import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; // or where PredictionLog is

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> savePrediction(PredictionLog log) async {
    await _db.collection('predictions').add({
      'label': log.label,
      'confidence': log.confidence,
      'time': Timestamp.fromDate(log.time),
      'imagePath': log.imagePath,
      'verified': log.verified,
    });
  }

  static Future<List<PredictionLog>> loadPredictions() async {
    final snap = await _db
        .collection('predictions')
        .orderBy('time', descending: true)
        .get();

    return snap.docs.map((d) {
      final data = d.data();
      return PredictionLog(
        label: data['label'],
        confidence: data['confidence'],
        time: (data['time'] as Timestamp).toDate(),
        imagePath: data['imagePath'],
        verified: data['verified'] ?? true,
      );
    }).toList();
  }

  static Future<void> updateVerification(PredictionLog log) async {
    await FirebaseFirestore.instance
        .collection('predictions')
        .where('imagePath', isEqualTo: log.imagePath)
        .limit(1)
        .get()
        .then((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        snapshot.docs.first.reference.update({
          'verified': log.verified,
          'actualLabel': log.actualLabel,
        });
      }
    });
  }


  static Future<void> clearAllPredictions() async {
    final snapshot = await _db.collection('predictions').get();

    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}


