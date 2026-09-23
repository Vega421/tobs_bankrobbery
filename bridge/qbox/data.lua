-- Qbox: the database side (players, player_vehicles). Server only.
-- Qbox and QBCore share these tables, so bridge/qb/data.lua just reuses this file's functions.
if Framework ~= "qbox" and Framework ~= "qb" then return end
if not IsDuplicityVersion() then return end

-- One row of `players` -> the person shape every framework returns
function QbPersonRow(row)
    if row == nil then return nil end
    local info = Db.Json(row.charinfo) or {}
    local job = Db.Json(row.job) or {}
    return {
        id = row.citizenid,
        firstname = info.firstname,
        lastname = info.lastname,
        dob = info.birthdate,
        phone = info.phone,
        gender = info.gender,
        job = {name = job.name, label = job.label,
               grade = job.grade and job.grade.level or 0, onduty = job.onduty == true},
    }
end

function Bridge.GetPerson(id)
    return QbPersonRow(Db.Single("SELECT citizenid, charinfo, job FROM players WHERE citizenid = ?", {id}))
end

-- Searches first name, last name and phone number. text is matched anywhere in the value.
function Bridge.SearchPeople(text, limit)
    local like = "%" .. tostring(text or "") .. "%"
    local rows = Db.Query([[
        SELECT citizenid, charinfo, job FROM players
        WHERE JSON_EXTRACT(charinfo, '$.firstname') LIKE ?
           OR JSON_EXTRACT(charinfo, '$.lastname') LIKE ?
           OR JSON_EXTRACT(charinfo, '$.phone') LIKE ?
           OR citizenid = ?
        LIMIT ?]], {like, like, like, text, limit or 25})
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = QbPersonRow(row) end
    return out
end

local function VehicleRow(row)
    if row == nil then return nil end
    return {
        plate = row.plate,
        model = row.vehicle,
        owner = row.citizenid,
        garage = row.garage,
        stored = row.state == 1,
        fakeplate = row.fakeplate,
    }
end

function Bridge.GetVehicles(id)
    local rows = Db.Query("SELECT plate, vehicle, citizenid, garage, state, fakeplate FROM player_vehicles WHERE citizenid = ?", {id})
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = VehicleRow(row) end
    return out
end

function Bridge.GetVehicleByPlate(plate)
    local v = VehicleRow(Db.Single("SELECT plate, vehicle, citizenid, garage, state, fakeplate FROM player_vehicles WHERE plate = ?", {plate}))
    if v then v.person = Bridge.GetPerson(v.owner) end
    return v
end

-- Licences live in players.metadata.licences: {driver = true, business = false, weapon = true}
function Bridge.GetLicences(id)
    local meta = Db.Json(Db.Scalar("SELECT metadata FROM players WHERE citizenid = ?", {id})) or {}
    return meta.licences or meta.licenses or {}
end

function Bridge.SetLicence(id, name, has)
    local raw = Db.Json(Db.Scalar("SELECT metadata FROM players WHERE citizenid = ?", {id}))
    if raw == nil then return false end
    local key = raw.licences and "licences" or (raw.licenses and "licenses" or "licences")
    raw[key] = raw[key] or {}
    raw[key][name] = has and true or false
    return Db.Execute("UPDATE players SET metadata = ? WHERE citizenid = ?", {json.encode(raw), id}) ~= nil
end

function Bridge.GetPhoneNumber(id)
    local p = Bridge.GetPerson(id)
    return p and p.phone or nil
end
