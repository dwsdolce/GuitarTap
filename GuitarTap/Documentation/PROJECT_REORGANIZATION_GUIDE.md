# Project Reorganization Guide

## Overview

This guide explains how to reorganize your FFT analyzer project with a clean folder structure separating views, models, and documentation.

---

## Recommended Folder Structure

```
GuitarTap/
├── GuitarTapApp.swift        (Main app entry point)
│
├── Models/
│   └── RealtimeFFTAnalyzer.swift       (FFT processing logic)
│
├── Views/
│   ├── ContentView.swift               (Main view)
│   ├── SpectrumView.swift              (Spectrum chart view)
│   ├── FFTAnalysisMetricsView.swift    (Full metrics panel)
│   ├── CompactFFTMetricsOverlay.swift  (Compact overlay)
│   └── ContentViewWithMetrics.swift    (Example integration)
│
└── Documentation/
    ├── README_METRICS.md
    ├── COMPLETE_SUMMARY.md
    ├── BEFORE_AFTER_COMPARISON.md
    ├── IMPLEMENTATION_SUMMARY.md
    ├── INTEGRATION_COMPLETE.md
    ├── PLATFORM_INTEGRATION_GUIDE.md
    ├── QUICK_REFERENCE_CARD.md
    ├── VISUAL_LAYOUT_GUIDE.md
    ├── FFT_METRICS_DOCUMENTATION.md
    └── FFT_METRICS_QUICK_START.md
```

---

## Step-by-Step Reorganization

### Step 1: Create Folder Groups in Xcode

1. Right-click on your project in the Project Navigator
2. Select "New Group" → Name it "Models"
3. Repeat for "Views" and "Documentation"

### Step 2: Move Files to Appropriate Groups

#### Move to Models/
- **RealtimeFFTAnalyzer.swift**
  - Drag into Models group
  - Core FFT processing logic

#### Move to Views/
- **ContentView.swift** (already there)
- **SpectrumView.swift** (extract from ContentView - see below)
- **FFTAnalysisMetricsView.swift**
- **CompactFFTMetricsOverlay.swift**
- **ContentViewWithMetrics.swift** (example/reference)

#### Move to Documentation/
- **README_METRICS.md**
- **COMPLETE_SUMMARY.md**
- **BEFORE_AFTER_COMPARISON.md**
- **IMPLEMENTATION_SUMMARY.md**
- **INTEGRATION_COMPLETE.md**
- **PLATFORM_INTEGRATION_GUIDE.md**
- **QUICK_REFERENCE_CARD.md**
- **VISUAL_LAYOUT_GUIDE.md**
- **FFT_METRICS_DOCUMENTATION.md**
- **FFT_METRICS_QUICK_START.md**

### Step 3: Extract SpectrumView from ContentView

The SpectrumView is currently embedded in ContentView.swift. Here's how to extract it:

1. **Create new file:** Views/SpectrumView.swift
2. **Copy the following from ContentView.swift:**
   - `SpectrumDataPoint` struct (lines ~27-37)
   - `SpectrumView` struct (lines ~39-372)
3. **Add imports to new file:**
   ```swift
   import SwiftUI
   import Charts
   ```
4. **Remove from ContentView.swift** (keep the file but delete SpectrumView code)
5. **ContentView.swift will automatically import** SpectrumView (same module)

---

## Detailed File Moves

### Models Group

| File | Current Location | New Location | Purpose |
|------|-----------------|--------------|---------|
| RealtimeFFTAnalyzer.swift | Root | Models/ | FFT processing engine |

### Views Group

| File | Current Location | New Location | Purpose |
|------|-----------------|--------------|---------|
| ContentView.swift | Root | Views/ | Main app view |
| SpectrumView.swift | (extract) | Views/ | Spectrum chart component |
| FFTAnalysisMetricsView.swift | Root | Views/ | Full metrics panel |
| CompactFFTMetricsOverlay.swift | Root | Views/ | Compact metrics overlay |
| ContentViewWithMetrics.swift | Root | Views/ | Example implementation |

### Documentation Group

