# Hermes Backend Protocol Draft

## Status

Draft based on installed Hermes Agent `0.18.2` source inspection.

This document defines only confirmed behavior. It is not a generic REST API.

## Endpoint

```swift
public struct HermesBackendEndpoint: Equatable, Sendable {
  public let baseURL: URL
  public let websocketURL: URL
}
```

Confirmed construction:

- HTTP base URL: `http://127.0.0.1:<port>`
- Status endpoint: `GET /api/status`
- JSON-RPC WebSocket endpoint: `ws://127.0.0.1:<port>/api/ws?token=<session-token>`

The Bridge must supply the port from its owned process launch. For loopback
mode, the client must use a Bridge-owned `HERMES_DASHBOARD_SESSION_TOKEN` value
and pass it as the `token` query parameter.

## Status And Version

```swift
public struct HermesBackendStatus: Decodable, Equatable, Sendable {
  public let version: String
  public let releaseDate: String?
  public let authRequired: Bool
  public let gatewayRunning: Bool
  public let gatewayState: String?
  public let activeAgents: Int?
  public let gatewayBusy: Bool?
  public let gatewayDrainable: Bool?
}
```

Confirmed source fields use JSON keys such as `version`, `release_date`,
`auth_required`, `gateway_running`, `gateway_state`, `active_agents`,
`gateway_busy`, and `gateway_drainable`.

## Backend Capabilities

```swift
public struct HermesBackendCapabilities: Equatable, Sendable {
  public let hermesVersion: String
  public let desktopBackendContract: Int?
  public let authMode: HermesBackendAuthMode
}

public enum HermesBackendAuthMode: Equatable, Sendable {
  case loopbackToken
  case oauthTicket
}
```

`desktopBackendContract` is confirmed in `session.create` and `session.info`
payloads as `desktop_contract`. Installed source defines value `3`.

## JSON-RPC Transport

Requests are JSON-RPC 2.0 frames sent over `/api/ws`:

```swift
public struct HermesRPCRequest<Params: Encodable>: Encodable {
  public let jsonrpc = "2.0"
  public let id: String
  public let method: String
  public let params: Params
}

public struct HermesRPCResponse<Result: Decodable>: Decodable {
  public let jsonrpc: String
  public let id: String?
  public let result: Result?
  public let error: HermesBackendError?
}
```

Server events are JSON-RPC notification frames:

```swift
public struct HermesBackendEvent<Payload: Decodable>: Decodable {
  public let type: String
  public let sessionID: String?
  public let payload: Payload?
}
```

The outer event frame uses method `event` and places this event object in
`params`.

## Run Request

Hermes source models a run as a session plus prompt submission.

```swift
public struct HermesRunRequest: Encodable, Equatable, Sendable {
  public let sessionID: String
  public let text: String
}
```

Confirmed RPC method:

- `prompt.submit`

Confirmed response shape:

```swift
public struct HermesRunSubmissionResult: Decodable, Equatable, Sendable {
  public let status: String
}
```

The confirmed streaming-start status is `streaming`.

## Run Identifier

```swift
public struct HermesRunIdentifier: Decodable, Equatable, Sendable {
  public let sessionID: String
  public let storedSessionID: String?
}
```

Confirmed source fields:

- `session_id`: short live UI session identifier.
- `stored_session_id`: durable session key returned by `session.create`.

## Run Status

```swift
public struct HermesRunStatus: Decodable, Equatable, Sendable {
  public let output: String?
}
```

Confirmed RPC method:

- `session.status`

The installed source returns a textual status summary under `output`; it is not
a stable structured run-state model.

## Cancellation

```swift
public struct HermesCancellationResult: Decodable, Equatable, Sendable {
  public let status: String
}
```

Confirmed RPC method:

- `session.interrupt`

Confirmed success status:

- `interrupted`

## Approval

```swift
public struct HermesApprovalRequest<Payload: Decodable>: Decodable, Equatable, Sendable {
  public let sessionID: String?
  public let payload: Payload?
}

public struct HermesApprovalResponse: Encodable, Equatable, Sendable {
  public let sessionID: String
  public let choice: String
  public let all: Bool?
}
```

Confirmed event:

- `approval.request`

Confirmed RPC method:

- `approval.respond`

Confirmed response field:

- `resolved`

## Error Envelope

```swift
public struct HermesBackendError: Decodable, Equatable, Sendable {
  public let code: Int
  public let message: String
}
```

Confirmed JSON-RPC error examples include parse error `-32700`, invalid request
`-32600`, invalid params `-32602`, unknown method `-32601`, internal error
`-32603`, and handler-defined application errors.

## Unsupported In This Draft

- Generic REST run endpoints.
- SSE event streams.
- Exhaustive capability endpoint.
- Exhaustive structured run status.
- Reconnection/resume guarantees beyond source-observed client behavior.
