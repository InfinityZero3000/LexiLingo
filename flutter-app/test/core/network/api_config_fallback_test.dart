import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/utils/constants.dart';

void main() {
  tearDown(() {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
  });

  test('an empty API_BASE_URL_FALLBACK means no fallback, not production', () {
    dotenv.loadFromString(envString: 'API_BASE_URL_FALLBACK=');

    expect(ApiConfig.fallbackBaseUrl, isEmpty);
    expect(ApiConfig.fallbackBaseUrl, isNot(AppConstants.apiBaseUrl));
  });

  test('an unset API_BASE_URL_FALLBACK means no fallback', () {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');

    expect(ApiConfig.fallbackBaseUrl, isEmpty);
  });

  test('an empty AI_SERVICE_URL_FALLBACK means no fallback', () {
    dotenv.loadFromString(envString: 'AI_SERVICE_URL_FALLBACK=');

    expect(ApiConfig.fallbackAiServiceUrl, isEmpty);
  });

  test('an explicit fallback is still honoured', () {
    dotenv.loadFromString(
      envString: 'API_BASE_URL_FALLBACK=http://127.0.0.1:9000/api/v1',
    );

    expect(ApiConfig.fallbackBaseUrl, 'http://127.0.0.1:9000/api/v1');
  });
}
