import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';

class _FailingDataSource extends IeltsDataSource {
  _FailingDataSource(this.error) : super(apiClient: ApiClient());
  final Object error;

  @override
  Future<List<IeltsTestSummary>> listTests({String? testType}) async =>
      throw error;
}

void main() {
  test(
    'an unexpected exception surfaces the generic key, not its text',
    () async {
      final provider = IeltsProvider(
        dataSource: _FailingDataSource(StateError('secret internals')),
      );
      await provider.loadTests();
      expect(provider.error, 'ielts.errorGeneric');
      expect(provider.error, isNot(contains('secret')));
    },
  );

  test('network failures surface the network key', () {
    expect(ieltsUserMessage(const SocketException('x')), 'ielts.errorNetwork');
    expect(
      ieltsUserMessage(const ServerException('No network connection')),
      'ielts.errorNetwork',
    );
    expect(
      ieltsUserMessage(
        const ServerException('Request /x failed with status 500'),
      ),
      'ielts.errorGeneric',
    );
  });
}
