import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thrown for auth problems we want to surface to the user with a message.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when the user backs out of a sign-in flow. The UI should treat this
/// as a no-op (no error snackbar).
class AuthCancelledException implements Exception {
  const AuthCancelledException();
}

/// Abstraction over authentication so the rest of the app never depends on a
/// concrete provider (CLAUDE.md §5 — services behind interfaces). Swapping
/// Firebase for something else, or faking it in tests, means one new class.
abstract class AuthService {
  /// Emits the current user (or null when signed out) and on every change.
  Stream<User?> authStateChanges();

  /// The currently signed-in user, if any.
  User? get currentUser;

  /// Google Sign-In → Firebase credential sign-in.
  Future<UserCredential> signInWithGoogle();

  /// Apple Sign-In. Stubbed until we're building on a Mac with an Apple
  /// Developer account (CLAUDE.md Phase 1 defers this for the Windows/Android
  /// dev setup).
  Future<UserCredential> signInWithApple();

  Future<void> signOut();
}

/// Firebase-backed [AuthService].
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<UserCredential> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the account picker.
        throw const AuthCancelledException();
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on AuthCancelledException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Sign-in failed. Please try again.');
    }
  }

  @override
  Future<UserCredential> signInWithApple() {
    // Deferred to a later phase (needs macOS + Apple Developer account).
    throw const AuthException(
      'Apple Sign-In is coming soon. Please use Google for now.',
    );
  }

  @override
  Future<void> signOut() async {
    // Sign out of both Google and Firebase so the next sign-in shows the
    // account picker again.
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
