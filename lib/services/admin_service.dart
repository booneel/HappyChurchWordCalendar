import 'package:firebase_auth/firebase_auth.dart';

/// IMPORTANT:
/// This service intentionally does NOT contain a real approval code.
/// For production, the code must be verified by a trusted backend/Cloud Function
/// or another server-side mechanism. Never put a real admin secret in Flutter code.
///
/// The Firebase account used here is only for the administrator and is invisible
/// to normal users. The UI asks for an approval code first; after server-side
/// verification, the app can sign the admin in with a custom token.
class AdminService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get isSignedInAsAdmin => _auth.currentUser != null;

  Future<void> signOut() => _auth.signOut();
}
