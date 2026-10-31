import 'package:cloud_firestore/cloud_firestore.dart';

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.copies,
  });

  static const maxCopies = 1000; // Same limit as firestore.rules

  final String id; // Firestore Document ID (the ISBN)
  final String title;
  final String author;
  final int copies;

  factory Book.fromMap(String id, Map<String, dynamic> data) {
    return Book(
      id: id,
      title: data['title'] as String? ?? '',
      author: data['author'] as String? ?? '',
      copies: (data['copies'] as num?)?.toInt() ?? 0,
    );
  }

  factory Book.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Book.fromMap(doc.id, doc.data() ?? const {});
  }

  bool get isAvailable => copies > 0;

  /// The required display format: Title – Author – Copies Available.
  String get displayLine => '$title – $author – $copies';

  /// Returns an error message, or null when [input] is a valid copies value.
  static String? validateCopies(String? input) {
    final text = input?.trim() ?? '';
    if (text.isEmpty) return 'Please enter the number of copies';
    // BigInt, so a very long number is reported as out of range.
    final value = BigInt.tryParse(text);
    if (value == null) return 'Please enter a whole number';
    if (value.isNegative || value > BigInt.from(maxCopies)) {
      return 'Copies must be between 0 and $maxCopies';
    }
    return null;
  }
}
