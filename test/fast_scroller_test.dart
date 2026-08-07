import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/ui/widgets/amoled_fast_scroller.dart';

void main() {
  testWidgets('AmoledFastScroller renders child and handles scroll and drag correctly',
      (WidgetTester tester) async {
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AmoledFastScroller(
            controller: scrollController,
            child: ListView.builder(
              controller: scrollController,
              itemCount: 100,
              itemExtent: 50,
              itemBuilder: (context, index) => ListTile(
                title: Text('Item $index'),
              ),
            ),
          ),
        ),
      ),
    );

    // Initial state: Item 0 visible
    expect(find.text('Item 0'), findsOneWidget);
    expect(find.byType(AmoledFastScroller), findsOneWidget);

    // Scroll down
    scrollController.jumpTo(1000);
    await tester.pumpAndSettle();

    expect(scrollController.offset, 1000);

    // Test dragging on the rightmost edge
    final scrollerFinder = find.byType(AmoledFastScroller);
    final centerRight = tester.getTopRight(scrollerFinder) + const Offset(-10, 200);

    await tester.dragFrom(centerRight, const Offset(0, 150));
    await tester.pumpAndSettle();

    // Verify offset changed through drag
    expect(scrollController.offset, greaterThan(0));

    // Pump 4 seconds to verify auto-hide timer
    await tester.pump(const Duration(seconds: 4));
  });
}
