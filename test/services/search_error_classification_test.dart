import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hmusic/data/models/search_outcome.dart';
import 'package:hmusic/data/services/native_music_search_service.dart';

void main() {
  group('classifySearchError', () {
    test('Dio cancel -> cancelled', () {
      final err = DioException.requestCancelled(
        requestOptions: RequestOptions(path: '/test'),
        reason: 'user_cancelled',
      );
      expect(classifySearchError(err), SearchErrorType.cancelled);
    });

    test('HTTP 404 -> notFound', () {
      final err = DioException.badResponse(
        statusCode: 404,
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 404,
        ),
      );
      expect(classifySearchError(err), SearchErrorType.notFound);
    });

    test('illegal text -> rateLimited', () {
      expect(
        classifySearchError(Exception('The request is illegal!')),
        SearchErrorType.rateLimited,
      );
    });

    test('format exception -> parse', () {
      expect(
        classifySearchError(const FormatException('bad json')),
        SearchErrorType.parse,
      );
    });
  });
}
