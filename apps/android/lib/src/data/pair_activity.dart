enum PairActivity {
  notebook('双人便签', 'memory'),
  draw('约会行动签', 'wish');

  const PairActivity(this.label, this.module);
  final String label, module;

  // R2 keeps plain-text module bodies readable on older clients.
  String get marker => '$label\n';

  bool contains(Map<String, dynamic> row) =>
      row['module'] == module &&
      row['body'] is String &&
      (row['body'] as String).startsWith(marker);

  static PairActivity? forRecord(Map<String, dynamic>? row) => row == null
      ? null
      : values.where((kind) => kind.contains(row)).firstOrNull;

  String withoutMarker(String body) {
    while (body.startsWith(marker)) {
      body = body.substring(marker.length);
    }
    return body;
  }

  String content(Map<String, dynamic> row) =>
      withoutMarker(row['body'] as String);

  String storedBody(String text) => '$marker${withoutMarker(text)}';
}
