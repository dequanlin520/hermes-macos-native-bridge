# Workspace Events

Workspace observation uses public AppKit notification centers:

- `NSWorkspace.shared.notificationCenter` for application launch,
  termination, active application changes, sleep/wake and screen sleep/wake;
- `DistributedNotificationCenter` for the documented screen lock and unlock
  notifications.

Application identity is reduced to:

- safe bundle identifier;
- bounded localized application name.

The bridge never emits executable path, PID, process arguments, environment,
window title, document title, URL, screen content, clipboard, keystrokes,
Prompt or backend token.

Observed workspace/session event kinds are:

- `applicationLaunched`
- `applicationTerminated`
- `activeApplicationChanged`
- `systemWillSleep`
- `systemDidWake`
- `screenDidSleep`
- `screenDidWake`
- `sessionLocked`
- `sessionUnlocked`
