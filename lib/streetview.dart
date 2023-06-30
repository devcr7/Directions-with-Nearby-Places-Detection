import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'secrets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart' as coord;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import "package:google_maps_webservice_ex/places.dart" as webplaces;
import 'package:google_maps_flutter_platform_interface/src/types/polyline.dart' as pir;

import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_maps_webservice_ex/places.dart';
import 'package:form_builder_extra_fields/form_builder_extra_fields.dart';
import 'package:http/http.dart' as http;

enum IconType {
  restaurants,
  hospitals,
  hotel,
  schools,
  gas_station,
  shopping_cart;
}

enum Get_markerType {
  restaurants,
  hospitals,
  hotel,
  schools,
  gas_station,
  shopping_cart;
}

void main() {
  runApp(NearbyPlacesMap());
}

class NearbyPlacesMap extends StatefulWidget {
  @override
  _NearbyPlacesMapState createState() => _NearbyPlacesMapState();
}

class _NearbyPlacesMapState extends State<NearbyPlacesMap> {
  GoogleMapController? _mapController;

  var _currentLocation;
  final Geolocator _geolocator = Geolocator();
  StreamSubscription<Position>? _positionStream;
  Set<Marker> _nearbyMarkers = {};
  Set<Marker> _defaultMarkers = {};
  late TextEditingController _controllerSource;
  late TextEditingController _controllerDestination;
  Map<String, dynamic> _locations = {};
  String _markerType = "";
  List<LatLng> _polylineCoordinates = [];
  LatLng _markerPosition = LatLng(40.714728, -73.998672);
  bool _iconSelected = false;
  bool _isLoading = true;
  bool _isTracking = false;
  Timer? _timer;
  String _travelMode = "driving";
  int _radius = 0;
  bool _showIndicator = false;
  String _selectedItem = "Driving";
  String _instruction = '';
  double _distance = 0.0;
  Text? _mode;
  String _distanceUnit = "meters";
  List<String> directions = [];
  List<String> manuever = [];
  List<LatLng> allPathPoints = [];
  List<int> distannces = [];
  Get_markerType _getMarkerType = Get_markerType.gas_station;
  List<Map<String,dynamic>> startpoints = [];
  List<PlacesDetailsResponse>? leftBuildings = [];
  List<PlacesDetailsResponse>? rightBuildings = [];
  List<PlacesDetailsResponse>? leftTrees = [];
  List<PlacesDetailsResponse>? rightTrees = [];
  List<PlacesDetailsResponse>? leftGrounds = [];
  List<PlacesDetailsResponse>? rightGrounds = [];
  List<PlacesDetailsResponse>? leftBridge = [];
  List<PlacesDetailsResponse>? rightBridge = [];
  List<PlacesDetailsResponse>? leftRoads = [];
  List<PlacesDetailsResponse>? rightRoads = [];
  List<PlacesDetailsResponse>? leftParks = [];
  List<PlacesDetailsResponse>? rightParks = [];
  List<PlacesDetailsResponse>? leftFarms = [];
  List<PlacesDetailsResponse>? rightFarms = [];
  List<String> objectsType = ['building','ground','tree','bridge','park','farm'];
  List<String> _dropdownItems = [  'Walking',  'Driving',  'Transit',];


  final webplaces.GoogleMapsPlaces _places = webplaces.GoogleMapsPlaces(
      apiKey: apiKey);

  @override
  void initState() {
    _controllerSource = TextEditingController();
    _controllerDestination = TextEditingController();
    _timer = Timer.periodic(Duration(seconds: 15), (timer) {
      _getCurrentLocation();
    });
    super.initState();
  }

  coord.TravelMode  travelMode(String _travelMode){
    switch(_travelMode){
      case 'Driving':
        return coord.TravelMode.driving;
      case 'Walking':
        return coord.TravelMode.walking;;
      case 'Bicycling':
        return coord.TravelMode.bicycling;;
      case 'Transit':
        return coord.TravelMode.transit;;
    }
    return coord.TravelMode.driving;
  }

