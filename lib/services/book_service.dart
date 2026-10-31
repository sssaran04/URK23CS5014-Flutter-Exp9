import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/book.dart';

/// Reads books and updates their copies. The app never adds or deletes a book.
class BookService {
  BookService({FirebaseFirestore? firestore})
      : _books = (firestore ?? FirebaseFirestore.instance).collection('books');

  final CollectionReference<Map<String, dynamic>> _books;

  // Always ask the server: the default get() answers from the local cache when
  // offline, which would show old copies or "Book not found" instead of an error.
  static const _serverOnly = GetOptions(source: Source.server);

  // update() waits forever while offline, so it needs a time limit.
  static const _updateTimeout = Duration(seconds: 15);

  Future<List<Book>> searchBooksByTitle(String input) async {
    final title = input.trim();
    if (title.isEmpty) return const [];

    // Firestore READ: exact title match.
    final exact = await _books.where('title', isEqualTo: title).get(_serverOnly);
    if (exact.docs.isNotEmpty) {
      return exact.docs.map(Book.fromFirestore).toList();
    }

    // Fallback: Firestore queries are case-sensitive and do not support
    // "contains", so "clean code" or "java" cannot match with where(). Fetch the
    // collection and match on the client instead.
    // Firestore READ: all documents in the books collection.
    final all = await _books.get(_serverOnly);
    return filterByTitle(all.docs.map(Book.fromFirestore), title);
  }

  Future<Book?> getBookById(String id) async {
    // Firestore READ: one document by its ID.
    final doc = await _books.doc(id).get(_serverOnly);
    return doc.exists ? Book.fromFirestore(doc) : null;
  }

  Future<void> updateCopies(String id, int copies) {
    // Firestore UPDATE: changes only copies; update() fails if the book is gone,
    // whereas set() would create it or overwrite its other fields.
    return _books.doc(id).update({'copies': copies}).timeout(_updateTimeout);
  }

  /// Case-insensitive "title contains query" matching.
  static List<Book> filterByTitle(Iterable<Book> books, String query) {
    final needle = query.trim().toLowerCase();
    return books.where((b) => b.title.toLowerCase().contains(needle)).toList();
  }
}
