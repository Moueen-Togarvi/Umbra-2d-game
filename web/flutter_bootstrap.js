{{flutter_js}}
{{flutter_build_config}}

// Keep the renderer alongside the game so first launch does not depend on a CDN.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
