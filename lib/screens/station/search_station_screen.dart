import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';

class SearchStationScreen extends StatefulWidget {
  const SearchStationScreen({super.key});

  @override
  State<SearchStationScreen> createState() => _SearchStationScreenState();
}

class _SearchStationScreenState extends State<SearchStationScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _locations = [];
  bool _loading = true;
  Timer? _debounce;
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    _initLocationThenFetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initLocationThenFetch() async {
    await _getUserLocation();
    await _fetchLocations();
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() => _userPosition = position);
      }
    } catch (_) {}
  }

  /// Haversine formula — returns distance in km
  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double deg) => deg * (pi / 180);

  String _formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} m';
    } else if (km < 10) {
      return '${km.toStringAsFixed(1)} km';
    } else {
      return '${km.round()} km';
    }
  }

  double? _distanceForLocation(Map<String, dynamic> loc) {
    if (_userPosition == null) return null;
    final lat = loc['latitude'] is num ? (loc['latitude'] as num).toDouble() : null;
    final lng = loc['longitude'] is num ? (loc['longitude'] as num).toDouble() : null;
    if (lat == null || lng == null) return null;
    return _calculateDistanceKm(
      _userPosition!.latitude, _userPosition!.longitude, lat, lng,
    );
  }

  Future<void> _fetchLocations([String? query]) async {
    setState(() => _loading = true);
    try {
      final path = query != null && query.isNotEmpty
          ? '/locations?search=$query'
          : '/locations';
      final response = await ApiService.get(path);
      if (response['success'] == true) {
        final locations = (response['locations'] as List)
            .cast<Map<String, dynamic>>();

        // Sort by distance if user location is available
        if (_userPosition != null) {
          locations.sort((a, b) {
            final distA = _distanceForLocation(a);
            final distB = _distanceForLocation(b);
            if (distA == null && distB == null) return 0;
            if (distA == null) return 1;
            if (distB == null) return -1;
            return distA.compareTo(distB);
          });
        }

        setState(() {
          _locations = locations;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load locations'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchLocations(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Locations')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search by city, state, or address...',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _fetchLocations();
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : _locations.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: () =>
                            _fetchLocations(_searchController.text),
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _locations.length,
                          itemBuilder: (context, index) =>
                              _buildLocationCard(_locations[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty
                ? 'No locations match your search'
                : 'No station locations available',
            style: GoogleFonts.inter(
                color: AppColors.textSecondary, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (_searchController.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                _searchController.clear();
                _fetchLocations();
              },
              child: const Text('Clear search'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> loc) {
    final location = loc['location'] ?? '';
    final address = loc['address'] ?? '';
    final total = loc['totalStations'] ?? 0;
    final ready = loc['readyStations'] ?? 0;
    final hasReady = ready > 0;
    final pricePerWh = loc['pricePerWh'] ?? 0.17;
    final pricePerKwh = pricePerWh * 1000;
    final latitude = loc['latitude'] is num ? (loc['latitude'] as num).toDouble() : null;
    final longitude = loc['longitude'] is num ? (loc['longitude'] as num).toDouble() : null;
    final hasCoords = latitude != null && longitude != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: hasReady
                  ? AppColors.primaryLight
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: hasReady ? AppColors.accent : AppColors.offline,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.text,
                  ),
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    address,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.ev_station_rounded,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$total station${total != 1 ? 's' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            hasReady ? AppColors.success : AppColors.offline,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasReady ? '$ready ready' : 'None ready',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color:
                            hasReady ? AppColors.success : AppColors.offline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.payments_outlined,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '₦${pricePerKwh.toStringAsFixed(0)}/kWh',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    if (_distanceForLocation(loc) != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.near_me_rounded,
                          size: 13, color: AppColors.accent),
                      const SizedBox(width: 3),
                      Text(
                        _formatDistance(_distanceForLocation(loc)!),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (hasCoords)
            GestureDetector(
              onTap: () => _openGoogleMaps(latitude, longitude, location),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_rounded,
                        size: 22, color: AppColors.accent),
                    const SizedBox(height: 4),
                    Text(
                      'Go',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openGoogleMaps(double lat, double lng, String name) async {
    final googleMapsUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
