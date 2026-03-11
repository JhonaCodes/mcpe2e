import 'dart:ui';

/// Enum defining all available event types
enum McpEventType {
  /// Simple tap on a widget
  tap,

  /// Long press / sustained tap
  longPress,

  /// Type text into a TextField
  textInput,

  /// Directional swipe
  swipe,

  /// Scroll with deltas
  scroll,

  /// Hide keyboard
  hideKeyboard,

  /// Show keyboard
  showKeyboard,

  /// Wait / delay
  wait,

  /// Assert that a widget exists
  assertExists,

  /// Assert widget text
  assertText,

  /// Double tap
  doubleTap,

  /// Drag and drop
  drag,

  /// Pinch (zoom)
  pinch,

  /// Select dropdown option by value or index
  selectDropdown,

  /// Toggle Checkbox, Switch, or Radio on/off
  toggle,

  /// Set Slider to a value 0.0–1.0 (percentage of track)
  setSliderValue,

  /// Navigate back (route pop)
  pressBack,

  /// Clear TextField without typing text
  clearText,

  /// Scroll parent until the target widget is visible in the viewport
  scrollUntilVisible,

  /// Assert that the widget is visible in the current viewport
  assertVisible,

  /// Assert that the widget is enabled (not disabled)
  assertEnabled,

  /// Assert the checked state of a Checkbox, Switch, or Radio
  assertSelected,

  /// Assert the TextEditingController value (not the display text)
  assertValue,

  /// Assert the number of children in a ListView/Column
  assertCount,

  /// Tap the widget whose inner text matches the given label
  tapByLabel,

  /// Tap at absolute screen coordinates (no registered widget needed)
  tapAt,
}

/// Additional parameters for events
class McpEventParams {
  // Common parameters
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

  // Dropdown-specific
  final String? dropdownValue; // Value to select (e.g.: "food", "transport")
  final int? dropdownIndex; // Or option index (0-based)

  // Slider
  final double? sliderValue; // Value 0.0–1.0 (percentage of track)

  // scrollUntilVisible
  final String? targetKey; // Key of the widget to make visible
  final int? maxScrollAttempts; // Maximum attempts (default: 20)

  // tapByLabel
  final String? label; // Visible text of the widget to tap

  // assertCount
  final int? expectedCount; // Expected number of children

  // tapAt — absolute screen coordinates
  final double? dx; // Absolute X coordinate in logical pixels
  final double? dy; // Absolute Y coordinate in logical pixels

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
    this.dx,
    this.dy,
  });

  /// Create from Map (useful for HTTP requests)
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
      dx: json['dx']?.toDouble(),
      dy: json['dy']?.toDouble(),
    );
  }

  /// Convert to Map (useful for logging)
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
      if (dx != null) 'dx': dx,
      if (dy != null) 'dy': dy,
    };
  }
}
