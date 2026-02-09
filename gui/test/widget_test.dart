import 'package:flutter_test/flutter_test.dart';
import 'package:utsutsu2d_gui/main.dart';

void main() {
  testWidgets('shows no model loaded message', (WidgetTester tester) async {
    await tester.pumpWidget(const Utsutsu2DApp());
    expect(find.text('No model loaded. Use --dart-define=MODEL_PATH=...'),
        findsOneWidget);
  });
}
