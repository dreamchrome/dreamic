import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:http/http.dart' as http;

//
// Firebase Functions streamer.
//
streamFirebaseFunction(
  String functionName,
  Map<String, dynamic> data,
  Function(String) onStreamReceived, {
  Function()? onStreamDone,
  Function? onStreamError,
}) async {
  final Uri firebaseFunctionUrl = AppConfigBase.firebaseFunctionUri(functionName);

  // Get the current user's ID token
  String? token;
  try {
    token = await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (e) {
    loge('Error getting ID token: $e');
    onStreamError?.call(e);
    return;
  }

  if (token == null) {
    logd('User not authenticated.');
    onStreamError?.call('User not authenticated.');
    return;
  }

  final request = http.Request('POST', firebaseFunctionUrl)
    ..headers['Content-Type'] = 'application/json'
    ..headers['Authorization'] = 'Bearer $token' // Add the token to the header
    ..body = jsonEncode(data);

  final streamedResponse = await http.Client().send(request);

  streamedResponse.stream.transform(utf8.decoder).listen(
        onStreamReceived,
        onDone: onStreamDone,
        onError: onStreamError,
      );
}

//
// Firebase Functions streamer with line-by-line handling.
//
streamFirebaseFuncionLineByLine(
  String functionName,
  Map<String, dynamic> data,
  Function(String) onStreamReceived, {
  Function()? onStreamDone,
  Function? onStreamError,
  bool sendLastLine = false,
}) async {
  final Uri firebaseFunctionUrl = AppConfigBase.firebaseFunctionUri(functionName);

  // Get the current user's ID token
  String? token;
  try {
    token = await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (e) {
    loge('Error getting ID token: $e');
    onStreamError?.call(e);
    return;
  }

  if (token == null) {
    logd('User not authenticated.');
    onStreamError?.call('User not authenticated.');
    return;
  }

  final request = http.Request('POST', firebaseFunctionUrl)
    ..headers['Content-Type'] = 'application/json'
    ..headers['Authorization'] = 'Bearer $token' // Add the token to the header
    ..body = jsonEncode(data);

  final streamedResponse = await http.Client().send(request);

  // Custom line-by-line handling with optional sending of last line
  String buffer = '';
  streamedResponse.stream.transform(utf8.decoder).listen(
    (chunk) {
      buffer += chunk;
      int index;
      while ((index = buffer.indexOf('\n')) != -1) {
        String line = buffer.substring(0, index);
        onStreamReceived(line);
        buffer = buffer.substring(index + 1);
      }
    },
    onDone: () {
      if (sendLastLine && buffer.isNotEmpty) {
        onStreamReceived(buffer);
      }
      if (onStreamDone != null) onStreamDone();
    },
    onError: onStreamError,
  );
}
