import 'package:flutter/material.dart';

/// App Colours - Centralised colour definitions for MyArea app
/// 
/// This file contains all the colour constants used throughout the app.
/// Colours are organised by purpose and include both light and dark theme variants.
class AppColours {
  // Private constructor to prevent instantiation
  AppColours._();

  // Background Colours
  static const Color background = Color(0xFFFFF9F2);
  
  // Event Card Colours
  static const Color eventCard = Color(0xFFFFFFFF);
  
  // Heart/Favorite Colours
  static const Color heart = Color(0xFFE0383B);
  
  // Title Accent Colours
  static const Color titleAccent = Color(0xFF55875f);
  
  // Button Colours
  static const Color buttonPrimary = Color(0xFF1B6BB3);
  
  // Filter Pill Icon Colours
  static const Color filterFree = Color(0xFFFFB800); // Nice yellow for free events
  static const Color filterCategory = Color(0xFF795548); // Brown for categories
  static const Color filterSelected = Color(0xFFFF9800); // Orange for selected filter pills
  
  // Event Card Icon Colours
  static const Color eventCalendar = Color(0xFF55875f); // titleAccent for calendar
  static const Color eventLocation = Color(0xFF1B6BB3); // buttonPrimary for location
  static const Color eventTicket = Color(0xFFFF7043); // Nice orange for tickets
  
  // TODO: Add more colour constants here as needed
  
}
