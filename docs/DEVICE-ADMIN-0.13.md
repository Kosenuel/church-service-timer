# W2 device administration evidence — 0.13

Date: 2026-10-18. Target: user's HD_W2 V6.02.232, 32×16; LedArt-Lite 2.3.14 (157). No password, Wi-Fi, program, scan or firmware setting changed during this investigation.

## Provenance

- `work/ledart/lib/arm64-v8a/libapp.so`, SHA-256 rechecked: `9397abf7ff63acd77ce871e743b3223428791996a822a0f1d3127be98334d878`.
- Existing artifact hashes and earlier physical results: `docs/w2-protocol-evidence.json`.
- Reused `work/hardware-diagnostics/dart-analysis.r2`, `dart-functions.json`, `dart-pool.json`, local radare2 6.2.4/r2flutter. Addresses below are ELF virtual addresses of this exact library, not APK offsets.
- Pool objects resolved with `r2flutter -j -O pp+0xOFFSET`. These are local static observations, not new REA MCP evidence IDs. No MCP setup/configuration changed.
- Earlier discovery/login/program-transfer tests do not validate the administration writes below.

## Static evidence ledger

| Anchor | Observation | Limit |
|---|---|---|
| CommandExtension.get:value0x8dfd58; PP+0x13ad0 | Wire commands getParameters27, setSpecifiedParam39, setDeviceLock49, setCardName8. | Complete map. Enum ordinals30/34 are not wire IDs. Packet.createHD7 calls map at0x8df878. |
| setDeviceLock0x8d5dd0, writes0x8d5ebc–0x8d5f24 | Password body prefix4, mode, length:u16BE, digest. | Exact sender; no physical change. |
| getHD7AesKey0x90b838 | Nonempty password digest is MD5(UTF8(password + fixed suffix below)). | Same function as verified login. |
| setDevicePwd0x983294, call0x9833a8 | New password passed to setter; old credentials used for authentication. | UI-to-command flow traced. |
| setSpecifyParametersNew0x92930c, writes0x9293a0–0x92944c | Header8, group:u8, parameter:u16BE, length:u32BE, raw data. | Command39, not UI request ID. |
| setSsid0x9836e8, new path0x98396c | UTF-8 SSID, group0/parameter4. Validation4–16 chars, regex `^[A-Za-z0-9_-]+$`. | Observed app limits, not all firmware limits. |
| setWifiNew0x9823e4, call0x9824d8 | Forwards group/parameter/data into command39 builder. | Confirms field layout/data flow. |
| Password callback0x983570–0x9835b4 | UTF-8 Wi-Fi password, group0/parameter5. | Follows device-lock transition; independent editing untested. |
| callback0x983488–0x9834e4; setPwd0x984eac | Device-password mode clears Wi-Fi password with empty parameter5. Wi-Fi-password mode first clears device lock, then sets parameter5. | Do not silently copy these cross-setting side effects. |
| SimpleColorCard.sync0xb2b310, store0xb2b7ac, PP+0x138b8 | Map key pwdComplexity becomes field0x6f. | Key resolved. |
| initState0x9e9568; readBackWiFiSetting0x984228; setSsid0x9836e8 | pwdComplexity>0 selects binary route; zero selects legacy TCP/JSON. | Dart true has bit4 clear; false has bit4 set. supportHD7 is separate. |
| parseFindCard0x8db718–0x8db768 | supportHD7 byte then pwdComplexity byte. | Existing exact224-byte mask: absolute offsets217/218; W2Probe.java agrees. Other masks change offsets. |
| parseFindCard0x8db76c–0x8db910; PP+0x138c0…0x138e0 | Mask byte10: bit0 apSsid64bytes, bit1 apPwd32, bit2 ip4, bit3 netmask4, bit5 hideSsid1, bit6 apChannel1, under apInfo. | String fields use Misc.parseString. Wi-Fi password read may expose secret. |
| getParametersForScanAll2 0x8da174 | Extended mask `00 0c ff 2d ec a9 61 00 00 d6 6f 01`. | Includes password; do not use blanket read unnecessarily. |
| createHttpGetData0x93ccdc; sendData0x93c844 | TCP6104 GET below;15-second receive wait. | Empty request target; no auth header found in builder. |
| WiFiSettingModelToJson0x93be14; AP0x93c12c; station0x93c034 | ap/station objects below. | Preserve original field values/types and unknown fields. |
| createHttpPostData0x975b1c; sendPostRequest0x9757e8 | JSON POST with UTF-8 byte length. | No Content-Type header in observed builder. |
| ScWifiSettingHelper.setWifiPassword0x9755d4 | Read model, change ap.password, POST. | Legacy Wi-Fi password field verified. |
| setWifiByHttp0x983a08 | Operation1 changes ap.ssid;2 changes ap.password. Reconstructs station state. | Do not copy station reset for a targeted edit. |

## Statically verified command bodies

Existing HD7 framing/session/encryption/HMAC/error checking still apply. Command-body integers below are big-endian. No administration write is physically verified yet.

Device password, command49:

```text
Nonempty: 04 02 00 10 || MD5(UTF8(newPassword + "64ACFEB8B6FE4EF082DB8F3CD428EB20"))
Empty:    04 00 00 00
```

