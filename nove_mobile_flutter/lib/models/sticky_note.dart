enum StickyColor { yellow, pink, green, blue }

class LinkedApp {
  final String packageName;
  final String name;

  const LinkedApp({required this.packageName, required this.name});

  Map<String, dynamic> toMap() => {'packageName': packageName, 'name': name};
  factory LinkedApp.fromMap(Map<String, dynamic> map) => LinkedApp(
    packageName: map['packageName'] as String,
    name: map['name'] as String,
  );
}

class StickyNote {
  final String id;
  final String title;
  final String content;
  final StickyColor color;
  final int createdAt;
  final LinkedApp? linkedApp;
  final double x;
  final double y;
  final bool isDeleted;

  const StickyNote({
    required this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.createdAt,
    this.linkedApp,
    this.x = 0,
    this.y = 0,
    this.isDeleted = false,
  });

  StickyNote copyWith({
    String? id,
    String? title,
    String? content,
    StickyColor? color,
    int? createdAt,
    LinkedApp? linkedApp,
    double? x,
    double? y,
    bool clearLink = false,
    bool? isDeleted,
  }) {
    return StickyNote(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      linkedApp: clearLink ? null : (linkedApp ?? this.linkedApp),
      x: x ?? this.x,
      y: y ?? this.y,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'color': color.name,
      'created_at': createdAt,
      'linked_app': linkedApp?.toMap(),
      'x': x,
      'y': y,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory StickyNote.fromMap(Map<String, dynamic> map) {
    return StickyNote(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      color: StickyColor.values.firstWhere(
        (c) => c.name == map['color'],
        orElse: () => StickyColor.yellow,
      ),
      createdAt: map['created_at'] as int,
      linkedApp: map['linked_app'] != null 
          ? LinkedApp.fromMap(Map<String, dynamic>.from(map['linked_app'])) 
          : null,
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      isDeleted: map['is_deleted'] == 1 || map['is_deleted'] == true || map['is_deleted'] == '1',
    );
  }
}