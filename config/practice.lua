Config = Config or {}

--- PRACTICE LINES
-- A Race Director drives one clean lap with /recordline <name>; the line is stored in
-- the database and later drives the AI practice cars when no race is running.
Config.Practice = {
    recordSpacing = 12.0,   -- metres between stored points while recording
    minPoints     = 10,     -- shorter recordings are discarded
    maxPoints     = 2000,   -- recording stops itself at this many points
    closeRadius   = 40.0,   -- end within this distance of the start = closed loop
}
