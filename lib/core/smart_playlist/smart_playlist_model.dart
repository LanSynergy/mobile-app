import 'dart:convert';

/// A single filter rule in a smart playlist.
class SmartRule {
  const SmartRule({
    required this.field,
    required this.operator,
    required this.value,
  });

  factory SmartRule.fromJson(Map<String, dynamic> json) => SmartRule(
    field: json['field'] as String,
    operator: json['operator'] as String,
    value: json['value'],
  );
  final String field;
  final String operator;
  final dynamic value;

  Map<String, dynamic> toJson() => {
    'field': field,
    'operator': operator,
    'value': value,
  };

  /// Human-readable summary (e.g. "Genre is Rock").
  String get summary {
    final op = switch (operator) {
      'is' => 'is',
      'isNot' => 'is not',
      'contains' => 'contains',
      'notContains' => 'doesn\'t contain',
      'gt' => '>',
      'lt' => '<',
      'inTheRange' => 'between',
      'inTheLast' => 'in last',
      _ => operator,
    };
    final val = value is List ? '${value[0]}–${value[1]}' : '$value';
    final suffix = operator == 'inTheLast' ? ' days' : '';
    return '${_fieldLabel(field)} $op $val$suffix';
  }

  static String _fieldLabel(String field) => switch (field) {
    'title' => 'Title',
    'artist' => 'Artist',
    'album' => 'Album',
    'genre' => 'Genre',
    'year' => 'Year',
    'duration' => 'Duration',
    'codec' => 'Codec',
    'bitrate' => 'Bitrate',
    'dateAdded' => 'Date added',
    'isFavorite' => 'Favorite',
    _ => field,
  };
}

/// A smart playlist definition with rules, sort, and limit.
class SmartPlaylist {
  const SmartPlaylist({
    required this.id,
    required this.name,
    this.combinator = 'all',
    this.rules = const [],
    this.sort = 'title',
    this.sortOrder = 'asc',
    this.limit,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final String combinator; // 'all' (AND) or 'any' (OR)
  final List<SmartRule> rules;
  final String sort;
  final String sortOrder; // 'asc' or 'desc'
  final int? limit;
  final DateTime createdAt;
  final DateTime updatedAt;

  SmartPlaylist copyWith({
    String? id,
    String? name,
    String? combinator,
    List<SmartRule>? rules,
    String? sort,
    String? sortOrder,
    int? limit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SmartPlaylist(
    id: id ?? this.id,
    name: name ?? this.name,
    combinator: combinator ?? this.combinator,
    rules: rules ?? this.rules,
    sort: sort ?? this.sort,
    sortOrder: sortOrder ?? this.sortOrder,
    limit: limit ?? this.limit,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Encode rules to JSON string for DB storage.
  String get rulesJson => jsonEncode(rules.map((r) => r.toJson()).toList());

  /// Decode rules from JSON string.
  static List<SmartRule> parseRules(String json) {
    final list = jsonDecode(json) as List;
    return list
        .cast<Map<String, dynamic>>()
        .map(SmartRule.fromJson)
        .toList(growable: false);
  }

  /// Human-readable rule summary for list display.
  String get ruleSummary {
    if (rules.isEmpty) return 'No rules';
    final parts = rules.take(3).map((r) => r.summary).join(' • ');
    final suffix = limit != null ? ' • max $limit' : '';
    final extra = rules.length > 3 ? ' (+${rules.length - 3} more)' : '';
    return '$parts$suffix$extra';
  }
}

/// Available fields for smart playlist rules.
const kSmartFields = <String, String>{
  'title': 'Title',
  'artist': 'Artist',
  'album': 'Album',
  'genre': 'Genre',
  'year': 'Year',
  'duration': 'Duration (sec)',
  'codec': 'Codec',
  'bitrate': 'Bitrate (kbps)',
  'dateAdded': 'Date added',
  'isFavorite': 'Favorite',
};

/// Available operators per field type.
const kStringOperators = ['is', 'isNot', 'contains', 'notContains'];
const kNumericOperators = ['is', 'isNot', 'gt', 'lt', 'inTheRange'];
const kDateOperators = ['inTheLast'];
const kBoolOperators = ['is'];

/// Returns the appropriate operators for a given field.
List<String> operatorsForField(String field) => switch (field) {
  'year' || 'duration' || 'bitrate' => kNumericOperators,
  'dateAdded' => kDateOperators,
  'isFavorite' => kBoolOperators,
  _ => kStringOperators,
};

/// Available sort options.
const kSmartSortOptions = <String, String>{
  'title': 'Title',
  'artist': 'Artist',
  'album': 'Album',
  'year': 'Year',
  'dateAdded': 'Date added',
  'duration': 'Duration',
  'random': 'Random',
};