  void getDirectionApi()  async{
    try {
      directions.clear();
      manuever.clear();
      startpoints.clear();
      var dio = Dio();
      var origin = '${_currentLocation.latitude},${_currentLocation.longitude}'; // Toronto
      var destination = '${_locations['destinationLatitude']},${_locations['destinationLongitude']}'; // Montreal
      var url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=${apiKey}';
      var response = await dio.get(url);
      if (response.statusCode == 200) {
        var data = (response.data);
        var steps = data['routes'][0]['legs'][0]['steps'];
        var polylinePoints = coord.PolylinePoints();
        for (var step in steps) {
          var direction = step['html_instructions'].replaceAll(
              RegExp('<[^>]*>'), '');
          if (step['maneuver'] != null) {
            direction += ' (${step['maneuver']})';
            manuever.add(step['maneuver']);
            startpoints.add(step['start_location']);
            distannces.add(step['distance']['value']);
            List<coord.PointLatLng> decodedPolyline =
            polylinePoints.decodePolyline(step['polyline']['points']);
            List<LatLng> points =
            decodedPolyline.map((point) => LatLng(point.latitude, point.longitude)).toList();
            allPathPoints.addAll(points);
            print(allPathPoints);
          }
          directions.add(direction);
        }
        print(directions);
      }
    } catch (e,s) {
      print(e);
    }
  }


  Future<Map<String, List<PlacesDetailsResponse>>> getBuildingsAlongPath( String objectype) async {
    final double maxDistanceFromPath = 30; // maximum distance from path to consider building as adjacent
    List<PlacesDetailsResponse> leftBuildings = [];
    List<PlacesDetailsResponse> rightBuildings = [];
    for (int i = 0; i < allPathPoints.length; i++) {
      LatLng point = allPathPoints[i];
      PlacesSearchResponse response = await _places.searchNearbyWithRadius(
          Location(lat:point.latitude, lng:point.longitude), maxDistanceFromPath,
          type: objectype);
      if (response.status == 'OK' && response.results.length > 0) {
        PlacesDetailsResponse buildingDetails =
        await _places.getDetailsByPlaceId(response.results[0].placeId);
        LatLng buildingLocation =
        LatLng(buildingDetails.result!.geometry!.location.lat, buildingDetails.result!.geometry!.location.lng);
        double distanceFromPath =  Geolocator.distanceBetween(point.latitude, point.longitude, buildingLocation.latitude, buildingLocation.longitude);
        if (distanceFromPath <= maxDistanceFromPath) {
          // Check if building is to the left or right of the path
          double crossProduct = (buildingLocation.longitude - point.longitude) *
              (allPathPoints[(i + 1) % allPathPoints.length].latitude - point.latitude) -
              (buildingLocation.latitude - point.latitude) *
                  (allPathPoints[(i + 1) % allPathPoints.length].longitude - point.longitude);
          if (crossProduct > 0) {
            // Building is to the left of the path
            leftBuildings.add(buildingDetails);
          } else {
            // Building is to the right of the path
            rightBuildings.add(buildingDetails);
          }
        }
      }
    }
    return {'left$objectype': leftBuildings, 'right$objectype': rightBuildings};
  }




