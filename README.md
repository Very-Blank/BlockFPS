# TODO

List of things to ignore.

## TIER 1

- [ ] Player
  - [ ] Inventory
  - [ ] Items

- [ ] Test level with enemies.
  - [ ] Saving and loading.
  - [ ] Basic assets
    - [ ] Textures
    - [ ] Models

## TIER 2

- [ ] Make box colliders handle rotation.
- [ ] Sounds
- [ ] Cheats like god mode etc.
- [ ] Proper outlines.
- [ ] Lighting
- [ ] Add tracy!

## DONE

- [x] Debug windows remove hidden state by merging everything.
- [x] Model loading.
- [x] Friction.
- [x] Textures.
- [x] Player spawner.
- [x] Add basic level editor/spawner view.
- [x] Add proper icon font.
- [x] Multiselection and multi editing for inspector!
- [x] Add a higher quality font to ImGui.
- [x] Add highlight to selected objects.
- [x] Clean up ImGui windows.
- [x] Selecting position with click and selecting objects by shift click.

# FIXME

- [ ] Imguizmo's rotation gizmo perspective is fucked.
- [ ] If capsule.height <= capsule.radius -> CRASH.
- [ ] Closing the launcher from close button:
  - [ ] Doesn't clear highlight's and probably also selections.
  - [ ] Doesn't remove gizmos/leaves the current tool on.
  - [ ] Doesn't enable inspector.

## BUGS POISONED

- [-] Translate tool, if avarage position changes because one or multiple bodies
  move it leads to incorrect translation.

```
velocity.y = 0
```

## BUGS SQUASHED

- [x] Disable and gray out inspector properties when not in select mode.
- [x] Hide outline from model properties.
- [x] Selection highlight incorrect.
- [x] Only syncInspector(true) if the window is open.
- [x] Pressing ecs again closes debug windows!
- [x] Reset player velocity when in debug windows.
