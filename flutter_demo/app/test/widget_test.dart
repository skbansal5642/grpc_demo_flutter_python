import 'package:flutter_test/flutter_test.dart';
import 'package:grpc_demo_app/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const GrpcDemoApp());
    expect(find.text('gRPC Demo'), findsOneWidget);
  });
}
