import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// FCM/APNs carries generic reminder copy only. Tokens are scoped to Firebase
/// Auth UIDs and are deleted from the device before another account may use it.
class PushService {
  PushService(this.auth, this.firestore, {FirebaseMessaging? messaging})
    : _messaging = messaging;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseMessaging? _messaging;
  FirebaseMessaging get messaging => _messaging ?? FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _openSubscription;
  String? _token;
  String? _ownerId;
  bool _enabled = false;
  int _generation = 0;
  void Function(String route)? _onTap;
  String? _pendingRoute;
  bool get enabled => _enabled;
  static const _routes = {'/today', '/plan', '/walking', '/protein', '/coach'};
  void setTapHandler(void Function(String route)? handler) {
    _onTap = handler;
    final pending = _pendingRoute;
    if (handler != null &&
        pending != null &&
        _enabled &&
        auth.currentUser?.uid == _ownerId) {
      _pendingRoute = null;
      handler(pending);
    }
  }

  static String tokenDocumentId(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  Future<bool> enable({void Function(String route)? onTap}) async {
    if (kIsWeb ||
        Firebase.apps.isEmpty ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return false;
    }
    final userId = auth.currentUser?.uid;
    if (userId == null) return false;
    if (_ownerId != userId) _pendingRoute = null;
    final generation = ++_generation;
    setTapHandler(onTap);
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (generation != _generation || auth.currentUser?.uid != userId) {
      return false;
    }
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    _ownerId = userId;
    _enabled = true;
    await messaging.setAutoInitEnabled(true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    if (generation != _generation || auth.currentUser?.uid != userId) {
      return false;
    }
    await _tokenSubscription?.cancel();
    _tokenSubscription = messaging.onTokenRefresh.listen((token) {
      unawaited(_register(token, userId, generation).catchError((Object _) {}));
    });
    await _openSubscription?.cancel();
    _openSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_open);
    final initial = await messaging.getInitialMessage();
    if (generation != _generation || auth.currentUser?.uid != userId) {
      return false;
    }
    if (initial != null) _open(initial);
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        await messaging.getAPNSToken() != null) {
      final token = await messaging.getToken();
      if (token != null) await _register(token, userId, generation);
    }
    return generation == _generation && auth.currentUser?.uid == userId;
  }

  void _open(RemoteMessage message) {
    if (!_enabled || auth.currentUser?.uid != _ownerId) return;
    final route = message.data['route'];
    if (route is String && _routes.contains(route)) {
      final handler = _onTap;
      if (handler == null) {
        _pendingRoute = route;
      } else {
        handler(route);
      }
    }
  }

  Future<void> _register(String token, String userId, int generation) async {
    if (!_enabled ||
        generation != _generation ||
        auth.currentUser?.uid != userId) {
      return;
    }
    final oldToken = _token;
    final id = tokenDocumentId(token);
    final reference = firestore
        .collection('users')
        .doc(userId)
        .collection('device_tokens')
        .doc(id);
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      final now = DateTime.now().toUtc().toIso8601String();
      transaction.set(reference, {
        'id': id,
        'user_id': userId,
        'created_at': existing.data()?['created_at'] ?? now,
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'updated_at': now,
      });
    });
    if (generation != _generation || auth.currentUser?.uid != userId) return;
    _token = token;
    if (oldToken != null && oldToken != token) {
      await firestore
          .collection('users')
          .doc(userId)
          .collection('device_tokens')
          .doc(tokenDocumentId(oldToken))
          .delete();
    }
  }

  /// Call before signing out, while the previous user's authorization is valid.
  Future<void> disable() async {
    ++_generation;
    _enabled = false;
    _onTap = null;
    _pendingRoute = null;
    await _tokenSubscription?.cancel();
    await _openSubscription?.cancel();
    final owner = _ownerId, token = _token;
    _ownerId = null;
    _token = null;
    try {
      if (owner != null && token != null) {
        await firestore
            .collection('users')
            .doc(owner)
            .collection('device_tokens')
            .doc(tokenDocumentId(token))
            .delete();
      }
    } finally {
      // Offline Firestore cleanup still revokes this installation's FCM token.
      if (Firebase.apps.isNotEmpty) {
        await messaging.setAutoInitEnabled(false);
        await messaging.deleteToken();
      }
    }
  }
}
