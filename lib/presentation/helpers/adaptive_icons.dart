import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

var adaptiveShareIcon = kIsWeb
    ? Icons.ios_share_rounded
    : Platform.isIOS || Platform.isMacOS
        ? Icons.ios_share_rounded
        : Icons.share_rounded;
