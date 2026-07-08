# Walkthrough: Sandbox Mode Setup Wizard and Integration

This walkthrough details the changes implemented to support the **Sandbox Mode Setup Wizard** and its corresponding gameplay/UI integrations.

---

## 1. Summary of Modified & New Files

| File Path | Description |
| :--- | :--- |
| [`scripts/autoloads/game_manager.gd`](file:///c:/Users/admin/Desktop/辛迪加/辛迪加项目/scripts/autoloads/game_manager.gd) | Add global `bench_pool` tracking, state duplication for undo, and `initialize_sandbox_mode` helper. |
| [`scripts/gameplay/action_logic.gd`](file:///c:/Users/admin/Desktop/辛迪加/辛迪加项目/scripts/gameplay/action_logic.gd) | Update replacement logic to pull from `bench_pool`, and implement effects-querying helper functions (`get_betray_effects_status`, `get_bargain_effects_status`). |
| [`scripts/ui/card_action_overlay.gd`](file:///c:/Users/admin/Desktop/辛迪加/辛迪加项目/scripts/ui/card_action_overlay.gd) | Update overlay to render all possible betray/bargain options (enabled vs. greyed out/disabled) in sandbox mode, letting the user choose. |
| [`scripts/ui/sandbox_setup_wizard.gd`](file:///c:/Users/admin/Desktop/辛迪加/辛迪加项目/scripts/ui/sandbox_setup_wizard.gd) | **[New File]** A Control UI wizard that guides the player step-by-step to define the board layout and relationships. |
| [`scripts/main.gd`](file:///c:/Users/admin/Desktop/辛迪加/辛迪加项目/scripts/main.gd) | Integrate the sandbox setup wizard, forward board card clicks to the wizard, and support sandbox state toggles. |

---

## 2. Sandbox Setup Wizard Flow (3 Steps)

When you toggle the **"沙盒模式" (Sandbox Mode)** button, the Setup Wizard opens. It guides you through the following phases:

### Step 1: Active Member Selection
* **UI**: Displays a grid of all 17 syndicate members with their portraits.
* **Logic**: You must select exactly **14 members** to be active. The remaining 3 members are excluded and placed into the `bench_pool` as inactive backup.
* **Next**: The "确定选择" (Confirm Selection) button becomes active once exactly 14 members are selected.

### Step 2: Slot Assignment
* **UI**: Hides the grid and displays a bottom dock containing the 14 selected members. The board slots (ColorRects) on the board become visible and highlighted with semi-transparent colors indicating their positions.
* **Logic**:
  1. Click on a member in the bottom dock to select them (the card is highlighted).
  2. Click on a highlighted board slot (e.g. Leader of Research, Subordinate of Fortification, or Unassigned Slot) to place the member there.
  3. The card immediately instantiates and flies to the designated slot position on the board.
  4. If a slot is already occupied, the existing member is displaced and returned to the "unplaced" state.
  5. Click on an already-placed member to select and recall them.
* **Next**: The "下一步" (Next) button is enabled when all 14 members are successfully placed on the board.

### Step 3: Relationship Drawing
* **UI**: Hides the slot ColorRects and displays the Relationship Editor bar at the top:
  - 🟢 **信任关系** (Form Trust / Green line)
  - 🔴 **仇敌关系** (Form Rivalry / Red line)
  - ⚪ **清除关系** (Clear Relationship / Neutral)
* **Logic**:
  1. Toggle one of the relationship modes (e.g., Trust).
  2. Click on two cards sequentially on the board.
  3. A trust (green) or rivalry (red) line will instantly be drawn between them, or cleared if "Clear" is selected.
* **Exit**: Click "完成布阵" (Complete Layout) to close the wizard and active the custom sandbox layout!

---

## 3. Sandboxed Action Selections

Normally, **Betray** and **Bargain** actions execute a single pre-rolled random effect.
In **Sandbox Mode**:
* When you hover over or click a card during a generated sandbox encounter:
  * The overlay lists **all** possible effects of **Betray** (6 choices) or **Bargain** (10 choices) in a scrollable list.
  * Effects that are valid under the current board state are fully colored and clickable. Hovering over them updates the description label.
  * Effects that are invalid are disabled and greyed out.
  * You can click **any valid effect** to immediately execute it, allowing you to test specific mechanics, outcomes, and chain reactions.

---

## 4. Compilation Verification

 Headless compilation was successfully verified on all modified scripts using Godot v4.6.1:
```cmd
& "D:\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe" --headless --check-only --path "c:\Users\admin\Desktop\辛迪加\辛迪加项目"
```
Result: **100% Compile Success** with no syntax or parser errors.
