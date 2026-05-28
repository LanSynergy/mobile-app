import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';

Widget eqSectionLabel(String title) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AfSpacing.s4,
    0,
    AfSpacing.s4,
    AfSpacing.s8,
  ),
  child: Text(
    title,
    style: AfTypography.bodySmall.copyWith(
      color: AfColors.textTertiary,
      fontWeight: FontWeight.w500,
    ),
  ),
);

Widget eqCard(List<Widget> children) => Material(
  color: AfColors.surfaceBase,
  borderRadius: AfRadii.borderLg,
  clipBehavior: Clip.antiAlias,
  child: Padding(
    padding: const EdgeInsets.all(AfSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  ),
);

Widget eqToggleTile(
  String title,
  String subtitle,
  bool value,
  ValueChanged<bool> onChanged, {
  bool enabled = true,
}) {
  return SwitchListTile.adaptive(
    value: value,
    onChanged: enabled ? onChanged : null,
    title: Text(title, style: AfTypography.bodyMedium),
    subtitle: Text(
      subtitle,
      style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
    ),
    activeThumbColor: AfColors.indigo500,
    contentPadding: EdgeInsets.zero,
  );
}

Widget eqSliderRow(
  String label,
  double value,
  double min,
  double max,
  int divisions,
  ValueChanged<double> onChanged,
  VoidCallback onChangeEnd, {
  String? suffix,
  int precision = 0,
  bool enabled = true,
}) {
  final display = value >= 0 && suffix == 'dB'
      ? '+${value.toStringAsFixed(precision)}'
      : value.toStringAsFixed(precision);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Text(label, style: AfTypography.bodyMedium),
          const Spacer(),
          Text(
            suffix != null ? '$display $suffix' : display,
            style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        activeColor: AfColors.indigo400,
        onChanged: enabled ? onChanged : null,
        onChangeEnd: enabled ? (_) => onChangeEnd() : null,
      ),
    ],
  );
}

Widget eqTextFieldRow(
  BuildContext context,
  String label,
  String value,
  String hint,
  ValueChanged<String> onSubmitted,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: AfTypography.bodySmall)),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: value,
            style: AfTypography.mono.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AfTypography.mono.copyWith(
                fontSize: 12,
                color: AfColors.textTertiary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AfColors.surfaceHigh),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AfColors.surfaceHigh),
              ),
            ),
            onFieldSubmitted: onSubmitted,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ],
    ),
  );
}
