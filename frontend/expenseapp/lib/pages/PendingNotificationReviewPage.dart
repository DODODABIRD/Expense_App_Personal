import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/databaseHelper.dart';
import '../services/error_log_service.dart';
import '../services/notification_expense_service.dart';

class PendingNotificationReviewPage extends StatefulWidget {
  final Future<void> Function()? onExpenseApproved;

  const PendingNotificationReviewPage({super.key, this.onExpenseApproved});

  @override
  State<PendingNotificationReviewPage> createState() =>
      _PendingNotificationReviewPageState();
}

class _PendingNotificationDraft {
  final int id;
  final TextEditingController nameController;
  final TextEditingController amountController;
  final String sourceApp;
  final DateTime receivedAt;
  DateTime date;
  String category;
  String type;

  _PendingNotificationDraft(Map<String, dynamic> row)
    : id = row['id'] as int,
      nameController = TextEditingController(
        text: row['name']?.toString() ?? '',
      ),
      amountController = TextEditingController(
        text: row['amount']?.toString() ?? '',
      ),
      sourceApp = row['sourceApp']?.toString() ?? '',
      receivedAt =
          DateTime.tryParse(row['receivedAt']?.toString() ?? '') ??
          DateTime.now(),
      date = DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now(),
      category = row['category']?.toString() ?? 'lainnya',
      type = row['type']?.toString() ?? 'unexpected';

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class _PendingNotificationReviewPageState
    extends State<PendingNotificationReviewPage> {
  static const _categories = [
    'makanan',
    'transportasi',
    'hiburan',
    'school supply',
    'baju',
    'elektronik',
    'kesehatan',
    'lainnya',
  ];
  static const _types = ['expected', 'unexpected', 'others'];

  List<_PendingNotificationDraft> _items = [];
  final Set<int> _busyIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPending() async {
    setState(() => _isLoading = true);
    try {
      final rows = await DatabaseHelp.getPendingNotificationExpenses();
      final items = rows.map(_PendingNotificationDraft.new).toList();
      if (!mounted) {
        for (final item in items) {
          item.dispose();
        }
        return;
      }
      for (final item in _items) {
        item.dispose();
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load pending notifications');
      if (mounted) setState(() => _isLoading = false);
      _showMessage('Could not load pending notifications.');
    }
  }

  int _amount(_PendingNotificationDraft item) =>
      int.tryParse(
        item.amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
      ) ??
      0;

  Future<void> _persistDraft(_PendingNotificationDraft item) async {
    final name = item.nameController.text.trim();
    final amount = _amount(item);
    if (name.isEmpty || amount <= 0) {
      throw const FormatException(
        'Enter a name and an amount greater than zero.',
      );
    }

    final updated = await DatabaseHelp.updatePendingNotificationExpense(
      id: item.id,
      name: name,
      amount: amount,
      date: _dateString(item.date),
      category: _categories.contains(item.category) ? item.category : 'lainnya',
      type: _types.contains(item.type) ? item.type : 'unexpected',
    );
    if (updated == 0) {
      throw StateError('This pending notification no longer exists.');
    }
  }

  Future<void> _saveDraft(_PendingNotificationDraft item) async {
    if (!_beginAction(item.id)) return;
    try {
      await _persistDraft(item);
      _showMessage('Changes saved.');
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Save pending notification edits');
      _showMessage(
        error is FormatException ? error.message : 'Could not save changes.',
      );
    } finally {
      _endAction(item.id);
    }
  }

  Future<void> _approveDraft(_PendingNotificationDraft item) async {
    if (!_beginAction(item.id)) return;
    try {
      await _persistDraft(item);
      final approved = await DatabaseHelp.approvePendingNotificationExpense(
        item.id,
      );
      if (!approved) {
        throw StateError('This pending notification no longer exists.');
      }

      item.dispose();
      if (!mounted) return;
      setState(() => _items.remove(item));
      await widget.onExpenseApproved?.call();
      _showMessage('Added to expenses.');
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Approve pending notification');
      _showMessage(
        error is FormatException
            ? error.message
            : 'Could not add this expense.',
      );
    } finally {
      _endAction(item.id);
    }
  }

  Future<void> _discardDraft(_PendingNotificationDraft item) async {
    if (!_beginAction(item.id)) return;
    try {
      final deleted = await DatabaseHelp.discardPendingNotificationExpense(
        item.id,
      );
      if (deleted == 0) {
        throw StateError('This pending notification no longer exists.');
      }

      item.dispose();
      if (mounted) setState(() => _items.remove(item));
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Discard pending notification');
      _showMessage('Could not discard this notification.');
    } finally {
      _endAction(item.id);
    }
  }

  bool _beginAction(int id) {
    if (_busyIds.contains(id)) return false;
    setState(() => _busyIds.add(id));
    return true;
  }

  void _endAction(int id) {
    if (mounted) setState(() => _busyIds.remove(id));
  }

  Future<void> _selectDate(_PendingNotificationDraft item) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: item.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => item.date = selected);
  }

  String _dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _label(String value) => value
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  String _sourceLabel(String packageName) =>
      NotificationExpenseService.supportedApps[packageName] ?? packageName;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadPending,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 44),
                  SizedBox(height: 12),
                  Text('No parsed notifications to review.'),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) =>
                  _buildDraftCard(_items[index], colors),
            ),
    );
  }

  Widget _buildDraftCard(_PendingNotificationDraft item, ColorScheme colors) {
    final busy = _busyIds.contains(item.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_sourceLabel(item.sourceApp)}  |  ${DateFormat('MMM d, y - HH:mm').format(item.receivedAt)}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: item.nameController,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Name or merchant',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: item.amountController,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _selectDate(item),
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(DateFormat('yMMMd').format(item.date)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _categories.contains(item.category)
                ? item.category
                : 'lainnya',
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(_label(category)),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) setState(() => item.category = value);
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _types.contains(item.type) ? item.type : 'unexpected',
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: _types
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(_label(type))),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) setState(() => item.type = value);
                  },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: 'Discard notification',
                onPressed: busy ? null : () => _discardDraft(item),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: 'Save changes',
                onPressed: busy ? null : () => _saveDraft(item),
                icon: const Icon(Icons.save_outlined),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: busy ? null : () => _approveDraft(item),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Add expense'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
