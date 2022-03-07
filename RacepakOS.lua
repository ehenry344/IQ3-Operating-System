local car = script.Parent.Car.Value
local racepakEvent = car:WaitForChild("RPDataBus")
local _Tune = require(car["A-Chassis Tune"])

local valueFolder = script.Parent.Values 
local carState = script.Parent.IsOn

-- System Setup Handling 

local nightLight = _Tune.Racepak.NightLight 
local warningData = _Tune.Racepak.Warnings 

-- simulation handling 

local function genSimulated(min, max, prec, modifier) 
	modifier = modifier and math.rad(modifier) or math.rad(5) 
	
	local mean, range = (max + min) / 2, (max - min) - 1 
	local currentPlace = 0 
	
	return function()
		if currentPlace >= (math.pi * 2) then -- prevent the waveform from stopping 
			currentPlace = 0 
		end
		currentPlace += modifier 
		
		return math.floor((mean + (range * math.sin(currentPlace))) * 10^prec + 0.5) / 10^prec
	end
end

-- updateCallbacks : contains special functions that modify input for special cases 

local updateCallbacks = { 
	["Gear"] = function(gear) 
		return (gear == -1 and "R") or (gear == 0 and "N") or gear 
	end,
	["Velocity"] = function(speed)
		return math.floor(math.min(speed.Magnitude * (10 / 12) * (60 / 88))) 
	end,
}

-- handle the setup updaters 

local function findValue(vName) -- Searches Common Directories For Value Instance 
	if valueFolder:FindFirstChild(vName) then 
		return valueFolder[vName] 
	end
	
	for _,v in pairs(script.Parent:GetDescendants()) do -- Search Plugins Folder 
		if v.Name == vName and (v:IsA("ValueBase") or v:IsA("TextLabel")) then
			return v
		end
	end
end

-- properly create the connections 

local usesRPM = nil 
local startupValues = {} -- Replace Placeholders On Startup 

for i,current in pairs(_Tune.Racepak.DisplayData) do 
	local updateString = ("Update" .. i) 
	local valName = current[1] 
	
	if type(valName) ~= "table" then
		local valInstance = findValue(valName) 
		
		usesRPM = not usesRPM and valName == "RPM"  -- Checks if RPM needs to be defined for the tach lights to function 
		
		if not valInstance then 
			startupValues[i] = valName 
			
			continue 
		end		
		
		local updateFunction = updateCallbacks[valName] 		
		local updateProperty = valInstance:IsA("ValueBase") and "Value" or valInstance:IsA("TextLabel") and "Text"
		
		-- Adds to the default values on startup 
		
		startupValues[i] = valInstance 
		
		-- connect the updaters 
					
		if updateFunction then
			valInstance:GetPropertyChangedSignal(updateProperty):Connect(function()
				racepakEvent:FireServer(updateString, updateFunction(valInstance[updateProperty])) 
			end)
			
			continue 
		end 
		
		valInstance:GetPropertyChangedSignal(updateProperty):Connect(function()
			racepakEvent:FireServer(updateString, valInstance[updateProperty]) 
		end)
	else		
		coroutine.wrap(function() -- Updates almost instantaneously on startup, not too concerned with default startup value 
			local newSimValue = genSimulated(valName[1], valName[2], valName[3]) 
			
			while task.wait(1) do
				if carState.Value then 
					racepakEvent:FireServer(updateString, newSimValue()) 
				end 
			end
		end)() 
	end
end

-- run system setup 

racepakEvent:FireServer("SystemSetup", {
	_Tune.Racepak.DisplayData, 
	_Tune.Racepak.RevLightArray, 
	_Tune.Racepak.ShiftLight,
	_Tune.Redline, 
	_Tune.Racepak.Justification
}) 

-- receiving data back 

racepakEvent.OnClientEvent:Connect(function()
	for i, value in pairs(startupValues) do 
		if typeof(value) == "Instance" then 
			local property = value:IsA("TextLabel") and "Text" or "Value" 
			
			value = updateCallbacks[value.Name] and updateCallbacks[value.Name](value[property]) or value[property]
		end
		
		racepakEvent:FireServer("Update"..i, value) 
	end
end)

-- handle generic startup connection 

carState:GetPropertyChangedSignal("Value"):Connect(function()
	racepakEvent:FireServer("ToggleDash", carState.Value)
end)

if not usesRPM then 	
	local RPM = valueFolder:WaitForChild("RPM")
	
	RPM:GetPropertyChangedSignal("Value"):Connect(function()
		racepakEvent:FireServer("UpdateRPM", RPM.Value) 
	end)
end

if nightLight then 
	game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed) 
		if gameProcessed or input.KeyCode ~= nightLight then 
			return 
		end
		
		racepakEvent:FireServer("NightLight") 
	end)
end

--[[
How to make the warning system work : 
	- Methods in which we can detect if the warnings will go : 
		-- 1. Connect to all of the values that are being monitored and wait for it to change 
		-- 2. Check within setup system if they are being connected 
]]