  void _getDirections() async {
    // setState(() {
    //   polylines.clear();
    // });
    // polylines.clear();

    String origin =
        '${_currentLocation!.latitude},${_currentLocation!.longitude}';
    String destination =
        '${_locations['destinationLatitude']},${_locations['destinationLongitude']}';

    String url = 'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=$origin&destination=$destination&key=$apiKey';

    var response = await http.get(Uri.parse(url));
    var data = jsonDecode(response.body);

    if (data['status'] == 'OK') {
      List<LatLng> routeCoords = [];
      List<LatLng> turnCoords = [];
      List<dynamic> steps = data['routes'][0]['legs'][0]['steps'];
      steps.forEach((step) {
        List<LatLng> stepCoords = _decodePolyline(step['polyline']['points']);
        routeCoords.addAll(stepCoords);
        if(step['maneuver'] == null){
          turnCoords.add(stepCoords.last);
        }
        else
        if (step['maneuver'] == 'turn-left' ||
            step['maneuver'] == 'turn-right' ||
            step['maneuver'] == 'roundabout-right' ||
            step['maneuver'] == 'roundabout-left' ||
            step['maneuver'] == 'turn-sharp-right' ||
            step['maneuver'] == 'turn-sharp-left' ||
            step['maneuver'] == 'turn-slight-right' ||
            step['maneuver'] == 'straight' ||
            step['maneuver'] == 'turn-slight-left') {
          turnCoords.add(stepCoords.last);
        }
      });

      double distance = 0;
      LatLng prevTurnCoord =
      LatLng(_currentLocation.latitude, _currentLocation.longitude);
      turnCoords.forEach((turnCoord) {
        double _bearing = Geolocator.bearingBetween(prevTurnCoord.latitude, prevTurnCoord.longitude, turnCoord.latitude, turnCoord.longitude);
        var turnDirection = getDirection(_bearing);
        double stepDistance = Geolocator.distanceBetween(prevTurnCoord.latitude,
            prevTurnCoord.longitude, turnCoord.latitude, turnCoord.longitude);
        distance += stepDistance;
        prevTurnCoord = turnCoord;
        print('Bearing is {$_bearing}');
        print('$turnDirection in ${stepDistance.toInt()} meters');
      });
    } else {
      print('Error getting directions');
    }
  }

  double getBearing(double lat1, double lng1, double lat2, double lng2) {
    double dLon = (lng2-lng1);
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1)*sin(lat2) - sin(lat1)*cos(lat2)*cos(dLon);
    double brng = ((atan2(y, x)))*180/pi;
    brng = (brng + 360) % 360;

    return brng; // Convert bearing to a compass bearing (0 to 360 degrees)
  }

  double toRadians(double degrees) {
    return degrees * pi / 180.0;
  }



