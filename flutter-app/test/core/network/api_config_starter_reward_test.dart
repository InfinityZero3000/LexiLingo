import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_config.dart';

void main() {
  tearDown(() {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
  });

  test('starter reward defaults to disabled in production', () {
    dotenv.loadFromString(envString: 'ENVIRONMENT=production');

    expect(ApiConfig.enableStarterReward, isFalse);
  });

  test('starter reward can be explicitly enabled in production', () {
    dotenv.loadFromString(
      envString: '''
ENVIRONMENT=production
ENABLE_STARTER_REWARD=true
''',
    );

    expect(ApiConfig.enableStarterReward, isTrue);
  });
}
