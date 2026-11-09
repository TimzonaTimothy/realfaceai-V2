import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realfaceai/widgets/app_text_field.dart';

void main() {
  testWidgets('AppTextField shows its label and validates', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: key,
          child: AppTextField(
            label: 'Email',
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ),
      ),
    ));

    expect(find.text('Email'), findsOneWidget);
    key.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
  });
}