| File | Current Location | New Location | Purpose |
|------|-----------------|--------------|---------|
| README_METRICS.md | Root | Documentation/ | Main metrics documentation |
| COMPLETE_SUMMARY.md | Root | Documentation/ | Full metrics overview |
| BEFORE_AFTER_COMPARISON.md | Root | Documentation/ | Visual before/after |
| IMPLEMENTATION_SUMMARY.md | Root | Documentation/ | Implementation details |
| INTEGRATION_COMPLETE.md | Root | Documentation/ | Integration status |
| PLATFORM_INTEGRATION_GUIDE.md | Root | Documentation/ | Platform layouts |
| QUICK_REFERENCE_CARD.md | Root | Documentation/ | One-page reference |
| VISUAL_LAYOUT_GUIDE.md | Root | Documentation/ | Layout strategies |
| FFT_METRICS_DOCUMENTATION.md | Root | Documentation/ | Technical deep dive |
| FFT_METRICS_QUICK_START.md | Root | Documentation/ | Code examples |

---

## After Reorganization

### Clean Root Directory
```
GuitarTap/
├── GuitarTapApp.swift
├── Models/
├── Views/
└── Documentation/
```

### Import Statements

After reorganization, all imports remain the same since files are in the same module:

```swift
// No changes needed - SwiftUI automatically finds types in same module
// These will continue to work:
let analyzer = RealtimeFFTAnalyzer(...)
FFTAnalysisMetricsView(analyzer: analyzer)
SpectrumView(frequencies: ...)
```

---

## Benefits of Reorganization

### ✅ Improved Navigation
- Quickly find views vs. models
- Documentation separate from code
- Logical grouping

### ✅ Better Collaboration
- Clear project structure for team members
- Easy to understand file purposes
- Standard iOS/macOS project layout

### ✅ Easier Maintenance
- Related files grouped together
- Documentation in one place
- Views isolated from business logic

### ✅ Scalability
- Room to add more views
- Room to add more models
- Room to add more docs

---

## Alternative: Git-Based Reorganization

If you want to preserve file history in Git:

```bash
# Navigate to project directory
cd GuitarTap

# Create folders
mkdir -p Models Views Documentation

# Move files (Git will track renames)
git mv RealtimeFFTAnalyzer.swift Models/
git mv FFTAnalysisMetricsView.swift Views/
git mv CompactFFTMetricsOverlay.swift Views/
git mv ContentViewWithMetrics.swift Views/
git mv *.md Documentation/

# Extract SpectrumView manually in Xcode
# (Create Views/SpectrumView.swift and copy code)

# Update Xcode project to reflect new structure
# (Drag files in Xcode Project Navigator)

# Commit
git commit -m "Reorganize project structure: separate views, models, and documentation"
```

---

## Verification Checklist

After reorganization:

- [ ] Project builds successfully
- [ ] All imports resolve correctly
- [ ] No broken references
- [ ] App runs on all platforms (iOS, iPad, Mac)
- [ ] Git history preserved (if using git mv)
- [ ] Xcode project file updated
- [ ] Documentation accessible
- [ ] Code navigation improved

---

## Troubleshooting

### Issue: "Cannot find 'SpectrumView' in scope"
**Solution:** Ensure SpectrumView.swift is added to the target (check File Inspector)

### Issue: Git shows deleted files
**Solution:** Use `git mv` instead of moving in Finder/Xcode first

### Issue: Xcode project won't build
**Solution:** Clean build folder (Cmd+Shift+K), then rebuild

### Issue: Files in wrong location in Finder
**Solution:** Xcode groups ≠ folder structure. Create physical folders, move files in Finder, then re-add to Xcode

---

## Next Steps

1. **Create the folder structure** in Xcode (groups)
2. **Move files** one at a time, testing build after each
3. **Extract SpectrumView** to its own file
4. **Clean and rebuild** to verify everything works
5. **Commit changes** if using version control

---

## Quick Command Reference

### Xcode Shortcuts
- **New Group:** Cmd+Opt+N (or right-click → New Group)
- **Move File:** Drag in Project Navigator
- **Clean Build:** Cmd+Shift+K
- **Build:** Cmd+B

### Useful Xcode Menu Items
- **File → New → Group** - Create new folder group
- **Editor → Show All Issues** - See build errors
- **Product → Clean Build Folder** - Reset build

---

Your project will be much more organized and maintainable after this reorganization! 🎉
