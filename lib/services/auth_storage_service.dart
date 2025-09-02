import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

class AuthStorageService {
  static final AuthStorageService _instance = AuthStorageService._internal();
  factory AuthStorageService() => _instance;
  AuthStorageService._internal();

  static const String _verifierKey = 'supabase-auth-code-verifier';
  static const String _pendingReferrerKey = 'pending-referrer-code';
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized && _prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      print('🔐 AuthStorageService initialized');
    } catch (e) {
      print('🔐 Error initializing AuthStorageService: $e');
      _isInitialized = false;
      _prefs = null;
      throw Exception('Failed to initialize AuthStorageService: $e');
    }
  }

  Future<Map<String, String>> generateAndStoreVerifier() async {
    await initialize();
    if (!_isInitialized || _prefs == null) {
      throw Exception('AuthStorageService not properly initialized');
    }
    
    try {
      // Clear any existing verifier first
      await clearVerifier();
      
      // Generate new verifier (random bytes, base64url-encoded)
      final verifier = base64Url.encode(List<int>.generate(32, (_) => Random().nextInt(256)))
        .replaceAll('=', '')  // Remove padding
        .replaceAll('+', '-') // URL-safe
        .replaceAll('/', '_'); // URL-safe
      
      // Generate code challenge (same as verifier for 'plain' method)
      final codeChallenge = verifier;
      
      // Store verifier
      final success = await _prefs!.setString(_verifierKey, verifier);
      if (!success) {
        throw Exception('Failed to store PKCE verifier');
      }
      
      // Verify storage
      final storedVerifier = await getVerifier();
      if (storedVerifier != verifier) {
        throw Exception('PKCE verifier verification failed');
      }
      
      print('🔐 Generated and stored new PKCE verifier');
      
      return {
        'verifier': verifier,
        'codeChallenge': codeChallenge,
      };
    } catch (e) {
      print('🔐 Error generating/storing PKCE verifier: $e');
      await clearVerifier(); // Clean up on error
      throw Exception('Failed to generate/store PKCE verifier: $e');
    }
  }

  Future<String?> getVerifier() async {
    await initialize();
    if (!_isInitialized || _prefs == null) {
      print('🔐 AuthStorageService not properly initialized when getting verifier');
      return null;
    }
    
    try {
      final verifier = _prefs!.getString(_verifierKey);
      if (verifier != null) {
        print('🔐 Retrieved PKCE verifier from storage');
      } else {
        print('🔐 No PKCE verifier found in storage');
      }
      return verifier;
    } catch (e) {
      print('🔐 Error retrieving PKCE verifier: $e');
      return null;
    }
  }

  Future<void> clearVerifier() async {
    await initialize();
    if (!_isInitialized || _prefs == null) {
      print('🔐 AuthStorageService not properly initialized when clearing verifier');
      return;
    }
    
    try {
      await _prefs!.remove(_verifierKey);
      print('🔐 Cleared PKCE verifier');
    } catch (e) {
      print('🔐 Error clearing PKCE verifier: $e');
    }
  }

  // Check if verifier exists
  Future<bool> hasVerifier() async {
    await initialize();
    if (!_isInitialized || _prefs == null) {
      print('🔐 AuthStorageService not properly initialized when checking verifier');
      return false;
    }
    
    try {
      return _prefs!.containsKey(_verifierKey);
    } catch (e) {
      print('🔐 Error checking PKCE verifier existence: $e');
      return false;
    }
  }

  // Referral: store pending referrer code captured from deep link
  Future<void> setPendingReferrer(String code) async {
    await initialize();
    if (!_isInitialized || _prefs == null) return;
    try {
      await _prefs!.setString(_pendingReferrerKey, code);
      print('🔗 Stored pending referrer code: $code');
    } catch (e) {
      print('🔗 Error storing pending referrer code: $e');
    }
  }

  Future<String?> getPendingReferrer() async {
    await initialize();
    if (!_isInitialized || _prefs == null) return null;
    try {
      final code = _prefs!.getString(_pendingReferrerKey);
      if (code != null) {
        print('🔗 Retrieved pending referrer code: $code');
      }
      return code;
    } catch (e) {
      print('🔗 Error retrieving pending referrer code: $e');
      return null;
    }
  }

  Future<void> clearPendingReferrer() async {
    await initialize();
    if (!_isInitialized || _prefs == null) return;
    try {
      await _prefs!.remove(_pendingReferrerKey);
      print('🔗 Cleared pending referrer code');
    } catch (e) {
      print('🔗 Error clearing pending referrer code: $e');
    }
  }
}