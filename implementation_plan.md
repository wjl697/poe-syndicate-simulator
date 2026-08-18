# Implementation Plan: Sandbox Mode Setup Wizard and Integration

This plan outlines the implementation of the Sandbox Mode Setup Wizard and the corresponding integrations in `game_manager.gd`, `action_logic.gd`, `card_action_overlay.gd`, and `main.gd`.

## Proposed Changes

### 1. Autoload Game State (`scripts/autoloads/game_manager.gd`)
We will add class-level tracking for the inactive bench members and expose helpers to initialize sandbox mode.

- **State Variables**:
  - Add `var bench_pool: Array[String] = []` to globally track the 3 excluded members.
- **Game Initialization**:
  - Update `_assign_members_randomly()` to populate the class-level `bench_pool` with the 3 names of bench members.
- **Undo / State Restore**:
  - In `save_state()`, duplicate `bench_pool` into `state.bench_pool`.
  - In `undo()`, restore `bench_pool` from `state.bench_pool`.
- **Sandbox Initialization Helper**:
  - Implement `func initialize_sandbox_mode(active_names: Array[String])`:
    - Set `is_sandbox_mode = true`.
    - Set `is_on_board = true`, `is_revealed = true`, and clear divisions/roles/ranks for the 14 active names.
    - Set `is_on_board = false` and add the remaining 3 names to `bench_pool`.
    - Clear relationships.
    - Emit `board_changed.emit()`.

### 2. Action Logic (`scripts/gameplay/action_logic.gd`)
We will refactor the member replacement logic to draw from and push back to `GameManager.bench_pool`, and add functions to list all betray/bargain effects with their validities.

- **Replacement Logic**:
  - Update `_kick_member_and_replace()`:
    - Append the kicked member's name to `gm.bench_pool`.
    - Pop the next replacement member from `gm.bench_pool` and set it active on the board as a 0-star free agent.
- **Effects Inspection helpers**:
  - Implement `static func get_betray_effects_status(gm, member) -> Array`:
    - Loop over the 6 `BetrayEffect` enums.
    - Compute validity (`is_valid`) based on relationships (trust/hierarchy) and divisions.
    - Build descriptive strings with actual target names.
    - Return an array of dictionaries representing each option's metadata.
  - Implement `static func get_bargain_effects_status(gm, member) -> Array`:
    - Loop over the 10 `BargainEffect` enums.
    - Compute validity (`is_valid`) based on current board state (imprisoned queue, unassigned members, divisions).
    - Randomly select and pre-assign target names for effects that require a target (like recruit, swap division).
    - Return an array of dictionaries representing each option's metadata.

### 3. Card Action Overlay (`scripts/ui/card_action_overlay.gd`)
We will update the action options rendering: if `is_sandbox_mode` is enabled and the action is `BETRAY` or `BARGAIN`, we render a scrollable list containing all possible options, flagging invalid ones as disabled/greyed out, and let the user pick which effect to execute.

- **Rendering Sandbox Effects**:
  - In `_build_action_panels()`, check if `GameManager.is_sandbox_mode` is `true` and the action is `BETRAY` or `BARGAIN`.
  - If so, call a helper `_create_sandbox_effects_panel(action, pos, w, h)`.
  - Inside the panel:
    - Create a vertical scroll layout containing buttons for all effects.
    - For each effect:
      - Render a button. If invalid, set `disabled = true` and reduce modulate opacity to grey it out.
      - Hook up hover signals to update a detailed description label above the button list.
      - Hook up `pressed` signal to set `cached_betray_effect`/`cached_bargain_effect`/`cached_bargain_target` on the member, and trigger execution.

### 4. Setup Wizard UI (`scripts/ui/sandbox_setup_wizard.gd`)
A new control node that guides the user through the 3 setup steps:

- **UI Structure**:
  - **Header**: Title, Back/Next navigation, Close button.
  - **Step 1 Panel (Selection)**:
    - GridContainer of all 17 members with name/portrait and selection indicators.
    - Selection limit: must select exactly 14.
  - **Step 2 Panel (Placement)**:
    - Horizontal scroll container of selected members (unplaced).
    - Makes board slot `ColorRect`s visible and semi-transparent.
    - Click slot `ColorRect` to assign the currently selected member to that slot.
    - Auto-displace or recall members if slots are occupied.
  - **Step 3 Panel (Relationships)**:
    - Buttons for Green (Trust), Red (Rivalry), Clear (Neutral).
    - Toggles active relationship mode.
    - Listens to board card clicks. Sequentially select two cards to create/clear a line.
- **Completing Sandbox Mode**:
  - Finalizes state and closes the wizard, leaving sandbox mode active.

### 5. Main Loop Integration (`scripts/main.gd`)
We will integrate the wizard with the main controller.

- **Sandbox Button Toggled**:
  - In `_on_sandbox_pressed()`, if sandbox mode is toggled to ON:
    - Instantiate and add `SandboxSetupWizard` to the HUD.
    - Pause normal game processes.
  - If sandbox mode is toggled to OFF:
    - Close the wizard if open.
    - Reset the board by calling `_on_reset_pressed()`.
