import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class NeoBrutalistCalendar extends StatefulWidget {
  final DateTimeRange? initialRange;
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final Function(DateTimeRange?) onRangeSelected;
  final Function(DateTime?)? onDateSelected;
  final bool singleDateMode;

  const NeoBrutalistCalendar({
    super.key,
    this.initialRange,
    this.initialDate,
    this.firstDate,
    this.lastDate,
    required this.onRangeSelected,
    this.onDateSelected,
    this.singleDateMode = false,
  });

  @override
  State<NeoBrutalistCalendar> createState() => _NeoBrutalistCalendarState();
}

class _NeoBrutalistCalendarState extends State<NeoBrutalistCalendar> {
  late DateTime _focusedMonth;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  DateTime? _hoverDate;
  DateTime? _selectedDate;

  DateTime get _firstDate => widget.firstDate ?? DateTime(2020);
  DateTime get _lastDate => widget.lastDate ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime.now();
    if (widget.singleDateMode) {
      _selectedDate = widget.initialDate;
    } else {
      if (widget.initialRange != null) {
        _rangeStart = widget.initialRange!.start;
        _rangeEnd = widget.initialRange!.end;
      }
    }
  }

  bool _isInRange(DateTime date) {
    if (_rangeStart == null || _rangeEnd == null) return false;
    return !date.isBefore(_rangeStart!) && !date.isAfter(_rangeEnd!);
  }

  bool _isRangeStart(DateTime date) {
    if (_rangeStart == null) return false;
    return _isSameDay(date, _rangeStart!);
  }

  bool _isRangeEnd(DateTime date) {
    if (_rangeEnd == null) return false;
    return _isSameDay(date, _rangeEnd!);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isDisabled(DateTime date) {
    return date.isBefore(_firstDate) || date.isAfter(_lastDate);
  }

  bool _isSingleDateSelected(DateTime date) {
    if (_selectedDate == null) return false;
    return _isSameDay(date, _selectedDate!);
  }

  void _onDayTapped(DateTime day) {
    if (_isDisabled(day)) return;

    setState(() {
      if (widget.singleDateMode) {
        _selectedDate = day;
        widget.onDateSelected?.call(day);
        widget.onRangeSelected(DateTimeRange(start: day, end: day));
      } else {
        if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
          _rangeStart = day;
          _rangeEnd = null;
        } else if (_rangeStart != null && _rangeEnd == null) {
          if (day.isBefore(_rangeStart!)) {
            _rangeEnd = _rangeStart;
            _rangeStart = day;
          } else {
            _rangeEnd = day;
          }
          widget.onRangeSelected(DateTimeRange(start: _rangeStart!, end: _rangeEnd!));
        }
      }
    });
  }

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  void _clearSelection() {
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
      _selectedDate = null;
    });
    widget.onRangeSelected(null);
    widget.onDateSelected?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF22262B) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with month navigation
          _buildHeader(isDark),
          const SizedBox(height: 12),
          // Day names
          _buildDayNames(isDark),
          const SizedBox(height: 8),
          // Calendar grid
          _buildCalendarGrid(isDark),
          const SizedBox(height: 12),
          // Selection info & clear button
          _buildFooter(isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final monthYear = DateFormat('MMMM yyyy', 'id_ID').format(_focusedMonth);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildNavButton(Icons.chevron_left_rounded, _previousMonth, isDark),
        Expanded(
          child: Text(
            monthYear.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.itim(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        _buildNavButton(Icons.chevron_right_rounded, _nextMonth, isDark),
      ],
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF5DF9FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Icon(icon, color: Colors.black, size: 24),
      ),
    );
  }

  Widget _buildDayNames(bool isDark) {
    final days = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: days.map((day) {
        return SizedBox(
          width: 40,
          child: Text(
            day,
            textAlign: TextAlign.center,
            style: GoogleFonts.itim(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFF5DF9FF) : Colors.black54,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid(bool isDark) {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7;

    final days = <Widget>[];

    // Empty cells before first day
    for (int i = 0; i < firstWeekday; i++) {
      days.add(const SizedBox(width: 40, height: 40));
    }

    // Day cells
    for (int day = 1; day <= lastDayOfMonth.day; day++) {
      final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
      days.add(_buildDayCell(date, isDark));
    }

    // Build rows
    final rows = <Widget>[];
    for (int i = 0; i < days.length; i += 7) {
      final rowDays = days.sublist(i, (i + 7 > days.length) ? days.length : i + 7);
      // Pad the last row if needed
      while (rowDays.length < 7) {
        rowDays.add(const SizedBox(width: 40, height: 40));
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: rowDays,
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildDayCell(DateTime date, bool isDark) {
    final isSingleSelected = widget.singleDateMode && _isSingleDateSelected(date);
    final isSelected = isSingleSelected || _isRangeStart(date) || _isRangeEnd(date);
    final isInRange = !widget.singleDateMode && _isInRange(date);
    final isDisabled = _isDisabled(date);
    final isToday = _isSameDay(date, DateTime.now());
    final isHover = _hoverDate != null && _isSameDay(date, _hoverDate!);

    Color bgColor;
    Color textColor;
    Color borderColor;
    double borderWidth = 2;

    if (isDisabled) {
      bgColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFF5F5F5);
      textColor = Colors.grey;
      borderColor = Colors.transparent;
    } else if (isSelected) {
      bgColor = const Color(0xFF5DF9FF);
      textColor = Colors.black;
      borderColor = Colors.black;
      borderWidth = 2.5;
    } else if (isInRange) {
      bgColor = const Color(0xFF5DF9FF).withValues(alpha: 0.4);
      textColor = isDark ? Colors.white : Colors.black;
      borderColor = Colors.transparent;
    } else if (isHover) {
      bgColor = isDark ? const Color(0xFF3A3F47) : const Color(0xFFE8E8E8);
      textColor = isDark ? Colors.white : Colors.black;
      borderColor = Colors.black;
    } else {
      bgColor = isDark ? const Color(0xFF1E2830) : Colors.white;
      textColor = isDark ? Colors.white : Colors.black;
      borderColor = Colors.transparent;
    }

    if (isToday && !isSelected) {
      borderColor = const Color(0xFFF9EB5D);
      borderWidth = 3;
    }

    return GestureDetector(
      onTap: () => _onDayTapped(date),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoverDate = date),
        onExit: (_) => setState(() => _hoverDate = null),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
            boxShadow: isSelected
                ? const [
                    BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '${date.day}',
              style: GoogleFonts.itim(
                fontSize: 14,
                fontWeight: isSelected || isInRange ? FontWeight.bold : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    final hasSelection = widget.singleDateMode ? _selectedDate != null : _rangeStart != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasSelection
                    ? (widget.singleDateMode ? 'Selected:' : 'Selected:')
                    : (widget.singleDateMode ? 'Tap to select date' : 'Tap to select start date'),
                style: GoogleFonts.itim(
                  fontSize: 12,
                  color: isDark ? Colors.grey : Colors.grey[600],
                ),
              ),
              if (_selectedDate != null && widget.singleDateMode) ...[
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate!),
                  style: GoogleFonts.itim(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF5DF9FF) : Colors.black,
                  ),
                ),
              ],
              if (_rangeStart != null && !widget.singleDateMode) ...[
                const SizedBox(height: 4),
                Text(
                  _rangeEnd != null
                      ? '${DateFormat('dd MMM', 'id_ID').format(_rangeStart!)} - ${DateFormat('dd MMM yyyy', 'id_ID').format(_rangeEnd!)}'
                      : '${DateFormat('dd MMM yyyy', 'id_ID').format(_rangeStart!)} - ?',
                  style: GoogleFonts.itim(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF5DF9FF) : Colors.black,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasSelection)
          GestureDetector(
            onTap: _clearSelection,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5D5D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.clear_rounded, size: 16, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    'Clear',
                    style: GoogleFonts.itim(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
