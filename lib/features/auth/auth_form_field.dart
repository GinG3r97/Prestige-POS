import 'package:flutter/material.dart';

import '../widgets/keyboard_accessory_field.dart';

/// Thin wrapper around [KeyboardAccessoryField] used by auth/onboarding/settings
/// forms. Behaviour is identical to the original AuthField (same constructor),
/// but every field now pops a glass accessory above the keyboard while focused.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.trailing,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return KeyboardAccessoryField(
      controller: controller,
      label: label,
      accessoryLabel: label,
      hint: hint,
      obscure: obscure,
      keyboardType: keyboardType,
      validator: validator,
      trailing: trailing,
    );
  }
}
