import "package:flutter/foundation.dart";

class AppState extends ChangeNotifier {
  int counter = 0;

  void increment() {
    counter += 1;
    notifyListeners();
  }
}
