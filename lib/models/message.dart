import 'package:cloud_firestore/cloud_firestore.dart';

/// One post on the message board.
class Message {
  final String id;
  final String text;
  final String authorUid;
  final String authorName;

  /// Null while a server timestamp is still pending.
  final DateTime? createdAt;
  final DateTime? editedAt;

  const Message({
    required this.id,
    required this.text,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
    required this.editedAt,
  });

  /// Reads a message document. Missing or non-[Timestamp] dates stay null.
  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const <String, dynamic>{};
    return Message(
      id: d.id,
      text: _string(data['text']),
      authorUid: _string(data['authorUid']),
      authorName: _string(data['authorName']),
      createdAt: _dateTime(data['createdAt']),
      editedAt: _dateTime(data['editedAt']),
    );
  }

  /// True once the message has an edit timestamp.
  bool get isEdited => editedAt != null;

  static String _string(dynamic value) => value is String ? value : '';

  static DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
