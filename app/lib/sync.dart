import 'dart:convert';

import 'package:flashkrd/store.dart';
import 'package:http/http.dart' as http;

class SyncError implements Exception {
  SyncError(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncClient {
  SyncClient(this.store);

  final Store store;

  Future<int> pull({required String baseUrl, String token = ''}) async {
    final root = _root(baseUrl);
    final headers = <String, String>{
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final listRes = await http.get(Uri.parse('$root/decks'), headers: headers);
    if (listRes.statusCode == 401) {
      throw SyncError('Unauthorized — check the sync token');
    }
    if (listRes.statusCode != 200) {
      throw SyncError('Sync failed (${listRes.statusCode})');
    }
    final decks = (jsonDecode(listRes.body) as Map<String, dynamic>)['decks'] as List;
    var updated = 0;
    for (final raw in decks) {
      final deck = raw as Map<String, dynamic>;
      final id = deck['id'] as String;
      final rev = deck['rev'] as int;
      final local = await store.deckRev(id);
      if (local != null && local >= rev) {
        continue;
      }
      final detail = await http.get(Uri.parse('$root/decks/$id'), headers: headers);
      if (detail.statusCode != 200) {
        throw SyncError('Failed to fetch $id (${detail.statusCode})');
      }
      final payload = jsonDecode(detail.body) as Map<String, dynamic>;
      await store.applyDeck(payload);
      await _pullFiles(root, headers, payload);
      updated += 1;
    }
    return updated;
  }

  Future<void> _pullFiles(
    String root,
    Map<String, String> headers,
    Map<String, dynamic> payload,
  ) async {
    final deckId = payload['id'] as String;
    final files = (payload['files'] as List).cast<Map<String, dynamic>>();
    for (final file in files) {
      if (file['deleted_at'] != null) {
        final gone = store.mediaFile(deckId, file['path'] as String);
        if (await gone.exists()) {
          await gone.delete();
        }
        continue;
      }
      final id = file['id'] as String;
      final path = file['path'] as String;
      final sha = file['sha256'] as String;
      final localSha = await store.fileSha(id);
      final dest = store.mediaFile(deckId, path);
      if (localSha == sha && await dest.exists()) {
        continue;
      }
      final res = await http.get(
        Uri.parse('$root/files/$deckId/${path.split('/').map(Uri.encodeComponent).join('/')}'),
        headers: headers,
      );
      if (res.statusCode != 200) {
        continue;
      }
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(res.bodyBytes, flush: true);
    }
  }

  String _root(String baseUrl) {
    var value = baseUrl.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isEmpty) {
      throw SyncError('Set a server URL in Settings');
    }
    return value;
  }
}
