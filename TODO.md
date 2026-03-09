# mcpe2e — TODO

## [x] tap_at — Tap por coordenadas absolutas ✅ IMPLEMENTADO

Flujo: `inspect_ui` → obtener x,y del widget → `tap_at x: 155 y: 244`

- Flutter lib: `McpEventType.tapAt`, `McpEventParams.dx/dy`, `_tapAt()`, parser en `/action`
- MCP server: tool `tap_at` con params `x`, `y` → `GET /action?key=_&type=tapat&dx=$x&dy=$y`
