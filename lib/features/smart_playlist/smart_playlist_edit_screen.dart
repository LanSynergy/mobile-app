import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/smart_playlist/smart_playlist_model.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

/// Create or edit a smart playlist — rule builder UI.
class SmartPlaylistEditScreen extends ConsumerStatefulWidget {
  final String? playlistId; // null = create new
  const SmartPlaylistEditScreen({super.key, this.playlistId});

  @override
  ConsumerState<SmartPlaylistEditScreen> createState() =>
      _SmartPlaylistEditScreenState();
}

class _SmartPlaylistEditScreenState
    extends ConsumerState<SmartPlaylistEditScreen> {
  final _nameController = TextEditingController();
  String _combinator = 'all';
  List<SmartRule> _rules = [];
  String _sort = 'title';
  String _sortOrder = 'asc';
  int? _limit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (widget.playlistId != null) {
      final db = ref.read(smartPlaylistDbProvider);
      final existing = await db.getById(widget.playlistId!);
      if (existing != null && mounted) {
        _nameController.text = existing.name;
        _combinator = existing.combinator;
        _rules = List.of(existing.rules);
        _sort = existing.sort;
        _sortOrder = existing.sortOrder;
        _limit = existing.limit;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    if (_rules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one rule')),
      );
      return;
    }

    final db = ref.read(smartPlaylistDbProvider);
    final playlist = SmartPlaylist(
      id: widget.playlistId ?? const Uuid().v4(),
      name: name,
      combinator: _combinator,
      rules: _rules,
      sort: _sort,
      sortOrder: _sortOrder,
      limit: _limit,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.save(playlist);
    ref.invalidate(smartPlaylistsProvider);
    if (mounted) context.pop();
  }

  void _addRule() {
    setState(() {
      _rules.add(const SmartRule(
        field: 'artist',
        operator: 'contains',
        value: '',
      ));
    });
  }

  void _removeRule(int index) {
    setState(() => _rules.removeAt(index));
  }

  void _updateRule(int index, SmartRule rule) {
    setState(() => _rules[index] = rule);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isEdit = widget.playlistId != null;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        title: Text(isEdit ? 'Edit Smart Playlist' : 'New Smart Playlist'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.indigo400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s8,
        ),
        children: [
          // Name
          TextField(
            controller: _nameController,
            style: AfTypography.titleSmall,
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: AfTypography.titleSmall.copyWith(
                color: AfColors.textTertiary,
              ),
              filled: true,
              fillColor: AfColors.surfaceBase,
              border: OutlineInputBorder(
                borderRadius: AfRadii.borderMd,
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: AfSpacing.s16),

          // Combinator
          Row(
            children: [
              Text('Match ', style: AfTypography.bodyMedium),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'any', label: Text('Any')),
                ],
                selected: {_combinator},
                onSelectionChanged: (v) =>
                    setState(() => _combinator = v.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: AfColors.surfaceBase,
                  selectedBackgroundColor: AfColors.indigo600,
                ),
              ),
              Text(' rules', style: AfTypography.bodyMedium),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),

          // Rules
          for (int i = 0; i < _rules.length; i++) ...[
            _RuleRow(
              rule: _rules[i],
              onChanged: (r) => _updateRule(i, r),
              onDelete: () => _removeRule(i),
            ),
            const SizedBox(height: AfSpacing.s8),
          ],

          // Add rule button
          OutlinedButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add rule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AfColors.indigo400,
              side: const BorderSide(color: AfColors.surfaceHigh),
              shape: RoundedRectangleBorder(borderRadius: AfRadii.borderMd),
            ),
          ),
          const SizedBox(height: AfSpacing.s24),

          // Sort
          Row(
            children: [
              Text('Sort by ', style: AfTypography.bodyMedium),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
              initialValue: _sort,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AfColors.surfaceBase,
                    border: OutlineInputBorder(
                      borderRadius: AfRadii.borderMd,
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  dropdownColor: AfColors.surfaceRaised,
                  items: kSmartSortOptions.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _sort = v ?? 'title'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _sortOrder == 'asc'
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: AfColors.textSecondary,
                ),
                onPressed: () => setState(() =>
                    _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc'),
                tooltip: _sortOrder == 'asc' ? 'Ascending' : 'Descending',
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),

          // Limit
          Row(
            children: [
              Text('Limit to ', style: AfTypography.bodyMedium),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(
                      text: _limit?.toString() ?? ''),
                  decoration: InputDecoration(
                    hintText: '∞',
                    filled: true,
                    fillColor: AfColors.surfaceBase,
                    border: OutlineInputBorder(
                      borderRadius: AfRadii.borderMd,
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) =>
                      _limit = int.tryParse(v),
                ),
              ),
              Text(' tracks', style: AfTypography.bodyMedium),
            ],
          ),
          const SizedBox(height: AfSpacing.s32),
        ],
      ),
    );
  }
}

