import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' as latlong;

import '../../../core/design/tokens.dart';
import '../../../core/utils/device_location.dart';

/// Full-screen map: tap to pin, or enter an address so the pin moves there.
class OutletLocationPinPicker extends StatefulWidget {
  const OutletLocationPinPicker({super.key, this.initial});

  final latlong.LatLng? initial;

  static Future<latlong.LatLng?> open(BuildContext context, {latlong.LatLng? initial}) {
    return Navigator.of(context).push<latlong.LatLng>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OutletLocationPinPicker(initial: initial),
      ),
    );
  }

  @override
  State<OutletLocationPinPicker> createState() => _OutletLocationPinPickerState();
}

class _OutletLocationPinPickerState extends State<OutletLocationPinPicker> {
  final MapController _mapController = MapController();
  final TextEditingController _addressController = TextEditingController();
  latlong.LatLng? _pin;
  latlong.LatLng _center = const latlong.LatLng(17.3850, 78.4867);
  bool _loadingGps = true;
  bool _searchingAddress = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.initial != null) {
      setState(() {
        _pin = widget.initial;
        _center = widget.initial!;
        _loadingGps = false;
      });
      return;
    }

    final pos = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 6));
    if (!mounted) return;
    if (pos != null) {
      final point = latlong.LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = point;
        _pin = point;
        _loadingGps = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(point, 16);
      });
      return;
    }

    setState(() => _loadingGps = false);
  }

  Future<void> _useMyLocation() async {
    final pos = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 8));
    if (!mounted) return;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read GPS. Enter an address or tap the map.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final point = latlong.LatLng(pos.latitude, pos.longitude);
    setState(() {
      _pin = point;
      _center = point;
    });
    _mapController.move(point, 17);
  }

  Future<void> _searchAndPinAddress() async {
    final query = _addressController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an area, landmark, or full address.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _searchingAddress = true);
    try {
      final locations = await locationFromAddress(query);
      if (!mounted) return;
      if (locations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No match for that address. Try a clearer place name or area.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final loc = locations.first;
      final point = latlong.LatLng(loc.latitude, loc.longitude);
      setState(() {
        _pin = point;
        _center = point;
      });
      _mapController.move(point, 16);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pin moved to ${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find that location. Check spelling or tap the map instead.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin outlet location'),
        actions: [
          TextButton(
            onPressed: _pin == null ? null : () => Navigator.pop(context, _pin),
            child: const Text('USE PIN', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: BestieTokens.cBrandSoft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter an address to move the pin, tap the map, or use My location.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addressController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchAndPinAddress(),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Enter location / address',
                            hintText: 'e.g. Kukatpally, Hyderabad',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.search, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _searchingAddress ? null : _searchAndPinAddress,
                        child: _searchingAddress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Go'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 15,
                    minZoom: 4,
                    maxZoom: 18,
                    onTap: (_, point) => setState(() => _pin = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.fieldforce.mobile',
                      maxZoom: 19,
                      keepBuffer: 2,
                      errorTileCallback: (tile, error, stackTrace) {},
                    ),
                    if (_pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pin!,
                            width: 48,
                            height: 48,
                            child: const Icon(Icons.location_on, color: Color(0xFFE11D48), size: 44),
                          ),
                        ],
                      ),
                  ],
                ),
                if (_loadingGps)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66FFFFFF),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.extended(
                    heroTag: 'pin-my-location',
                    onPressed: _useMyLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('My location'),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton(
                onPressed: _pin == null ? null : () => Navigator.pop(context, _pin),
                child: Text(_pin == null ? 'ENTER ADDRESS OR TAP MAP' : 'CONFIRM OUTLET PIN'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
