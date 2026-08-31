-- beeadvice.lua  ->  install to /home/lib/beeadvice.lua
-- The words for a climate mismatch. Takes a beeclimate.status
-- verdict and turns it into something a human can act on; no state,
-- no requires, so every screen and the chat box can share the exact
-- same phrasing.
--
-- A verdict's gaps are signed in hive terms: positive means the hive
-- must move UP (warmer / damper) to suit the bee, negative means
-- down. The bee's own way out is the mirror image -- a hive that
-- must warm up by 2 is a bee that needs Down 2 tolerance.

local advice = {}

-- One line for the dashboard, the log, or chat.
function advice.line(st)
  if st.ok then
    return ("Climate %s -- %s works here"):format(st.apiary, st.species)
  end
  local parts = {}
  if st.temp ~= 0 then
    parts[#parts + 1] = ("%d %s"):format(math.abs(st.temp),
                        st.temp > 0 and "warmer" or "cooler")
  end
  if st.humid ~= 0 then
    parts[#parts + 1] = ("%d %s"):format(math.abs(st.humid),
                        st.humid > 0 and "damper" or "drier")
  end
  return ("! %s wants %s, hive is %s -- needs %s"):format(
         st.species, st.want, st.apiary, table.concat(parts, " + "))
end

-- The tolerance alleles that would let the bee live with the hive as
-- it stands, e.g. "Down 2 temperature + Up 1 humidity tolerance".
function advice.tolerance(st)
  local out = {}
  if st.temp ~= 0 then
    out[#out + 1] = ("%s %d temperature"):format(
                    st.temp > 0 and "Down" or "Up", math.abs(st.temp))
  end
  if st.humid ~= 0 then
    out[#out + 1] = ("%s %d humidity"):format(
                    st.humid > 0 and "Down" or "Up", math.abs(st.humid))
  end
  if #out == 0 then return "no tolerance" end
  return table.concat(out, " + ") .. " tolerance"
end

-- Both ways out of a mismatch: move the hive, or breed the gene.
-- The alveary blocks named here are the Forestry ones; a plain
-- apiary can only be moved to a different biome.
function advice.fix(st)
  local out = {}
  if st.temp > 0 then
    out[#out + 1] = ("warm the hive by %d (Alveary Heater)"):format(st.temp)
  elseif st.temp < 0 then
    out[#out + 1] = ("cool the hive by %d (Alveary Fan)"):format(-st.temp)
  end
  if st.humid > 0 then
    out[#out + 1] = "damp it (Alveary Hygroregulator, water)"
  elseif st.humid < 0 then
    out[#out + 1] = "dry it (Alveary Hygroregulator, ice)"
  end
  out[#out + 1] = "or breed in " .. advice.tolerance(st)
  return table.concat(out, "; ")
end

return advice
