import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/di/injection_container.dart' as di;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('initializeDependencies completes with skipDatabase=true', () async {
    await di.initializeDependencies(skipDatabase: true);
  });
}
