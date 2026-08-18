import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/core/core.dart';

void main() {
  group('Adaptive Layout & Breakpoints Standards Test', () {
    test('Breakpoint thresholds match target surface matrix', () {
      expect(AppBreakpoints.compactMax, equals(399));
      expect(AppBreakpoints.mobileMax, equals(599));
      expect(AppBreakpoints.tabletMin, equals(600));
      expect(AppBreakpoints.tabletMax, equals(1023));
      expect(AppBreakpoints.desktopMin, equals(1024));
      expect(AppBreakpoints.ultraWideMin, equals(1920));
    });

    test('ScreenClass resolves correctly for all surfaces', () {
      expect(getScreenClass(360), equals(ScreenClass.compact)); // S1 / compact POS
      expect(getScreenClass(500), equals(ScreenClass.mobile));  // S1
      expect(getScreenClass(768), equals(ScreenClass.tablet));  // S2, S3
      expect(getScreenClass(1280), equals(ScreenClass.desktop)); // S5, S6
      expect(getScreenClass(2560), equals(ScreenClass.ultraWide)); // Ultra-wide / 4K
    });

    testWidgets('AdaptiveLayout renders mobile view on small screens', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveLayout(
            mobile: (_) => const Text('Mobile Surface'),
            tablet: (_) => const Text('Tablet Surface'),
            desktop: (_) => const Text('Desktop Surface'),
          ),
        ),
      );

      expect(find.text('Mobile Surface'), findsOneWidget);
      expect(find.text('Tablet Surface'), findsNothing);
      expect(find.text('Desktop Surface'), findsNothing);
    });

    testWidgets('AdaptiveLayout renders tablet view on 768px screens', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveLayout(
            mobile: (_) => const Text('Mobile Surface'),
            tablet: (_) => const Text('Tablet Surface'),
            desktop: (_) => const Text('Desktop Surface'),
          ),
        ),
      );

      expect(find.text('Tablet Surface'), findsOneWidget);
      expect(find.text('Mobile Surface'), findsNothing);
      expect(find.text('Desktop Surface'), findsNothing);
    });

    testWidgets('AdaptiveLayout renders desktop view on 1280px screens', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveLayout(
            mobile: (_) => const Text('Mobile Surface'),
            tablet: (_) => const Text('Tablet Surface'),
            desktop: (_) => const Text('Desktop Surface'),
          ),
        ),
      );

      expect(find.text('Desktop Surface'), findsOneWidget);
      expect(find.text('Mobile Surface'), findsNothing);
      expect(find.text('Tablet Surface'), findsNothing);
    });

    testWidgets('ConstrainedContent clamps wide monitors to max width', (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: ConstrainedContent(
            maxWidth: 1440,
            child: SizedBox(width: double.infinity, height: 100, key: Key('inner')),
          ),
        ),
      );

      final renderBox = tester.renderObject<RenderBox>(find.byKey(const Key('inner')));
      expect(renderBox.size.width, equals(1440));
    });
  });
}
