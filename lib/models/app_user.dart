import 'package:cloud_firestore/cloud_firestore.dart';

/// A registered message-board user stored in Firestore.
class AppUser {
  final String uid;
  final String firstName;
  final String lastName;
  final String role;

  /// Null when the profile has not been written yet or the field is missing.
  final DateTime? registrationDateTime;

  const AppUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.registrationDateTime,
  });

  /// Builds a user from a Firestore map. Missing strings become empty;
  /// [registrationDateTime] is read only when it is a [Timestamp].
  factory AppUser.fromMap(Map<String, dynamic> m) {
    return AppUser(
      uid: _string(m['uid']),
      firstName: _string(m['firstName']),
      lastName: _string(m['lastName']),
      role: _string(m['role']),
      registrationDateTime: _dateTime(m['registrationDateTime']),
    );
  }

  /// True when every profile field is present and non-empty.
  bool get isComplete =>
      uid.trim().isNotEmpty &&
      firstName.trim().isNotEmpty &&
      lastName.trim().isNotEmpty &&
      role.trim().isNotEmpty &&
      registrationDateTime != null;

  /// "First Last".
  String get displayName => '$firstName $lastName';

  static String _string(dynamic value) => value is String ? value : '';

  static DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
