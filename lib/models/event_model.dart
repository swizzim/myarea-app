import 'package:timezone/timezone.dart' as tz;

class Event {
  final int id;
  final String title;
  final String description;
  final List<String> category;
  final double latitude;
  final double longitude;
  final String address;
  final String? coverPhoto;
  final String? coverPhotoCrop; // Add crop data field
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final double ticketPrice;
  final bool variable;
  final String website;
  final String timezone;
  final bool isDeleted;
  final String? status;
  
  // New location fields
  final String? venue;
  final String? street;
  final String? suburb;
  final String? city;
  final String? state;
  final String? postcode;
  final String? country;
  
  // New schedule data structure
  final Map<String, dynamic>? scheduleData;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.address,
    this.coverPhoto,
    this.coverPhotoCrop, // Add crop data parameter
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.ticketPrice,
    required this.variable,
    required this.website,
    required this.timezone,
    this.isDeleted = false,
    this.status,
    this.venue,
    this.street,
    this.suburb,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.scheduleData,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'cover_photo': coverPhoto,
      'cover_photo_crop': coverPhotoCrop, // Add crop data to map
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'ticket_price': ticketPrice,
      'variable_price': variable ? 1 : 0,
      'website': website,
      'timezone': timezone,
      'is_deleted': isDeleted ? 1 : 0,
      'status': status,
      'venue': venue,
      'street': street,
      'suburb': suburb,
      'city': city,
      'state': state,
      'postcode': postcode,
      'country': country,
      'schedule_data': scheduleData,
    };
  }

  static Event fromMap(Map<String, dynamic> map) {
    return Event(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      category: map['category'] is List ? List<String>.from(map['category']) : (map['category'] is String ? [map['category']] : []),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      address: map['address'],
      coverPhoto: map['cover_photo'],
      coverPhotoCrop: map['cover_photo_crop'], // Add crop data from map
      startDate: DateTime.parse(map['start_date']),
      endDate: DateTime.parse(map['end_date']),
      createdAt: DateTime.parse(map['created_at']),
      ticketPrice: (map['ticket_price'] as num).toDouble(),
      variable: map['variable_price'] == true || map['variable_price'] == 1,
      website: map['website'],
      timezone: map['timezone'] ?? 'Australia/Sydney',
      isDeleted: map['is_deleted'] == true || map['is_deleted'] == 1,
      status: map['status'],
      venue: map['venue'],
      street: map['street'],
      suburb: map['suburb'],
      city: map['city'],
      state: map['state'],
      postcode: map['postcode'],
      country: map['country'],
      scheduleData: map['schedule_data'],
    );
  }

  DateTime get dateTime => startDate;
  DateTime get endDateTime => endDate;

  /// Returns the last DateTime (in the event's timezone) the event occurs, considering scheduleData (single, recurring, exceptions).
  /// Fallback to endDate at 23:59 if no scheduleData.
  DateTime? getLastDateTimeWithSchedule() {
    final tzName = timezone.isNotEmpty ? timezone : 'UTC';
    final location = tz.getLocation(tzName);
    final schedule = scheduleData;



    // Helper to parse date+time in event timezone
    DateTime? parseLocal(String date, String time) {
      try {
        final dt = DateTime.parse('$date $time'.trim().replaceAll(' ', 'T'));
        return tz.TZDateTime(location, dt.year, dt.month, dt.day, dt.hour, dt.minute);
      } catch (_) {
        return null;
      }
    }

    // Fallback to endDate at 23:59
    DateTime? fallbackEnd() {
      try {
        final fallback = tz.TZDateTime(location, endDate.year, endDate.month, endDate.day, 23, 59);
        return fallback;
      } catch (_) {
        return null;
      }
    }

    if (schedule == null) {
      return fallbackEnd();
    }

    // Build set of closed dates from exceptions
    Set<String> closedDates = {};
    if (schedule['exceptions'] != null) {
      for (final ex in schedule['exceptions']) {
        if (ex['closed'] == true && ex['date'] != null) {
          closedDates.add(ex['date']);
        }
      }

    }

    // 1. Check for single occurrences
    if (schedule['single'] != null) {
      final singles = schedule['single'];
      List<Map<String, dynamic>> singlesList = [];
      if (singles is Map<String, dynamic>) {
        singlesList = [singles];
      } else if (singles is List) {
        singlesList = singles.cast<Map<String, dynamic>>();
      }
      

      
      // Get the latest datetime among singles (date + close time), excluding closed dates
      List<DateTime> singleEnds = [];
      for (final s in singlesList) {
        final date = s['date'] as String?;
        final close = s['close'] as String?;
        if (date != null && close != null) {
          // Skip if this date is closed by an exception
          if (closedDates.contains(date)) {
            continue;
          }
          
          final dt = parseLocal(date, close);
          if (dt != null) {
            singleEnds.add(dt);
          }
        }
      }
      
      if (singleEnds.isNotEmpty) {
        singleEnds.sort((a, b) => b.compareTo(a));
        final latest = singleEnds.first;
        return latest;
      }
    }

    // 2. Recurring: use endDate + latest close time for the last day, but check for exceptions that close the last day
    if (schedule['recurring'] != null && endDate != null) {
      final recurring = schedule['recurring'] as Map<String, dynamic>;

      
      // Find the latest close time among recurring rules
      List<String> closeTimes = [];
      for (final v in recurring.values) {
        if (v is Map && v['close'] != null) {
          closeTimes.add(v['close']);
        }
      }
      String closeTime = closeTimes.isNotEmpty ? closeTimes.reduce((a, b) => a.compareTo(b) > 0 ? a : b) : '23:59';
      
      // Try to find the last non-closed date within the event period
      DateTime dt = endDate;
      final startDate = this.startDate;
      
      // Check up to 30 days back from end date to find the last occurrence
      for (int i = 0; i < 30 && dt.isAfter(startDate.subtract(Duration(days: 1))); i++) {
        final dateStr = dt.toIso8601String().split('T').first;
        
        // Skip if this date is closed by an exception
        if (!closedDates.contains(dateStr)) {
          final recurEnd = parseLocal(dateStr, closeTime);
          if (recurEnd != null) {
            return recurEnd;
          }
        }
        
        dt = dt.subtract(Duration(days: 1));
      }
      
      // If we couldn't find any non-closed dates, fallback to endDate
      return fallbackEnd();
    }

    // Fallback
    return fallbackEnd();
  }

  /// Returns true if the event is currently active (has not ended), considering schedule data and exceptions.
  /// This is useful for determining if an event should be shown in current listings.
  bool get isCurrentlyActive {
    // Check if the event has any future occurrences instead of checking if the last occurrence has passed
    return hasFutureOccurrences();
  }

  /// Returns true if the event has any future occurrences, considering schedule data and exceptions.
  /// This is more lenient than checking if the last occurrence has passed.
  bool hasFutureOccurrences() {
    final schedule = scheduleData;
    if (schedule == null) {
      // No schedule data, check if event's end date is in the future
      final now = DateTime.now();
      final tzName = timezone.isNotEmpty ? timezone : 'UTC';
      final location = tz.getLocation(tzName);
      final nowInEventTz = tz.TZDateTime.now(location);
      
      return endDate.isAfter(nowInEventTz);
    }

    // Build set of closed dates from exceptions
    Set<String> closedDates = {};
    if (schedule['exceptions'] != null) {
      for (final ex in schedule['exceptions']) {
        if (ex['closed'] == true && ex['date'] != null) {
          closedDates.add(ex['date']);
        }
      }
    }

    final now = DateTime.now();
    final tzName = timezone.isNotEmpty ? timezone : 'UTC';
    final location = tz.getLocation(tzName);
    final nowInEventTz = tz.TZDateTime.now(location);
    final todayStr = nowInEventTz.toIso8601String().split('T').first;

    // Helper to check if a date/time is in the future
    bool isDateTimeInFuture(String dateStr, String? timeStr) {
      try {
        DateTime dateTime;
        if (timeStr != null) {
          // Parse date and time together
          final dateTimeStr = '${dateStr}T${timeStr}';
          dateTime = DateTime.parse(dateTimeStr);
        } else {
          // Parse date only, assume end of day
          dateTime = DateTime.parse('${dateStr}T23:59:59');
        }
        
        // Convert to event timezone for comparison
        final eventTz = tz.getLocation(tzName);
        final dateTimeInEventTz = tz.TZDateTime.from(dateTime, eventTz);
        
        return dateTimeInEventTz.isAfter(nowInEventTz);
      } catch (_) {
        return false;
      }
    }

    // 1. Check single occurrences
    if (schedule['single'] != null) {
      final singles = schedule['single'];
      List<Map<String, dynamic>> singlesList = [];
      if (singles is Map<String, dynamic>) {
        singlesList = [singles];
      } else if (singles is List) {
        singlesList = singles.cast<Map<String, dynamic>>();
      }

      for (final s in singlesList) {
        final date = s['date'] as String?;
        if (date != null) {
          // Skip if this date is closed by an exception
          if (closedDates.contains(date)) {
            continue;
          }
          
          // Check if this occurrence is in the future
          final closeTime = s['close'] as String?;
          if (isDateTimeInFuture(date, closeTime)) {
            return true;
          }
        }
      }
    }

    // 2. Check recurring occurrences
    if (schedule['recurring'] != null) {
      final recurring = schedule['recurring'] as Map<String, dynamic>;
      
      // Get the day names that have recurring rules
      final dayNames = recurring.keys.toList();
      if (dayNames.isEmpty) {
        return false;
      }

      // Check the next 30 days for future occurrences
      DateTime currentDate = nowInEventTz;
      for (int i = 0; i < 30; i++) {
        final dateStr = currentDate.toIso8601String().split('T').first;
        
        // Skip if this date is closed by an exception
        if (closedDates.contains(dateStr)) {
          currentDate = currentDate.add(Duration(days: 1));
          continue;
        }

        // Get the day name for this date
        final dayName = _getDayName(currentDate.weekday);
        
        // Check if this day has a recurring rule
        if (dayNames.contains(dayName)) {
          final dayRule = recurring[dayName] as Map<String, dynamic>?;
          if (dayRule != null) {
            final closeTime = dayRule['close'] as String?;
            if (isDateTimeInFuture(dateStr, closeTime)) {
              return true;
            }
          }
        }
        
        currentDate = currentDate.add(Duration(days: 1));
      }
    }

    return false;
  }

  /// Returns a set of dates that are closed due to exceptions.
  /// This can be useful for UI components that need to show closed dates.
  Set<String> get closedDates {
    final schedule = scheduleData;
    if (schedule == null || schedule['exceptions'] == null) {
      return {};
    }
    
    Set<String> closedDates = {};
    for (final ex in schedule['exceptions']) {
      if (ex['closed'] == true && ex['date'] != null) {
        closedDates.add(ex['date']);
      }
    }
    return closedDates;
  }

  /// Returns true if the event has scheduled occurrences within the specified date range.
  /// This considers schedule data (single and recurring) and excludes dates closed by exceptions.
  bool hasOccurrencesInDateRange(DateTime fromDate, DateTime toDate) {
    final schedule = scheduleData;
    if (schedule == null) {
      // No schedule data, check if event's overall range overlaps with the specified range
      return (startDate.isBefore(toDate) || startDate.isAtSameMomentAs(toDate)) &&
             (endDate.isAfter(fromDate) || endDate.isAtSameMomentAs(fromDate));
    }

    // Build set of closed dates from exceptions
    Set<String> closedDates = {};
    if (schedule['exceptions'] != null) {
      for (final ex in schedule['exceptions']) {
        if (ex['closed'] == true && ex['date'] != null) {
          closedDates.add(ex['date']);
        }
      }
    }

    // Helper to check if a date is within the range
    bool isDateInRange(String dateStr) {
      try {
        final date = DateTime.parse(dateStr);
        return date.isAfter(fromDate.subtract(Duration(days: 1))) &&
               date.isBefore(toDate.add(Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }

    // 1. Check single occurrences
    if (schedule['single'] != null) {
      final singles = schedule['single'];
      List<Map<String, dynamic>> singlesList = [];
      if (singles is Map<String, dynamic>) {
        singlesList = [singles];
      } else if (singles is List) {
        singlesList = singles.cast<Map<String, dynamic>>();
      }

      for (final s in singlesList) {
        final date = s['date'] as String?;
        if (date != null) {
          // Skip if this date is closed by an exception
          if (closedDates.contains(date)) {
            continue;
          }
          
          // Check if this date is within the specified range
          if (isDateInRange(date)) {
            return true;
          }
        }
      }
    }

    // 2. Check recurring occurrences
    if (schedule['recurring'] != null) {
      final recurring = schedule['recurring'] as Map<String, dynamic>;
      
      // Get the day names that have recurring rules
      final dayNames = recurring.keys.toList();
      if (dayNames.isEmpty) {
        return false;
      }

      // Check each day in the specified range
      DateTime currentDate = fromDate;
      while (currentDate.isBefore(toDate.add(Duration(days: 1)))) {
        final dateStr = currentDate.toIso8601String().split('T').first;
        
        // Skip if this date is closed by an exception
        if (closedDates.contains(dateStr)) {
          currentDate = currentDate.add(Duration(days: 1));
          continue;
        }

        // Get the day name for this date
        final dayName = _getDayName(currentDate.weekday);
        
        // Check if this day has a recurring rule
        if (dayNames.contains(dayName)) {
          return true;
        }
        
        currentDate = currentDate.add(Duration(days: 1));
      }
    }

    return false;
  }

  /// Helper method to convert weekday number to day name
  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
        return 'sunday';
      default:
        return '';
    }
  }
} 