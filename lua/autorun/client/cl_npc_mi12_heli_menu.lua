-- ============================================================
--  MI-12 Homer — Q-Menu Control Panel
--  lua/autorun/client/cl_npc_mi12_heli_menu.lua
-- ============================================================

if not CLIENT then return end

-- ─── Palette ────────────────────────────────────────────────
local col_section_title = Color(210, 210, 210, 255)
local col_accent        = Color(0,   200, 120, 255)

local SECTION_COLORS = {
    ["NPC Call Settings"]    = Color(60,  120, 200, 120),
    ["Probability & Timing"] = Color(80,  160, 100, 120),
    ["Flight Behaviour"]     = Color(60,  160, 100, 120),
    ["Debug"]                = Color(100, 100, 110, 120),
    ["Manual Spawn"]         = Color(140, 80,  200, 120),
}

local function AddColoredCategory(panel, text)
    local bg = SECTION_COLORS[text]
    if not bg then panel:Help(text) return end

    local cat = vgui.Create("DPanel", panel)
    cat:SetTall(24)
    cat:Dock(TOP)
    cat:DockMargin(0, 8, 0, 4)
    cat.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, bg)
        surface.SetDrawColor(0, 0, 0, 35)
        surface.DrawOutlinedRect(0, 0, w, h)
        local tc = (bg.r + bg.g + bg.b < 200)
            and Color(255, 255, 255, 255)
            or  Color(0,   0,   0,   255)
        draw.SimpleText(text, "DermaDefaultBold", 8, h / 2, tc,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    panel:AddItem(cat)
end

-- Manual spawn concommand
concommand.Add("mi12_spawnheli", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("MI12_ManualSpawn")
    net.SendToServer()
end)

-- Tab — re-uses the shared "Bombin Support" tab
hook.Add("AddToolMenuTabs", "MI12_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "MI12_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "MI-12", "MI-12")
end)

hook.Add("PopulateToolMenu", "MI12_ToolMenu", function()
    spawnmenu.AddToolMenuOption(
        "Bombin Support",
        "MI-12",
        "npc_mi12_heli_settings",
        "MI-12 Settings",
        "", "",
        function(panel)
            panel:ClearControls()

            -- Header banner
            local header = vgui.Create("DPanel", panel)
            header:SetTall(32)
            header:Dock(TOP)
            header:DockMargin(0, 0, 0, 8)
            header.Paint = function(self, w, h)
                surface.SetDrawColor(0, 0, 0, 255)
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(col_accent)
                surface.DrawRect(0, h - 2, w, 2)
                draw.SimpleText(
                    "MI-12 Homer Flyover Controller",
                    "DermaLarge", 8, h / 2,
                    col_section_title,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
                )
            end
            panel:AddItem(header)

            AddColoredCategory(panel, "NPC Call Settings")
            panel:CheckBox("Enable MI-12 calls", "npc_mi12_enabled")

            AddColoredCategory(panel, "Probability & Timing")
            panel:NumSlider("Call chance (0-1)",         "npc_mi12_chance",    0,   1, 2)
            panel:NumSlider("Check interval (seconds)",  "npc_mi12_interval",  1,  60, 0)
            panel:NumSlider("Per-NPC cooldown (seconds)","npc_mi12_cooldown",  10, 180, 0)
            panel:NumSlider("Delay after flare (s)",     "npc_mi12_delay",     1,  15, 0)
            panel:NumSlider("Heli lifetime (seconds)",   "npc_mi12_lifetime",  5, 120, 0)

            AddColoredCategory(panel, "Flight Behaviour")
            panel:NumSlider("Speed (HU/s)",              "npc_mi12_speed",   100, 1200, 0)
            panel:NumSlider("Orbit radius (HU)",         "npc_mi12_radius",  500, 8000, 0)
            panel:NumSlider("Height above ground (HU)",  "npc_mi12_height",  500, 8000, 0)

            AddColoredCategory(panel, "Debug")
            panel:CheckBox("Enable debug prints", "npc_mi12_announce")

            AddColoredCategory(panel, "Manual Spawn")
            panel:Button("Spawn MI-12 now", "mi12_spawnheli")
        end
    )
end)
