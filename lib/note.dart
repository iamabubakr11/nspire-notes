import 'dart:convert';

class Note {
  final int? id;
  final String title;
  final String content;
  final String category;
  final DateTime eventAt;
  final DateTime updatedAt;
  final bool pinned;

  const Note({
    this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.eventAt,
    required this.updatedAt,
    this.pinned = false,
  });

  Note copyWith({int? id, String? title, String? content, String? category,
    DateTime? eventAt, DateTime? updatedAt, bool? pinned}) => Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      eventAt: eventAt ?? this.eventAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
    );

  Map<String, Object?> toDatabase() => {
    'title': title, 'content': content, 'category': category,
    'event_at': eventAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(), 'pinned': pinned ? 1 : 0,
  };

  factory Note.fromDatabase(Map<String, Object?> m) => Note(
    id: m['id'] as int,
    title: m['title'] as String,
    content: m['content'] as String,
    category: m['category'] as String,
    eventAt: DateTime.parse(m['event_at'] as String),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    pinned: (m['pinned'] as int) == 1,
  );

  Map<String, dynamic> toJson() => {
    'title': title, 'content': content, 'category': category,
    'eventAt': eventAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(), 'pinned': pinned,
  };

  factory Note.fromJson(Map<String, dynamic> m) => Note(
    title: (m['title'] as String).trim(),
    content: m['content'] as String,
    category: (m['category'] as String?) ?? 'Другое',
    eventAt: DateTime.parse(m['eventAt'] as String),
    updatedAt: DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now(),
    pinned: m['pinned'] == true,
  );
}

String serializeNotes(List<Note> notes) => const JsonEncoder.withIndent('  ').convert({
  'app': 'Nspire Notes', 'version': 1,
  'exportedAt': DateTime.now().toIso8601String(),
  'notes': notes.map((n) => n.toJson()).toList(),
});

List<Note> deserializeNotes(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map || decoded['app'] != 'Nspire Notes' ||
      decoded['version'] != 1 || decoded['notes'] is! List) {
    throw const FormatException('Неподдерживаемый формат резервной копии');
  }
  final entries = decoded['notes'] as List;
  if (entries.length > 10000) throw const FormatException('Слишком много заметок');
  return entries.map((v) {
    if (v is! Map<String, dynamic>) throw const FormatException('Некорректная заметка');
    final result = Note.fromJson(v);
    if (result.title.isEmpty || result.title.length > 120 || result.content.length > 100000) {
      throw const FormatException('Некорректное содержимое заметки');
    }
    return result;
  }).toList();
}