// Helper method to convert radians to degrees
  double toDegrees(double radians) {
    return radians * 180.0 / pi;
  }

  String getDirection(double bearing) {
    if (bearing >= 45 && bearing < 135) {
      return "Turn left";
    } else if (bearing >= 135 && bearing < 225) {
      return "Make a U-turn";
    } else if (bearing >= 225 && bearing < 315) {
      return "Turn right";
    } else {
      return "Continue straight";
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  @override
  void dispose() {
    _controllerSource.dispose();
    _controllerDestination.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.requestPermission();
    final position = await Geolocator.getCurrentPosition();

    setState(() {
      _currentLocation = position;
      if (_locations['destinationLatitude'] != null && _locations['destinationLongitude'] != null && startpoints.length >0 && manuever.length > 0 ) {
        _distance = Geolocator.distanceBetween(_currentLocation.latitude, _currentLocation.longitude, startpoints[0]['lat'], startpoints[0]['lng']);
        for (var i = 0; i < startpoints.length -1 ; i ++) {
          _distance += Geolocator.distanceBetween(startpoints[i]['lat'], startpoints[i]['lng'], startpoints[i+1]['lat'], startpoints[i+1]['lng']);
        }
        if (_distance/ 1000 >= 1) {
          _distance = _distance/1000;
          _distanceUnit = "km";
        }

      }
      if ( startpoints.length >0 && manuever.length > 0 ) {
        var dist =  Geolocator.distanceBetween(
            _currentLocation.latitude, _currentLocation.longitude, startpoints[0]['lat'], startpoints[0]['lng']
        );
        String distUnit = "meter";
        if (dist/1000 >= 1 ) {
          distUnit = "km";
          dist = dist/1000;
        }
        if (dist <= 30 && distUnit == "meter") {
          _instruction = "Please take a ${manuever[0]} in ${dist.toStringAsFixed(2)} ${distUnit} ";
          _showIndicator = true;
          startpoints.removeAt(0);
          manuever.removeAt(0);
        } else {
          _instruction = "Please take a ${manuever[0]} in ${dist.toStringAsFixed(2)} ${distUnit} ";
          _showIndicator = false;
        }
        if (startpoints.length == 0 && manuever.length == 0)
          _instruction = "you will be reaching your detination in ${dist.toStringAsFixed(2)} ${distUnit}";

      }
      // _instruction =  getInstruction(LatLng(_currentLocation.latitude, _currentLocation.longitude), manuever,startpoints,directions);
      _markerPosition = LatLng(position.latitude, position.longitude);
      _isLoading = false;
      _locations['currentLatitude'] = _currentLocation.latitude;
      _locations['currentLongitude'] = _currentLocation.longitude;
      if (_controllerSource.text == '') {
        _locations['sourceLatitude'] = _currentLocation!.latitude!;
        _locations['sourceLongitude'] = _currentLocation!.longitude!;
      }
      if (_isTracking) {
        _getPolyPoints(_travelMode);
        // _getDirections();
        // getDirectionApi();
        _mapController?.animateCamera(CameraUpdate.newLatLng(
          LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
        ));
      }
    });
  }

  Future<BitmapDescriptor> _getPlaceIcon() async {
    final ImageConfiguration config = ImageConfiguration(size: Size(12, 12));
    final BitmapDescriptor bitmap = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(76.0, 76.0)),
      'assets/images/$_markerType.png',
    );
    return bitmap;
  }

  Future<void> _getPolyPoints(String _travelmode) async {
    _polylineCoordinates.clear();
    coord.PolylinePoints polylinePoints = coord.PolylinePoints();
    coord.PolylineResult result;
    String mode="";
    if (!_isTracking) {
      result = await polylinePoints.getRouteBetweenCoordinates(
          apiKey,
          coord.PointLatLng(
              _locations['sourceLatitude'], _locations['sourceLongitude']),
          coord.PointLatLng(_locations['destinationLatitude'],
              _locations['destinationLongitude']), travelMode: travelMode(_travelMode));
    } else {
      result = await polylinePoints.getRouteBetweenCoordinates(
          apiKey,
          coord.PointLatLng(_currentLocation!.latitude, _currentLocation!.longitude),
          coord.PointLatLng(_locations['destinationLatitude'],
              _locations['destinationLongitude']), travelMode: travelMode(_travelMode));
    }
    if (result.points.isNotEmpty) {
      result.points.forEach(
            (coord.PointLatLng point) =>
            _polylineCoordinates.add(LatLng(point.latitude, point.longitude)),
      );
      setState((){});
    }
  }

  Future<Iterable<String>> _getSuggestions(String pattern) async {
    final webplaces.PlacesAutocompleteResponse response =
    await _places.autocomplete(pattern);
    if (response.errorMessage != null) {
      return [];
    }
    final List<String?> predictions =
    response.predictions.map((p) => p.description).toList();
    final Iterable<String> filteredPredictions =
    predictions.where((p) => p != null).map((p) => p!);
    return filteredPredictions;
  }

  void _showSortedMarkes(IconType iconType) {
    _iconSelected = !_iconSelected;
    setState(() {});

    switch (iconType) {
      case IconType.gas_station:
        _getMarkerType = Get_markerType.gas_station;
        _getNearbyPlaces(Get_markerType.gas_station);

        break;
      case IconType.hospitals:
        _getMarkerType = Get_markerType.hospitals;
        _getNearbyPlaces(Get_markerType.hospitals);

        break;
      case IconType.hotel:
        _getMarkerType = Get_markerType.hotel;
        _getNearbyPlaces(Get_markerType.hotel);

        break;
      case IconType.schools:
        _getMarkerType = Get_markerType.schools;
        _getNearbyPlaces(Get_markerType.schools);

        break;
      case IconType.shopping_cart:
        _getMarkerType = Get_markerType.shopping_cart;
        _getNearbyPlaces(Get_markerType.shopping_cart);

        break;
      case IconType.restaurants:
        _getMarkerType = Get_markerType.restaurants;
        _getNearbyPlaces(Get_markerType.restaurants);

        break;
    }
  }

  void _animateCameraandDestination() {
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
          min(_locations['sourceLatitude'], _locations['destinationLatitude']),
          min(_locations['sourceLongitude'],
              _locations['destinationLongitude'])),
      northeast: LatLng(
          max(_locations['sourceLatitude'], _locations['destinationLatitude']),
          max(_locations['sourceLongitude'],
              _locations['destinationLongitude'])),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100.0));
    // padding to adjust the camera zoom ), );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  Future<void> _getNearbyPlaces(Get_markerType get_markerType) async {
    // create a Places API client
    switch (get_markerType) {
      case Get_markerType.hotel:
        _markerType = 'lodging';
        break;
      case Get_markerType.hospitals:
        _markerType = 'hospital';
        break;
      case Get_markerType.schools:
        _markerType = 'school';
        break;
      case Get_markerType.restaurants:
        _markerType = "restaurant";
        break;
      case Get_markerType.shopping_cart:
        _markerType = "shopping_mall";
        break;
      case Get_markerType.gas_station:
        _markerType = "gas_station";
        break;
    }
    final places = webplaces.GoogleMapsPlaces(
        apiKey: apiKey); //

    // search for nearby places
    final result = await places.searchNearbyWithRadius(
      webplaces.Location(
          lat: _currentLocation!.latitude, lng: _currentLocation!.longitude),
      _radius*1000,
      type: _markerType,
    );
    _nearbyMarkers.clear();
    for (var place in result.results) {
      _nearbyMarkers.add(
        Marker(
          markerId: MarkerId(place.placeId),
          position: LatLng(
              place!.geometry!.location!.lat, place!.geometry!.location!.lng),
          icon: await _getPlaceIcon(),
          infoWindow: InfoWindow(
            title: place.name,
            snippet: place.vicinity,
          ),
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            leading: Visibility(
              visible: _iconSelected,
              child: BackButton(
                onPressed: () {
                  _radius = 0;
                  _iconSelected = !_iconSelected;
                  setState(() {});
                },
              ),
            ),
            title: !_iconSelected
                ? Text('Directions & Nearby Places POC')
                : Text(_markerType.toUpperCase()),
            centerTitle: !_iconSelected,
          ),
          body: SafeArea(
            child: Column(
              children: [
                !_isTracking ? Container(
                    child: SizedBox(height: 10), color: Colors.transparent)
                : Container(),
                Visibility(
                  visible: _iconSelected,
                  child: Column(
                    children:[
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: FormBuilderSearchableDropdown<String>(
                          name: "select_radius",
                          popupProps: PopupProps.menu(
                            showSelectedItems: false,
                            showSearchBox: false,
                          ),
                          items: List.generate(50, (index) => (index +1).toString()),
                          onChanged: (value) {
                            setState(() {
                              _radius = int.parse(value!);
                              _getNearbyPlaces(_getMarkerType);
                            });
                          },

                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Select a radius (km)',
                            hintStyle: const TextStyle(fontSize: 16),
                            contentPadding: const EdgeInsets.all(8),
                          ),
                          // selectedItem: "2",

                          // popupShape: const RoundedRectangleBorder(
                          //   borderRadius: BorderRadius.only(
                          //     topLeft: Radius.circular(SpaceConstants.borderRadius10),
                          //     topRight: Radius.circular(SpaceConstants.borderRadius10),
                          //   ),
                          // ),
                        ),
                      ),
                  ],

                  ),
                ),
                _isTracking ? Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  color: Colors.green,
                  child: Column(
                    children: [
                      Text(
                        _instruction,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      SizedBox(height: 8),
                      Text(
                          'Distance to destination is ${_distance.toStringAsFixed(2)} ${_distanceUnit}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18, color: Colors.white)
                      ),
                    ],
                  ),
                ) : Container(),
                Visibility(
                  visible: !_iconSelected && !_isTracking,
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: TypeAheadFormField<String>(
                          textFieldConfiguration: TextFieldConfiguration(
                            controller: _controllerSource,
                            decoration: InputDecoration(
                              labelText: 'Current location',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          suggestionsCallback: (String pattern) async {
                            return _getSuggestions(pattern);
                          },
                          itemBuilder:
                              (BuildContext context, String suggestion) {
                            return ListTile(
                              title: Text(suggestion),
                            );
                          },
                          onSuggestionSelected: (String suggestion) async {
                            webplaces.PlacesDetailsResponse response =
                            await _places.getDetailsByPlaceId(
                                (await _places.autocomplete(suggestion))
                                    .predictions[0]
                                    .placeId as String);
                            if (response.errorMessage == null) {
                              setState(() {
                                _locations['sourceLatitude'] =
                                    response.result?.geometry?.location.lat;
                                _locations['sourceLongitude'] =
                                    response.result?.geometry?.location.lng;
                                _controllerSource.text = suggestion;
                                _defaultMarkers.remove(Marker(
                                  markerId: MarkerId('sourceMarker'),
                                  position: LatLng(_locations['sourceLatitude'],
                                      _locations['sourceLongitude']),
                                  icon: BitmapDescriptor.defaultMarker,
                                ));
                                if (_currentLocation!.latitude !=
                                    _locations['sourceLatitude'] &&
                                    _currentLocation!.longitude !=
                                        _locations['sourceLongitude']) {
                                  _defaultMarkers.add(
                                    Marker(
                                      markerId: MarkerId('sourceMarker'),
                                      position: LatLng(
                                          _locations['sourceLatitude'],
                                          _locations['sourceLongitude']),
                                      icon: BitmapDescriptor.defaultMarker,
                                    ),
                                  );
                                }
                                if (_controllerDestination.text != '') {
                                  _getPolyPoints(_travelMode);
                                  _animateCameraandDestination();
                                }
                              });
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: TypeAheadFormField<String>(
                          textFieldConfiguration: TextFieldConfiguration(
                            controller: _controllerDestination,
                            decoration: InputDecoration(
                              labelText: 'Search for destination',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          suggestionsCallback: (String pattern) async {
                            return _getSuggestions(pattern);
                          },
                          itemBuilder:
                              (BuildContext context, String suggestion) {
                            return ListTile(
                              title: Text(suggestion),
                            );
                          },
                          onSuggestionSelected: (String suggestion) async {
                            webplaces.PlacesDetailsResponse response =
                            await _places.getDetailsByPlaceId(
                                (await _places.autocomplete(suggestion))
                                    .predictions[0]
                                    .placeId as String);
                            if (response.errorMessage == null) {
                              setState(() {
                                _locations['destinationLatitude'] =
                                    response.result?.geometry?.location.lat;
                                _locations['destinationLongitude'] =
                                    response.result?.geometry?.location.lng;
                                _controllerDestination.text = suggestion;

                                getDirectionApi();
                                _defaultMarkers.remove(Marker(
                                  markerId: MarkerId('destinationMarker'),
                                  position: LatLng(
                                      _locations['destinationLatitude'],
                                      _locations['destinationLongitude']),
                                  icon: BitmapDescriptor.defaultMarker,
                                ));
                                _defaultMarkers.add(
                                  Marker(
                                    markerId: MarkerId('destinationMarker'),
                                    position: LatLng(
                                        _locations['destinationLatitude'],
                                        _locations['destinationLongitude']),
                                    icon: BitmapDescriptor.defaultMarker,
                                  ),
                                );
                                _getPolyPoints(_travelMode);
                                _animateCameraandDestination();
                              });
                            }
                          },
                        ),
                      )
                    ],
                  ),
                ),
                _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : Expanded(
                  child: Container(
                    // margin: EdgeInsets.fromLTRB(0, 80, 0, 0),
                    child: Stack(children: [
                      GoogleMap(
                        onCameraMove: (cameraPosition) {

                        },
                        myLocationEnabled: true,
                        zoomControlsEnabled: false,
                        onMapCreated: _onMapCreated,
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_currentLocation!.latitude,
                              _currentLocation!.longitude),
                          // target: LatLng(12.651268,71.657112),
                          zoom: _isTracking ? 20.0 : 14.0,
                        ),
                        markers: _iconSelected
                            ? _nearbyMarkers
                            : _defaultMarkers,
                        polylines: !_iconSelected
                            ? {
                          pir.Polyline(
                              polylineId: PolylineId('route'),
                              points: _polylineCoordinates,
                              width: 4,
                              color: Colors.blue)
                        }
                            : {},
                      ),
                      Positioned(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Visibility(
                            visible: !_iconSelected && !_isTracking,
                            child: Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceEvenly,
                              children: [
                                FloatingActionButton.extended(
                                  onPressed: () {
                                    _showSortedMarkes(IconType.restaurants);
                                  },
                                  label: Text('Restaurants'),
                                  icon: Icon(Icons.restaurant),
                                  elevation:
                                  0, // Set elevation to 0 to remove the shadow
                                ),
                                SizedBox(width: 20.0),
                                FloatingActionButton.extended(
                                  onPressed: () {
                                    _showSortedMarkes(IconType.hotel);
                                  },
                                  label: Text('Hotels'),
                                  icon: Icon(Icons.hotel),
                                  elevation: 0,
                                ),
                                SizedBox(width: 20.0),
                                FloatingActionButton.extended(
                                  onPressed: () {
                                    _showSortedMarkes(IconType.hospitals);
                                  },
                                  label: Text('Hospitals & clinics'),
                                  icon: Icon(Icons.local_hospital),
                                  elevation: 0,
                                ),
                                SizedBox(width: 20.0),
                                FloatingActionButton.extended(
                                  onPressed: () {
                                    _showSortedMarkes(
                                        IconType.shopping_cart);
                                  },
                                  label: Text('Shopping'),
                                  icon: Icon(Icons.shopping_cart),
                                  elevation: 0,
                                ),
                                SizedBox(width: 20.0),
                                FloatingActionButton.extended(
                                  onPressed: () {
                                    _showSortedMarkes(IconType.schools);
                                  },
                                  label: Text('Schools'),
                                  icon: Icon(Icons.school),
                                  elevation: 0,
                                ),
                                SizedBox(width: 20.0),
                                FloatingActionButton.extended(
                                  onPressed: () {
                                    _showSortedMarkes(IconType.gas_station);
                                  },
                                  label: Text('Petrol'),
                                  icon: Icon(Icons.local_gas_station),
                                  elevation: 0,
                                ),
                              ],
                            ),
                          ),
                        ),),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: Visibility(
            visible: _iconSelected == false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // SizedBox(width: 20),
                  FloatingActionButton(
                    onPressed: (){},
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _selectedItem == "Driving" ? Icon(CupertinoIcons.car) : _selectedItem == "Walking" ? Icon(CupertinoIcons.person) :  Icon(CupertinoIcons.bus) ,
                        Positioned(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedItem,
                            items: _dropdownItems
                                .map((item) =>
                                DropdownMenuItem<String>(
                                    child: Text(item),
                                    value: item,
                                    alignment: AlignmentDirectional.center
                                ),
                            )
                                .toList(),
                            selectedItemBuilder: (BuildContext context) {
                              return _dropdownItems.map<Widget>((String item) {
                                return  Text(
                                  item,
                                  style: TextStyle(
                                    color: item == _selectedItem ? Colors.blue : Colors.black,
                                  ),
                                );
                              }).toList();
                            },
                            onChanged: (value) {
                              setState(() {
                                _selectedItem = value!;
                                _travelMode = _selectedItem;
                                _getPolyPoints(_travelMode);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 30),
                  FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        _defaultMarkers.remove(Marker(
                          markerId: MarkerId('sourceMarker'),
                          position: LatLng(_locations['sourceLatitude'],
                              _locations['sourceLongitude']),
                          icon: BitmapDescriptor.defaultMarker,

                        ));
                        final newCameraPosition = CameraPosition(
                          target: LatLng(_currentLocation!.latitude!,
                              _currentLocation!.longitude!),
                          zoom: 14.5,
                        );
                        final newCameraUpdate =
                        CameraUpdate.newCameraPosition(newCameraPosition);
                        _mapController?.animateCamera(newCameraUpdate);
                        _controllerSource.text = '';
                        _isTracking = !_isTracking;

                      });
                    },
                    child: Icon(Icons.directions_run),
                  ),
                  SizedBox(height: 10),
                  FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        final newCameraPosition = CameraPosition(
                          target: LatLng(_currentLocation!.latitude!,
                              _currentLocation!.longitude!),
                          zoom: 14,
                        );
                        final newCameraUpdate =
                        CameraUpdate.newCameraPosition(newCameraPosition);
                        _mapController?.animateCamera(newCameraUpdate);
                      });
                    },
                    child: Icon(CupertinoIcons.location),
                  ),

                ],
              ),
            ),
          ),
        ));
  }
}