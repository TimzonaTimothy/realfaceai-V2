import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The app's text input.
///
/// Anatomy, top to bottom:
///   label (+ optional trailing link, e.g. "Forgot password?")
///   field: 44 px, white, hairline border, cobalt border + soft halo on focus
///   helper or error line
///
/// The label sits above the field instead of floating inside it, so it is
/// always readable and never collides with the value. Password fields get a
/// show/hide toggle for free.
class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final Widget? labelTrailing;
  final String? hint;
  final String? helper;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool isPassword;
  final bool enabled;
  final bool autofocus;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final int maxLines;
  final int? maxLength;
  final TextStyle? style;
  final TextAlign textAlign;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.labelTrailing,
    this.hint,
    this.helper,
    this.prefixIcon,
    this.suffix,
    this.isPassword = false,
    this.enabled = true,
    this.autofocus = false,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.maxLines = 1,
    this.maxLength,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _focused = false;
  bool _hover = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() => _focused = _focus.hasFocus);

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.controller?.text ?? '',
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(widget.controller?.text ?? _value),
      builder: (state) {
        final hasError = state.hasError;
        final borderColor = hasError
            ? AppColors.tally
            : _focused
                ? AppColors.cobalt
                : _hover
                    ? AppColors.borderHover
                    : AppColors.borderLight;

        Widget? suffix = widget.suffix;
        if (widget.isPassword) {
          suffix = IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            splashRadius: 18,
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          );
        }

        final field = TextField(
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          obscureText: widget.isPassword && _obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          textAlign: widget.textAlign,
          style: widget.style ??
              TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
          onChanged: (v) {
            _value = v;
            state.didChange(v);
            widget.onChanged?.call(v);
          },
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hint,
            counterText: '',
            filled: true,
            fillColor:
                widget.enabled ? AppColors.bgInput : AppColors.bgSubtle,
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(widget.prefixIcon,
                    size: 18,
                    color: _focused ? AppColors.cobalt : AppColors.textMuted),
            suffixIcon: suffix,
            contentPadding: EdgeInsets.symmetric(
                horizontal: widget.prefixIcon == null ? 14 : 0,
                vertical: 13),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label!,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.05,
                      ),
                    ),
                  ),
                  if (widget.labelTrailing != null) widget.labelTrailing!,
                ],
              ),
              const SizedBox(height: 8),
            ],
            MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: widget.enabled ? AppColors.bgInput : AppColors.bgSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                      color: borderColor, width: _focused ? 1.5 : 1),
                  boxShadow: _focused
                      ? AppShadows.focus(
                          hasError ? AppColors.tally : AppColors.cobalt)
                      : AppShadows.xs,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                  child: field,
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.topLeft,
              child: (hasError || widget.helper != null)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasError) ...[
                            Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(Icons.error_outline_rounded,
                                  size: 14, color: AppColors.tally),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              hasError ? state.errorText! : widget.helper!,
                              style: TextStyle(
                                color: hasError
                                    ? AppColors.tally
                                    : AppColors.textMuted,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }

  String _value = '';
}

/// A small text link, sized for use next to a field label.
class InlineLink extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const InlineLink(this.text, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.cobalt,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
