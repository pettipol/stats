# Disk module: uncaught NSException in `NSGridView.removeRow(at:)` → SIGABRT on macOS 26 (Tahoe)

## Environment
- macOS 26.5.1 (Tahoe), build 25F80 — Apple Silicon (arm64)
- Stats 3.0.5 (build 810), notarized Developer ID build
- Reproduced on both the released `.app` and a local debug build

## Symptom
Stats crashes shortly after launch (often before/just after placing its menu bar items, so the
menu bar appears empty), with no user interaction. `EXC_CRASH / SIGABRT`, `abort() called`.

## Faulting backtrace (thread 0, main queue)
```
9  objc_exception_throw
10 -[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:]
11 -[NSGridView removeRowAtIndex:] +180
12 Disk  (+148888)                              // Modules/Disk/preview.swift teardown
13 Disk  (+31144)
14 _dispatch_call_block_and_release             // Preview.capacityCallback, dispatched to main
...
29 -[NSApplication run]
```

## Root cause
`Preview` (Modules/Disk/preview.swift) keeps an `NSGridView` (`self.disks`) with one data row +
one separator row per non-boot disk. On every `capacityCallback`, rows for disks that dropped out
of the current reading are removed one-by-one via `removeRow(at:)`.

Two problems make `-[NSGridView removeRowAtIndex:]` raise an (uncaught) `NSRangeException`:

1. **Cell views are detached before the row is removed.**
   `row.cells.forEach { $0.removeFromSuperview() }` runs *before* `removeRow(at:)`, which desyncs
   NSGridView's internal row/cell bookkeeping. On macOS 26 this trips an internal consistency
   assertion inside `removeRowAtIndex:` (the `+180` frame).

2. **Indices are only guarded against `NSNotFound`.**
   `removeRow(at:)` also throws for an index `>= numberOfRows`, or for a `NSGridRow` reference that
   shifted after a previous removal in the same pass. `index(of:) != NSNotFound` is not sufficient.

The `previewView` is instantiated unconditionally (`private let previewView = Preview(.disk)` in
Modules/Disk/main.swift) and is fed on every reading, so the buggy path runs in the background
regardless of whether the popup/settings window is open. It fires whenever the mounted-disk set
changes; machines with several external disks (which mount/unmount/spin down) hit it reliably.

## Repro
1. Enable the Disk module on macOS 26.
2. Attach 2+ external disks and let them mount/unmount (or sleep/spin down).
3. Stats aborts within seconds–minutes; menu bar items disappear.

## Proposed fix (Modules/Disk/preview.swift)
- Add a helper that removes a row only when it is still present at a valid, identity-matched index:
  ```swift
  private func removeGridRow(_ target: NSGridRow?) {
      guard let target = target else { return }
      let idx = self.disks.index(of: target)
      guard idx != NSNotFound, idx >= 0, idx < self.disks.numberOfRows else { return }
      guard self.disks.row(at: idx) === target else { return }
      self.disks.removeRow(at: idx)
  }
  ```
- Remove the grid rows FIRST, then detach cell views; clear `gridRow`/`separatorRow` after removal.
- Guard the initial column placement with `self.disks.numberOfColumns >= 3` (latent range-exception
  on `column(at:)` if a row is ever added with fewer cells).

## Workaround for users
Disable the Disk module (Settings → Modules), or:
`defaults write eu.exelban.Stats Disk_state -bool false` with Stats quit, then relaunch.
