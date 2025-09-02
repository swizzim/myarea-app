class EventCategory {
  final int id;
  final String name;

  EventCategory({required this.id, required this.name});

  factory EventCategory.fromMap(Map<String, dynamic> map) {
    return EventCategory(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
} 