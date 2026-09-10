import 'package:flashkrd/app_state.dart';
import 'package:flashkrd/card_body.dart';
import 'package:flashkrd/models.dart';
import 'package:flutter/material.dart';
import 'package:fsrs/fsrs.dart' hide State;

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.state, this.deckId});

  final AppState state;
  final String? deckId;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<Note> _queue = const [];
  var _index = 0;
  var _back = false;
  var _loading = true;

  Note? get _note =>
      _index < _queue.length ? _queue[_index] : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await widget.state.due(deckId: widget.deckId);
    if (!mounted) {
      return;
    }
    setState(() {
      _queue = notes;
      _index = 0;
      _back = false;
      _loading = false;
    });
  }

  Future<void> _rate(Rating rating) async {
    final note = _note;
    if (note == null) {
      return;
    }
    await widget.state.rate(note, rating);
    if (!mounted) {
      return;
    }
    setState(() {
      _index += 1;
      _back = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loading ? 'Review' : '${_index.clamp(0, _queue.length)} / ${_queue.length}',
        ),
      ),
      body: _loading
          ? const Center(child: Text('Loading…', style: TextStyle(fontSize: 22)))
          : _note == null
              ? const Center(
                  child: Text('Nothing due.', style: TextStyle(fontSize: 24)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!_back) {
                            setState(() => _back = true);
                          }
                        },
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                          child: _card(context, _note!),
                        ),
                      ),
                    ),
                    if (_back) _ratings() else _revealBar(),
                  ],
                ),
    );
  }

  Widget _card(BuildContext context, Note note) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBody(text: note.front, store: widget.state.store, deckId: note.deckId),
        if (_back) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(thickness: 2, color: Colors.black87),
          ),
          CardBody(text: note.back, store: widget.state.store, deckId: note.deckId),
          if (note.extra.isNotEmpty) ...[
            const SizedBox(height: 16),
            CardBody(text: note.extra, store: widget.state.store, deckId: note.deckId),
          ],
        ],
      ],
    );
  }

  Widget _revealBar() {
    return Material(
      color: const Color(0xFFE8E4DA),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: () => setState(() => _back = true),
              child: const Text('Show answer', style: TextStyle(fontSize: 20)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ratings() {
    return Material(
      color: const Color(0xFFE8E4DA),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Row(
            children: [
              _rateButton('Again', Rating.again, const Color(0xFFB71C1C)),
              const SizedBox(width: 8),
              _rateButton('Hard', Rating.hard, const Color(0xFFE65100)),
              const SizedBox(width: 8),
              _rateButton('Good', Rating.good, const Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              _rateButton('Easy', Rating.easy, const Color(0xFF1565C0)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rateButton(String label, Rating rating, Color color) {
    return Expanded(
      child: SizedBox(
        height: 64,
        child: FilledButton(
          onPressed: () => _rate(rating),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
          ),
          child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
