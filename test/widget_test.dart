// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hmusic/main.dart';
import 'package:hmusic/presentation/providers/js_proxy_provider.dart';
import 'package:hmusic/presentation/providers/update_provider.dart';
import 'package:hmusic/presentation/providers/initialization_provider.dart';

class _FakeUpdateNotifier extends UpdateNotifier {
  @override
  Future<void> check() async {
    state = const UpdateState();
  }
}

class _FakeInitializationNotifier extends InitializationNotifier {
  _FakeInitializationNotifier(Ref ref) : super(ref);

  @override
  Future<void> initialize() async {
    state = const InitializationState(
      progress: 1.0,
      message: 'ready',
      isCompleted: true,
    );
  }
}

void main() {
  testWidgets('App boots and renders MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jsProxyProvider.overrideWith((ref) => JSProxyNotifier(ref, autoInit: false)),
          updateProvider.overrideWith((ref) => _FakeUpdateNotifier()),
          initializationProvider.overrideWith(
            (ref) => _FakeInitializationNotifier(ref),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
