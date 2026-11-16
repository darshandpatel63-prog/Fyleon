// The black-video-screen bug: a Stack with only a zero-size non-positioned child collapses to 0 x 0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/shared/widgets/full_screen_stack.dart';

void main() {
  testWidgets('a plain Stack collapses when its only non-positioned child is empty (the old bug)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, c) => Stack(
              children: const [
                Positioned.fill(child: ColoredBox(key: Key('fill'), color: Colors.red)),
                SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('fill'))), Size.zero);
  });

  testWidgets('FullScreenStack always fills the screen, even with empty children', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, c) => const FullScreenStack(
              children: [
                Positioned.fill(child: ColoredBox(key: Key('fill'), color: Colors.red)),
                SizedBox.shrink(),
                SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
    final body = tester.getSize(find.byType(Scaffold));
    expect(tester.getSize(find.byKey(const Key('fill'))), body);
    expect(body.height, greaterThan(100));
  });
}
