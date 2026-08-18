CharacterRepository = CharacterRepository or {}

--- @param accountId string
-- @param callback function(ok: boolean, charactersOrError: table|string)
CharacterRepository.findByAccountId = function(accountId, callback)
    Character:where("account_id", accountId):orderBy("created_at", "ASC"):get(callback)
end
