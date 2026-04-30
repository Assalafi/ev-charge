import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchLocations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocations([String? query]) async {
    setState(() => _loading = true);
    try {
      final path = query != null && query.isNotEmpty
          ? '/locations?search=$query'
          : '/locations';
      final response = await ApiService.get(path);
      if (response['success'] == true) {
        setState(() {
          _locations = (response['locations'] as List)
              .cast<Map<String, dynamic>>();
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
    final minimumCharge = loc['minimumCharge'] ?? 150;
    final pricePerKwh = pricePerWh * 1000;
    final latitude = loc['latitude'];
    final longitude = loc['longitude'];
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
              color: hasReady ? AppColors.primary : AppColors.offline,
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
                    const SizedBox(width: 12),
                    Text(
                      'min ₦${minimumCharge.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasCoords)
            IconButton(
              icon: const Icon(Icons.near_me_rounded),
              color: AppColors.primary,
              onPressed: () => _openGoogleMaps(latitude, longitude, location),
              tooltip: 'Navigate',
            ),
        ],
      ),
    );
  }

  Future<void> _openGoogleMaps(double lat, double lng, String name) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$name';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
