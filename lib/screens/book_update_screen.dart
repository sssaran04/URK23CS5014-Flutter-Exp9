import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/book_service.dart';
import '../widgets/book_result_card.dart';
import '../widgets/labeled_text_field.dart';
import '../widgets/message_view.dart';

enum _SearchState { idle, emptyInput, loading, results, notFound, error }

class BookUpdateScreen extends StatefulWidget {
  const BookUpdateScreen({super.key, this.service});

  /// Lets tests supply a service backed by a fake Firestore.
  final BookService? service;

  @override
  State<BookUpdateScreen> createState() => _BookUpdateScreenState();
}

class _BookUpdateScreenState extends State<BookUpdateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _copiesFieldKey = GlobalKey<FormFieldState<String>>();
  final _titleController = TextEditingController();
  final _copiesController = TextEditingController();
  late final BookService _service = widget.service ?? BookService();

  _SearchState _state = _SearchState.idle;
  List<Book> _books = const [];
  Book? _selected;
  String _error = '';
  bool _updating = false;

  bool get _busy => _state == _SearchState.loading || _updating;

  @override
  void dispose() {
    _titleController.dispose();
    _copiesController.dispose();
    super.dispose();
  }

  /// Sets the copies field and removes any old validation error.
  void _setCopiesText(String text) {
    _copiesFieldKey.currentState?.reset();
    _copiesController.text = text;
  }

  void _select(Book? book) {
    _selected = book;
    _setCopiesText(book == null ? '' : '${book.copies}');
  }

  Future<void> _search() async {
    if (_busy) return;

    final input = _titleController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _select(null);
        _state = _SearchState.emptyInput;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _select(null);
      _state = _SearchState.loading;
    });

    try {
      // Firestore READ: runs the title query (and the fallback if needed).
      final books = await _service.searchBooksByTitle(input);
      if (!mounted) return;
      setState(() {
        _books = books;
        _state = books.isEmpty ? _SearchState.notFound : _SearchState.results;
        if (books.length == 1) _select(books.single);
      });
    } on FirebaseException catch (e) {
      _showSearchError(_messageFor(e));
    } catch (_) {
      _showSearchError('Something went wrong. Please try again.');
    }
  }

  void _showSearchError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _state = _SearchState.error;
    });
  }

  Future<void> _update() async {
    final book = _selected;
    if (book == null || _busy) return;
    if (!_formKey.currentState!.validate()) return;

    final newCopies = int.parse(_copiesController.text.trim());
    FocusScope.of(context).unfocus();
    setState(() => _updating = true);

    try {
      // Firestore READ: fails at once when offline, before update() can be
      // queued, and gives the true old value if someone else changed it.
      final current = await _service.getBookById(book.id);
      if (current == null) {
        _showSnackBar('This book no longer exists.');
        return;
      }

      // Firestore UPDATE: only the copies field of this document.
      await _service.updateCopies(book.id, newCopies);

      // Firestore READ: the updated document, from the server.
      final updated = await _service.getBookById(book.id);
      if (!mounted || updated == null) return;
      setState(() {
        _books = [for (final b in _books) b.id == book.id ? updated : b];
        _select(updated);
      });
      _showSnackBar('Copies updated: ${current.copies} → ${updated.copies}');
    } on FirebaseException catch (e) {
      _showSnackBar(_messageFor(e));
    } on TimeoutException {
      _showSnackBar('No response from the server. Check your internet '
          'connection and search again to confirm the copies.');
    } catch (_) {
      _showSnackBar('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied by the Firestore security rules.';
      case 'not-found':
        return 'This book no longer exists.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'No internet connection. Please check it and try again.';
      default:
        return 'Could not reach Firestore (${e.code}). Please try again.';
    }
  }

  List<Widget> _buildResults() {
    switch (_state) {
      case _SearchState.idle:
        return const [
          MessageView(
            icon: Icons.menu_book_outlined,
            message: 'Enter a title and tap Search',
          ),
        ];
      case _SearchState.emptyInput:
        return const [
          MessageView(
            icon: Icons.info_outline,
            message: 'Please enter a book title',
          ),
        ];
      case _SearchState.loading:
        return const [Center(child: CircularProgressIndicator())];
      case _SearchState.results:
        return [
          if (_selected == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Tap a book to select it'),
            ),
          for (final book in _books)
            BookResultCard(
              book: book,
              selected: book.id == _selected?.id,
              onTap: _updating ? null : () => setState(() => _select(book)),
            ),
        ];
      case _SearchState.notFound:
        return const [
          MessageView(icon: Icons.search_off, message: 'Book not found'),
        ];
      case _SearchState.error:
        return [
          MessageView(
            icon: Icons.error_outline,
            message: _error,
            isError: true,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update Book Copies')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LabeledTextField(
              controller: _titleController,
              label: 'Book title',
              icon: Icons.menu_book,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
            ),
            const SizedBox(height: 12),
            LabeledTextField(
              fieldKey: _copiesFieldKey,
              controller: _copiesController,
              label: 'Updated number of copies',
              icon: Icons.numbers,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: Book.validateCopies,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _search,
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _selected == null || _busy ? null : _update,
                    icon: _updating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Update'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._buildResults(),
          ],
        ),
      ),
    );
  }
}
