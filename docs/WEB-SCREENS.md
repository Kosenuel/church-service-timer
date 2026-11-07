# Web screens

While the host device shares to screens (**Live → Share to screens**), any browser on the same Wi-Fi can follow the service without the app: a laptop on a projector, a smart TV, a tablet, or people's own phones. Nothing needs the internet.

## Three views

| View | Shows | Opened with |
|---|---|---|
| **Order of service** | The rundown with the current item marked "Now". No times at all. Speakers only if **Show speakers** is on. | The guest code, or nothing when access is open |
| **Stage display** | The countdown, cues and quick messages, full screen | The team code |
| **Service overview** | Time left, ahead or behind, finish time, the full rundown with durations and speakers | The team code |

A browser that joined with the team code switches freely between all three. A browser that joined with the guest code can only open the order of service; switching up asks for the team code.

No view shows private operator notes, and no browser can control the service. Control stays in the app.

## Codes

| | Guest code | Team code |
|---|---|---|
| Created | Automatically (4 digits) | Automatically (6 digits), each time sharing starts |
| Changes | Only when you tap **Change guest code**; you can set 4–8 letters or digits | When sharing starts again, or with **New team code** |
| Use | On a slide, the bulletin or the join slide | Read out or shown to the team on the day |

Changing a code signs out the browsers that used the old one. After five wrong codes a browser waits 30 seconds, then longer with each further five.

**Order of service** access can be **Off**, **Needs the guest code** (the default) or **Open to anyone on this Wi-Fi**. At most 100 order-of-service browsers follow at once; stage displays and the team are never turned away by that limit.

## Opening the page

Screens & devices → **Web screens** shows three ways in:

1. **Easy name**, e.g. `grace-community.local:8080`. The phone announces it on the Wi-Fi itself (mDNS), so it keeps working when the phone's address changes. It is made from the church profile name, kept short (at most 20 characters: filler and generic words such as "the" or "church" are dropped, and long names become initials, e.g. `rccg-victory`), and can be edited. iPhones, iPads, Macs and most laptops open it; some Android phones do not.
2. **QR code**, which every phone camera reads.
3. **Address**, e.g. `192.168.1.23:8080`, as a last resort.

**Export join slide** makes an image (light or dark) with the church name, a large QR, the easy name, the guest code and the address, ready to project. Pick the screen it is for: 16:9 HD or 4K, 16:10, 4:3, Portrait 9:16 or Square. Each is laid out for its shape. If the phone's address changes afterwards, the panel says the slide is out of date.

## Requests from the stage

When **Requests from the stage** is on (Settings → Screens & devices), a Stage display opened with the team code shows a small **Request** button at the bottom left during a service. It offers three fixed choices: **Need 2 minutes**, **Ready to finish** and **Microphone issue**. The operator sees the request on Live and can acknowledge or dismiss it, or add 2 minutes for a time request. The button then shows "Sent", "Seen by operator" or "2 minutes added". Guest-code viewers never see it, a display can send at most one request every 5 seconds, and requests expire after 2 minutes.

## Limits

- The host device must stay open and on the same network, as for paired phones.
- Guest Wi-Fi often keeps devices apart ("client isolation"); phones on it cannot reach the host device. Use a network where devices can see each other, or the host device's hotspot.
- A printed address or QR stops working if the router gives the phone a new address. Ask for the phone's address to be reserved on the router, or show the join slide instead of printing it.
- The page is plain HTTP on the local network, protected by the codes. Browsers can only read what their view shows.
