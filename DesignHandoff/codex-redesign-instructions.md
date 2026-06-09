# iOS Redesign Instructions for Codex

## Goal

Implement the new redesigned dashboard UI from the Figma/React handoff into the existing iOS app.

The design files are in:

- DesignHandoff/App.tsx
- DesignHandoff/App_Design.pdf
- DesignHandoff/theme.css

Use these as the source of truth for the visual design.

## Very important rules

1. Do not rewrite the whole app.
2. Do not change the Bluetooth/device connection logic.
3. Do not change sleep tracking algorithms.
4. Do not change existing data models unless absolutely necessary.
5. Do not remove existing real data bindings.
6. Do not hardcode fake health/sleep/recovery data if real app data already exists.
7. Only redesign the SwiftUI interface and reusable UI components.
8. Implement screen by screen.
9. Start with the main dashboard/home screen only.
10. After every step, build the app and fix compile errors.

## Design reference

The React prototype in `DesignHandoff/App.tsx` represents the intended dashboard design.

Translate the React/Tailwind design into native SwiftUI.

Use SwiftUI equivalents:

- `div` containers → `VStack`, `HStack`, `ZStack`, `ScrollView`
- Tailwind dark background → SwiftUI `Color`
- rounded cards → `RoundedRectangle` backgrounds
- progress rings → SwiftUI `Circle().trim(...)`
- lucide icons → SF Symbols where possible
- bottom navigation → native SwiftUI custom tab bar or existing app navigation

## Main dashboard requirements

The dashboard should have:

### 1. Dark WHOOP-style background

Use a very dark background similar to:

- Main background: `#090A0C`
- Card background: `#1C1E22`
- Card border: `#2A2D33`

### 2. Top date selector

At the top center:

- Left chevron
- Text: `TODAY`
- Right chevron

Style:

- Small rounded pill
- Dark gray background
- White/gray text

### 3. App title

Under the date selector, show the app name.

The design note says the title should say:

`Whose`

Use the exact app name that already exists in the iOS app if different.

### 4. Remove unwanted top-left circle/avatar

The handwritten PDF note says to remove the small top-left circle/avatar labeled `BS`.

Do not implement that.

### 5. Main progress rings

Create three progress rings:

- Sleep
- Recovery
- Strain

Visual style:

- Circular rings
- Value in the center
- Small uppercase label below
- Sleep color: blue
- Recovery color: yellow
- Strain color: blue/cyan

Use real app values if available.

If real data is missing, use placeholders only temporarily and add a TODO comment.

### 6. AI insights card

Create a card under the rings.

The handwritten note says:

- This is where AI insights will appear when AI is connected.
- It should not say “placeholder”.
- Use something like `AI Insights` or a real generated insight if available.

For now, implement:

Title/content example:

`AI Insights`
`Your recovery and HRV trends will appear here once insights are available.`

Do not add a separate chat feature.

### 7. Health Monitor and Stress Monitor cards

Create two small cards side by side:

- Health Monitor
- Stress Monitor

Style:

- Dark cards
- Rounded corners
- Thin border
- Small uppercase headings
- Right chevron
- Compact metric content

Use existing app data if available.

### 8. My Day section

Add section title:

`My Day`

Add a plus button on the right if appropriate.

### 9. Daily Outlook row

Create a row/card:

- Icon
- Text: `Your Daily Outlook`
- Chevron on the right

### 10. Today’s Activities card

Create a card:

Title:

`TODAY'S ACTIVITIES`

Content should show activities such as:

- Sleep
- Workout
- Other tracked activity

The handwritten note says this area contains activities like workout and sleep.

Use existing app activity/sleep data if available.

Include action buttons:

- `ADD ACTIVITY`
- `START ACTIVITY`

Only wire these buttons to existing functionality if it already exists. Otherwise, leave safe TODO comments.

### 11. Tonight’s Sleep card

Create a card:

Title:

`TONIGHT'S SLEEP`

Include:

- Recommended bedtime
- Alarm/wake time
- `SET ALARM` button

Use existing sleep recommendation/alarm data if available.

### 12. Today’s Agenda instead of Journal

The handwritten PDF note says:

- Replace `My Journal` with a to-do list.
- It should say `TODAY'S AGENDA`.
- User can add todo items.
- User can tick items off.

Implement a simple local SwiftUI todo UI if no existing todo model exists.

Required behavior:

- Show list of todo items.
- Allow checking/unchecking.
- Allow adding a new todo.
- Allow editing/deleting if simple to implement.
- Use `@State` for now if the app has no persistence layer.
- If the app already has storage, use the app’s existing storage pattern.

### 13. Bottom navigation

The design currently has bottom navigation.

Handwritten notes say:

- Remove the community/chat feature.
- Remove the floating circular WHOOP/W button on the bottom right.

So implement bottom navigation without:

- Community
- Chat
- Floating W button

Keep only the real app tabs that exist.

Suggested tabs:

- Home
- Health
- More

If the existing app already has a working tab structure, preserve it and only restyle it.

## Implementation strategy

First, inspect the existing iOS project and identify:

- Current Home/Dashboard SwiftUI view
- Existing tab bar/navigation code
- Existing health/sleep/recovery/strain data models
- Existing components for cards or progress rings
- Existing colors/theme files

Then create or update reusable SwiftUI components:

- `DashboardCard`
- `ProgressRingView`
- `MetricCard`
- `TodayAgendaView`
- `BottomNavBar` only if the app uses a custom tab bar

Do not duplicate large code unnecessarily.

## Files likely to change

You should find the real file names first. Likely examples:

- `HomeView.swift`
- `DashboardView.swift`
- `MainTabView.swift`
- `ContentView.swift`
- `Theme.swift`
- `Assets.xcassets`

Do not assume these names. Search the project first.

## Output after implementation

After implementing the Home/Dashboard redesign, report:

1. Files changed
2. What was implemented
3. What existing data was reused
4. What is still TODO
5. Whether the app builds successfully