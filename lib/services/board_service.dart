import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hw02_message_board/models/app_user.dart';
import 'package:hw02_message_board/models/message.dart';

/// A board read or write that failed validation or was rejected by Firestore.
class BoardException implements Exception {
  /// Creates an exception that keeps the Firestore-style [code].
  const BoardException(this.code, this.message);

  /// Machine-readable code, such as `permission-denied`.
  final String code;

  /// Message safe to show in the UI.
  final String message;

  @override
  String toString() => message;
}

/// Reads and writes `users/{uid}` and `messages/{msgId}`.
class BoardService {
  /// Uses [FirebaseFirestore.instance] when [db] is omitted.
  BoardService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Roles offered on the registration form.
  static const roles = ['student', 'instructor', 'guest'];

  static const _maxTextLength = 500;
  static const _probeAllowed =
      'ALLOWED (unexpected) – rules did not block this';

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  CollectionReference<Map<String, dynamic>> get _messages =>
      _db.collection('messages');

  /// Creates or replaces the signed-in user's profile document.
  Future<void> saveUserRecord({
    required String uid,
    required String firstName,
    required String lastName,
    required String role,
  }) {
    return _guard(() {
      return _users.doc(uid).set({
        'uid': uid,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'role': role,
        'registrationDateTime': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Returns the profile for [uid], or null when the document is missing.
  Future<AppUser?> getUserRecord(String uid) {
    return _guard(() async {
      final snap = await _users.doc(uid).get();
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return AppUser.fromMap(data);
    });
  }

  /// Live board, oldest message first.
  Stream<List<Message>> messageBoard() {
    return _messages
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(Message.fromDoc).toList());
  }

  /// A new document id the UI can reuse across post retries.
  String newMessageId() => _messages.doc().id;

  /// Writes [messageId] once. Returns false when that id already exists.
  Future<bool> postMessage({
    required String messageId,
    required String authorUid,
    required String authorName,
    required String text,
  }) {
    final trimmed = _requireText(text);
    return _guard(() {
      final ref = _messages.doc(messageId);
      return _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return false;
        tx.set(ref, {
          'text': trimmed,
          'authorUid': authorUid,
          'authorName': authorName,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    });
  }

  /// Replaces the body of a message the caller is allowed to edit.
  Future<void> editMessage({
    required String messageId,
    required String newText,
  }) {
    final trimmed = _requireText(newText);
    return _guard(() {
      return _messages.doc(messageId).update({
        'text': trimmed,
        'editedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Deletes a message the caller is allowed to delete.
  Future<void> deleteMessage({required String messageId}) {
    return _guard(() => _messages.doc(messageId).delete());
  }

  /// Server read of `messages` with no client-side auth check.
  Future<String> probeSignedOutRead() {
    return _probe(
      () => _messages.limit(1).get(const GetOptions(source: Source.server)),
    );
  }

  /// Update of [messageId] with no client-side ownership check.
  Future<String> probeCrossUserUpdate(String messageId) {
    return _probe(
      () => _messages.doc(messageId).update({
        'text': 'hacked',
        'editedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  /// Delete of [messageId] with no client-side ownership check.
  Future<String> probeCrossUserDelete(String messageId) {
    return _probe(() => _messages.doc(messageId).delete());
  }

  /// Create that claims [fakeAuthorUid], with no client-side uid check.
  Future<String> probeForgedCreate(String fakeAuthorUid) {
    return _probe(
      () => _messages.add({
        'text': 'forged',
        'authorUid': fakeAuthorUid,
        'authorName': 'Mallory',
        'createdAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  String _requireText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > _maxTextLength) {
      throw const BoardException(
        'invalid-argument',
        'Message text must be 1–500 characters.',
      );
    }
    return trimmed;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on BoardException {
      rethrow;
    } on FirebaseException catch (e) {
      throw _translate(e);
    }
  }

  BoardException _translate(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return BoardException(
          e.code,
          'Firestore denied this action (permission-denied).',
        );
      case 'unavailable':
        return BoardException(
          e.code,
          "Can't reach Firestore. Check your connection.",
        );
      case 'not-found':
        return BoardException(e.code, 'That record was not found.');
      case 'invalid-argument':
        return BoardException(
          e.code,
          'The request contained an invalid value.',
        );
      default:
        return BoardException(
          e.code,
          'Something went wrong. Please try again.',
        );
    }
  }

  Future<String> _probe(Future<void> Function() action) async {
    try {
      await action();
      return _probeAllowed;
    } on FirebaseException catch (e) {
      return 'DENIED by Firestore: [${e.code}] ${e.message}';
    }
  }
}
