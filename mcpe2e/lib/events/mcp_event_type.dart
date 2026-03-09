import 'dart:ui';

/// Enum que define todos los tipos de eventos disponibles
enum McpEventType {
  /// Tap simple en un widget
  tap,

  /// Tap sostenido/prolongado
  longPress,

  /// Escribir texto en un TextField
  textInput,

  /// Deslizamiento direccional
  swipe,

  /// Scroll con deltas
  scroll,

  /// Ocultar teclado
  hideKeyboard,

  /// Mostrar teclado
  showKeyboard,

  /// Esperar/delay
  wait,

  /// Verificar que widget existe
  assertExists,

  /// Verificar texto de widget
  assertText,

  /// Double tap
  doubleTap,

  /// Drag and drop
  drag,

  /// Pinch (zoom)
  pinch,

  /// Seleccionar opción de dropdown por valor o índice
  selectDropdown,

  /// Activar/desactivar Checkbox, Switch o Radio
  toggle,

  /// Posicionar Slider a un valor 0.0–1.0 (porcentaje del track)
  setSliderValue,

  /// Navegar atrás (pop de ruta)
  pressBack,

  /// Limpiar TextField sin escribir texto
  clearText,

  /// Scrollear padre hasta que el widget target sea visible en viewport
  scrollUntilVisible,

  /// Verificar que el widget está visible en el viewport actual
  assertVisible,

  /// Verificar que el widget está habilitado (no disabled)
  assertEnabled,

  /// Verificar el estado checked de Checkbox, Switch o Radio
  assertSelected,

  /// Verificar el valor del TextEditingController (no el display text)
  assertValue,

  /// Verificar cantidad de hijos en un ListView/Column
  assertCount,

  /// Tapear el widget cuyo texto interno coincide con el label dado
  tapByLabel,
}

/// Parámetros adicionales para eventos
class McpEventParams {
  // Parámetros comunes
  final String? text;
  final Duration? duration;
  final double? distance;
  final String? direction; // 'left', 'right', 'up', 'down'
  final double? deltaX;
  final double? deltaY;
  final bool? clearFirst;
  final String? expectedText;
  final Offset? targetPosition;
  final double? scale;

  // Dropdown específico
  final String? dropdownValue; // Valor a seleccionar (ej: "food", "transport")
  final int? dropdownIndex; // O índice de la opción (0-based)

  // Slider
  final double? sliderValue; // Valor 0.0–1.0 (porcentaje del track)

  // scrollUntilVisible
  final String? targetKey; // Key del widget a hacer visible
  final int? maxScrollAttempts; // Máximo de intentos (default: 20)

  // tapByLabel
  final String? label; // Texto visible del widget a tapear

  // assertCount
  final int? expectedCount; // Cantidad esperada de hijos

  const McpEventParams({
    this.text,
    this.duration,
    this.distance,
    this.direction,
    this.deltaX,
    this.deltaY,
    this.clearFirst,
    this.expectedText,
    this.targetPosition,
    this.scale,
    this.dropdownValue,
    this.dropdownIndex,
    this.sliderValue,
    this.targetKey,
    this.maxScrollAttempts,
    this.label,
    this.expectedCount,
  });

  /// Crear desde Map (útil para HTTP requests)
  factory McpEventParams.fromJson(Map<String, dynamic> json) {
    return McpEventParams(
      text: json['text'] as String?,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      distance: json['distance']?.toDouble(),
      direction: json['direction'] as String?,
      deltaX: json['deltaX']?.toDouble(),
      deltaY: json['deltaY']?.toDouble(),
      clearFirst: json['clearFirst'] as bool?,
      expectedText: json['expectedText'] as String?,
      scale: json['scale']?.toDouble(),
      dropdownValue: json['dropdownValue'] as String?,
      dropdownIndex: json['dropdownIndex'] as int?,
      sliderValue: json['sliderValue']?.toDouble(),
      targetKey: json['targetKey'] as String?,
      maxScrollAttempts: json['maxScrollAttempts'] as int?,
      label: json['label'] as String?,
      expectedCount: json['expectedCount'] as int?,
    );
  }

  /// Convertir a Map (útil para logging)
  Map<String, dynamic> toJson() {
    return {
      if (text != null) 'text': text,
      if (duration != null) 'duration': duration!.inMilliseconds,
      if (distance != null) 'distance': distance,
      if (direction != null) 'direction': direction,
      if (deltaX != null) 'deltaX': deltaX,
      if (deltaY != null) 'deltaY': deltaY,
      if (clearFirst != null) 'clearFirst': clearFirst,
      if (expectedText != null) 'expectedText': expectedText,
      if (scale != null) 'scale': scale,
      if (dropdownValue != null) 'dropdownValue': dropdownValue,
      if (dropdownIndex != null) 'dropdownIndex': dropdownIndex,
      if (sliderValue != null) 'sliderValue': sliderValue,
      if (targetKey != null) 'targetKey': targetKey,
      if (maxScrollAttempts != null) 'maxScrollAttempts': maxScrollAttempts,
      if (label != null) 'label': label,
      if (expectedCount != null) 'expectedCount': expectedCount,
    };
  }
}
