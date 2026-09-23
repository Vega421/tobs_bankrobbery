-- ESX Legacy: the database side (users, owned_vehicles, user_licenses). Server only.
if Framework ~= "esx" then return end
if not IsDuplicityVersion() then return end

local function PersonRow(row)
    if row == nil then return nil end
    return {
        id = row.identifier,
        firstname = row.firstname,
        lastname = row.lastname,
        dob = row.dateofbirth,
        phone = row.phone_number,
        gender = row.sex,
        job = {name = row.job, grade = row.job_grade or 0, onduty = true},
    }
end

function Bridge.GetPerson(id)
    return PersonRow(Db.Single([[
        SELECT identifier, firstname, lastname, dateofbirth, phone_number, sex, job, job_grade
        FROM users WHERE identifier = ?]], {id}))
end

function Bridge.SearchPeople(text, limit)
    local like = "%" .. tostring(text or "") .. "%"
    local rows = Db.Query([[
        SELECT identifier, firstname, lastname, dateofbirth, phone_number, sex, job, job_grade
        FROM users
        WHERE firstname LIKE ? OR lastname LIKE ? OR phone_number LIKE ? OR identifier = ?
        LIMIT ?]], {like, like, like, text, limit or 25})
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = PersonRow(row) end
    return out
end

local function VehicleRow(row)
    if row == nil then return nil end
    local data = Db.Json(row.vehicle) or {}
    return {
        plate = row.plate,
        model = data.model or data.hash,
        owner = row.owner,
        stored = row.stored == 1,
    }
end

function Bridge.GetVehicles(id)
    local rows = Db.Query("SELECT owner, plate, vehicle, stored FROM owned_vehicles WHERE owner = ?", {id})
    local out = {}
    for _, row in ipairs(rows or {}) do out[#out + 1] = VehicleRow(row) end
    return out
end

function Bridge.GetVehicleByPlate(plate)
    local v = VehicleRow(Db.Single("SELECT owner, plate, vehicle, stored FROM owned_vehicles WHERE plate = ?", {plate}))
    if v then v.person = Bridge.GetPerson(v.owner) end
    return v
end

-- esx_license keeps one row per licence in user_licenses (type, owner)
function Bridge.GetLicences(id)
    local rows = Db.Query("SELECT type FROM user_licenses WHERE owner = ?", {id})
    local out = {}
    for _, row in ipairs(rows or {}) do out[row.type] = true end
    return out
end

function Bridge.SetLicence(id, name, has)
    if has then
        return Db.Execute("INSERT IGNORE INTO user_licenses (type, owner) VALUES (?, ?)", {name, id}) ~= nil
    end
    return Db.Execute("DELETE FROM user_licenses WHERE type = ? AND owner = ?", {name, id}) ~= nil
end

function Bridge.GetPhoneNumber(id)
    return Db.Scalar("SELECT phone_number FROM users WHERE identifier = ?", {id})
end