Empty disables the lock; a blank form must not trigger this. No read-current-plaintext device connection password command was found. Show password can reveal an app-saved password, labelled as such.

Newer Wi-Fi, command39:

```text
08 || group:u8 || parameter:u16BE || byteLength:u32BE || bytes
SSID: group0, parameter4, UTF8(newSsid)
Wi-Fi password: group0, parameter5, UTF8(newWifiPassword)
Example SSID TEST_WIFI: 08 00 00 04 00 00 00 09 54 45 53 54 5f 57 49 46 49
```

Independent simultaneous device/Wi-Fi password protection is unknown. Do not automatically clear the other password simply because LedArt's mode-switch UI does so.

Legacy TCP6104 exact builder strings (escapes mean CRLF):

```text
GET  HTTP/1.1\r\nHost: <ip>:6104\r\nConnection: Keep-Alive\r\n
POST  HTTP/1.1\r\nHost: <ip>:6104\r\nConnection: Keep-Alive\r\nContent-Length: <UTF8-byte-count>\r\n\r\n<JSON>
```

No extra final blank line appears in GET builder. JSON fields: `ap={ssid,password,ip,netmask}`, `station={status,enable,ssid,password}`. Preserve readback primitive types/values/unknown fields; exact station primitive types remain unresolved. Result key is `success` (PP+0x12190), accepted value type unresolved. Nonempty response is not success evidence; disconnect during write is uncertain completion.

## Read-only validation plan and observations

1. First ADB attempt blocked; scoped permissions then permitted ADB. Phone wlan0 was192.168.1.17/24, not prior sign subnet192.168.10.0/24. No discovery sent to unrelated LAN.
2. On sign Wi-Fi send existing command27 mask `00 0c ff 0d ec a9 61 00 00 c6 00 01`. Validate HR magic, lengths, status, command, sequence, checksum, terminator and exact mask before reading numeric pwdComplexity atwire218. Do not log raw reply/UUID.
3. Minimal derived mask changing byte10 to01 requests SSID without password. Inferred from verified parser; validate actual mask/length. With other fields unchanged, SSID64bytes beginswire219 followed by chunk capacity. Old224-byte parser must not be reused unchanged.
4. If pwdComplexity==0, one TCP6104 GET is a candidate legacy read probe. Keep body in memory. Emit only keys/types/password-present flags and necessary public metadata; never raw response or secrets.
5. No writes during discovery/page load; no speculative command8 probes.

## Safe implementation and remaining unknowns

- Separate app-friendly name, advertised controller name and Wi-Fi SSID. setCardName8 exists but no payload/caller recovered; do not guess or change GUID.
- Require authenticated connection, explicit confirmation, no active service, and recovery guidance for password/network changes. After a device-password attempt, discard the app-saved credential and require entry on reconnect; the operator should retain both old and new details until verified. Ambiguous timeout requires verification, not success claims or blind retries.
- Wi-Fi changes may immediately disconnect; prepare new details/recovery first. No promise of seamless reconnection or rollback.
- Keep secrets out of logs/reports/fixtures/repository. App-saved device password is distinct from Wi-Fi readback.
- Gate features by demonstrated capability. Scan, polarity and firmware remain outside scope.
- Mode interactions, independent password protection, write ACK behavior, reboot requirements and readback confirmation need controlled physical tests on this exact firmware.

## Physical read-only result

2026-10-18: after operator reconnected phone to sign Wi-Fi, existing `W2Probe` running through ADB/app_process received a valid224-byte command27 response from192.168.10.1:6101. All HR header, sequence, checksum, terminator and expected-mask checks passed. Public fields:32×16, color0, model145, HD_W2 V6.02.232, protocol1, deviceLock2, HD7=1, **pwdComplexity=1**, packetLength4096. This establishes the newer binary route for the actual sign. No TCP6104 request, password read or administration write executed. A preliminary toybox-nc discovery got no reply; the existing Java probe succeeded. An extended SSID probe was drafted locally but was not deployed/executed and is not evidence of extended-query support.

`PasswordCheckUtils._checkPWD` at0x90bc20 additionally validates8–16 characters, rejects NUL/space, all-identical characters and whole-string constant codepoint-step sequences. `W2Administration.kt` uses a conservative printable-ASCII subset of these constraints for **new** passwords; existing-password login is unchanged. It exports pure command39/49 body builders without cross-clearing or network calls. `scripts/W2AdministrationChecks.kt` includes fixed independent digest/wire fixtures, bounds/invalid-input checks and capability gating.

Existing `W2Display.exchange` checks authenticated HD7 replies and status0. Command39/49 ACK behavior and continued validity of the old session after password changes have not been physically measured. Integration must close the session after an administration attempt and distinguish acknowledged requests from verified post-change settings. It must not reuse program-transfer success evidence as proof of credential/network changes.

Validation: compiled `W2Administration.kt` plus `W2AdministrationChecks.kt` with the retained Kotlin2.2.21 compiler on JDK21.0.12.1 using a writable temporary directory. All **36 standalone checks passed**. No transport executed in these tests.
