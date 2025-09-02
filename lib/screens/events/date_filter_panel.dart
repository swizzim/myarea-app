import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:myarea_app/styles/app_colours.dart';

class DateFilterPanel extends StatefulWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  
  const DateFilterPanel({
    super.key,
    this.fromDate, 
    this.toDate
  });
  
  @override
  State<DateFilterPanel> createState() => _DateFilterPanelState();
}

class _DateFilterPanelState extends State<DateFilterPanel> {
  DateTime? _from;
  DateTime? _to;
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _from = widget.fromDate;
    _to = widget.toDate;
    _focusedDay = DateTime.now();
    _selectedDay = _from ?? DateTime.now();
  }

  void _clearSelection() {
    setState(() {
      _from = null;
      _to = null;
      _selectedDay = DateTime.now();
    });
    Navigator.pop(context, {'from': null, 'to': null});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColours.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Filter by Date Range', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Selected date range display
            if (_from != null || _to != null) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColours.buttonPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, 
                      size: 16, 
                      color: AppColours.buttonPrimary
                    ),
                    SizedBox(width: 8),
                    Text(
                      _from != null && _to != null
                          ? '${DateFormat('MMM d').format(_from!)} - ${DateFormat('MMM d, yyyy').format(_to!)}'
                          : _from != null
                              ? 'From ${DateFormat('MMM d, yyyy').format(_from!)}'
                              : 'Select dates',
                      style: TextStyle(
                        color: AppColours.buttonPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Calendar
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppColours.buttonPrimary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
                ),
                child: TableCalendar(
                  firstDay: DateTime.now(),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_from, day) || isSameDay(_to, day),
                  rangeStartDay: _from,
                  rangeEndDay: _to,
                  calendarFormat: CalendarFormat.month,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Month',
                  },
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
                    weekendTextStyle: TextStyle(color: Colors.black87),
                    holidayTextStyle: TextStyle(color: Colors.black87),
                    selectedDecoration: BoxDecoration(
                      color: AppColours.buttonPrimary,
                      shape: BoxShape.circle,
                    ),
                    rangeStartDecoration: BoxDecoration(
                      color: AppColours.buttonPrimary,
                      shape: BoxShape.circle,
                    ),
                    rangeEndDecoration: BoxDecoration(
                      color: AppColours.buttonPrimary,
                      shape: BoxShape.circle,
                    ),
                    withinRangeDecoration: BoxDecoration(
                      color: AppColours.buttonPrimary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: AppColours.buttonPrimary.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    leftChevronIcon: Icon(
                      Icons.chevron_left,
                      color: AppColours.buttonPrimary,
                    ),
                    rightChevronIcon: Icon(
                      Icons.chevron_right,
                      color: AppColours.buttonPrimary,
                    ),
                    titleTextStyle: TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                      if (_from == null) {
                        _from = selectedDay;
                      } else if (_to == null && selectedDay.isAfter(_from!)) {
                        _to = selectedDay;
                      } else {
                        _from = selectedDay;
                        _to = null;
                      }
                    });
                  },
                  onRangeSelected: (start, end, focusedDay) {
                    if (start != null && end != null) {
                      setState(() {
                        _from = start;
                        _to = end;
                        _focusedDay = focusedDay;
                      });
                    }
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedDay = focusedDay;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Bottom buttons
            Theme(
              data: Theme.of(context).copyWith(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearSelection,
                      child: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        splashFactory: NoSplash.splashFactory,
                        side: BorderSide(color: AppColours.buttonPrimary),
                        foregroundColor: AppColours.buttonPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, {'from': _from, 'to': _to}),
                      child: const Text('Apply'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        backgroundColor: AppColours.buttonPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        splashFactory: NoSplash.splashFactory,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
