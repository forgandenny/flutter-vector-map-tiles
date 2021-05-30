import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';
import 'disposable_state.dart';
import 'tile_identity.dart';
import 'vector_tile_provider.dart';
import 'debounce.dart';
import 'tile_widgets.dart';

class VectorTileLayerOptions extends LayerOptions {
  final VectorTileProvider tileProvider;
  final Theme theme;

  VectorTileLayerOptions({required this.tileProvider, required this.theme});
}

class VectorTileLayer extends StatefulWidget {
  final VectorTileLayerOptions options;
  final MapState mapState;
  final Stream<Null> stream;

  const VectorTileLayer(this.options, this.mapState, this.stream);

  @override
  State<StatefulWidget> createState() {
    return _VectorTileLayerState();
  }
}

class _VectorTileLayerState extends DisposableState<VectorTileLayer> {
  StreamSubscription<Null>? _subscription;
  late ScheduledDebounce _debounce;
  late final TileWidgets _tileWidgets;

  MapState get _mapState => widget.mapState;
  double get _clampedZoom => _mapState.zoom.roundToDouble();

  _VectorTileLayerState() {
    _debounce = ScheduledDebounce(
        _update, Duration(milliseconds: 100), Duration(milliseconds: 200));
  }

  @override
  void initState() {
    super.initState();
    _tileWidgets =
        TileWidgets(widget.options.tileProvider, widget.options.theme);
    _subscription = widget.stream.listen((event) {
      _debounce.update();
    });
    _debounce.update();
  }

  @override
  void dispose() {
    super.dispose();
    _subscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final tileWidgets = _tileWidgets.all.entries
        .map((entry) => _positionTile(entry.key, entry.value))
        .toList();
    return Stack(children: tileWidgets);
  }

  void _update() {
    if (disposed) {
      return;
    }
    final center = _mapState.center;
    final pixelBounds = _tiledPixelBounds(center);
    final tileRange = _pixelBoundsToTileRange(pixelBounds);
    final tiles = _expand(tileRange);
    _tileWidgets.update(tiles);
    setState(() {});
  }

  Bounds _tiledPixelBounds(LatLng center) {
    var scale = _mapState.getZoomScale(_mapState.zoom, _clampedZoom);
    var centerPoint = _mapState.project(center, _clampedZoom).floor();
    var halfSize = _mapState.size / (scale * 2);

    return Bounds(centerPoint - halfSize, centerPoint + halfSize);
  }

  Bounds _pixelBoundsToTileRange(Bounds bounds) => Bounds(
        bounds.min.unscaleBy(_tileSize).floor(),
        bounds.max.unscaleBy(_tileSize).ceil() - const CustomPoint(1, 1),
      );

  List<TileIdentity> _expand(Bounds range) {
    final zoom = _clampedZoom;
    final tiles = <TileIdentity>[];
    for (num x = range.min.x; x <= range.max.x; ++x) {
      for (num y = range.min.y; y <= range.max.y; ++y) {
        tiles.add(TileIdentity(zoom, x, y));
      }
    }
    return tiles;
  }

  Widget _positionTile(TileIdentity tile, Widget tileWidget) {
    final zoomScale = _zoomScale(_mapState.zoom, tile.z.toDouble());
    final pixelOrigin =
        _mapState.getNewPixelOrigin(_mapState.center, _mapState.zoom).round();
    final origin =
        _mapState.project(_mapState.unproject(pixelOrigin), _mapState.zoom);
    final translate = origin.multiplyBy(zoomScale) - pixelOrigin;
    final tilePosition =
        tile.scaleBy(_tileSize).multiplyBy(zoomScale) - origin + translate;
    return Positioned(
        key: Key(
            'PositionedGridTile_${tile.z.toInt()}_${tile.x.toInt()}_${tile.y.toInt()}'),
        top: tilePosition.y.toDouble(),
        left: tilePosition.x.toDouble(),
        width: (_tileSize.x * zoomScale),
        height: (_tileSize.y * zoomScale),
        child: tileWidget);
  }

  double _zoomScale(double mapZoom, double tileZoom) {
    final crs = _mapState.options.crs;
    return crs.scale(tileZoom) / crs.scale(mapZoom);
  }
}

final _tileSize = CustomPoint(256, 256);