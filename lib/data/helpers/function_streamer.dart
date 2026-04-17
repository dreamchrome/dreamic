import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:dreamic/app/app_config_base.dart';
import 'package:dreamic/utils/logger.dart';
import 'package:http/http.dart' as http;

//
// Firebase Functions streamer.
//
Future<StreamSubscription<String>> streamFirebaseFunction(
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
    token = await FirebaseAuth.instanceFor(app: AppConfigBase.firebaseApp)
        .currentUser
        ?.getIdToken();
  } catch (e) {
    loge('Error getting ID token: $e');
    onStreamError?.call(e);
    return Stream<String>.empty().listen((_) {});
  }

  if (token == null) {
    logd('User not authenticated.');
    onStreamError?.call('User not authenticated.');
    return Stream<String>.empty().listen((_) {});
  }

  final request = http.Request('POST', firebaseFunctionUrl)
    ..headers['Content-Type'] = 'application/json'
    ..headers['Authorization'] = 'Bearer $token'
    ..body = jsonEncode(data);

  final client = http.Client();
  http.StreamedResponse streamedResponse;
  try {
    streamedResponse = await client.send(request);
  } catch (e) {
    client.close();
    onStreamError?.call(e);
    return Stream<String>.empty().listen((_) {});
  }

  var cancelled = false;
  final controller = StreamController<String>(
    onCancel: () {
      cancelled = true;
      client.close();
    },
  );

  streamedResponse.stream.transform(utf8.decoder).listen(
    controller.add,
    onDone: () {
      try {
        if (!cancelled) onStreamDone?.call();
      } finally {
        client.close();
        controller.close();
      }
    },
    onError: (error) {
      try {
        if (!cancelled) onStreamError?.call(error);
      } finally {
        client.close();
        controller.close();
      }
    },
  );

  return controller.stream.listen(onStreamReceived);
}

//
// Firebase Functions streamer with line-by-line handling.
//
Future<StreamSubscription<String>> streamFirebaseFuncionLineByLine(
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
    token = await FirebaseAuth.instanceFor(app: AppConfigBase.firebaseApp)
        .currentUser
        ?.getIdToken();
  } catch (e) {
    loge('Error getting ID token: $e');
    onStreamError?.call(e);
    return Stream<String>.empty().listen((_) {});
  }

  if (token == null) {
    logd('User not authenticated.');
    onStreamError?.call('User not authenticated.');
    return Stream<String>.empty().listen((_) {});
  }

  final request = http.Request('POST', firebaseFunctionUrl)
    ..headers['Content-Type'] = 'application/json'
    ..headers['Authorization'] = 'Bearer $token'
    ..body = jsonEncode(data);

  final client = http.Client();
  http.StreamedResponse streamedResponse;
  try {
    streamedResponse = await client.send(request);
  } catch (e) {
    client.close();
    onStreamError?.call(e);
    return Stream<String>.empty().listen((_) {});
  }

  var cancelled = false;
  final controller = StreamController<String>(
    onCancel: () {
      cancelled = true;
      client.close();
    },
  );

  // Custom line-by-line handling with optional sending of last line
  String buffer = '';
  streamedResponse.stream.transform(utf8.decoder).listen(
    (chunk) {
      buffer += chunk;
      int index;
      while ((index = buffer.indexOf('\n')) != -1) {
        String line = buffer.substring(0, index);
        controller.add(line);
        buffer = buffer.substring(index + 1);
      }
    },
    onDone: () {
      try {
        if (!cancelled) {
          if (sendLastLine && buffer.isNotEmpty) {
            controller.add(buffer);
          }
          onStreamDone?.call();
        }
      } finally {
        client.close();
        controller.close();
      }
    },
    onError: (error) {
      try {
        if (!cancelled) onStreamError?.call(error);
      } finally {
        client.close();
        controller.close();
      }
    },
  );

  return controller.stream.listen(onStreamReceived);
}
