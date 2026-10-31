import 'package:book_update_firestore/models/book.dart';
import 'package:book_update_firestore/screens/book_update_screen.dart';
import 'package:book_update_firestore/services/book_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _javaId = '9780134685991';

class _DeniedUpdateService extends BookService {
  _DeniedUpdateService(FirebaseFirestore db) : super(firestore: db);

  @override
  Future<void> updateCopies(String id, int copies) async {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
  }
}

class _OfflineService extends BookService {
  _OfflineService(FirebaseFirestore db) : super(firestore: db);

  bool updateCalled = false;

  @override
  Future<Book?> getBookById(String id) async {
    throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
  }

  @override
  Future<void> updateCopies(String id, int copies) async {
    updateCalled = true;
  }
}

Future<FakeFirebaseFirestore> _seeded() async {
  final db = FakeFirebaseFirestore();
  final books = db.collection('books');
  await books
      .doc(_javaId)
      .set({'title': 'Effective Java', 'author': 'Joshua Bloch', 'copies': 5});
  await books.doc('9780132350884').set(
      {'title': 'Clean Code', 'author': 'Robert C. Martin', 'copies': 0});
  await books.doc('9781617294136').set(
      {'title': 'Flutter in Action', 'author': 'Eric Windmill', 'copies': 2});
  await books.doc('9780596007126').set(
      {'title': 'Flutter Patterns', 'author': 'Test Author', 'copies': 7});
  return db;
}

Finder get _titleField => find.widgetWithText(TextFormField, 'Book title');
Finder get _copiesField =>
    find.widgetWithText(TextFormField, 'Updated number of copies');
Finder get _updateButton => find.widgetWithText(FilledButton, 'Update');

String _copiesText(WidgetTester tester) =>
    tester.widget<TextFormField>(_copiesField).controller!.text;

bool _updateEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_updateButton).onPressed != null;

Future<void> _pump(WidgetTester tester, BookService service) {
  return tester.pumpWidget(
    MaterialApp(home: BookUpdateScreen(service: service)),
  );
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(_titleField, text);
  await tester.tap(find.widgetWithText(FilledButton, 'Search'));
  await tester.pumpAndSettle();
}

Future<void> _update(WidgetTester tester, String copies) async {
  await tester.enterText(_copiesField, copies);
  await tester.tap(_updateButton);
  await tester.pumpAndSettle();
}

