import 'dart:async';
import 'package:location/location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:map_ar/secrets.dart';
import 'package:map_ar/streetview.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Maps demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.white
      ),
      home: NearbyPlacesMap(),
    );
  }
}

class MapSample extends StatefulWidget {
  const MapSample({Key? key}) : super(key: key);

  @override
  State<MapSample> createState() => _MapSampleState();
}

class _MapSampleState extends State<MapSample> {
  final Completer<GoogleMapController> _controller = Completer();

  static const LatLng sourceLocation = LatLng(12.91995, 77.67175);
  static const LatLng destination = LatLng(12.920397, 77.50429);

  List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polyline = {};
  Set<Marker> _markers = {};
  LocationData? _currentLocation;
  bool _loading = true;
  void _getCurrentLocation() async {

    Location location = Location();

    GoogleMapController googleMapController = await _controller.future;

    location.getLocation().then((location){
      _currentLocation = location;
      _loading = false;
      setState(() {
      });
    });
    location.onLocationChanged.listen((event) {
      _currentLocation = event;
      googleMapController.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(event!.latitude!,event!.longitude!))));
      setState(() {
      });
    });
  }
  void _getPolyPoints() async {
    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        apiKey,
        PointLatLng(sourceLocation.latitude, sourceLocation.longitude),
        PointLatLng(destination.latitude, destination.longitude)
    );
    if(result.points.isNotEmpty){
      result.points.forEach((PointLatLng point) => _polylineCoordinates.add(LatLng(point.latitude, point.longitude)),
      );
      setState(() {});
    }
  }
  @override
  void initState(){
    _getCurrentLocation();
    _getPolyPoints();
    super.initState();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading == true ?
      Center(
        child: CircularProgressIndicator(
        ),
      ) : GoogleMap(
        initialCameraPosition: CameraPosition(target: LatLng(_currentLocation!.latitude!,_currentLocation!.longitude!), zoom: 14.5),
        polylines: {
          Polyline(polylineId: PolylineId('route'),
              points: _polylineCoordinates,
              width: 4,
            color: Colors.blue
          )
        },
        markers: {
          Marker(
            markerId: MarkerId('1'),
            position: LatLng(sourceLocation.latitude, sourceLocation.longitude),
            icon: BitmapDescriptor.defaultMarker,
          ),
          Marker(
            markerId: MarkerId('2'),
            position: LatLng(destination.latitude, destination.longitude),
            icon: BitmapDescriptor.defaultMarker,
          ),
          Marker(
            markerId: MarkerId('3'),
            position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
            icon: BitmapDescriptor.defaultMarker,
          ),
        },
        onMapCreated: (mapController){
          _controller.complete(mapController);
        },
      ),
    );
  }
}




