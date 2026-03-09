import 'package:flutter/widgets.dart';

/// Tipos de widgets soportados por MCP
enum McpWidgetType {
  button,
  textField,
  text,
  list,
  card,
  image,
  container,
  dropdown,
  checkbox,
  radio,
  switchWidget,
  slider,
  tab,
  custom,
}

/// Key con metadata completa para MCP
/// Contiene toda la información necesaria para registro y eventos
class McpMetadataKey extends Key {
  /// Identificador único del widget (usado para acciones remotas)
  final String id;

  /// Tipo de widget
  final McpWidgetType widgetType;

  /// Descripción legible del widget
  final String? description;

  /// Contexto/pantalla donde se encuentra
  final String? screen;

  /// Tags adicionales para búsqueda/filtrado
  final List<String>? tags;

  /// Metadata adicional customizada
  final Map<String, dynamic>? customMetadata;

  const McpMetadataKey({
    required this.id,
    required this.widgetType,
    this.description,
    this.screen,
    this.tags,
    this.customMetadata,
  }) : super.empty();

  /// Obtener capabilities (acciones disponibles) basadas en el tipo de widget
  List<String> get capabilities {
    switch (widgetType) {
      case McpWidgetType.button:
        return [
          'tap',
          'long_press',
          'double_tap',
          'assert_exists',
          'assert_text',
        ];
      case McpWidgetType.textField:
        return ['tap', 'text_input', 'clear', 'assert_exists', 'assert_text'];
      case McpWidgetType.text:
        return ['assert_exists', 'assert_text'];
      case McpWidgetType.list:
        return ['scroll', 'swipe', 'assert_exists'];
      case McpWidgetType.image:
        return ['tap', 'assert_exists'];
      case McpWidgetType.card:
      case McpWidgetType.container:
        return ['tap', 'swipe', 'assert_exists'];
      case McpWidgetType.dropdown:
        return ['tap', 'select_dropdown', 'assert_exists'];
      case McpWidgetType.checkbox:
      case McpWidgetType.radio:
      case McpWidgetType.switchWidget:
        return ['tap', 'toggle', 'assert_exists', 'assert_selected'];
      case McpWidgetType.slider:
        return ['set_slider_value', 'assert_exists', 'assert_value'];
      case McpWidgetType.tab:
        return ['tap', 'assert_exists', 'assert_selected'];
      case McpWidgetType.custom:
        return ['tap', 'assert_exists'];
    }
  }

  /// Convertir a formato esperado por MCP Server Rust
  /// Compatible con example_widgets.json format
  Map<String, dynamic> toMcpFormat() {
    return {
      'key': id,
      'type': _getFlutterWidgetType(),
      if (description != null) 'label': description,
      if (description != null) 'description': description,
      if (customMetadata?['purpose'] != null)
        'purpose': customMetadata!['purpose'],
      'capabilities': capabilities,
      if (screen != null) 'screen': screen,
      if (tags != null && tags!.isNotEmpty) 'tags': tags,
    };
  }

  /// Mapear McpWidgetType a nombres de widgets Flutter reales
  String _getFlutterWidgetType() {
    switch (widgetType) {
      case McpWidgetType.button:
        return 'ElevatedButton';
      case McpWidgetType.textField:
        return 'TextField';
      case McpWidgetType.text:
        return 'Text';
      case McpWidgetType.list:
        return 'ListView';
      case McpWidgetType.card:
        return 'Card';
      case McpWidgetType.image:
        return 'Image';
      case McpWidgetType.container:
        return 'Container';
      case McpWidgetType.dropdown:
        return 'DropdownButtonFormField';
      case McpWidgetType.checkbox:
        return 'Checkbox';
      case McpWidgetType.radio:
        return 'Radio';
      case McpWidgetType.switchWidget:
        return 'Switch';
      case McpWidgetType.slider:
        return 'Slider';
      case McpWidgetType.tab:
        return 'Tab';
      case McpWidgetType.custom:
        return 'Widget';
    }
  }

  /// Convertir a JSON (usa formato MCP por defecto)
  Map<String, dynamic> toJson() => toMcpFormat();

  /// Crear desde JSON (útil para testing/mocking)
  factory McpMetadataKey.fromJson(Map<String, dynamic> json) {
    return McpMetadataKey(
      id: json['id'] as String,
      widgetType: McpWidgetType.values.firstWhere(
        (e) => e.name == json['widgetType'],
        orElse: () => McpWidgetType.custom,
      ),
      description: json['description'] as String?,
      screen: json['screen'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      customMetadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'McpMetadataKey(id: $id, type: ${widgetType.name}, screen: $screen)';
  }
}
