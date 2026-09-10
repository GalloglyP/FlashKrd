import 'package:flashkrd/app_state.dart';
import 'package:flashkrd/review_screen.dart';
import 'package:flashkrd/settings_screen.dart';
import 'package:flutter/material.dart';

class DecksScreen extends StatelessWidget {
  const DecksScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('FlashKrd'),
            actions: [
              IconButton(
                iconSize: 32,
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => SettingsScreen(state: state),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                )
              else if (state.status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(state.status, style: const TextStyle(fontSize: 18)),
                ),
              Expanded(
                child: state.decks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No decks yet.\nSync from your server.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 22, height: 1.4),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                        itemCount: state.decks.length,
                        separatorBuilder: (context, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final deck = state.decks[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            title: Text(
                              deck.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              deck.dueCount == 0
                                  ? 'Caught up · rev ${deck.rev}'
                                  : '${deck.dueCount} due · rev ${deck.rev}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 32),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => ReviewScreen(
                                    state: state,
                                    deckId: deck.id,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              Material(
                color: const Color(0xFFE8E4DA),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: FilledButton(
                              onPressed: state.syncing ? null : state.pull,
                              child: Text(
                                state.syncing ? 'Syncing…' : 'Sync',
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: FilledButton.tonal(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) => ReviewScreen(state: state),
                                  ),
                                );
                              },
                              child: const Text('Review all', style: TextStyle(fontSize: 20)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
