import 'package:flashkrd/models.dart';
import 'package:flashkrd/store.dart';
import 'package:flashkrd/sync.dart';
import 'package:flutter/foundation.dart';
import 'package:fsrs/fsrs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  AppState(this.store);

  final Store store;
  final Scheduler scheduler = Scheduler(enableFuzzing: false);
  late final SyncClient sync = SyncClient(store);

  bool ready = false;
  String serverUrl = '';
  String token = '';
  String status = '';
  String? error;
  bool syncing = false;
  List<Deck> decks = const [];

  Future<void> load() async {
    await store.open();
    final prefs = await SharedPreferences.getInstance();
    serverUrl = prefs.getString('serverUrl') ?? '';
    token = prefs.getString('token') ?? '';
    await refreshDecks();
    ready = true;
    notifyListeners();
  }

  Future<void> refreshDecks() async {
    decks = await store.decks();
    notifyListeners();
  }

  Future<void> saveSettings({required String serverUrl, required String token}) async {
    this.serverUrl = serverUrl.trim();
    this.token = token.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', this.serverUrl);
    await prefs.setString('token', this.token);
    notifyListeners();
  }

  Future<void> pull() async {
    syncing = true;
    error = null;
    status = 'Syncing…';
    notifyListeners();
    try {
      final count = await sync.pull(baseUrl: serverUrl, token: token);
      await refreshDecks();
      status = count == 0 ? 'Already up to date' : 'Updated $count deck${count == 1 ? '' : 's'}';
    } catch (err) {
      error = err.toString();
      status = '';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<List<Note>> due({String? deckId}) {
    return store.dueNotes(deckId: deckId);
  }

  Future<Duration> rate(Note note, Rating rating) async {
    final current = await store.cardFor(note.id);
    final (:card, reviewLog: _) = scheduler.reviewCard(current, rating);
    await store.saveCard(note.id, card);
    await refreshDecks();
    return card.due.toUtc().difference(DateTime.now().toUtc());
  }
}
