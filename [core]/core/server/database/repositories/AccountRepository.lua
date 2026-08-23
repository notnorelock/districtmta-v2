-- Thin facade over the Account Active Record model - AccountService
-- calls this, never Account/Model/QueryBuilder directly.
AccountRepository = AccountRepository or {}

--- @param id number
-- @param callback function(ok: boolean, accountOrError: table|nil|string)
AccountRepository.findById = function(id, callback)
    Account:find(id, callback)
end

--- @param login string already-normalized (lowercase) login
-- @param callback function(ok: boolean, accountOrError: table|nil|string)
AccountRepository.findByLogin = function(login, callback)
    Account:where("login", login):first(callback)
end

--- @param email string already-normalized (lowercase) email
-- @param callback function(ok: boolean, accountOrError: table|nil|string)
AccountRepository.findByEmail = function(email, callback)
    Account:where("email", email):first(callback)
end

--- @param mtaSerial string MTA's own getPlayerSerial() value
-- @param callback function(ok: boolean, accountOrError: table|nil|string)
AccountRepository.findByMtaSerial = function(mtaSerial, callback)
    Account:where("mta_serial", mtaSerial):first(callback)
end

--- @param data table { mtaSerial, login, email, passwordHash }
-- @param callback function(ok: boolean, accountOrError: table|string)
AccountRepository.create = function(data, callback)
    Account:create({
        mta_serial = data.mtaSerial,
        login = data.login,
        email = data.email,
        password_hash = data.passwordHash,
    }, callback)
end

--- @param id number
-- @param mtaSerial string
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountRepository.updateMtaSerial = function(id, mtaSerial, callback)
    Account:query():where("id", id):update({ mta_serial = mtaSerial }, callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountRepository.touchLastSeen = function(id, callback)
    Account:query():where("id", id):update({ last_seen_at = os.date("!%Y-%m-%d %H:%M:%S") }, callback)
end

--- Clears a lapsed premium_expires_at back to NULL (uses Model.NULL,
--- not plain `nil` - see Model.lua).
-- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountRepository.clearExpiredPremium = function(id, callback)
    Account:query():where("id", id):update({ premium_expires_at = Model.NULL }, callback)
end

--- @param id number
-- @param role number one of Enums.AccountRole's values
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountRepository.updateRole = function(id, role, callback)
    Account:query():where("id", id):update({ role = role }, callback)
end

--- Adds to the account's own money balance - a single atomic
-- `money = money + ?` UPDATE, not a read-then-write, so two concurrent
-- give/take calls for the same account (e.g. a duty payout landing at
-- the same moment as a /przelej transfer) can never race and drop one
-- of them.
-- @param id number
-- @param amount number positive integer to add
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountRepository.giveMoney = function(id, amount, callback)
    Database.execute("UPDATE `accounts` SET `money` = `money` + ? WHERE `id` = ?", { amount, id }, callback)
end

--- Subtracts from the account's own money balance, floored at 0 (GREATEST
-- in the same atomic UPDATE, not a separate check) - same race-safety
-- reasoning as giveMoney above.
-- @param id number
-- @param amount number positive integer to subtract
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountRepository.takeMoney = function(id, amount, callback)
    Database.execute("UPDATE `accounts` SET `money` = GREATEST(0, `money` - ?) WHERE `id` = ?", { amount, id }, callback)
end
