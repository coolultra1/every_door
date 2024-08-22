import 'dart:convert';
import 'dart:async';
import 'package:every_door/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:oauth2_client/access_token_response.dart';
import 'package:oauth2_client/authorization_response.dart';
import 'package:oauth2_client/src/oauth2_utils.dart';
import 'package:oauth2_client/oauth2_client.dart';
import 'package:random_string/random_string.dart';

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';

class OpenStreetMapOAuth2Client extends OAuth2Client {
  OpenStreetMapOAuth2Client(bool isWeb)
      : super(
          authorizeUrl: 'https://$kOsmAuth2Endpoint/oauth2/authorize',
          tokenUrl: 'https://$kOsmAuth2Endpoint/oauth2/token',
          redirectUri: isWeb ? '$kInstanceUrl/oauth.html' : 'everydoor:/oauth',
          customUriScheme: isWeb ? 'http' : 'everydoor',
        );
}

class OAuthHelperError implements Exception {
  final String message;

  OAuthHelperError(this.message);

  @override
  String toString() => 'OAuthHelperError($message)';
}

class OpenStreetMapOAuthHelper {
  static const scopes = ['read_prefs', 'write_api', 'write_notes'];
  static const kTokenKey = 'osmToken';
  static String? _codeVerifier;
  static OpenStreetMapOAuthHelper? _instance;
  static OpenStreetMapOAuthHelper get instance {
    _instance ??= OpenStreetMapOAuthHelper._internal();
    return _instance!;
  }

  // Private named constructor
  OpenStreetMapOAuthHelper._internal();

  final OAuth2Client _client = OpenStreetMapOAuth2Client(kIsWeb);
  final String _clientId = 'l2Kg0oCr4YUgJvwHj7mEDYHnK5fZ70WhhtNhdLybS2c';
  final String _clientSecret = 'CHahJEaQO69FKblcRtG8-NKQ6vBV3yBKIBiqu8VU6u8';

  Future<AccessTokenResponse?> getToken([bool requestAuth = true]) async {
    var token = await _loadToken();
    print("Loaded token");
    if (token != null) {
      if (token.refreshNeeded()) {
        if (token.refreshToken != null) {
          token = await _refreshToken(token.refreshToken!, requestAuth);
        } else {
          if (!requestAuth) return null;
          token = await _fetchToken();
        }
      }
    } else {
      if (!requestAuth) return null;
      print("Requesting auth");
      token = await _fetchToken();
      print("Wait for fetching token over!");
    }

    if (!token.isValid()) {
      throw OAuthHelperError(
          'Provider error ${token.httpStatusCode}: ${token.error}: ${token.errorDescription}');
    }

    if (!token.isBearer()) {
      throw OAuthHelperError('Only Bearer tokens are supported.');
    }

    return token;
  }

  Future<AccessTokenResponse?> _loadToken() async {
    final secure = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true));
    String? data;
    try {
      data = await secure.read(key: kTokenKey);
    } on PlatformException {
      await secure.deleteAll();
    }
    return data == null ? null : AccessTokenResponse.fromMap(jsonDecode(data));
  }

  Future<void> _saveToken(AccessTokenResponse? token) async {
    print("Saving token");
    final secure = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true));
    try {
      if (token == null) {
        await secure.delete(key: kTokenKey);
      } else {
        await secure.write(key: kTokenKey, value: jsonEncode(token.respMap));
      }
    } on PlatformException {
      await secure.deleteAll();
      if (token != null) {
        await secure.write(key: kTokenKey, value: jsonEncode(token.respMap));
      }
    }
  }

Completer<AccessTokenResponse> accessTokenResponseCompleter = Completer<AccessTokenResponse>();

Future<AccessTokenResponse> _fetchToken() async {
    _codeVerifier = randomAlphaNumeric(80);
    final codeChallenge = OAuth2Utils.generateCodeChallenge(_codeVerifier!);

    final authResponseFuture = _client.requestAuthorization(
        clientId: _clientId, scopes: scopes, codeChallenge: codeChallenge);

    if (!kIsWeb) {
        final authResponse = await authResponseFuture;
        return await processAuthCode(authResponse.code);
    } else {
        return await accessTokenResponseCompleter.future;
    }
}

 Future<AccessTokenResponse> processAuthCode(String? code) async {
    // Complete the completer to signal that the code is available
    AccessTokenResponse token = await _client.requestAccessToken(
        code: code!,
        clientId: _clientId,
        clientSecret: _clientSecret,
        codeVerifier: _codeVerifier);

    if (!accessTokenResponseCompleter.isCompleted) {
        accessTokenResponseCompleter.complete(token);
    }

    await _processRetrievedToken(token);
    print("Awaited processing! - Returning on processAuthCode.");
    return token;
}

  Future<AccessTokenResponse> _processRetrievedToken(
      AccessTokenResponse token) async {
    print("Processing");
    if (token.isValid()) await _saveToken(token);
    print("Processed. Returning on processRetrievedToken.");
    return token;
  }

  Future<AccessTokenResponse> _refreshToken(String refreshToken,
      [bool requestAuth = true]) async {
    AccessTokenResponse token;
    try {
      token = await _client.refreshToken(refreshToken, clientId: _clientId);
    } catch (e) {
      if (!requestAuth) rethrow;
      return await _fetchToken();
    }

    if (token.isValid()) {
      if (!token.hasRefreshToken()) token.refreshToken = refreshToken;
      await _saveToken(token);
    } else {
      if (token.error == 'invalid_grant') {
        // expired
        await _saveToken(null);
        final token2 = await getToken();
        if (token2 == null) {
          throw OAuthHelperError(
              'Token and refresh token expired, and could not get a fresh one.');
        }
        token = token2;
      } else {
        throw OAuthHelperError(
            'Error refreshing a token ${token.error}: ${token.errorDescription}');
      }
    }

    return token;
  }

  Future<void> deleteToken() async {
    final token = await _loadToken();
    if (token != null) {
      await _saveToken(null);
      await _client.revokeToken(
        token,
        clientId: _clientId,
        clientSecret: _clientSecret,
      );
    }
  }

  Future<String?> getAuthorizationValue([AccessTokenResponse? token]) async {
    if (token == null) {
      try {
        token = await getToken(false);
      } on Exception catch (e) {
        Logger('OpenStreetMapOAuthHelper')
            .warning('Failed to get token in getAuthValue', e);
        return null;
      }
      if (token == null) return null; // Not authorizing here
    }
    return 'Bearer ${token.accessToken}';
  }
}
