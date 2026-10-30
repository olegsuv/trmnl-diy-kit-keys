# All three keys for the TRMNL 7.5" DIY Kit

A patch for [TRMNL firmware](https://github.com/usetrmnl/trmnl-firmware) v1.8.18 on the
**TRMNL 7.5" (OG) DIY Kit** (Seeed EE04 carrier board + XIAO ESP32-S3 Plus). It makes
all three keys on the board useful, and fast:

- **KEY1, KEY2 and KEY3 all wake the device** and tell the server which one it was.
  Stock firmware only wires up KEY3.
- **Instant screen switching.** The device keeps the current image for each key on
  flash. A key press draws its screen straight from flash, before Wi-Fi is even up.
  It then asks the server and only redraws if that screen changed since it was cached.
- **Presses are never lost.** After a press the device spends ~10 s talking to the
  server. A key pressed during that time used to do nothing; now it is remembered and
  handled as soon as the device would otherwise go to sleep.
- **Optional built-in Wi-Fi** network, used whenever none is saved, so a Wi-Fi reset
  does not send you back to the captive portal.

It needs a server that sends one image per key — see [Server side](#server-side). With
a stock server the keys still wake the device and report themselves; there is just no
cache.

| key | GPIO | does |
|-----|------|------|
| KEY1 | 2 | wake, screen 1 |
| KEY2 | 3 | wake, screen 2 |
| KEY3 | 5 | wake, screen 3; long press still resets Wi-Fi, double click still runs the special function |

Tested on one kit, on firmware v1.8.18, against a self-hosted
[BYOS](https://docs.usetrmnl.com/go/diy/byos) server. Not affiliated with TRMNL.

## Build and flash

```sh
pip install platformio
cp wifi.local.example wifi.local   # optional: built-in Wi-Fi, git-ignored
./build.sh COM3                    # or /dev/ttyACM0; no port = build only
```

`build.sh` clones the firmware into `../trmnl-firmware-keys` (short path: ESP-IDF builds
break on long Windows paths), resets it to the tag, applies `keys.patch` and builds the
`TRMNL_7inch5_OG_DIY_Kit` environment. Saved Wi-Fi and server pairing survive flashing.

The board is only on USB while awake. If the port is missing, `build.sh` waits for it:
**press KEY1 briefly**. Do not hold KEY3 for that — a long KEY3 press is the stock
"forget Wi-Fi" gesture.

Flashing stock firmware from usetrmnl.com/flash undoes all of this.

## Server side

### Which key was pressed

`/api/display` gets `Update-Source: key1`, `key2` or `key3` instead of the stock wake
reasons, with what the cache did appended:

```
key2;cache=hit            drawn from flash
key2;cache=miss           nothing cached for that key yet
key2;cache=bad            cached file unreadable (deleted; normal download follows)
key2;cache=same           that screen was already on the panel
key3;cache=hit;deferred   KEY3 was pressed while the device was still busy
```

Timer wake-ups keep sending `timer`. A server should remember the last key per device
and keep serving that screen on timer polls. Strip everything after the first `;` before
matching.

### One image per key

Add `key_images` to the `/api/display` response: the current image for KEY1..KEY3, in
that order ([example](examples/display-response.json)). The device:

- downloads each one whose `filename` differs from what it has cached, into
  `/key1.png`..`/key3.png` (only PNGs are cached);
- draws the current screen from that cache when `filename` matches one of the
  `key_images`.

`filename` is the cache key, so it has to change exactly when the picture does. Hash the
data you draw, plus a fingerprint of your rendering code, or a new font or layout will
never reach devices that already cached a screen with the same data.

### Serve 1-bit PNGs, not BMPs

Worth doing with or without this patch. v1.8.18 caches PNGs under their filename and
forces a full refresh every 8th update. For BMPs it does neither, and draws every BMP
with a partial update, forever. Ghosting builds up and the panel looks washed out until
a reset. An 800x480 1-bit grayscale PNG is also ~2-5 KB instead of 48 KB.

## How it works

`keys.patch` touches:

- **`sleep_session.cpp`**: ext1 wake on any of the three keys (`ANY_LOW`). The RTC
  pull-ups only hold with the RTC peripherals powered in deep sleep, which costs a
  little extra sleep current.
- **`bl.cpp`**: works out which key woke the device and draws its cached image before
  Wi-Fi. KEY3 keeps the stock long-press and double-click handling.
- **`key_cache.cpp`** (new):
  - the flash cache;
  - redraws: one fast full refresh when switching screens, partial for the same screen;
  - presses latched while the device is awake: the device sleeps for 1 ms and wakes up
    as if that key had woken it.
- **`display_session.cpp`**: hooks the cache into the normal `/api/display` flow.
- **`parse_response_api_display.cpp`**: parses `key_images`.
- **`header.cpp`**: sends the `Update-Source` above.
- **`filesystem.cpp`**: the stock purge of old images skips the `/key*.png` files.
- **`WifiCaptive.cpp`**: falls back to the compiled-in network.

## Licence

GPL-3.0, like the TRMNL firmware it patches.