void main() {
  const warning = 'Not Available – All Copies Issued';

  group('search', () {
    testWidgets('a single match shows the book and pre-fills copies',
        (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      expect(_updateEnabled(tester), isFalse);
      await _search(tester, 'Effective Java');
      expect(find.text('Effective Java – Joshua Bloch – 5'), findsOneWidget);
      expect(_copiesText(tester), '5');
      expect(_updateEnabled(tester), isTrue);
    });

    testWidgets('lower-case partial input uses the fallback', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'java');
      expect(find.text('Effective Java – Joshua Bloch – 5'), findsOneWidget);
    });

    testWidgets('no match shows Book not found', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'Harry Potter');
      expect(find.text('Book not found'), findsOneWidget);
      expect(_updateEnabled(tester), isFalse);
    });

    testWidgets('empty title shows a message', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, '   ');
      expect(find.text('Please enter a book title'), findsOneWidget);
    });

    testWidgets('copies == 0 shows the warning in red', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'Clean Code');
      expect(tester.widget<Text>(find.text(warning)).style?.color, Colors.red);
    });

    testWidgets('several matches need a tap, which pre-fills copies',
        (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'flutter');
      expect(find.text('Tap a book to select it'), findsOneWidget);
      expect(_copiesText(tester), '');
      expect(_updateEnabled(tester), isFalse);

      await tester.tap(find.text('Flutter Patterns – Test Author – 7'));
      await tester.pumpAndSettle();
      expect(_copiesText(tester), '7');
      expect(_updateEnabled(tester), isTrue);
    });

    testWidgets('a new search clears the selection', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'Effective Java');
      await _search(tester, 'Harry Potter');
      expect(_copiesText(tester), '');
      expect(_updateEnabled(tester), isFalse);
    });
  });

  group('update', () {
    testWidgets('changes only copies and shows the new value', (tester) async {
      final db = await _seeded();
      await _pump(tester, BookService(firestore: db));
      await _search(tester, 'Effective Java');
      await _update(tester, '8');

      expect(find.text('Effective Java – Joshua Bloch – 8'), findsOneWidget);
      expect(find.text('Copies updated: 5 → 8'), findsOneWidget);
      expect(_copiesText(tester), '8');

      final doc = await db.collection('books').doc(_javaId).get();
      expect(doc.data(), {
        'title': 'Effective Java',
        'author': 'Joshua Bloch',
        'copies': 8,
      });
      expect((await db.collection('books').get()).docs, hasLength(4));
    });

    testWidgets('zero copies shows the red warning', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'Flutter in Action');
      await _update(tester, '0');
      expect(find.text('Flutter in Action – Eric Windmill – 0'), findsOneWidget);
      expect(find.text(warning), findsOneWidget);
    });

    testWidgets('updating a book that was deleted never recreates it',
        (tester) async {
      final db = await _seeded();
      await _pump(tester, BookService(firestore: db));
      await _search(tester, 'Effective Java');
      await db.collection('books').doc(_javaId).delete();
      await _update(tester, '8');
      expect(find.text('This book no longer exists.'), findsOneWidget);
      expect((await db.collection('books').doc(_javaId).get()).exists, isFalse);
    });

    testWidgets('permission denied shows a readable message', (tester) async {
      final db = await _seeded();
      await _pump(tester, _DeniedUpdateService(db));
      await _search(tester, 'Effective Java');
      await _update(tester, '8');
      expect(
        find.text('Permission denied by the Firestore security rules.'),
        findsOneWidget,
      );
      expect(find.text('Effective Java – Joshua Bloch – 5'), findsOneWidget);
    });

    testWidgets('offline shows a message and sends no update', (tester) async {
      final service = _OfflineService(await _seeded());
      await _pump(tester, service);
      await _search(tester, 'Effective Java');
      await _update(tester, '8');
      expect(
        find.text('No internet connection. Please check it and try again.'),
        findsOneWidget,
      );
      expect(service.updateCalled, isFalse);
    });
  });

  group('invalid copies', () {
    test('validator rejects bad values and accepts the limits', () {
      expect(Book.validateCopies(''), 'Please enter the number of copies');
      expect(Book.validateCopies('abc'), 'Please enter a whole number');
      expect(Book.validateCopies('1.5'), 'Please enter a whole number');
      const range = 'Copies must be between 0 and 1000';
      expect(Book.validateCopies('-1'), range);
      expect(Book.validateCopies('1001'), range);
      expect(Book.validateCopies('99999999999999999999999'), range);
      expect(Book.validateCopies('0'), isNull);
      expect(Book.validateCopies('1000'), isNull);
    });

    testWidgets('the field keeps digits only', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await tester.enterText(_copiesField, '-1a2');
      expect(_copiesText(tester), '12');
    });

    for (final (input, message) in [
      ('', 'Please enter the number of copies'),
      ('abc', 'Please enter the number of copies'), // digits-only field empties it
      ('1001', 'Copies must be between 0 and 1000'),
    ]) {
      testWidgets('"$input" is rejected and Firestore is unchanged',
          (tester) async {
        final db = await _seeded();
        await _pump(tester, BookService(firestore: db));
        await _search(tester, 'Effective Java');
        await _update(tester, input);
        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('Copies updated'), findsNothing);
        final doc = await db.collection('books').doc(_javaId).get();
        expect(doc.data()?['copies'], 5);
      });
    }

    testWidgets('selecting again clears the validation error', (tester) async {
      await _pump(tester, BookService(firestore: await _seeded()));
      await _search(tester, 'Effective Java');
      await _update(tester, '1001');
      await tester.tap(find.text('Effective Java – Joshua Bloch – 5'));
      await tester.pumpAndSettle();
      expect(find.text('Copies must be between 0 and 1000'), findsNothing);
      expect(_copiesText(tester), '5');
    });
  });
}
