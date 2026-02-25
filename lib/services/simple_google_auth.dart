// =============================================================================
// SIMPLE GOOGLE AUTH SERVICE
// =============================================================================
// Easy Google sign-in - works with any Google account (personal or workspace)
// No restrictions - all features available to all users
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'app_logger.dart';

class SimpleGoogleAuth {
  static final SimpleGoogleAuth _instance = SimpleGoogleAuth._internal();

  factory SimpleGoogleAuth() => _instance;

  SimpleGoogleAuth._internal();

  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    forceCodeForRefreshToken: true,
  );

  /// Sign in with any Google account
  /// Works with personal (gmail.com) and workspace accounts
  /// All features available to all users
  Future<UserCredential?> signIn() async {
    try {
      // Sign out first for fresh login
      await _googleSignIn.signOut();

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        AppLogger.log('Sign-in cancelled');
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      AppLogger.log('Signed in: ${userCredential.user?.email}');

      return userCredential;
    } catch (e) {
      AppLogger.log('Sign-in error: $e');
      return null;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      await _googleSignIn.signOut();
      AppLogger.log('Signed out');
    } catch (e) {
      AppLogger.log('Sign-out error: $e');
    }
  }

  /// Get current user
  User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  /// Check if user is signed in
  bool isSignedIn() {
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Get user email
  String? getUserEmail() {
    return FirebaseAuth.instance.currentUser?.email;
  }
}
