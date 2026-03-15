# Changelog

All notable changes to Zigmund are documented here, organized by feature area.

---

## Documentation

- Rewrite README ([#44](https://github.com/Softorize/zigmund/pull/44))

## Bug Fixes and Quality Improvements

- Fix IPv6 port-stripping bug and eliminate global state in middleware ([#43](https://github.com/Softorize/zigmund/pull/43))
- Fix remaining parity stubs ([#26](https://github.com/Softorize/zigmund/pull/26))
- Fix CI governance ripgrep issue ([#15](https://github.com/Softorize/zigmund/pull/15))
- Fix CI Linux regex opaque type issue ([#14](https://github.com/Softorize/zigmund/pull/14))
- Enable compression via czlib ([#13](https://github.com/Softorize/zigmund/pull/13))
- Fix CSRF test client memory leak ([#12](https://github.com/Softorize/zigmund/pull/12))
- Fix middleware memory leaks ([#10](https://github.com/Softorize/zigmund/pull/10))
- Fix Zig 0.15.2 API compatibility ([#9](https://github.com/Softorize/zigmund/pull/9))

## OpenAPI and Schema

- Add Swagger UI OAuth2 redirect, parameter examples, and schema defaults ([#42](https://github.com/Softorize/zigmund/pull/42))
- Separate input/output OpenAPI schemas ([#36](https://github.com/Softorize/zigmund/pull/36))
- OpenAPI generator cleanup ([#3](https://github.com/Softorize/zigmund/pull/3))

## Response Models

- Add computed response fields ([#41](https://github.com/Softorize/zigmund/pull/41))

## Request Handling

- Add discriminated union body parsing ([#40](https://github.com/Softorize/zigmund/pull/40))
- Add encoder content negotiation ([#35](https://github.com/Softorize/zigmund/pull/35))
- Add extra data type helpers ([#34](https://github.com/Softorize/zigmund/pull/34))
- Add nested model validation ([#33](https://github.com/Softorize/zigmund/pull/33))

## Middleware

- Add trusted host middleware ([#39](https://github.com/Softorize/zigmund/pull/39))
- Add HTTPS redirect middleware ([#37](https://github.com/Softorize/zigmund/pull/37))
- Add timeout middleware ([#30](https://github.com/Softorize/zigmund/pull/30))

## Streaming

- Add JSON Lines streaming support ([#38](https://github.com/Softorize/zigmund/pull/38))

## Observability

- Add correlation ID propagation ([#32](https://github.com/Softorize/zigmund/pull/32))
- Add health check endpoints ([#29](https://github.com/Softorize/zigmund/pull/29))

## API Design

- Add API versioning support ([#31](https://github.com/Softorize/zigmund/pull/31))
- Add RFC 7807 Problem Details error responses ([#28](https://github.com/Softorize/zigmund/pull/28))

## Security

- Add JWT HS256 signing ([#27](https://github.com/Softorize/zigmund/pull/27))

## Parity Examples

- Add reference parity examples ([#25](https://github.com/Softorize/zigmund/pull/25))
- Add how-to parity examples ([#24](https://github.com/Softorize/zigmund/pull/24))
- Add advanced parity examples, batch 2 ([#23](https://github.com/Softorize/zigmund/pull/23))
- Add advanced parity examples, batch 1 ([#22](https://github.com/Softorize/zigmund/pull/22))
- Add tutorial parity stubs ([#21](https://github.com/Softorize/zigmund/pull/21))
- Add tutorial security parity examples ([#20](https://github.com/Softorize/zigmund/pull/20))
- Add tutorial dependency parity examples ([#19](https://github.com/Softorize/zigmund/pull/19))
- Add tutorial body parity examples ([#18](https://github.com/Softorize/zigmund/pull/18))

## Refactoring

- Deduplicate parameter alias logic ([#17](https://github.com/Softorize/zigmund/pull/17))
- Decompose application god file into modules ([#11](https://github.com/Softorize/zigmund/pull/11))

## Enterprise and Hardening

- Add enterprise hardening baseline ([#16](https://github.com/Softorize/zigmund/pull/16))

## Audit and Stability

- Final tracker update ([#8](https://github.com/Softorize/zigmund/pull/8))
- Fix audit findings: items 13, 16, 18, 19, 30 ([#7](https://github.com/Softorize/zigmund/pull/7))
- Fix audit findings: app items 14, 23, 24, 37, 38 ([#6](https://github.com/Softorize/zigmund/pull/6))
- Fix audit findings: items 29, 11, 36, 15, 39, 40, 41, 42 ([#5](https://github.com/Softorize/zigmund/pull/5))
- Fix WebSocket audit items 7, 8, 12, 44 ([#4](https://github.com/Softorize/zigmund/pull/4))
- Fix audit findings, batch 1 ([#2](https://github.com/Softorize/zigmund/pull/2))
- P0 critical fixes from audit ([#1](https://github.com/Softorize/zigmund/pull/1))
