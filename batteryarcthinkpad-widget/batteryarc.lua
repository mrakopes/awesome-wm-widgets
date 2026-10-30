-------------------------------------------------
-- Battery Arc Widget for Awesome Window Manager
-- Shows the battery level of the laptop, based on upower
-- More details could be found here:
-- https://github.com/streetturtle/awesome-wm-widgets/tree/master/batteryarc-widget

-- @author Pavel Makhov
-- @copyright 2020 Pavel Makhov
-------------------------------------------------

local awful = require("awful")
local beautiful = require("beautiful")
local gdebug = require("gears.debug")
local gtimer = require("gears.timer")
local naughty = require("naughty")
local protected_call = require("gears.protected_call")
local wibox = require("wibox")

local LOW_LEVEL = 15
local MEDIUM_LEVEL = 40

-- rc.lua usually creates one widget per screen, and creates another one each
-- time a screen is plugged in. There is only one battery though, so all the
-- widgets share one poller and one notification. The table is weak so that a
-- widget of a removed screen can be garbage collected.
local widgets = setmetatable({}, { __mode = 'k' })

local config -- settings of the first created widget, used by the shared poller
local battery -- last state read from upower
local poll_timer
local notification_id
local last_warning_time
local last_poll_failed = false

local function parse_upower_output(stdout)
    local output = '\n' .. stdout
    local function field(pattern)
        return output:match('\n%s*' .. pattern)
    end

    local status = field('state:%s+(%S+)')
    local charge = tonumber(field('percentage:%s+(%d+)'))
    if status == nil or charge == nil then
        return nil
    end

    local rate = field('energy%-rate:%s+([%d.,]+) W')
    return {
        status = status:lower(),
        charge = charge,
        rate = rate and tonumber((rate:gsub(',', '.'))),
        time_left = field('time to %a+:%s+([^\n]+)'),
        icon = field("icon%-name:%s+'([^']*)'"),
    }
end

local function show_notification(timeout)
    if battery == nil then
        return
    end

    local details = {}
    if battery.time_left ~= nil then
        table.insert(details, battery.time_left .. ' remaining')
    end
    if battery.rate ~= nil and battery.rate > 0 then
        table.insert(details, string.format('%.1f W', battery.rate))
    end

    -- A notification is a wibox and an icon surface, which are only released
    -- by the garbage collector. Reuse the one on the screen, if there is any.
    local notification = naughty.notify {
        replaces_id = notification_id,
        icon = battery.icon and config.msg_icon_dir .. '/' .. battery.icon .. '.svg',
        icon_size = config.notify_icon_size,
        title = 'Battery ' .. battery.status .. ', ' .. battery.charge .. '%',
        text = table.concat(details, ', '),
        timeout = timeout,
        position = config.warning_msg_position,
        bg = config.notify_bg_color,
        width = config.notify_width,
    }
    notification_id = notification and notification.id
end

local function notify_about_changes(previous)
    local is_low = battery.status == 'discharging' and battery.charge <= LOW_LEVEL
    if not is_low then
        last_warning_time = nil
    end

    local warning_due = is_low and (last_warning_time == nil
            or os.difftime(os.time(), last_warning_time) >= config.warning_interval)
    -- the icon changes with the charge level, while the battery is low that is
    -- handled by warning_interval. Nothing to compare with on the first poll.
    local changed = previous ~= nil and (battery.status ~= previous.status
            or (not is_low and battery.icon ~= previous.icon))

    if warning_due or changed then
        if is_low then
            last_warning_time = os.time()
        end
        show_notification(config.warning_timeout)
    end
end

local function on_upower_output(stdout)
    local previous = battery
    local current = parse_upower_output(stdout)

    -- upower can fail temporarily, keep showing the last known state until then
    if current == nil then
        if not last_poll_failed then
            gdebug.print_warning('batteryarc: cannot parse the output of upower')
        end
        last_poll_failed = true
        return
    end
    last_poll_failed = false
    battery = current

    for widget in pairs(widgets) do
        widget.render_battery(battery)
    end

    if config.enable_battery_warning then
        notify_about_changes(previous)
    end
end

