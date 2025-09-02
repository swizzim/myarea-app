import 'package:flutter/material.dart';
import 'package:myarea_app/styles/app_colours.dart';

class CategoryFilterPanel extends StatefulWidget {
  final List<String> categories;
  final List<String> selectedCategories;
  
  const CategoryFilterPanel({
    super.key,
    required this.categories, 
    required this.selectedCategories
  });
  
  @override
  State<CategoryFilterPanel> createState() => _CategoryFilterPanelState();
}

class _CategoryFilterPanelState extends State<CategoryFilterPanel> {
  late Set<String> _tempSelected;
  
  @override
  void initState() {
    super.initState();
    _tempSelected = Set<String>.from(widget.selectedCategories);
  }

  void _clearSelection() {
    setState(() {
      _tempSelected.clear();
    });
    Navigator.pop(context, <String>[]);
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
            const Text('Filter by Categories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.categories.map((cat) {
                final bool selected = _tempSelected.contains(cat);
                IconData? icon;
                Color? iconColor;
                switch (cat.toLowerCase()) {
                  case 'music':
                    icon = Icons.music_note;
                    iconColor = const Color(0xFF9C27B0); // Purple
                    break;
                  case 'nightlife':
                    icon = Icons.nightlife;
                    iconColor = const Color(0xFF673AB7); // Deep purple
                    break;
                  case 'exhibitions':
                    icon = Icons.palette;
                    iconColor = const Color(0xFFE91E63); // Pink
                    break;
                  case 'theatre, dance & film':
                    icon = Icons.theater_comedy;
                    iconColor = const Color(0xFFFF5722); // Deep orange
                    break;
                  case 'tours':
                    icon = Icons.directions_walk;
                    iconColor = const Color(0xFF4CAF50); // Green
                    break;
                  case 'markets':
                    icon = Icons.shopping_basket;
                    iconColor = const Color(0xFF795548); // Brown
                    break;
                  case 'food & drink':
                    icon = Icons.restaurant;
                    iconColor = const Color(0xFFFF9800); // Orange
                    break;
                  case 'dating':
                    icon = Icons.favorite;
                    iconColor = const Color(0xFFE91E63); // Pink
                    break;
                  case 'comedy':
                    icon = Icons.emoji_emotions;
                    iconColor = const Color(0xFFFFC107); // Amber
                    break;
                  case 'talks, courses & workshops':
                    icon = Icons.record_voice_over;
                    iconColor = const Color(0xFF2196F3); // Blue
                    break;
                  case 'health & fitness':
                    icon = Icons.fitness_center;
                    iconColor = const Color(0xFF4CAF50); // Green
                    break;
                  default:
                    icon = null;
                    iconColor = null;
                }
                return Material(
                  elevation: 0.7,
                  shadowColor: Colors.black12,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _tempSelected.remove(cat);
                        } else {
                          _tempSelected.add(cat);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      margin: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: selected
                            ? (iconColor ?? AppColours.filterSelected).withOpacity(0.15)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? (iconColor ?? AppColours.filterSelected).withOpacity(0.25)
                              : Colors.grey[300]!,
                          width: 1.1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 16, color: iconColor ?? Colors.grey[600]),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: selected
                                  ? AppColours.buttonPrimary
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            selected ? Icons.check : Icons.add,
                            size: 16,
                            color: selected
                                ? AppColours.buttonPrimary
                                : Colors.grey[500],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
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
                      onPressed: () => Navigator.pop(context, _tempSelected.toList()),
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
