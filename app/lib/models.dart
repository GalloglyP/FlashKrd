class Deck {
  const Deck({
    required this.id,
    required this.title,
    required this.description,
    required this.rev,
    this.dueCount = 0,
  });

  final String id;
  final String title;
  final String description;
  final int rev;
  final int dueCount;
}

class Note {
  const Note({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.extra,
    required this.tags,
    required this.sortIndex,
  });

  final String id;
  final String deckId;
  final String front;
  final String back;
  final String extra;
  final List<String> tags;
  final int sortIndex;
}
