# Events

Core event model for mcpe2e.

## Files

| File | Description |
|------|-------------|
| `mcp_event_type.dart` | `McpEventType` enum (25 types) and `McpEventParams` |
| `mcp_metadata_key.dart` | `McpMetadataKey` (extends `Key`) and `McpWidgetType` enum |
| `mcp_events_core.dart` | `McpEvents` singleton — public facade for registration and execution |

## McpEventType (25 types)

**Gestures**: `tap` · `doubleTap` · `longPress` · `swipe` · `drag` · `scroll` · `pinch`

**Input**: `textInput` · `clearText` · `selectDropdown` · `toggle` · `setSliderValue`

**Keyboard & Navigation**: `hideKeyboard` · `showKeyboard` · `pressBack` · `scrollUntilVisible` · `tapByLabel` · `wait`

**Assertions**: `assertExists` · `assertText` · `assertVisible` · `assertEnabled` · `assertSelected` · `assertValue` · `assertCount`

## McpWidgetType (14 types)

`button` · `textField` · `text` · `list` · `card` · `image` · `container` · `dropdown` · `checkbox` · `radio` · `switchWidget` · `slider` · `tab` · `custom`

## McpMetadataKey

Extends Flutter's `Key` — assign it directly to any widget:

```dart
const submitButton = McpMetadataKey(
  id: 'checkout.submit_button',   // unique ID used by mcpe2e_server tools
  widgetType: McpWidgetType.button,
  description: 'Submit order',
  screen: 'CheckoutScreen',
);

ElevatedButton(
  key: submitButton,  // McpMetadataKey IS a Key
  onPressed: _submit,
  child: const Text('Place Order'),
)
```

## McpEventParams

Optional parameters passed alongside an event type:

```dart
McpEventParams({
  String? text,              // textInput, tapByLabel
  Duration? duration,        // longPress, wait
  double? distance,          // swipe
  String? direction,         // swipe, scroll ('up' | 'down' | 'left' | 'right')
  double? deltaX,            // scroll — horizontal delta
  double? deltaY,            // scroll — vertical delta
  bool clearFirst,           // textInput — clear before typing
  String? expectedText,      // assertText, assertValue
  double? scale,             // pinch
  String? dropdownValue,     // selectDropdown — match by value string
  int? dropdownIndex,        // selectDropdown — match by index
  double? sliderValue,       // setSliderValue — 0.0 to 1.0
  String? targetKey,         // scrollUntilVisible — widget to scroll to
  int? maxScrollAttempts,    // scrollUntilVisible — default 20
  String? label,             // tapByLabel — visible text to find
  int? expectedCount,        // assertCount — expected child count
})
```
