import 'package:flutter/material.dart';
// import 'package:myarea_app/screens/settings/merge_drops_demo_screen.dart'; // Removed merge drops demo
// import 'package:myarea_app/screens/map/mapbox_map_screen.dart'; // Removed mapbox map screen

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Merge Drops Demo card removed
          // Mapbox Map card removed
        ],
      ),
    );
  }
} 