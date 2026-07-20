# Network Events

Network observation uses `Network.framework` through `NWPathMonitor`.

The bridge reports:

- availability: `available`, `unavailable` or `unknown`;
- interface summary: `wiredEthernet`, `wifi`, `cellular`, `loopback`, `other`,
  `unavailable` or `unknown`;
- expensive state;
- constrained state.

The monitor is idempotent on start and stop, runs on a dedicated queue and
debounces duplicate path states. It does not capture IP addresses, SSIDs, DNS
servers, router addresses, host names or network payload content.

The broker emits only typed network event kinds:

- `networkAvailable`
- `networkUnavailable`
- `networkInterfaceChanged`
- `networkExpensiveChanged`
- `networkConstrainedChanged`
