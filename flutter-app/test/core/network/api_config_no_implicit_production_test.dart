import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/utils/constants.dart';

void main() {
  tearDown(() {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
  });

  test('a non-production build with no API_BASE_URL stays local', () {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development\nAPI_BASE_URL=');

    expect(ApiConfig.baseUrl, AppConstants.localApiBaseUrl);
    expect(ApiConfig.baseUrl, isNot(AppConstants.apiBaseUrl));
  });

  test('a non-production build with no AI_SERVICE_URL stays local', () {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');

    expect(ApiConfig.aiServiceUrl, AppConstants.localAiServiceUrl);
    expect(ApiConfig.aiServiceUrl, isNot(AppConstants.aiServiceUrl));
  });

  test('a configured URL is used as given', () {
    dotenv.loadFromString(
      envString: 'API_BASE_URL=http://192.168.1.5:8000/api/v1',
    );

    expect(ApiConfig.baseUrl, 'http://192.168.1.5:8000/api/v1');
  });

  test('a production-config build keeps its production URL', () {
    dotenv.loadFromString(
      envString:
          'ENVIRONMENT=production\nDEBUG_MODE=false\nAPI_BASE_URL=https://www.lexilingo.me/api/v1\n',
    );

    expect(ApiConfig.baseUrl, 'https://www.lexilingo.me/api/v1');
  });

  test('DEBUG_MODE=false with no URL still resolves to production', () {
    dotenv.loadFromString(
      envString: 'ENVIRONMENT=production\nDEBUG_MODE=false',
    );

    expect(ApiConfig.baseUrl, AppConstants.apiBaseUrl);
    expect(ApiConfig.aiServiceUrl, AppConstants.aiServiceUrl);
  });
}
