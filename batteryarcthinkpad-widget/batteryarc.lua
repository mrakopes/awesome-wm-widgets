-------------------------------------------------
-- Battery Arc Widget for Awesome Window Manager
-- Shows the battery level of the laptop
-- More details could be found here:
-- https://github.com/streetturtle/awesome-wm-widgets/tree/master/batteryarc-widget

-- @author Pavel Makhov
-- @copyright 2020 Pavel Makhov
-------------------------------------------------

local awful = require("awful")
local beautiful = require("beautiful")
local naughty = require("naughty")
local wibox = require("wibox")
local watch = require("awful.widget.watch")

local HOME = os.getenv("HOME")
local WIDGET_DIR = HOME .. '/.config/awesome/awesome-wm-widgets/batteryarc-widget'

local batteryarc_widget = {}

local notify_icon
local last_status=''
local last_icon=''
--local notify_color
local notify = {}

local function worker(user_args)

    local args = user_args or {}

    local font = args.font or 'Play 6'
    local arc_thickness = args.arc_thickness or 2
    local show_current_level = args.show_current_level or false
    local size = args.size or 18
    local timeout = args.timeout or 10
    local show_notification_mode = args.show_notification_mode or 'on_hover' -- on_hover / on_click
    local notification_position = args.notification_position or 'top_right' -- see naughty.notify position argument

    local main_color = args.main_color or beautiful.fg_color
    local bg_color = args.bg_color or '#ffffff11'
    local low_level_color = args.low_level_color or '#e53935'
    local medium_level_color = args.medium_level_color or '#c0ca33'
    local charging_color = args.charging_color or '#43a047'
    local discharging_color = args.discharging_color or '#1e90ff'
    local notify_bg_color = args.notify_bg_color or '#000000'
    local notify_fg_color = args.notify_fg_color or '#eee9ef'
    local notify_icon_size = args.notify_icon_size or 200
    local notify_width = args.notify_width or 350


    local warning_msg_title = args.warning_msg_title or 'Battery level is low!'
    local warning_msg_text = args.warning_msg_text or 'Battery is dying'
    local warning_msg_position = args.warning_msg_position or 'bottom_right'
    local warning_msg_icon = args.warning_msg_icon or WIDGET_DIR .. '/spaceman.jpg'
    local msg_icon_dir = args.msg_icon_dir or '/usr/share/icons/Arc/status/symbolic'
    local enable_battery_warning = args.enable_battery_warning
    if enable_battery_warning == nil then
        enable_battery_warning = true
    end

    local upower_device = args.upower_device or '/org/freedesktop/UPower/devices/DisplayDevice'

    local text = wibox.widget {
        font = font,
        align = 'center',
        valign = 'center',
        widget = wibox.widget.textbox
    }

    local text_with_background = wibox.container.background(text)

    batteryarc_widget = wibox.widget {
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

    local last_battery_check = os.time()

    local notification
    --[[ Show warning notification ]]
    local function show_battery_warning(notify, timeout)

        awful.spawn.easy_async([[bash -c 'acpi']],
                function(stdout, _, _, _)
                    naughty.destroy(notification)
		    local text = notify.text ~= nil
		   		and notify.text..'\n\n'..stdout
				or stdout
                    notification = naughty.notify {
                        icon = notify.icon,
                        icon_size = notify_icon_size,
	                title = notify.title,
	                text = text,
                        timeout = timeout or notify.timeout or 30,
                        -- timeout = 0,
                        -- hover_timeout = 0.5,
                        position = warning_msg_position,
                        bg = notify_bg_color,
                        -- fg = notify.color or notify_fg_color,
                        width = notify_width,
                    }
	        end)
    end

    local function update_widget(widget, stdout)
        local charge = 0
        local status
	local time_empty
	local icon
	local rate

        for s in stdout:gmatch("[^\r\n]+") do
	    if status == nil then
	        local read_status = string.match(s, '[%s]*state:[%s]+([%w%p]+)')
                if read_status ~= nil then
	            status = string.lower(read_status)
	        end
	    end
	    if rate == nil then
	        local read_rate = string.match(s, '[%s]*energy.rate:[%s]+([%d]+) W')
                if read_rate ~= nil then
	            rate = tonumber(read_rate)
	        end
	    end
	    if charge == 0 then
	        local read_charge = string.match(s, '[%s]*percentage:[%s]+([%w]+)')
                if read_charge ~= nil then
	            charge = tonumber(read_charge)
	        end
	    end
	    if time_empty == nil then
	        local read_time_empty = string.match(s, '[%s]*time to [%w]+:[%s]+(.+)')
                if read_time_empty ~= nil then
	            time_empty = read_time_empty
	        end
	    end
	    if icon == nil then
	        local read_icon = string.match(s, '[%s]*icon.name:[%s]+\'(.*)\'')
                if read_icon ~= nil then
	            icon = read_icon
	        end
	    end
	end

--	charge=2
--	status


	-- local notify_title = status..', '..charge..'%'
	-- local notify_text = time_empty ~= nil
	--     and time_empty..' remaining'
	--     or ''


	-- notify_icon = msg_icon_dir..'/'..icon..'.svg'
	-- -- text_with_background.bgimage = notify_icon



	notify.title = 'Battery '..status..', '..charge..'%'
	notify.text = time_empty ~= nil
	    and time_empty..' remaining'
	    or ''


	notify.text = rate ~= nil
		and notify.text..', '..rate..' W'
		or notify.text

	notify.icon = msg_icon_dir..'/'..icon..'.svg'


        widget.value = charge

        if show_current_level == true then
            --- if battery is fully charged (100) there is not enough place for three digits, so we don't show any text
            text.text = charge == 100
                    and ''
                    or string.format('%d', charge)
        else
            text.text = ''
        end


	local fg_color

--    	    fg_color = charging_color

        if charge <= 15 then
    	    fg_color = low_level_color
            text_with_background.bg = low_level_color
        elseif charge > 15 and charge < 40 then
    	    fg_color = medium_level_color
	else
    	    fg_color = main_color
        end

        widget.colors = { fg_color }

        if status == 'charging' then
            text_with_background.bg = charging_color
            text_with_background.fg = '#000000'
        elseif status == 'discharging' then
            -- text_with_background.bg = fg_color
            text_with_background.bg = fg_color ~= nil
	                            and fg_color
	                            or '#ffffff'

            text_with_background.fg = '#000000'
	else
            text_with_background.bg = '#00000000'
            text_with_background.fg = main_color
        end

        -- if 5 minutes have elapsed since the last warning
        if (enable_battery_warning and os.difftime(os.time(), last_battery_check) > 10)
	        and (
		        ( charge <= 15 and status ~= 'charging' and os.difftime(os.time(), last_battery_check) > 60)
		    or  ( status ~= last_status )
		    or  ( icon ~= last_icon )
		) then

            last_battery_check = os.time()
	    show_battery_warning(notify)
	    last_status = status
	    last_icon = icon
        end

-- v--test
--        show_battery_warning('battery tester', notify_text..main_color, notify_color)
-- ^--test

    end

    -- watch('upower -i '..upower_device, timeout, update_widget, batteryarc_widget)
    watch('cat '..HOME..'/tmp/upower-test.txt', timeout, update_widget, batteryarc_widget)

    if show_notification_mode == 'on_hover' then
        batteryarc_widget:connect_signal("mouse::enter", function() show_battery_warning(notify, 5) end)
        -- batteryarc_widget:connect_signal("mouse::leave", function() naughty.destroy(notification) end)
    elseif show_notification_mode == 'on_click' then
        batteryarc_widget:connect_signal('button::press', function(_, _, _, button)
            if (button == 1) then show_battery_status() end
        end)
    end

    return batteryarc_widget

end

return setmetatable(batteryarc_widget, { __call = function(_, ...)
    return worker(...)
end })
