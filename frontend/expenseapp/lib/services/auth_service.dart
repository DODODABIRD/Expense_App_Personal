import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> register(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> signOut() => _auth.signOut();

  static Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You must be signed in');
    final email = user.email;
    if (email == null) {
      throw StateError('No email address is associated with this account');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: oldPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  static Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You must be signed in');
    await user.delete();
  }

  static Future<String> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You must be signed in');
    final token = await user.getIdToken();
    if (token == null) throw StateError('Firebase did not return an ID token');
    return token;
  }
}
