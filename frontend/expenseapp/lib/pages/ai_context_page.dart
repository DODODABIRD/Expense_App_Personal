import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/ApiService.dart';
import '../services/error_log_service.dart';
import '../services/notification_expense_service.dart';
import '../widgets/neo_animations.dart';
import '../widgets/neo_snackbar.dart';

class AiContextPage extends StatefulWidget {
  const AiContextPage({super.key, this.loadReference});

  /// Overrides the backend call so the page can be tested without a server.
  final Future<Map<String, dynamic>> Function()? loadReference;

  @override
  State<AiContextPage> createState() => _AiContextPageState();
}

class _AiContextPageState extends State<AiContextPage> {
  _AiContext? _context;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _context == null;
      _loadError = null;
    });
    try {
      final response =
          await (widget.loadReference ?? Throw.getAiNotificationReference)();
      if (!mounted) return;
      setState(() {
        _context = _AiContext.fromResponse(response);
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load AI notification context');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _refreshMemory() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final count = await NotificationExpenseService.instance
          .updateAiNotificationReference();
      await _load();
      if (!mounted) return;
      _showMessage('AI memory refreshed with $count expenses.');
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Refresh AI notification context');
      if (!mounted) return;
      _showMessage('Could not refresh AI memory: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (isError) {
      NeoSnackBar.error(context, message);
    } else {
      NeoSnackBar.success(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'AI memory',
          style: GoogleFonts.itim(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload AI memory',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading && _context == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _context == null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _load,
              child: _context == null || _context!.categories.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(_context!),
            ),
    );
  }

  Widget _buildContent(_AiContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        FadeSlideAnimation(child: _buildHeroCard(context)),
        const SizedBox(height: 26),
        _buildSectionHeader(
          'Where each category lands',
          '${context.categories.length} categories',
        ),
        const SizedBox(height: 12),
        FadeSlideAnimation(
          delay: const Duration(milliseconds: 80),
          child: _RangeMap(context: context),
        ),
        const SizedBox(height: 26),
        _buildSectionHeader('Category breakdown'),
        const SizedBox(height: 12),
        for (var index = 0; index < context.categories.length; index++)
          FadeSlideAnimation(
            delay: Duration(milliseconds: 120 + index * 60),
            child: _CategoryCard(
              category: context.categories[index],
              color: _categoryColor(context.categories[index].category),
            ),
          ),
        const SizedBox(height: 8),
        _buildHowItWorksCard(),
      ],
    );
  }

  Widget _buildHeroCard(_AiContext context) {
    final updatedLabel = _relativeTime(context.updatedAt);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD166),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(6, 6), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'NOTIFICATION AI MEMORY',
                      style: GoogleFonts.itim(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.psychology_alt_rounded, size: 26),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${context.sampleSize}',
            style: GoogleFonts.itim(
              fontSize: 56,
              height: 0.95,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            context.sampleSize == 1
                ? 'expense remembered'
                : 'expenses remembered',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'This snapshot is what the AI reads before guessing the category '
            'and usual price range of a new payment notification.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten_rounded, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OVERALL RANGE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_money(context.min)} – ${_money(context.max)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NeoButton(
            text: _isRefreshing ? 'REFRESHING' : 'REFRESH MEMORY',
            onPressed: _isRefreshing ? null : _refreshMemory,
            isLoading: _isRefreshing,
            width: double.infinity,
            height: 48,
            fontSize: 13,
            backgroundColor: Colors.white,
            shadowOffset: 4,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: Colors.black.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 5),
              Text(
                'Last synced $updatedLabel',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, [String? trailing]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.itim(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        if (trailing != null)
          Text(
            trailing.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
      ],
    );
  }

  Widget _buildHowItWorksCard() {
    final colors = Theme.of(context).colorScheme;
    const steps = [
      'The AI reads this snapshot before parsing a new payment notification.',
      'Each category keeps its own low–high range and most common item names.',
      'It never copies an old amount. The range only guides category and type.',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'How the AI uses this',
                  style: GoogleFonts.itim(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD166),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[index],
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: colors.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (index != steps.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD166),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(6, 6),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 3),
                ),
                child: const Icon(Icons.psychology_alt_rounded, size: 38),
              ),
              const SizedBox(height: 18),
              Text(
                'The AI has no memory yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.itim(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Build the reference from your expenses so the notification '
                'AI knows the usual price range of every category.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 20),
              NeoButton(
                text: 'BUILD AI MEMORY',
                onPressed: _isRefreshing ? null : _refreshMemory,
                isLoading: _isRefreshing,
                width: double.infinity,
                height: 48,
                fontSize: 13,
                backgroundColor: Colors.white,
                shadowOffset: 4,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Tip: refresh it after adding a batch of new expenses so the ranges '
          'stay close to your current spending.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colors.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    final colors = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 40),
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 46,
          color: colors.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 14),
        Text(
          'Could not load the AI memory',
          textAlign: TextAlign.center,
          style: GoogleFonts.itim(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _loadError ?? 'The server did not respond.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: NeoButton(
            text: 'TRY AGAIN',
            icon: Icons.refresh_rounded,
            onPressed: _load,
            height: 46,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _RangeMap extends StatelessWidget {
  const _RangeMap({required this.context});

  final _AiContext context;

  @override
  Widget build(BuildContext buildContext) {
    final span = math.max(context.max - context.min, 1);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(buildContext).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          for (final category in context.categories) ...[
            _MapRow(
              category: category,
              globalMin: context.min,
              globalSpan: span,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 92, right: 80),
            child: Row(
              children: [
                _AxisLabel(
                  text: _compactMoney(context.min),
                  alignment: Alignment.centerLeft,
                ),
                _AxisLabel(
                  text: _compactMoney(
                    context.min + ((context.max - context.min) / 2).round(),
                  ),
                  alignment: Alignment.center,
                ),
                _AxisLabel(
                  text: _compactMoney(context.max),
                  alignment: Alignment.centerRight,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF70D6FF),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
              ),
              const SizedBox(width: 5),
              const Text('range', style: TextStyle(fontSize: 10.5)),
              const SizedBox(width: 14),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
              ),
              const SizedBox(width: 5),
              const Text('average', style: TextStyle(fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapRow extends StatelessWidget {
  const _MapRow({
    required this.category,
    required this.globalMin,
    required this.globalSpan,
  });

  final _CategoryRange category;
  final int globalMin;
  final int globalSpan;

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(category.category);

    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _categoryLabel(category.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const markerSpace = 10.0;
              final usable = math.max(constraints.maxWidth - markerSpace, 1.0);
              double x(num value) =>
                  markerSpace / 2 +
                  ((value - globalMin) / globalSpan).clamp(0.0, 1.0) * usable;
              final left = x(category.min);
              final width = math.min(
                math.max(x(category.max) - left, 8.0),
                constraints.maxWidth,
              );
              final barLeft = math.min(left, constraints.maxWidth - width);
              final average = x(
                category.average,
              ).clamp(5.0, constraints.maxWidth - 5.0);

              return SizedBox(
                height: 26,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 12,
                      child: Container(
                        height: 1.5,
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                    Positioned(
                      left: barLeft,
                      top: 6,
                      child: Container(
                        width: width,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                      ),
                    ),
                    Positioned(
                      left: average - 5,
                      top: 8,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 78,
          child: Text(
            '${_compactMoney(category.min)}–${_compactMoney(category.max)}',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.color});

  final _CategoryRange category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Icon(
                  _categoryIcon(category.category),
                  size: 24,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _categoryLabel(category.category),
                      style: GoogleFonts.itim(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${category.count} '
                      '${category.count == 1 ? 'expense' : 'expenses'} '
                      'in memory',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: Row(
              children: [
                _StatBlock(label: 'LOWEST', value: _money(category.min)),
                _StatDivider(),
                _StatBlock(label: 'AVERAGE', value: _money(category.average)),
                _StatDivider(),
                _StatBlock(label: 'HIGHEST', value: _money(category.max)),
              ],
            ),
          ),
          if (category.commonItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'FAMILIAR ITEMS',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in category.commonItems)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (category.types.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final type in category.types) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: type == 'unexpected'
                          ? const Color(0xFFFFD6D6)
                          : const Color(0xFFD7F9EF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                    child: Text(
                      type,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel({required this.text, required this.alignment});

  final String text;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: Colors.black.withValues(alpha: 0.18),
    );
  }
}

class _AiContext {
  const _AiContext({
    required this.sampleSize,
    required this.min,
    required this.max,
    required this.categories,
    required this.updatedAt,
  });

  final int sampleSize;
  final int min;
  final int max;
  final List<_CategoryRange> categories;
  final DateTime? updatedAt;

  factory _AiContext.fromResponse(Map<String, dynamic> response) {
    final template = response['template'] is Map
        ? Map<String, dynamic>.from(response['template'] as Map)
        : const <String, dynamic>{};
    final rawCategories = template['categories'];
    final categories = <_CategoryRange>[];

    if (rawCategories is List) {
      for (final raw in rawCategories) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final range = map['priceRange'] is Map
            ? Map<String, dynamic>.from(map['priceRange'] as Map)
            : const <String, dynamic>{};
        final min = _asInt(range['min']);
        final max = _asInt(range['max']);
        if (min <= 0 || max < min) continue;
        categories.add(
          _CategoryRange(
            category: (map['category']?.toString() ?? 'lainnya')
                .trim()
                .toLowerCase(),
            count: _asInt(map['count']),
            min: min,
            max: max,
            average: _asInt(map['averagePrice'], fallback: min),
            commonItems: map['commonItems'] is List
                ? (map['commonItems'] as List)
                      .map((item) => item.toString())
                      .where((item) => item.isNotEmpty)
                      .toList()
                : const [],
            types: map['types'] is List
                ? (map['types'] as List)
                      .map((item) => item.toString())
                      .where((item) => item.isNotEmpty)
                      .toList()
                : const [],
          ),
        );
      }
    }

    final range = template['priceRange'] is Map
        ? Map<String, dynamic>.from(template['priceRange'] as Map)
        : const <String, dynamic>{};
    var min = _asInt(range['min']);
    var max = _asInt(range['max']);
    if (min <= 0 || max < min) {
      if (categories.isEmpty) {
        min = 0;
        max = 0;
      } else {
        min = categories.map((item) => item.min).reduce(math.min);
        max = categories.map((item) => item.max).reduce(math.max);
      }
    }

    return _AiContext(
      sampleSize: _asInt(
        template['sampleSize'],
        fallback: categories.fold(0, (sum, item) => sum + item.count),
      ),
      min: min,
      max: max,
      categories: categories,
      updatedAt: DateTime.tryParse(
        response['updatedAt']?.toString() ?? '',
      )?.toLocal(),
    );
  }
}

class _CategoryRange {
  const _CategoryRange({
    required this.category,
    required this.count,
    required this.min,
    required this.max,
    required this.average,
    required this.commonItems,
    required this.types,
  });

  final String category;
  final int count;
  final int min;
  final int max;
  final int average;
  final List<String> commonItems;
  final List<String> types;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

final NumberFormat _moneyFormat = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String _money(int value) => _moneyFormat.format(value);

String _compactMoney(int value) {
  final abs = value.abs();
  if (abs >= 1000000) {
    final millions = value / 1000000;
    final digits = millions == millions.roundToDouble() ? 0 : 1;
    return 'Rp ${millions.toStringAsFixed(digits).replaceAll('.', ',')} jt';
  }
  if (abs >= 1000) {
    final thousands = value / 1000;
    final digits = thousands == thousands.roundToDouble() ? 0 : 1;
    return 'Rp ${thousands.toStringAsFixed(digits).replaceAll('.', ',')} rb';
  }
  return 'Rp $value';
}

String _relativeTime(DateTime? time) {
  if (time == null) return 'never';
  final diff = DateTime.now().difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

String _categoryLabel(String category) {
  final trimmed = category.trim();
  if (trimmed.isEmpty) return 'Lainnya';
  if (trimmed == trimmed.toLowerCase()) {
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }
  return trimmed;
}

Color _categoryColor(String category) {
  switch (category) {
    case 'makanan':
      return const Color(0xFFFFD166);
    case 'school supply':
      return const Color(0xFFC77DFF);
    case 'baju':
      return const Color(0xFFFF99C8);
    case 'elektronik':
      return const Color(0xFF70D6FF);
    case 'transportasi':
      return const Color(0xFF06D6A0);
    case 'kesehatan':
      return const Color(0xFFFF70A6);
    case 'hiburan':
      return const Color(0xFFB5E48C);
    default:
      return const Color(0xFFE5E7EB);
  }
}

IconData _categoryIcon(String category) {
  switch (category) {
    case 'makanan':
      return Icons.fastfood_rounded;
    case 'school supply':
      return Icons.school_rounded;
    case 'baju':
      return Icons.checkroom_rounded;
    case 'elektronik':
      return Icons.devices_rounded;
    case 'transportasi':
      return Icons.directions_car_rounded;
    case 'kesehatan':
      return Icons.medical_services_rounded;
    case 'hiburan':
      return Icons.celebration_rounded;
    default:
      return Icons.category_rounded;
  }
}