local function poll()
    poll_timer:stop()
    local pid = awful.spawn.easy_async('upower -i ' .. config.upower_device, function(stdout)
        -- an error here must not stop the timer, the widget would never refresh again
        protected_call(on_upower_output, stdout)
        poll_timer:again()
    end)

    -- the callback above is never called when the command could not be started
    if type(pid) == 'string' then
        if not last_poll_failed then
            gdebug.print_warning('batteryarc: cannot run upower: ' .. pid)
        end
        last_poll_failed = true
        poll_timer:again()
    end
end

local function worker(user_args)

    local args = user_args or {}

    local font = args.font or 'Play 6'
    local arc_thickness = args.arc_thickness or 2
    local show_current_level = args.show_current_level or false
    local size = args.size or 18
    local show_notification_mode = args.show_notification_mode or 'on_hover' -- on_hover / on_click / off

    local main_color = args.main_color or beautiful.fg_color
    local bg_color = args.bg_color or '#ffffff11'
    local low_level_color = args.low_level_color or '#e53935'
    local medium_level_color = args.medium_level_color or '#c0ca33'
    local charging_color = args.charging_color or '#43a047'

    local text = wibox.widget {
        font = font,
        align = 'center',
        valign = 'center',
        widget = wibox.widget.textbox
    }

    local text_with_background = wibox.container.background(text)

    local batteryarc = wibox.widget {
        text_with_background,
        max_value = 100,
        rounded_edge = true,
        thickness = arc_thickness,
        start_angle = 4.71238898, -- 2pi*3/4
        forced_height = size,
        forced_width = size,
        bg = bg_color,
        paddings = 2,
        widget = wibox.container.arcchart
    }

    local rendered_charge, rendered_status

    -- The arc and background setters redraw the wibar, even with the same value
    batteryarc.render_battery = function(state)
        if state.charge == rendered_charge and state.status == rendered_status then
            return
        end
        rendered_charge, rendered_status = state.charge, state.status

        batteryarc.value = state.charge

        --- if battery is fully charged (100) there is not enough place for three digits, so we don't show any text
        text.text = (show_current_level and state.charge ~= 100)
                and string.format('%d', state.charge)
                or ''

        local arc_color = main_color
        if state.charge <= LOW_LEVEL then
            arc_color = low_level_color
        elseif state.charge < MEDIUM_LEVEL then
            arc_color = medium_level_color
        end
        batteryarc.colors = { arc_color }

        if state.status == 'charging' then
            text_with_background.bg = charging_color
            text_with_background.fg = '#000000'
        elseif state.status == 'discharging' then
            text_with_background.bg = arc_color or '#ffffff'
            text_with_background.fg = '#000000'
        else
            text_with_background.bg = '#00000000'
            text_with_background.fg = main_color
        end
    end

    widgets[batteryarc] = true

    if show_notification_mode == 'on_hover' then
        batteryarc:connect_signal('mouse::enter', function() show_notification(5) end)
    elseif show_notification_mode == 'on_click' then
        batteryarc:connect_signal('button::press', function(_, _, _, button)
            if button == 1 then show_notification(5) end
        end)
    end

    if config == nil then
        config = {
            upower_device = args.upower_device or '/org/freedesktop/UPower/devices/DisplayDevice',
            -- msg_icon_dir = args.msg_icon_dir or '/usr/share/icons/Arc/status/symbolic',
            msg_icon_dir = args.msg_icon_dir or '/usr/share/icons/breeze-dark/status/32',
            notify_bg_color = args.notify_bg_color or '#000000',
            notify_icon_size = args.notify_icon_size or 200,
            notify_width = args.notify_width or 350,
            warning_msg_position = args.warning_msg_position or 'bottom_right',
            warning_timeout = args.warning_timeout or 30,
            warning_interval = args.warning_interval or 300,
            enable_battery_warning = args.enable_battery_warning ~= false,
        }
        poll_timer = gtimer { timeout = args.timeout or 10, callback = poll }
        poll_timer:start()
        poll()
    elseif battery ~= nil then
        batteryarc.render_battery(battery)
    end

    return batteryarc

end

return setmetatable({}, { __call = function(_, ...)
    return worker(...)
end })
