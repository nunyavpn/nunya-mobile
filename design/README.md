# Design

Nunya on a phone, screen by screen. Each screen is shown light, then dark.

| | |
| --- | --- |
| **Tabs** | Home (the connection over the map), Servers, Settings. Bypass rules, Diagnostics and Support live in Settings. Every tab icon has a label. |
| **Touch** | Every target is 44px or more, rows are 64px, and Connect is 56px and full width, where the thumb rests. |
| **Spacing** | 16px gutters and 18–24px corners. Only the map and a selected row's tint reach the screen's edge. |
| **Type** | Titles 30/800, the state 22/800, rows 16/700 with 13 under, labels 11.5 capitals, fields 16 so the page never zooms. |
| **The connection** | On Home, a sheet over the map. On every other tab, a one-line bar above the tabs. |
| **Honesty** | In proxy mode, “only apps set to use it” stays on the sheet and the bar, closed or open. |

## Home

The map fills the screen and the connection is a sheet over it. Closed, the sheet shows the state, the server and Connect; dragged up, it shows traffic and addresses. Pinch and drag move the map; there are no zoom buttons.

**Off**

<img src="screens/off-light.png" width="300" alt="Off, light"> <img src="screens/off-dark.png" width="300" alt="Off, dark">

**Connecting**

<img src="screens/connecting-light.png" width="300" alt="Connecting, light"> <img src="screens/connecting-dark.png" width="300" alt="Connecting, dark">

**Connected**

<img src="screens/connected-light.png" width="300" alt="Connected, light"> <img src="screens/connected-dark.png" width="300" alt="Connected, dark">

**Connected sheet dragged up**

<img src="screens/connected-sheet-dragged-up-light.png" width="300" alt="Connected sheet dragged up, light"> <img src="screens/connected-sheet-dragged-up-dark.png" width="300" alt="Connected sheet dragged up, dark">

## Servers

One full-width list. The selected server is tinted edge to edge, under its own ⋯. The connection rides above the tabs, so Connect is one tap away from any row.

**Servers connected**

<img src="screens/servers-connected-light.png" width="300" alt="Servers connected, light"> <img src="screens/servers-connected-dark.png" width="300" alt="Servers connected, dark">

**Row actions**

<img src="screens/row-actions-light.png" width="300" alt="Row actions, light"> <img src="screens/row-actions-dark.png" width="300" alt="Row actions, dark">

## Sheets

Everything that was a dialog on the desktop rises from the bottom, with its actions at thumb height.

**Add servers**

<img src="screens/add-servers-light.png" width="300" alt="Add servers, light"> <img src="screens/add-servers-dark.png" width="300" alt="Add servers, dark">

**Vpn mode before android asks**

<img src="screens/vpn-mode-before-android-asks-light.png" width="300" alt="Vpn mode before android asks, light"> <img src="screens/vpn-mode-before-android-asks-dark.png" width="300" alt="Vpn mode before android asks, dark">

## Settings

Grouped rows. Mode is a choice between two named things, because they cover different amounts of the phone.

**Settings**

<img src="screens/settings-light.png" width="300" alt="Settings, light"> <img src="screens/settings-dark.png" width="300" alt="Settings, dark">

## The board

The screens were drawn from [board/](board/README.md), a page that renders each one with the desktop app's own colours, icons, flags and map. `nonya.png` is the app's artwork.
