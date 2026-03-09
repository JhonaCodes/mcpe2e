# E2E MCP Example

This example demonstrates how to use the `e2e_mcp` library in your Flutter app.

## Project Structure

```
example/
├── lib/
│   ├── main.dart           # Main app
│   └── mcp/
│       ├── mcp_keys.dart   # Widget metadata definitions
│       └── run.dart        # Server control script
└── pubspec.yaml
```

## Files

### mcp/mcp_keys.dart
Defines all widget metadata with IDs, types, descriptions, and purposes.

### mcp/run.dart  
Standalone script to start the MCP HTTP server.

### main.dart
Flutter app that registers widgets and uses the keys.

## Running

1. Start your Flutter app:
```bash
flutter run
```

2. In another terminal, start the MCP server:
```bash
dart lib/mcp/run.dart
```

3. Test the endpoints:
```bash
# Get widget context
curl http://localhost:7777/mcp/context | jq

# Tap a button
curl "http://localhost:7777/action?key=home_button"

# Input text
curl "http://localhost:7777/action?key=email_input&type=textinput&text=test@test.com"
```

## Integration with MCP Rust Server

The `/mcp/context` endpoint provides JSON that the Rust MCP server reads to generate tools for Claude Desktop.

See the main README for full documentation.
