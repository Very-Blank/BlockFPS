# TODO:

List of things to ignore.

## TIER 1

- [ ] Player spawner.
- [ ] Add level editor/spawner view.
- [ ] Textures.
- [ ] Model loading.

## TIER 2

- [ ] Cheats like god mode etc.
- [ ] Proper outlines.
- [ ] Add tracy!

## DONE

- [x] Add proper icon font.
- [x] Multiselection and multi editing for inspector!
- [x] Add a higher quality font to ImGui.
- [x] Add highlight to selected objects.
- [x] Clean up ImGui windows.
- [x] Selecting position with click and selecting objects by shift click.

# FIXME

- [ ] Imguizmo's rotation gizmo perspective is fucked.
- [ ] If capsule.height <= capsule.radius -> CRASH.
- [ ] Translate tool, if avarage position changes because one or multiple bodies
      move it leads to incorrect translation.

## BUGS killed

- [x] Selection highlight incorrect.
- [x] Only syncInspector(true) if the window is open.
- [x] Pressing ecs again closes debug windows!
- [x] Reset player velocity when in debug windows.
