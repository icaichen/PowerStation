# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PowerStation is a macOS productivity application that provides window management and workstation organization capabilities. It's built using SwiftUI and requires accessibility permissions to control other applications' windows.

## Build Commands

```bash
# Build the project
xcodebuild -project PowerStation.xcodeproj -scheme PowerStation build

# Clean and build
xcodebuild -project PowerStation.xcodeproj -scheme PowerStation clean build

# Run the application (after building)
open /Users/chencai/Library/Developer/Xcode/DerivedData/PowerStation-*/Build/Products/Debug/PowerStation.app
```

## Architecture

The application is structured as a single-file SwiftUI app (`PowerStationApp.swift`) with the following key components:

### Core Classes
- **WindowManager**: Singleton class managing window operations, workstation storage, and accessibility API interactions
- **AppDelegate**: Handles system integration including status bar, global hotkeys, and accessibility permissions

### Key Data Models
- **WindowInfo**: Represents application window metadata (position, size, app info)
- **Workstation**: Collections of window arrangements that can be saved and restored
- **SplitPosition**: Enum defining window split layouts (left, right, top, bottom, quarters, etc.)
- **LayoutPreset**: Predefined window arrangements for common use cases

### SwiftUI Views
- **ContentView**: Main tabbed interface with workstation management and window splitting
- **WorkstationListView**: Displays saved workstations with load/delete functionality
- **WindowSplitterView**: Interface for applying window layouts to active applications
- **AppSwitcherView**: Grid view of running applications for window management
- **SettingsView**: Application preferences and configuration

### System Integration
- **Status Bar**: Menu bar icon (⊞) with quick access to main functions
- **Global Hotkeys**: Cmd+Opt+S/T for saving workstations, Cmd+Opt+1-4 for window splits
- **Accessibility API**: Uses AXUIElement for window positioning and resizing
- **Permissions**: Requires accessibility and Apple Events permissions for window control

## Dependencies

- **SwiftUI**: UI framework
- **Combine**: For `@Published` properties and reactive updates
- **Cocoa**: AppKit integration for window management
- **Carbon**: System-level keyboard event handling
- **Accessibility Framework**: Window manipulation via AXUIElement APIs

## Important Implementation Notes

### Accessibility Requirements
The app requires accessibility permissions to function. It uses AXUIElement APIs to:
- Get window information from other applications
- Move and resize windows programmatically
- Monitor window changes

### Entitlements
The app disables sandboxing and requires specific entitlements:
- `com.apple.security.app-sandbox`: false
- `com.apple.security.automation.apple-events`: true
- Apple Events exceptions for Finder and System Events

### Data Persistence
Workstations are saved to UserDefaults as JSON data. The WindowManager handles serialization/deserialization of window arrangements.

### Global Hotkey Implementation
Uses NSEvent.addGlobalMonitorForEvents to capture system-wide keyboard shortcuts for window management operations.