import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isIOS => !kIsWeb && Platform.isIOS;
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// AdMob only exists on phones/tablets.
bool get adsSupported => isAndroid || isIOS;
