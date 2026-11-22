import 'package:firebase_auth/firebase_auth.dart';

/// Friendly failure from [AuthService]. Widgets should show [message].
class AuthException implements Exception {
  final String code;
  final String message;

  const AuthException(this.code, this.message);

  @override
  String toString() => message;
}

/// Email/password auth against [FirebaseAuth].
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Emits the signed-in user, or null after sign-out.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Creates an account. [email] is trimmed. Throws [AuthException] on failure.
  Future<User> register({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'user-null',
          'Could not create the account. Please try again.',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw _fromAuth(e);
    } on FirebaseException catch (e) {
      throw _fromFirebase(e);
    }
  }

  /// Signs in with email and password. [email] is trimmed.
  Future<User> signIn({required String email, required String password}) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          'user-null',
          'Could not sign in. Please try again.',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw _fromAuth(e);
    } on FirebaseException catch (e) {
      throw _fromFirebase(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw _fromAuth(e);
    } on FirebaseException catch (e) {
      throw _fromFirebase(e);
    }
  }

  AuthException _fromAuth(FirebaseAuthException e) {
    return AuthException(e.code, _messageFor(e.code));
  }

  AuthException _fromFirebase(FirebaseException e) {
    return AuthException(
      e.code,
      e.message ?? 'Something went wrong. Please try again.',
    );
  }

  String _messageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email or password is incorrect.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
