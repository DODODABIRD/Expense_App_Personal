import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/error_log_service.dart';

class DeveloperLogsPage extends StatefulWidget {
  final ErrorLogService? errorLogService;

  const DeveloperLogsPage({super.key, this.errorLogService});

  @override
  State<DeveloperLogsPage> createState() => _DeveloperLogsPageState();
}

class _DeveloperLogsPageState extends State<DeveloperLogsPage> {
  List<ErrorLogEntry>? _entries;
  Object? _loadError;
  bool _isLoading = true;
  bool _isSharing = false;

  ErrorLogService get _errorLogService =>
      widget.errorLogService ?? ErrorLogService.instance;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      final entries = await _errorLogService.readLogs();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load developer error logs');
      if (!mounted) return;
      setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _shareLogs() async {
    setState(() => _isSharing = true);
    try {
      final file = await _errorLogService.exportToTextFile();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'Expense App Error Logs',
          sharePositionOrigin: _sharePositionOrigin(),
        ),
      );
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Export and share developer logs');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share error logs: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Rect? _sharePositionOrigin() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Developer logs',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh logs',
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Export and share logs',
            onPressed: _isSharing ? null : _shareLogs,
            icon: _isSharing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: _isLoading && entries == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && entries == null
          ? _buildLoadError()
          : RefreshIndicator(
              onRefresh: _loadLogs,
              child: entries == null || entries.isEmpty
                  ? _buildEmptyState(colors)
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildLogEntry(entries[index], colors),
                    ),
            ),
    );
  }

  Widget _buildLoadError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline_rounded, size: 42),
        const SizedBox(height: 12),
        const Center(child: Text('Unable to load developer logs.')),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colors) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.task_alt_rounded, size: 44, color: colors.primary),
        const SizedBox(height: 12),
        const Center(child: Text('No errors recorded.')),
      ],
    );
  }

  Widget _buildLogEntry(ErrorLogEntry entry, ColorScheme colors) {
    final timestamp = DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(entry.timestamp.toLocal());
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white24
        : Colors.black87;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.error_outline_rounded, color: Colors.red),
        title: Text(
          entry.message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text('$timestamp · ${entry.context}'),
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: colors.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(entry.message),
                if (entry.stackTrace.isNotEmpty) ...[
                  const Divider(height: 24),
                  SelectableText(
                    entry.stackTrace,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
