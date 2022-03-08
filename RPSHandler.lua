-- Handle the Whitelist 

local whitelist = require(9042302209) 

local car = script.Parent.Parent
local F = {}

local racepak = car.Body:WaitForChild("IQ3")
local tachLights = racepak:WaitForChild("Lites")
local warningLights = racepak:WaitForChild("WarningLites")
local screenUI = racepak:WaitForChild("Screen"):WaitForChild("NumReadout")
local RPMBar = screenUI:WaitForChild("RPMbar")

-- Handle Whitelist 

if not (whitelist.Licensed[game.CreatorId] or whitelist.Owners[game.CreatorId] and game:GetService("RunService"):IsStudio()) then 
	racepak:Destroy()
	script.Parent:Destroy() 
end

-- setup data 

local currentClient = nil -- client that is using the dash at a given time (can be used in order to communicate server -> client)

local defaultText = {} -- text to be displayed on startup 
local tachIntervals = {} 

local flashInterval = false 
local maxRPM = nil 

-- TODO : Make the whitelist system (work in RDRA, NRDA, Real Deal Grudge) 

-- RPM Updates / Light Handling 

local didFlash = false 

local function updateTachLights(tachValue) 	
	local mappedTach = (tachValue / maxRPM) 
	RPMBar.Frame.Size = UDim2.new(mappedTach, 0, 1, 0) 
	RPMBar.Frame.ImageLabel.Size = UDim2.new(1 / mappedTach, 0, 1, 0) 
	
	if flashInterval and tachValue >= flashInterval then 
		if not didFlash then 
			for _,v in pairs(tachLights:GetChildren()) do
				v.Material = Enum.Material.Neon 
				v.BrickColor = BrickColor.new("Br. yellowish orange")
			end
			
			didFlash = true -- Make it so we can turn them off 
		end
		
		return 
	end
	
	if didFlash then 
		tachLights[1].BrickColor = BrickColor.new("Lime green")
		tachLights[2].BrickColor = BrickColor.new("Lime green")
		tachLights[3].BrickColor = BrickColor.new("New Yeller")
		tachLights[4].BrickColor = BrickColor.new("New Yeller")
		tachLights[5].BrickColor = BrickColor.new("New Yeller")
		
		didFlash = false 
	end
	
	for i = 1, #tachIntervals do 
		if tachValue >= tachIntervals[i] then 
			tachLights[i].Material = Enum.Material.Neon
		else
			tachLights[i].Material = Enum.Material.SmoothPlastic 
		end
	end
end

-- handle server sided rpm updates 

F.UpdateRPM = updateTachLights -- (tach lights still need to work if not defined by user previously) 

-- handle nightlight and other options for the dash 

function F.NightLight()
	screenUI.Brightness = (screenUI.Brightness > 1) and 1 or 2 
end

-- handle warning light 

function F.Warning(channel, status)
	warningLights[channel].Material = (status and Enum.Material.Neon) or Enum.Material.SmoothPlastic 
end

-- handle toggling screen on / off 

function F.ToggleDash(dashState)   
	if dashState then -- Dash On 
		task.wait(1.5)
		
		for _,v in pairs(screenUI:GetChildren()) do 
			if v.Name ~= "Background" then 
				if tonumber(v.Name) then
					v.Text = defaultText[tonumber(v.Name)] 
				end		
				
				v.Visible = true 
			else 
				v.BackgroundColor3 = Color3.fromRGB(7, 102, 255)
			end
		end		
		
		task.wait(1)	
		
		for _,v in pairs(screenUI:GetChildren()) do
			if tonumber(v.Name) then 
				v.Text = "" 
			end
		end
		
		task.wait(0.5)
		
		racepak.Screen.BlueLight.Enabled = true 
		
		script.Parent:FireClient(currentClient) 
	else 
		racepak.Screen.BlueLight.Enabled = false 
		
		for _,v in pairs(screenUI:GetChildren()) do 
			if v.Name ~= "Background" then 
				v.Visible = false  
			else
				v.BackgroundColor3 = Color3.fromRGB(84, 122, 88)
			end
		end
	end
end

-- handle setup data input 

function F.SystemSetup(setupPacket)  
	assert(setupPacket, "RACEPAK CRITICAL ERROR : Failed to fetch Setup Packet") 
	
	for i = 1, #setupPacket[1] do -- Display Modifiers 
		local dispLabel = screenUI:WaitForChild("Disp" .. i) 
		
		-- Create Updater Callbacks 
		
		if setupPacket[1][i][1] == "RPM" then -- Pretty Much the Only Special Case 
			screenUI[i].TextXAlignment = Enum.TextXAlignment[(setupPacket[5] or "Center")] 
			
			F[i] = function(value)
				updateTachLights(value)
				screenUI[i].Text = math.floor(value) 
			end
		else 
			F[i] = function(value)
				screenUI[i].Text = value 
			end
		end
		
		-- Populate Default Text 
		
		dispLabel.Text = setupPacket[1][i][2] 		
		defaultText[i] = setupPacket[1][i][3]
	end
	
	for i = 1, #setupPacket[2] do 
		tachIntervals[i] = setupPacket[2][i]
	end
	
	flashInterval = setupPacket[3] 
	maxRPM = setupPacket[4] 
end

-- end of setup stuff for the racepak

script.Parent.OnServerEvent:Connect(function(pl,Fnc,...)
	currentClient = pl -- just setting the current client for the setup variable 

	F[Fnc](...)
end)

car.DriveSeat.ChildRemoved:connect(function(child)
	if child.Name=="SeatWeld" then
		F.ToggleDash(false)
	end
end)

