import 'package:flutter/widgets.dart';

mixin SetStateSafeMixin<T extends StatefulWidget> on State<T> {
  void setStateSafe(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }
}
