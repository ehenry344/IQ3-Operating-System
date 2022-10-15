--[[
gilaga4815 

A-Chassis Racepak IQ3 Drag Plugin 

Created : 
Updated : 10 / 15 / 2022 
]]

local car = script.Parent.Car.Value
local racepakEvent = car:WaitForChild("RPDataBus")
local _Tune = require(car["A-Chassis Tune"])

local valueFolder = script.Parent.Values 
local carState = script.Parent.IsOn

-- System Setup Handling 

local nightLight = _Tune.Racepak.NightLight 
local optimizationSlope = _Tune.Racepak.Optimization.OptimizationSlope 
local testMode = _Tune.Racepak.TestingMode 

-- simulation handling 

local function genSimulated(min : number, max : number, prec : number, modifier : number): func  
	modifier = modifier and math.rad(modifier) or math.rad(5) 
	
	local mean, range = (max + min) / 2, (max - min) - 1 
	local currentPlace = 0 
	
	return function(): number 
		if currentPlace >= (math.pi * 2) then -- prevent the waveform from stopping 
			currentPlace = 0 
		end
		currentPlace += modifier 
		
		return math.floor((mean + (range * math.sin(currentPlace))) * 10^prec + 0.5) / 10^prec
	end
end

-- input modifiers for special cases 

local updateCallbacks = { 
	["Gear"] = function(gear : number): string? 
		return (gear == -1 and "R") or (gear == 0 and "N") or gear 
	end,
	["Velocity"] = function(speed : Vector3): number 
		return math.floor(math.min(speed.Magnitude * (10 / 12) * (60 / 88))) 
	end,
}

-- acquire the relevant values to track 

local function findValue(vName : string): Instance? -- Searches Common Directories For Value Instance 
	if valueFolder:FindFirstChild(vName) then 
		return valueFolder[vName] 
	end
	
	for _,v in pairs(script.Parent:GetDescendants()) do -- Search Plugins Folder 
		if v.Name == vName and (v:IsA("ValueBase") or v:IsA("TextLabel")) then
			return v
		end
	end
end

-- manage warning instances 

local function handleWarning(valueName : string): table  
	for channel, data in pairs(_Tune.Racepak.Warnings) do 
		if data[1] == valueName and type(data[2]) == "table" then 
			return {channel, data[2], (data[3] or "Out")}
		end
	end
end

-- setup the connections 

local usesRPM = nil 
local startupValues = {} 

-- create optimal connection object to reduce un-necessary spam from the remotes

local function setupConnection(trackValue : Instance, displayIndice : number, doRegulate : boolean) 
	local upProperty = trackValue:IsA("ValueBase") and "Value" or "Text" 	
	local upFunction = updateCallbacks[trackValue.Name] 

	local warningInfo = handleWarning(trackValue.Name) 

	local lastValue = upFunction and upFunction(trackValue[upProperty]) or trackValue[upProperty] 
	local lastUpdate = os.clock() -- Allows for value slope determination 
	
	local handleWarning 
	
	if warningInfo then 
		handleWarning = function(nValue)
			local status = warningInfo[3] == "Out" and 
				(nValue < warningInfo[2][1] or nValue > warningInfo[2][2]) or 
				warningInfo[3] == "In" and 
				(nValue > warningInfo[2][1] and nValue < warningInfo[2][2]) 

			racepakEvent:FireServer("Warning", warningInfo[1], status) 
		end
	end
	
	if type(lastValue) == "string" then -- Not going to be extending optimization priviledges for string values as their required exceptions negatively impact every other update
		trackValue:GetPropertyChangedSignal(upProperty):Connect(function()
			local newValue = tonumber(string.match(trackValue[upProperty], "%d+"))
			
			racepakEvent:FireServer(displayIndice, trackValue[upProperty])  
			
			if warningInfo then 
				handleWarning(newValue) 
			end 
		end)
	else 
		trackValue:GetPropertyChangedSignal(upProperty):Connect(function()						
			local newValue = upFunction and upFunction(trackValue[upProperty]) or trackValue[upProperty] 
					
			if doRegulate and math.abs(newValue - lastValue) / (os.clock() - lastUpdate) <= optimizationSlope then 
				return 
			end
		
			racepakEvent:FireServer(displayIndice, newValue) 
						
			if warningInfo and os.clock() - lastUpdate > 1 then -- >:D 
				handleWarning(newValue) 
			end
			
			lastUpdate = os.clock() 
			lastValue = newValue 	
		end)
	end
end

-- init  

for labelIndex,current in pairs(_Tune.Racepak.DisplayData) do 
	local valName = current[1] 
	
	if type(valName) ~= "table" then
		local valInstance = findValue(valName) 
		
		if not valInstance then
			startupValues[labelIndex] = valName 
			continue 
		end 
		
		startupValues[labelIndex] = valInstance 
		
		usesRPM = not usesRPM and valName == "RPM" 
		
		setupConnection(
			valInstance, 
			labelIndex, 
			_Tune.Racepak.Optimization.RegulatedValues[valName] 
		)
	else		
		coroutine.wrap(function() 
			local newSim = genSimulated(valName[1], valName[2], valName[3]) 

			while task.wait(1) do
				if carState.Value then 
					racepakEvent:FireServer(labelIndex, newSim()) 
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
		racepakEvent:FireServer(i, value) 
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