/// A single rule row with field, operator, and value inputs.
class _RuleRow extends StatelessWidget {
  final SmartRule rule;
  final ValueChanged<SmartRule> onChanged;
  final VoidCallback onDelete;

  const _RuleRow({
    required this.rule,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final operators = operatorsForField(rule.field);
    // If current operator isn't valid for the new field, reset it
    final effectiveOp =
        operators.contains(rule.operator) ? rule.operator : operators.first;

    return Container(
      padding: const EdgeInsets.all(AfSpacing.s12),
      decoration: BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderMd,
      ),
      child: Row(
        children: [
          // Field picker
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: rule.field,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              dropdownColor: AfColors.surfaceRaised,
              style: AfTypography.bodySmall,
              items: kSmartFields.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final newOps = operatorsForField(v);
                onChanged(SmartRule(
                  field: v,
                  operator: newOps.first,
                  value: v == 'isFavorite' ? true : '',
                ));
              },
            ),
          ),
          const SizedBox(width: 8),
          // Operator picker
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: effectiveOp,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              dropdownColor: AfColors.surfaceRaised,
              style: AfTypography.bodySmall,
              items: operators
                  .map((op) => DropdownMenuItem(
                      value: op, child: Text(_opLabel(op))))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                onChanged(SmartRule(
                  field: rule.field,
                  operator: v,
                  value: rule.value,
                ));
              },
            ),
          ),
          const SizedBox(width: 8),
          // Value input
          Expanded(
            flex: 4,
            child: _buildValueInput(),
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AfColors.textTertiary,
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildValueInput() {
    if (rule.field == 'isFavorite') {
      return Switch.adaptive(
        value: rule.value == true,
        onChanged: (v) => onChanged(SmartRule(
          field: rule.field,
          operator: rule.operator,
          value: v,
        )),
        activeTrackColor: AfColors.indigo500,
      );
    }

    return TextField(
      controller: TextEditingController(text: '${rule.value}'),
      style: AfTypography.bodySmall,
      keyboardType: _isNumericField(rule.field)
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: _isNumericField(rule.field) ? '0' : 'value',
        hintStyle:
            AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (v) {
        final parsed = _isNumericField(rule.field) ? (int.tryParse(v) ?? v) : v;
        onChanged(SmartRule(
          field: rule.field,
          operator: rule.operator,
          value: parsed,
        ));
      },
    );
  }

  bool _isNumericField(String field) =>
      field == 'year' || field == 'duration' || field == 'bitrate' ||
      field == 'dateAdded';

  String _opLabel(String op) => switch (op) {
        'is' => 'is',
        'isNot' => 'is not',
        'contains' => 'contains',
        'notContains' => 'not contains',
        'gt' => '>',
        'lt' => '<',
        'inTheRange' => 'between',
        'inTheLast' => 'last N days',
        _ => op,
      };
}
