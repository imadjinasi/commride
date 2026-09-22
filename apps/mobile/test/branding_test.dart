import 'package:commride_mobile/src/widgets/commride_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical CommRide branding paths stay explicit', () {
    expect(
      CommRideBrandAssets.appIcon,
      'assets/branding/commride-app-icon.png',
    );
    expect(
      CommRideBrandAssets.primaryLogo,
      'assets/branding/commride-primary-logo.png',
    );
    expect(
      CommRideBrandAssets.monochrome,
      'assets/branding/commride-monochrome.png',
    );
  });

  testWidgets('primary logo uses the approved asset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CommRideBrandImage(
            variant: CommRideBrandVariant.primary,
            size: 96,
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('commride-brand-primary')),
    );
    expect(image.semanticLabel, 'CommRide');
    expect(image.width, 96);
    expect(image.height, 96);
  });
}
