import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:myarea_app/styles/app_colours.dart';

class LocationFilterPanel extends StatefulWidget {
  final double? distanceKm;
  final double? searchCenterLat;
  final double? searchCenterLng;
  
  const LocationFilterPanel({
    super.key,
    this.distanceKm, 
    this.searchCenterLat, 
    this.searchCenterLng
  });
  
  @override
  State<LocationFilterPanel> createState() => _LocationFilterPanelState();
}

class _LocationFilterPanelState extends State<LocationFilterPanel> {
  double? _distance;
  LatLng? _userLatLng;
  LatLng? _searchCenter;
  late MapController _mapController;
  double _currentZoom = 12.0;
  
  // Continuous exponential scaling from 1km to 100km
  static const double _minDistance = 1.0;
  static const double _maxDistance = 100.0;

  @override
  void initState() {
    super.initState();
    _distance = widget.distanceKm ?? 10;
    _mapController = MapController();
    
    _handleLocationPermission();
    // Default to Sydney coordinates
    _userLatLng = LatLng(-33.8688, 151.2093);
    
    // Initialize search center - use provided search center or user location
    if (widget.searchCenterLat != null && widget.searchCenterLng != null) {
      _searchCenter = LatLng(widget.searchCenterLat!, widget.searchCenterLng!);
    } else {
      _searchCenter = _userLatLng;
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animateZoomForDistance(_distance ?? 10);
    });
  }

  Future<void> _handleLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        if (mounted) {
          setState(() {
            _userLatLng = LatLng(position.latitude, position.longitude);
            // If no search center is set, use user location as default
            if (_searchCenter == null) {
              _searchCenter = _userLatLng;
            }
          });
        }
      } catch (e) {
        // If getting location fails, keep default Sydney coordinates
        print('Failed to get user location: $e');
      }
    } else if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Location Permission Required'),
            content: const Text('To use your location, please enable location permissions in your device settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Geolocator.openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _distance = null;
    });
    Navigator.pop(context, {'clear': true});
  }

  void _recenterToUserLocation() {
    if (_userLatLng != null) {
      setState(() {
        _searchCenter = _userLatLng;
      });
      _mapController.move(_userLatLng!, _currentZoom);
    } else {
      // If no user location, try to get it
      _handleLocationPermission();
    }
  }

  double _sliderValueToDistance(double sliderValue) {
    // Exponential function: distance = minDistance * (maxDistance/minDistance)^sliderValue
    return _minDistance * math.pow(_maxDistance / _minDistance, sliderValue);
  }

  double _distanceToSliderValue(double distance) {
    // Inverse of the exponential function
    if (distance <= _minDistance) return 0.0;
    if (distance >= _maxDistance) return 1.0;
    return math.log(distance / _minDistance) / math.log(_maxDistance / _minDistance);
  }

  double _calculateZoom(double distanceKm, double mapSizePx) {
    final circleDiameterPx = mapSizePx * 0.8;
    final distanceMeters = distanceKm * 1000;
    const earthCircumference = 40075016.686; // meters
    const tileSizePx = 256.0;
    final zoom = (math.log(circleDiameterPx / tileSizePx) / math.log(2)) +
        (math.log(earthCircumference / (distanceMeters * 2)) / math.log(2));
    return zoom.clamp(2.0, 16.0);
  }

  // Add: Inverse of _calculateZoom to get distance from zoom
  double _zoomToDistance(double zoom, double mapSizePx) {
    final circleDiameterPx = mapSizePx * 0.8;
    const earthCircumference = 40075016.686; // meters
    const tileSizePx = 256.0;
    // Rearranged from _calculateZoom
    final meters = earthCircumference / (2 * math.pow(2, zoom - (math.log(circleDiameterPx / tileSizePx) / math.log(2))));
    return (meters / 1000).clamp(_minDistance, _maxDistance);
  }

  void _animateZoomForDistance(double distanceKm) {
    final mapSize = MediaQuery.of(context).size.width - 32;
    final newZoom = _calculateZoom(distanceKm, mapSize);
    if (_searchCenter != null) {
      _mapController.move(_searchCenter!, newZoom);
    }
    setState(() {
      _currentZoom = newZoom;
    });
  }

  Widget _buildLocationMap() {
    final distanceKm = _distance ?? 10;
    final mapSize = MediaQuery.of(context).size.width - 32;
    final circleRadiusPx = (mapSize * 0.4).toDouble();
    return Container(
      width: mapSize,
      height: mapSize,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _searchCenter,
                zoom: _currentZoom,
                interactiveFlags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                // Restrict map to Sydney bounds
                maxBounds: LatLngBounds(
                  LatLng(-34.118, 150.520), // Southwest corner of Sydney
                  LatLng(-33.578, 151.343), // Northeast corner of Sydney
                ),
                onMapEvent: (MapEvent event) {
                  if (event is MapEventMove || event is MapEventMoveEnd) {
                    final mapSize = MediaQuery.of(context).size.width - 32;
                    final newDistance = _zoomToDistance(event.zoom, mapSize);
                    setState(() {
                      _searchCenter = event.center;
                      _currentZoom = event.zoom;
                      _distance = newDistance;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: MediaQuery.of(context).devicePixelRatio > 1.5
                      ? 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png'
                      : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.myarea_app',
                  maxZoom: 19,
                ),
                // User location marker
                if (_userLatLng != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _userLatLng!,
                        width: 20,
                        height: 20,
                        builder: (context) => Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // Fixed circle overlay
            IgnorePointer(
              child: Center(
                child: Container(
                  width: circleRadiusPx * 2,
                  height: circleRadiusPx * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColours.buttonPrimary.withOpacity(0.15),
                    border: Border.all(
                      color: AppColours.buttonPrimary.withOpacity(0.4),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            // Search center pin overlay
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColours.buttonPrimary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColours.buttonPrimary.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
            // User location button
            if (_userLatLng != null)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _recenterToUserLocation,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.my_location,
                      size: 20,
                      color: AppColours.buttonPrimary,
                    ),
                  ),
                ),
              ),
            // OSM Attribution icon
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) {
                      return SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: double.infinity,
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () async {
                                  Navigator.pop(context);
                                  final url = Uri.parse('https://www.openstreetmap.org/copyright');
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(url, mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                                  child: Text('© OpenStreetMap'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColours.buttonPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSliderValue = _distance != null ? _distanceToSliderValue(_distance!) : 0.5;
    final displayDistance = _distance ?? _sliderValueToDistance(0.5);
    
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
            const Text(
              'Filter by Location',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            // Add explanatory copy for Sydney limitation
            const Text(
              'For our initial launch, event search is limited to the Sydney area.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 16),
            // Location map
            _buildLocationMap(),
            const SizedBox(height: 16),
            // Custom distance slider
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Search Radius',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _distance == null ? 'Any' : '${displayDistance.toStringAsFixed(0)} km',
                      style: TextStyle(
                        color: AppColours.buttonPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: MediaQuery.of(context).size.width - 32,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColours.buttonPrimary,
                      inactiveTrackColor: AppColours.buttonPrimary.withOpacity(0.2),
                      thumbColor: AppColours.buttonPrimary,
                      overlayColor: AppColours.buttonPrimary.withOpacity(0.1),
                      valueIndicatorColor: AppColours.buttonPrimary,
                      valueIndicatorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      trackHeight: 4,
                      trackShape: RectangularSliderTrackShape(),
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
                    ),
                    child: Slider(
                      value: currentSliderValue,
                      min: 0.0,
                      max: 1.0,
                      divisions: null, // Remove divisions for completely smooth sliding
                      label: _distance == null ? 'Any' : '${displayDistance.toStringAsFixed(0)} km',
                      onChanged: (val) {
                        final newDistance = _sliderValueToDistance(val);
                        _animateZoomForDistance(newDistance);
                        setState(() => _distance = newDistance);
                      },
                    ),
                  ),
                ),
              ],
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
                      onPressed: () => Navigator.pop(context, {'distance': _distance, 'searchCenterLat': _searchCenter?.latitude, 'searchCenterLng': _searchCenter?.longitude}),
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
